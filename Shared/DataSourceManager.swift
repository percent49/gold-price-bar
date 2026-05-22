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

    // 渐进式回填：每天拉 90 天数据，间隔 5 分钟，不触发限流
    private nonisolated static let backfillChunkDays = 90
    private nonisolated static let backfillCooldownSeconds: TimeInterval = 60

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
        for source in sources where source.enabled {
            startPolling(source)
        }
    }

    func stopAll() {
        for (_, task) in refreshTasks {
            task.cancel()
        }
        refreshTasks.removeAll()
    }

    func startProgressiveBackfill(yearsBack: Int = 20) {
        for source in sources where source.enabled {
            startBackfillTask(for: source, yearsBack: yearsBack)
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
            let to = Date()
            guard let targetFrom = calendar.date(byAdding: .year, value: -yearsBack, to: to) else { return }
            let yesterday = calendar.date(byAdding: .day, value: -1, to: to) ?? to

            // 用独立游标跟踪回填进度，不受实时数据干扰
            let cursorKey = "backfill_cursor_\(sourceID)"
            let defaults = UserDefaults.standard

            var cursor: Date
            if let saved = defaults.object(forKey: cursorKey) as? Date {
                cursor = saved
            } else {
                // 首次：从 20 年前开始
                cursor = targetFrom
            }

            while !Task.isCancelled && cursor < yesterday {
                let chunkTo = min(calendar.date(byAdding: .day, value: Self.backfillChunkDays, to: cursor) ?? yesterday, yesterday)
                guard cursor < chunkTo else { break }

                do {
                    let points = try await source.fetchHistory(from: cursor, to: chunkTo)
                    if !points.isEmpty {
                        try await db.upsertDailyPrices(points)
                    }
                } catch {
                    // 静默失败，等下一轮重试
                }

                cursor = chunkTo
                defaults.set(cursor, forKey: cursorKey)
                try? await Task.sleep(for: .seconds(Self.backfillCooldownSeconds))
            }
        }
    }

    var correlations: [SourceCorrelation] {
        get async {
            let targetIDs = sources.filter { $0.id != "gold" && $0.enabled }.map { $0.id }
            return await engine.computeAll(baseSourceID: "gold", targetSourceIDs: targetIDs)
        }
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
                    retryCount = 0
                    await self.maybeUpsertDailyPrice(quote)
                } catch {
                    retryCount += 1
                    if retryCount > 3 {
                        await self.clearQuote(for: sourceID)
                    }
                    GoldPriceLog.warn("数据源 [\(sourceID)] 拉取失败 (重试 \(retryCount)/3): \(error.localizedDescription)")
                }

                let interval = source.refreshInterval
                let backoff = min(Double(retryCount) * interval, 60)
                try? await Task.sleep(for: .seconds(interval + backoff))
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
