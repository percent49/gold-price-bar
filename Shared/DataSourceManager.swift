import Foundation

actor DataSourceManager {
    static let shared = DataSourceManager()

    private var sources: [any DataSource] = []
    private var refreshTasks: [String: Task<Void, Never>] = [:]
    private var backfillTasks: [String: Task<Void, Never>] = [:]
    let db: DatabaseManager
    private let engine: CorrelationEngine

    private var _quotes: [String: DataSourceQuote] = [:]
    var quotes: [String: DataSourceQuote] { _quotes }

    // 渐进式回填：每天拉 90 天数据，间隔 1 分钟，不触发限流
    private nonisolated static let backfillChunkDays = 90
    private nonisolated static let backfillCooldownSeconds: TimeInterval = 60

    // 实时拉取：连续失败上限和冷却期
    private nonisolated static let maxPollRetries = 3
    private nonisolated static let pollCooldownSeconds: TimeInterval = 300  // 5 分钟

    init(db: DatabaseManager = .shared) {
        self.db = db
        self.engine = CorrelationEngine(db: db)
    }

    func register(_ source: any DataSource) async throws {
        sources.append(source)
        try await db.registerSource(DataSourceInfo(
            id: source.id, name: source.name, unit: source.unit, enabled: source.enabled
        ))
    }

    func startAll() {
        // 错开启动：同 API 数据源之间加 5s 间隔，避免并发触发 FRED 限流
        var delay: TimeInterval = 0
        for source in sources where source.enabled {
            let src = source
            let d = delay
            Task {
                try? await Task.sleep(for: .seconds(d))
                startPolling(src)
            }
            delay += (src.id == "usdcny" || src.id == "dxy" || src.id == "ust10y") ? 5 : 1
        }
    }

    func stopAll() {
        for (_, task) in refreshTasks {
            task.cancel()
        }
        refreshTasks.removeAll()
    }

    func startProgressiveBackfill(yearsBack: Int = 20) {
        // 启动后快速检查缺口，每个源间隔 8s 避免并发限流
        var delay: TimeInterval = 5
        for source in sources where source.enabled {
            let src = source
            let d = delay
            Task {
                try? await Task.sleep(for: .seconds(d))
                startBackfillTask(for: src, yearsBack: yearsBack)
            }
            delay += 8
        }
    }

    func stopBackfill() {
        for (_, task) in backfillTasks {
            task.cancel()
        }
        backfillTasks.removeAll()
    }

    // MARK: - Private: Progressive Backfill

    private func startBackfillTask(for source: any DataSource, yearsBack: Int) {
        let sourceID = source.id
        backfillTasks[sourceID]?.cancel()

        backfillTasks[sourceID] = Task { [weak self] in
            guard let self else { return }
            let calendar = Calendar.current
            let now = Date()
            let endDate = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: now) ?? now)
            let defaults = UserDefaults.standard
            let cursorKey = "backfill_cursor_\(sourceID)"

            // ── 阶段 1：补齐近期缺口（每次启动必做） ──
            // 从最新数据日期到昨天，如果有缺口就拉
            let oneDay: TimeInterval = 86400
            while !Task.isCancelled {
                let lastDate = await db.getLastDate(sourceID: sourceID) ?? endDate
                // 昨天之前如果缺了超过 1 天，补齐
                let yesterday = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -1, to: now) ?? now)
                guard lastDate < yesterday.addingTimeInterval(-oneDay) else { break }
                let gapFrom = max(lastDate, yesterday.addingTimeInterval(-oneDay * Double(Self.backfillChunkDays)))
                do {
                    let points = try await source.fetchHistory(from: gapFrom, to: yesterday)
                    if !points.isEmpty {
                        try await db.upsertDailyPrices(points)
                        GoldPriceLog.debug("缺口补齐 [\(sourceID)]: \(points.count)条 \(gapFrom) → \(yesterday)")
                    }
                } catch {
                    GoldPriceLog.warn("缺口补齐失败 [\(sourceID)]: \(error.localizedDescription)")
                }
                try? await Task.sleep(for: .seconds(30))
            }

            // ── 阶段 2：历史回填（从游标继续往深处拉） ──
            guard let targetFrom = calendar.date(byAdding: .year, value: -yearsBack, to: now) else { return }
            var cursor: Date
            if let saved = defaults.object(forKey: cursorKey) as? Date, saved > targetFrom {
                cursor = saved
            } else {
                cursor = endDate
            }

            while !Task.isCancelled && cursor > targetFrom {
                let chunkFrom = max(calendar.date(byAdding: .day, value: -Self.backfillChunkDays, to: cursor) ?? targetFrom, targetFrom)
                guard chunkFrom < cursor else { break }

                do {
                    let points = try await source.fetchHistory(from: chunkFrom, to: cursor)
                    if !points.isEmpty {
                        try await db.upsertDailyPrices(points)
                        GoldPriceLog.debug("回填成功 [\(sourceID)]: \(points.count)条 \(chunkFrom) → \(cursor)")
                    }
                    cursor = chunkFrom
                    defaults.set(cursor, forKey: cursorKey)
                } catch {
                    GoldPriceLog.warn("回填失败 [\(sourceID)] \(cursor): \(error.localizedDescription)")
                }

                try? await Task.sleep(for: .seconds(Self.backfillCooldownSeconds))
            }
        }
    }

    var correlations: [SourceCorrelation] {
        get async {
            return await computeCorrelations()
        }
    }

    func computeCorrelations(from: Date? = nil, to: Date? = nil) async -> [SourceCorrelation] {
        await engine.invalidateCache()
        let targetIDs = sources.filter { $0.id != "gold" && $0.enabled }.map { $0.id }
        return await engine.computeAll(baseSourceID: "gold", targetSourceIDs: targetIDs, from: from, to: to)
    }

    func refreshCorrelations() async {
        await engine.invalidateCache()
    }

    func getQuote(for sourceID: String) -> DataSourceQuote? {
        _quotes[sourceID]
    }

    var registeredSources: [DataSourceInfo] {
        sources.map { DataSourceInfo(id: $0.id, name: $0.name, unit: $0.unit, enabled: $0.enabled) }
    }

    // MARK: - Private

    private func startPolling(_ source: any DataSource) {
        let sourceID = source.id
        refreshTasks[sourceID]?.cancel()

        refreshTasks[sourceID] = Task { [weak self] in
            guard let self else { return }
            var retryCount = 0

            while !Task.isCancelled {
                do {
                    let quote = try await source.fetchQuote()
                    await self.updateQuote(quote, for: sourceID)
                    if retryCount > 0 {
                        GoldPriceLog.debug("数据源 [\(sourceID)] 恢复，之前连续失败 \(retryCount) 次")
                    }
                    retryCount = 0
                    await self.maybeUpsertDailyPrice(quote)
                } catch {
                    retryCount += 1
                    if retryCount > Self.maxPollRetries {
                        await self.clearQuote(for: sourceID)
                        GoldPriceLog.warn("数据源 [\(sourceID)] 连续失败 \(Self.maxPollRetries) 次，进入 \(Int(Self.pollCooldownSeconds / 60)) 分钟冷却")
                        try? await Task.sleep(for: .seconds(Self.pollCooldownSeconds))
                        retryCount = 0
                        continue
                    }
                    GoldPriceLog.warn("数据源 [\(sourceID)] 拉取失败 (重试 \(retryCount)/\(Self.maxPollRetries)): \(error.localizedDescription)")
                }

                let interval = source.refreshInterval
                // 成功 → 正常间隔；失败 → 指数退避 (10s/20s/40s)，不超过正常间隔
                let sleepSeconds: Double = retryCount > 0
                    ? min(pow(2.0, Double(retryCount - 1)) * 10, interval)
                    : interval
                try? await Task.sleep(for: .seconds(sleepSeconds))
            }
        }
    }

    private func updateQuote(_ quote: DataSourceQuote, for sourceID: String) {
        _quotes[sourceID] = quote
    }

    private func clearQuote(for sourceID: String) {
        _quotes[sourceID] = nil
    }

    private func maybeUpsertDailyPrice(_ quote: DataSourceQuote) async {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let point = DailyPricePoint(
            sourceID: quote.sourceID,
            date: Date(),
            open: quote.price,
            high: quote.price,
            low: quote.price,
            close: quote.price
        )
        try? await db.upsertDailyPrice(point)
    }
}
