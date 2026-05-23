import Foundation
import AppKit

@MainActor
final class GoldPriceViewModel: ObservableObject {
    static let maxHistoryPoints = 1_800
    private static let sourcePreferenceKey = "gold_price_source_preference"
    private static let currencyPreferenceKey = "gold_price_currency_preference"
    private static let alertPriceKey = "gold_price_alert"
    private static let alertHistoryKey = "gold_price_alert_history"
    private static let compactHistoryWindow: TimeInterval = 90
    private static let chartHistoryWindow: TimeInterval = 4 * 60
    private static let minimumHistoryStep: TimeInterval = 0.001

    @Published private(set) var quote: GoldQuote?
    @Published private(set) var history: [GoldPricePoint] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var selectedSource: GoldPriceSourcePreference
    @Published private(set) var preferredCurrency: GoldPriceCurrencyPreference
    @Published private(set) var alertPrice: Double?
    @Published private(set) var alertCurrency: GoldPriceCurrencyPreference = .cnyPerGram
    @Published private(set) var alertTriggered = false
    @Published private(set) var alertTriggeredMessage: String?
    @Published private(set) var alertTriggeredAt: Date?
    @Published private(set) var alertFlashOn = false
    @Published private(set) var alertHistory: [GoldQuote.AlertRecord] = []

    // Multi-source support
    private let dataSourceManager = DataSourceManager.shared
    @Published private(set) var sourceQuotes: [String: DataSourceQuote] = [:]
    @Published private(set) var correlations: [SourceCorrelation] = []
    @Published private(set) var otherSourceItems: [OtherSourceItem] = []
    @Published private(set) var dataPointCounts: [String: Int] = [:]
    @Published private(set) var dataSyncedAt: Date?
    @Published private(set) var isBackfilling: Bool = false

    struct OtherSourceItem: Identifiable {
        let id: String
        let name: String
        let priceText: String
        let unit: String
    }

    private var alertFlashTimer: Timer?
    private var alertSoundTimer: Timer?

    private let service: GoldPriceService
    private let refreshInterval: Duration
    private var refreshTask: Task<Void, Never>?
    private let userDefaults: UserDefaults
    private var refreshSequence = 0
    init(
        service: GoldPriceService = GoldPriceService(),
        refreshInterval: Duration = .seconds(1),
        autoStart: Bool = false,
        userDefaults: UserDefaults = .standard
    ) {
        self.service = service
        self.refreshInterval = refreshInterval
        self.userDefaults = userDefaults
        self.selectedSource = Self.loadSourcePreference(from: userDefaults)
        self.preferredCurrency = Self.loadCurrencyPreference(from: userDefaults)
        let savedAlert = userDefaults.double(forKey: Self.alertPriceKey)
        self.alertPrice = savedAlert == 0 ? nil : savedAlert
        self.alertHistory = Self.loadAlertHistory(from: userDefaults)

        if autoStart {
            GoldPriceLog.appStart()
            start()
            startMultiSourceSync()
        }
    }

    deinit {
        refreshTask?.cancel()
    }

    func start() {
        guard refreshTask == nil else {
            return
        }

        refreshTask = Task { [weak self] in
            guard let self else {
                return
            }

            GoldPriceLog.appStart()
            let clock = ContinuousClock()
            while !Task.isCancelled {
                let cycleStartedAt = clock.now
                await refresh()

                do {
                    try await clock.sleep(
                        until: cycleStartedAt.advanced(by: refreshInterval),
                        tolerance: .milliseconds(100)
                    )
                } catch {
                    GoldPriceLog.refreshSkipped(reason: "sleep interrupted: \(error.localizedDescription)")
                    return
                }
            }
        }
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    func refresh() async {
        guard !isRefreshing else {
            return
        }

        let requestSource = selectedSource
        let requestSequence = refreshSequence
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            GoldPriceLog.refreshStart(source: requestSource.displayName)
            let quote = try await service.fetchQuote(preferredSource: requestSource)
            guard requestSequence == refreshSequence, requestSource == selectedSource else {
                GoldPriceLog.refreshSkipped(reason: "stale request (source changed)")
                return
            }
            GoldPriceLog.refreshSuccess(source: quote.sourceName, price: quote.pricePerOunce, cny: quote.pricePerGramCNY)
            apply(quote)
            errorMessage = nil
        } catch {
            guard requestSequence == refreshSequence, requestSource == selectedSource else {
                return
            }
            GoldPriceLog.refreshError(error, source: requestSource.displayName)
            errorMessage = error.localizedDescription
        }
    }

    func toggleCurrency() {
        preferredCurrency = preferredCurrency == .usdPerOunce ? .cnyPerGram : .usdPerOunce
        userDefaults.set(preferredCurrency.rawValue, forKey: Self.currencyPreferenceKey)
        GoldPriceLog.currencyToggled(to: preferredCurrency.displayName)
    }

    func setAlert(price: Double) {
        alertPrice = price
        alertCurrency = preferredCurrency
        alertTriggered = false
        alertTriggeredMessage = nil
        alertTriggeredAt = nil
        alertFlashOn = false
        alertFlashTimer?.invalidate()
        alertFlashTimer = nil
        previousCNYForAlert = nil
        userDefaults.set(price, forKey: Self.alertPriceKey)
        GoldPriceLog.alertSet(price: price, currency: alertCurrency.displayName)
    }

    func clearAlert() {
        alertPrice = nil
        userDefaults.removeObject(forKey: Self.alertPriceKey)
        GoldPriceLog.alertCleared()
    }

    func dismissTriggeredAlert() {
        alertTriggered = false
        alertTriggeredMessage = nil
        alertTriggeredAt = nil
        alertFlashOn = false
        alertFlashTimer?.invalidate()
        alertFlashTimer = nil
        alertSoundTimer?.invalidate()
        alertSoundTimer = nil
        GoldPriceLog.alertDismissed()
    }

    var alertDescription: String? {
        guard let price = alertPrice else { return nil }
        switch alertCurrency {
        case .usdPerOunce:
            return "\(GoldPriceFormatting.usd(price)) / OZ"
        case .cnyPerGram:
            return "\(GoldPriceFormatting.rmb(price)) / 克"
        }
    }

    /// 提醒价转换为 USD/oz（图表统一用 pricePerOunce）
    var alertPriceInUSD: Double? {
        guard let alertPrice else { return nil }
        switch alertCurrency {
        case .usdPerOunce:
            return alertPrice
        case .cnyPerGram:
            guard let rate = quote?.usdToCNYRate, rate > 0 else { return nil }
            return (alertPrice * GoldPriceFormatting.gramsPerTroyOunce) / rate
        }
    }

    private var previousCNYForAlert: Double?

    private func checkAlert(from previousQuote: GoldQuote?, to newQuote: GoldQuote) {
        guard let target = alertPrice, !alertTriggered else {
            GoldPriceLog.debug("Alert check skipped | alertPrice=\(alertPrice?.description ?? "nil") triggered=\(alertTriggered)")
            return
        }

        let prevPrice: Double?
        let currPrice: Double
        switch alertCurrency {
        case .usdPerOunce:
            prevPrice = previousQuote?.pricePerOunce ?? previousCNYForAlert
            currPrice = newQuote.pricePerOunce
            previousCNYForAlert = currPrice
        case .cnyPerGram:
            prevPrice = previousQuote?.pricePerGramCNY ?? previousCNYForAlert
            guard let currCNY = newQuote.pricePerGramCNY else {
                GoldPriceLog.warn("Alert check aborted | CNY rate unavailable")
                return
            }
            currPrice = currCNY
            previousCNYForAlert = currPrice
        }

        GoldPriceLog.alertCheck(previous: prevPrice, current: currPrice, target: target, currency: alertCurrency.displayName)

        guard let prev = prevPrice else { return }

        let crossed = (prev - target) * (currPrice - target) <= 0
            && abs(currPrice - target) < max(target * 0.02, 1.0)

        guard crossed else { return }

        GoldPriceLog.alertTriggered(price: currPrice, currency: alertCurrency.displayName)
        let now = Date()
        let timeStr = GoldPriceFormatting.shortTime(now)
        alertTriggered = true
        alertTriggeredAt = now
        alertFlashOn = true
        alertFlashTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.alertFlashOn.toggle()
            }
        }
        switch alertCurrency {
        case .usdPerOunce:
            alertTriggeredMessage = "金价已到达 \(GoldPriceFormatting.usd(currPrice)) / OZ\n触发时间：\(GoldPriceFormatting.fullTime(now))"
        case .cnyPerGram:
            alertTriggeredMessage = "金价已到达 \(GoldPriceFormatting.rmb(currPrice)) / 克\n触发时间：\(GoldPriceFormatting.fullTime(now))"
        }
        NSSound(named: .init("Glass"))?.play()
        alertSoundTimer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in
            NSSound(named: .init("Glass"))?.play()
        }

        let record = GoldQuote.AlertRecord(
            targetPrice: target,
            triggeredPrice: currPrice,
            currency: alertCurrency == .cnyPerGram ? "RMB" : "USD",
            timestamp: now
        )
        alertHistory.insert(record, at: 0)
        if alertHistory.count > 50 { alertHistory.removeLast() }
        persistAlertHistory()

        clearAlert()
    }

    func changeSource(to newSource: GoldPriceSourcePreference) async {
        guard newSource != selectedSource else {
            await refresh()
            return
        }

        let oldName = selectedSource.displayName
        selectedSource = newSource
        GoldPriceLog.sourceChanged(from: oldName, to: newSource.displayName)
        userDefaults.set(newSource.rawValue, forKey: Self.sourcePreferenceKey)
        refreshSequence += 1
        history.removeAll()
        quote = nil
        errorMessage = nil

        while isRefreshing {
            try? await Task.sleep(for: .milliseconds(50))
        }

        await refresh()
    }

    var sessionHigh: Double? {
        history.map(\.pricePerOunce).max()
    }

    var sessionLow: Double? {
        history.map(\.pricePerOunce).min()
    }

    var sessionMove: String? {
        guard let first = history.first?.pricePerOunce, let last = history.last?.pricePerOunce else {
            return nil
        }

        return GoldPriceFormatting.sessionMoveText(from: first, to: last)
    }

    var sessionChangePercent: Double? {
        guard let first = history.first?.pricePerOunce, let last = history.last?.pricePerOunce else {
            return nil
        }

        return GoldPriceFormatting.signedPercent(from: first, to: last)
    }

    var latestPriceText: String {
        guard let quote else {
            return "--"
        }

        return GoldPriceFormatting.usd(quote.pricePerOunce)
    }

    var latestPerGramText: String {
        guard let quote else {
            return "--"
        }

        return GoldPriceFormatting.usd(quote.pricePerGram)
    }

    var latestPriceCNYText: String {
        guard let quote, let value = quote.pricePerOunceCNY else {
            return "--"
        }

        return GoldPriceFormatting.rmb(value)
    }

    var latestPerGramCNYText: String {
        guard let quote, let value = quote.pricePerGramCNY else {
            return "--"
        }

        return GoldPriceFormatting.rmb(value)
    }

    var latestUpdatedText: String? {
        guard let fetchedAt = quote?.fetchedAt else {
            return nil
        }

        return GoldPriceFormatting.shortTime(fetchedAt)
    }

    var menuBarTitle: String {
        guard let quote else {
            return "Gold"
        }

        switch preferredCurrency {
        case .usdPerOunce:
            return GoldPriceFormatting.menuBarPrice(quote.pricePerOunce)
        case .cnyPerGram:
            if let cny = quote.pricePerGramCNY {
                return GoldPriceFormatting.menuBarCNYPrice(cny)
            }
            return GoldPriceFormatting.menuBarPrice(quote.pricePerOunce)
        }
    }

    var compactHistory: [GoldPricePoint] {
        historyPoints(within: Self.compactHistoryWindow)
    }

    var chartHistory: [GoldPricePoint] {
        historyPoints(within: Self.chartHistoryWindow)
    }

    var sourceName: String {
        quote?.sourceName ?? selectedSource.displayName
    }

    private static func loadSourcePreference(from userDefaults: UserDefaults) -> GoldPriceSourcePreference {
        guard
            let rawValue = userDefaults.string(forKey: sourcePreferenceKey),
            let preference = GoldPriceSourcePreference(rawValue: rawValue)
        else {
            return .automatic
        }

        return preference
    }

    private func persistAlertHistory() {
        guard let data = try? JSONEncoder().encode(alertHistory) else { return }
        userDefaults.set(data, forKey: Self.alertHistoryKey)
    }

    private static func loadAlertHistory(from userDefaults: UserDefaults) -> [GoldQuote.AlertRecord] {
        guard let data = userDefaults.data(forKey: alertHistoryKey),
              let records = try? JSONDecoder().decode([GoldQuote.AlertRecord].self, from: data) else {
            return []
        }
        return records
    }

    private static func loadCurrencyPreference(from userDefaults: UserDefaults) -> GoldPriceCurrencyPreference {
        guard
            let rawValue = userDefaults.string(forKey: currencyPreferenceKey),
            let preference = GoldPriceCurrencyPreference(rawValue: rawValue)
        else {
            return .cnyPerGram
        }

        return preference
    }

    private func apply(_ quote: GoldQuote) {
        let previousQuote = self.quote

        GoldPriceLog.currentPriceInfo(
            usd: quote.pricePerOunce,
            cnyPerGram: quote.pricePerGramCNY,
            source: quote.sourceName,
            alert: alertPrice
        )

        checkAlert(from: previousQuote, to: quote)

        self.quote = quote

        guard shouldAppendHistoryPoint(for: quote, previousQuote: previousQuote) else {
            return
        }

        // Chart x-values must stay strictly increasing. Upstream timestamps can
        // repeat or move backward, which makes the line fold onto itself.
        let point = GoldPricePoint(
            timestamp: nextHistoryTimestamp(),
            pricePerOunce: quote.pricePerOunce
        )
        history.append(point)

        if history.count > Self.maxHistoryPoints {
            history.removeFirst(history.count - Self.maxHistoryPoints)
        }
    }

    private func shouldAppendHistoryPoint(for quote: GoldQuote, previousQuote: GoldQuote?) -> Bool {
        guard let previousQuote else {
            return true
        }

        return previousQuote.sourceUpdatedAt != quote.sourceUpdatedAt
            || previousQuote.pricePerOunce != quote.pricePerOunce
            || previousQuote.bidPerOunce != quote.bidPerOunce
            || previousQuote.askPerOunce != quote.askPerOunce
            || previousQuote.sourceName != quote.sourceName
    }

    private func historyPoints(within window: TimeInterval) -> [GoldPricePoint] {
        guard let latestTimestamp = history.last?.timestamp else {
            return []
        }

        // Keep the chart frozen until a fresh upstream sample is appended.
        let cutoff = latestTimestamp.addingTimeInterval(-window)
        return history.filter { $0.timestamp >= cutoff }
    }

    private func nextHistoryTimestamp() -> Date {
        let now = Date()

        guard let lastTimestamp = history.last?.timestamp, now <= lastTimestamp else {
            return now
        }

        return lastTimestamp.addingTimeInterval(Self.minimumHistoryStep)
    }

    // MARK: - Multi-Source Sync

    func syncMultiSource() {
        Task {
            let quotes = await dataSourceManager.quotes
            let counts = await dataSourceManager.db.countAllPoints()
            let corr = await dataSourceManager.correlations
            await MainActor.run {
                sourceQuotes = quotes
                otherSourceItems = buildOtherItems(quotes: quotes)
                dataPointCounts = counts
                dataSyncedAt = Date()
                correlations = corr
                let totalPoints = counts.values.reduce(0, +)
                isBackfilling = totalPoints < 365 * 4 && !quotes.isEmpty
            }
        }
    }

    private func buildOtherItems(quotes: [String: DataSourceQuote]) -> [OtherSourceItem] {
        // 从黄金报价里拿汇率
        let usdToCNYRate = quotes["gold"]?.usdToCNYRate

        let silverItem: OtherSourceItem
        if let silver = quotes["silver"] {
            let cnyPerGram: String
            if let rate = usdToCNYRate, rate > 0 {
                let rmb = silver.price * rate / 31.1035
                cnyPerGram = String(format: "%.2f", rmb)
            } else {
                cnyPerGram = "--"
            }
            silverItem = OtherSourceItem(id: "silver", name: "白银", priceText: cnyPerGram, unit: "¥/克")
        } else {
            silverItem = OtherSourceItem(id: "silver", name: "白银", priceText: "--", unit: "¥/克")
        }

        let dxyItem = OtherSourceItem(
            id: "dxy", name: "美元指数",
            priceText: quotes["dxy"].map { String(format: "%.2f", $0.price) } ?? "--",
            unit: "指数"
        )

        let ustItem = OtherSourceItem(
            id: "ust10y", name: "10Y美债",
            priceText: quotes["ust10y"].map { String(format: "%.2f%%", $0.price) } ?? "--",
            unit: "年化收益率"
        )

        let oilItem = OtherSourceItem(
            id: "oil", name: "原油",
            priceText: quotes["oil"].map { String(format: "%.2f", $0.price) } ?? "--",
            unit: "USD/桶"
        )

        let fxItem = OtherSourceItem(
            id: "usdcny", name: "汇率",
            priceText: quotes["usdcny"].map { String(format: "%.4f", $0.price) } ?? "--",
            unit: "CNY/USD"
        )

        return [silverItem, oilItem, fxItem, dxyItem, ustItem]
    }

    private func startMultiSourceSync() {
        Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.syncMultiSource()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
}
