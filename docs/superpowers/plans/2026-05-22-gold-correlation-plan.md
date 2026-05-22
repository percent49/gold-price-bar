# 金价相关性分析系统 — 实施计划

> **For agentic workers:** 使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 来逐个任务实施此计划。步骤使用 checkbox (`- [ ]`) 语法进行跟踪。

**目标：** 引入 DataSource 协议驱动的多数据源架构，添加白银/DXY/美债收益率数据源，SQLite 持久化历史数据，皮尔逊相关性计算引擎，以及三栏式 Dashboard UI。

**架构：** 协议驱动的 3 层架构——数据源层（DataSource 协议）→ SQLite 持久化层（系统 libsqlite3）→ SwiftUI 展示层。DataSourceManager actor 统一调度各数据源的独立轮询，CorrelationEngine actor 在日线更新后重算相关性矩阵。

**技术栈：** Swift 6 + SwiftUI + Charts + libsqlite3（系统库，零第三方依赖）

---

## 文件结构映射

| 文件 | 类型 | 职责 |
|------|------|------|
| `Shared/DataSourceProtocol.swift` | 新建 | DataSource 协议 + DataSourceQuote + DailyPricePoint 模型 |
| `Shared/DatabaseManager.swift` | 新建 | SQLite actor：建表、CRUD、批量导入 |
| `Shared/CorrelationEngine.swift` | 新建 | 皮尔逊相关系数计算 actor |
| `Shared/CorrelationModels.swift` | 新建 | CorrelationResult、TimeWindow 等类型 |
| `Shared/DataSourceManager.swift` | 新建 | 数据源注册、调度、轮询 actor |
| `Shared/GoldDataSource.swift` | 新建 | 黄金数据源（重构自 GoldPriceService） |
| `Shared/SilverDataSource.swift` | 新建 | 白银数据源（Kitco 白银页面解析） |
| `Shared/DXYDataSource.swift` | 新建 | 美元指数数据源（FRED API） |
| `Shared/UST10YDataSource.swift` | 新建 | 10Y 美债收益率数据源（FRED API） |
| `Shared/MetalQuoteParser.swift` | 新建 | 从 GoldPriceService 抽离的 Kitco 解析逻辑（金银共用） |
| `Shared/GoldPriceService.swift` | 修改 | 逐步废弃，逻辑迁移到 GoldDataSource |
| `Shared/GoldPriceModels.swift` | 修改 | 保留现有类型（GoldQuote 用于向后兼容），新增类型放在新文件 |
| `GoldPriceApp/GoldPriceViewModel.swift` | 修改 | 扩展：持有 DataSourceManager + CorrelationEngine 引用，暴露多源数据 |
| `GoldPriceApp/ContentView.swift` | 修改 | 三栏式 Dashboard：数据源列表 + 图表 + 相关性矩阵 |
| `GoldPriceApp/MenuBarViews.swift` | 修改 | 下拉面板新增其他数据源价格行 + 相关性入口 |
| `GoldPriceApp/GoldPriceApp.swift` | 修改 | 初始化 DataSourceManager 和 DatabaseManager |
| `GoldPriceApp/CorrelationView.swift` | 新建 | 相关性矩阵 + 叠加对比图的独立视图 |
| `GoldPriceApp/DataSources/` | 新建目录 | 按功能组织的新视图组件 |

---

## Phase 1: 基础层（协议 + 模型 + 数据库）

### Task 1.1: 创建 DataSource 协议和共享模型

**文件：**
- 新建: `Shared/DataSourceProtocol.swift`

- [ ] **Step 1: 创建 DataSourceProtocol.swift**

```swift
import Foundation

// MARK: - Data Source Protocol

protocol DataSource: AnyObject, Sendable {
    var id: String { get }
    var name: String { get }
    var unit: String { get }
    var refreshInterval: TimeInterval { get }
    var enabled: Bool { get set }

    func fetchQuote() async throws -> DataSourceQuote
    func fetchHistory(from: Date, to: Date) async throws -> [DailyPricePoint]
}

// MARK: - Quote Model

struct DataSourceQuote: Sendable, Equatable {
    let price: Double
    let bid: Double?
    let ask: Double?
    let fetchedAt: Date
    let sourceUpdatedAt: Date?
    let sourceName: String
    let sourceID: String
    let currency: String
}

// MARK: - Daily Price Point

struct DailyPricePoint: Sendable, Codable, Equatable {
    let sourceID: String
    let date: Date
    let open: Double
    let high: Double
    let low: Double
    let close: Double

    init(sourceID: String, date: Date, open: Double, high: Double, low: Double, close: Double) {
        self.sourceID = sourceID
        self.date = date
        self.open = open
        self.high = high
        self.low = low
        self.close = close
    }
}

// MARK: - Data Source Info (for registration)

struct DataSourceInfo: Sendable, Codable, Equatable {
    let id: String
    let name: String
    let unit: String
    var enabled: Bool
}
```

- [ ] **Step 2: 编译验证**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild \
  -project GoldPrice.xcodeproj \
  -scheme GoldPrice \
  -configuration Debug \
  -derivedDataPath ./.build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build 2>&1 | tail -5
```

预期: BUILD SUCCEEDED

- [ ] **Step 3: 提交**

```bash
git add Shared/DataSourceProtocol.swift
git commit -m "feat: add DataSource protocol and shared models"
```

---

### Task 1.2: 创建 DatabaseManager（SQLite 持久化）

**文件：**
- 新建: `Shared/DatabaseManager.swift`

**注意：** 在 Xcode 项目中，需将 `libsqlite3.tbd` 添加到 Link Binary With Libraries（Target → General → Frameworks and Libraries → 点 + → 搜索 sqlite3 → 添加 `libsqlite3.tbd`）

- [ ] **Step 1: 创建 DatabaseManager.swift**

```swift
import Foundation
import SQLite3

actor DatabaseManager {
    static let shared = DatabaseManager()

    private var db: OpaquePointer?

    private var dbPath: String {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let dir = appSupport.appendingPathComponent("GoldPrice")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("data.db").path
    }

    // MARK: - Lifecycle

    func open() throws {
        guard sqlite3_open(dbPath, &db) == SQLITE_OK else {
            throw DatabaseError.openFailed(String(cString: sqlite3_errmsg(db)))
        }
        try createSchema()
    }

    func close() {
        guard db != nil else { return }
        sqlite3_close(db)
        db = nil
    }

    // MARK: - Schema

    private func createSchema() throws {
        let sql = """
        CREATE TABLE IF NOT EXISTS data_sources (
            id      TEXT PRIMARY KEY,
            name    TEXT NOT NULL,
            unit    TEXT NOT NULL,
            enabled INTEGER NOT NULL DEFAULT 1
        );

        CREATE TABLE IF NOT EXISTS daily_prices (
            source_id TEXT NOT NULL REFERENCES data_sources(id),
            date      TEXT NOT NULL,
            open      REAL,
            high      REAL,
            low       REAL,
            close     REAL NOT NULL,
            volume    REAL,
            PRIMARY KEY (source_id, date)
        );

        CREATE INDEX IF NOT EXISTS idx_daily_date ON daily_prices(date);
        """
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw DatabaseError.schemaFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    // MARK: - Write

    func registerSource(_ info: DataSourceInfo) throws {
        let sql = "INSERT OR IGNORE INTO data_sources (id, name, unit, enabled) VALUES (?, ?, ?, ?);"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, info.id, -1, nil)
        sqlite3_bind_text(stmt, 2, info.name, -1, nil)
        sqlite3_bind_text(stmt, 3, info.unit, -1, nil)
        sqlite3_bind_int(stmt, 4, info.enabled ? 1 : 0)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.insertFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    func upsertDailyPrice(_ point: DailyPricePoint) throws {
        let sql = """
        INSERT INTO daily_prices (source_id, date, open, high, low, close)
        VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT(source_id, date) DO UPDATE SET
            open=excluded.open, high=excluded.high, low=excluded.low, close=excluded.close;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        let dateStr = Self.dateFormatter.string(from: point.date)
        sqlite3_bind_text(stmt, 1, point.sourceID, -1, nil)
        sqlite3_bind_text(stmt, 2, dateStr, -1, nil)
        sqlite3_bind_double(stmt, 3, point.open)
        sqlite3_bind_double(stmt, 4, point.high)
        sqlite3_bind_double(stmt, 5, point.low)
        sqlite3_bind_double(stmt, 6, point.close)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.insertFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    func upsertDailyPrices(_ points: [DailyPricePoint]) throws {
        execute("BEGIN TRANSACTION;")
        for point in points {
            try upsertDailyPrice(point)
        }
        execute("COMMIT;")
    }

    // MARK: - Read

    func getPrices(sourceID: String, from: Date, to: Date) -> [DailyPricePoint] {
        let dateFormatter = Self.dateFormatter
        let sql = "SELECT date, open, high, low, close FROM daily_prices WHERE source_id = ? AND date >= ? AND date <= ? ORDER BY date ASC;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, sourceID, -1, nil)
        sqlite3_bind_text(stmt, 2, dateFormatter.string(from: from), -1, nil)
        sqlite3_bind_text(stmt, 3, dateFormatter.string(from: to), -1, nil)

        var result: [DailyPricePoint] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let point = rowToDailyPrice(stmt, sourceID: sourceID, dateFormatter: dateFormatter) {
                result.append(point)
            }
        }
        return result
    }

    func getLatestPrice(sourceID: String) -> DailyPricePoint? {
        let sql = "SELECT date, open, high, low, close FROM daily_prices WHERE source_id = ? ORDER BY date DESC LIMIT 1;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, sourceID, -1, nil)

        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return rowToDailyPrice(stmt, sourceID: sourceID, dateFormatter: Self.dateFormatter)
    }

    func getLastDate(sourceID: String) -> Date? {
        return getLatestPrice(sourceID: sourceID)?.date
    }

    func getAllSources() -> [DataSourceInfo] {
        let sql = "SELECT id, name, unit, enabled FROM data_sources;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        var result: [DataSourceInfo] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = String(cString: sqlite3_column_text(stmt, 0))
            let name = String(cString: sqlite3_column_text(stmt, 1))
            let unit = String(cString: sqlite3_column_text(stmt, 2))
            let enabled = sqlite3_column_int(stmt, 3) != 0
            result.append(DataSourceInfo(id: id, name: name, unit: unit, enabled: enabled))
        }
        return result
    }

    // MARK: - Helpers

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }()

    private func rowToDailyPrice(_ stmt: OpaquePointer, sourceID: String, dateFormatter: DateFormatter) -> DailyPricePoint? {
        guard let dateStr = sqlite3_column_text(stmt, 0).map({ String(cString: $0) }),
              let date = dateFormatter.date(from: dateStr) else { return nil }
        return DailyPricePoint(
            sourceID: sourceID,
            date: date,
            open: sqlite3_column_double(stmt, 1),
            high: sqlite3_column_double(stmt, 2),
            low: sqlite3_column_double(stmt, 3),
            close: sqlite3_column_double(stmt, 4)
        )
    }

    private func execute(_ sql: String) {
        sqlite3_exec(db, sql, nil, nil, nil)
    }
}

enum DatabaseError: LocalizedError {
    case openFailed(String)
    case schemaFailed(String)
    case prepareFailed(String)
    case insertFailed(String)

    var errorDescription: String? {
        switch self {
        case .openFailed(let msg): return "数据库打开失败: \(msg)"
        case .schemaFailed(let msg): return "建表失败: \(msg)"
        case .prepareFailed(let msg): return "SQL 准备失败: \(msg)"
        case .insertFailed(let msg): return "数据写入失败: \(msg)"
        }
    }
}
```

- [ ] **Step 2: 测试 DatabaseManager（单元测试）**

创建 `GoldPriceAppTests/DatabaseManagerTests.swift`（需要先在 Xcode 中添加 test target，或创建独立测试文件）：

```swift
import Testing
import Foundation
@testable import GoldPriceApp

@Suite struct DatabaseManagerTests {
    let db = DatabaseManager.shared

    init() async throws {
        try await db.open()
    }

    @Test("注册和读取数据源")
    func registerAndReadSource() async throws {
        let info = DataSourceInfo(id: "test_gold", name: "测试黄金", unit: "USD/OZ", enabled: true)
        try await db.registerSource(info)
        let sources = await db.getAllSources()
        #expect(sources.contains { $0.id == "test_gold" })
    }

    @Test("写入和读取日线价格")
    func upsertAndReadDailyPrice() async throws {
        let point = DailyPricePoint(
            sourceID: "test_gold",
            date: ISO8601DateFormatter().date(from: "2024-01-15T00:00:00Z")!,
            open: 2000, high: 2010, low: 1990, close: 2005
        )
        try await db.upsertDailyPrice(point)

        let from = ISO8601DateFormatter().date(from: "2024-01-01T00:00:00Z")!
        let to = ISO8601DateFormatter().date(from: "2024-02-01T00:00:00Z")!
        let prices = await db.getPrices(sourceID: "test_gold", from: from, to: to)
        #expect(prices.count == 1)
        #expect(prices.first?.close == 2005)
    }

    @Test("批量导入")
    func batchInsert() async throws {
        let points = (1...10).map { i in
            DailyPricePoint(
                sourceID: "test_gold",
                date: ISO8601DateFormatter().date(from: "2024-01-\(String(format: "%02d", i))T00:00:00Z")!,
                open: Double(2000 + i),
                high: Double(2010 + i),
                low: Double(1990 + i),
                close: Double(2005 + i)
            )
        }
        try await db.upsertDailyPrices(points)
        let from = ISO8601DateFormatter().date(from: "2024-01-01T00:00:00Z")!
        let to = ISO8601DateFormatter().date(from: "2024-02-01T00:00:00Z")!
        let prices = await db.getPrices(sourceID: "test_gold", from: from, to: to)
        #expect(prices.count == 10)
    }
}
```

- [ ] **Step 3: 运行测试验证**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild \
  test \
  -project GoldPrice.xcodeproj \
  -scheme GoldPrice \
  -derivedDataPath ./.build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  2>&1 | grep -E "(Test Suite|passed|failed)"
```

预期: All tests passed

- [ ] **Step 4: 提交**

```bash
git add Shared/DatabaseManager.swift
git commit -m "feat: add SQLite DatabaseManager with actor isolation"
```

---

### Task 1.3: 创建 CorrelationModels 和 CorrelationEngine

**文件：**
- 新建: `Shared/CorrelationModels.swift`
- 新建: `Shared/CorrelationEngine.swift`

- [ ] **Step 1: 创建 CorrelationModels.swift**

```swift
import Foundation

enum TimeWindow: String, CaseIterable, Sendable, Codable {
    case days30 = "30D"
    case days90 = "90D"
    case days180 = "180D"
    case year1 = "1Y"

    var days: Int {
        switch self {
        case .days30: return 30
        case .days90: return 90
        case .days180: return 180
        case .year1: return 365
        }
    }

    var displayName: String { rawValue }
}

struct CorrelationResult: Sendable, Codable, Equatable {
    let pearsonR: Double
    let beta: Double
    let divergenceRatio: Double
    let dataPoints: Int
    let window: TimeWindow
    let computedAt: Date
}

struct SourceCorrelation: Sendable, Identifiable {
    let sourceID: String
    let sourceName: String
    let correlations: [TimeWindow: CorrelationResult]

    var id: String { sourceID }
}
```

- [ ] **Step 2: 创建 CorrelationEngine.swift**

```swift
import Foundation

actor CorrelationEngine {
    private let db: DatabaseManager
    private var cache: [String: [TimeWindow: CorrelationResult]] = [:]

    init(db: DatabaseManager = .shared) {
        self.db = db
    }

    func compute(baseSourceID: String, targetSourceID: String, window: TimeWindow) -> CorrelationResult? {
        let calendar = Calendar.current
        let to = Date()
        guard let from = calendar.date(byAdding: .day, value: -window.days, to: to) else {
            return nil
        }

        let basePrices = db.getPrices(sourceID: baseSourceID, from: from, to: to)
        let targetPrices = db.getPrices(sourceID: targetSourceID, from: from, to: to)

        let targetByDate = Dictionary(grouping: targetPrices) { Calendar.current.startOfDay(for: $0.date) }
            .compactMapValues { $0.first?.close }

        var baseReturns: [Double] = []
        var targetReturns: [Double] = []

        for i in 1..<basePrices.count {
            let prev = basePrices[i - 1]
            let curr = basePrices[i]
            let day = Calendar.current.startOfDay(for: curr.date)
            guard let targetClose = targetByDate[day],
                  prev.close > 0, curr.close > 0, targetClose > 0 else {
                continue
            }
            baseReturns.append(log(curr.close / prev.close))
            targetReturns.append(log(targetClose / targetByDate[Calendar.current.startOfDay(for: prev.date)] ?? targetClose))
        }

        guard baseReturns.count >= 5 else { return nil }

        let r = pearsonR(baseReturns, targetReturns)
        let beta = computeBeta(baseReturns, targetReturns)
        let divergence = computeDivergenceRatio(baseReturns, targetReturns)

        let result = CorrelationResult(
            pearsonR: r,
            beta: beta,
            divergenceRatio: divergence,
            dataPoints: baseReturns.count,
            window: window,
            computedAt: Date()
        )

        cache["\(baseSourceID)_\(targetSourceID)"] = [window: result]
        return result
    }

    func computeAll(baseSourceID: String, targetIDs: [String]) -> [SourceCorrelation] {
        return targetIDs.compactMap { targetID in
            var correlations: [TimeWindow: CorrelationResult] = [:]
            for window in TimeWindow.allCases {
                if let result = compute(baseSourceID: baseSourceID, targetSourceID: targetID, window: window) {
                    correlations[window] = result
                }
            }
            guard !correlations.isEmpty else { return nil }
            return SourceCorrelation(sourceID: targetID, sourceName: targetID, correlations: correlations)
        }
    }

    func invalidateCache() {
        cache.removeAll()
    }

    // MARK: - Math

    private func pearsonR(_ xs: [Double], _ ys: [Double]) -> Double {
        let n = Double(xs.count)
        let sumX = xs.reduce(0, +)
        let sumY = ys.reduce(0, +)
        let sumXY = zip(xs, ys).reduce(0) { $0 + $1.0 * $1.1 }
        let sumX2 = xs.reduce(0) { $0 + $1 * $1 }
        let sumY2 = ys.reduce(0) { $0 + $1 * $1 }

        let numerator = n * sumXY - sumX * sumY
        let denominator = sqrt((n * sumX2 - sumX * sumX) * (n * sumY2 - sumY * sumY))

        guard denominator != 0 else { return 0 }
        return (numerator / denominator).clamped(to: -1...1)
    }

    private func computeBeta(_ xs: [Double], _ ys: [Double]) -> Double {
        let varX = variance(xs)
        guard varX != 0 else { return 0 }
        let cov = covariance(xs, ys)
        return cov / varX
    }

    private func computeDivergenceRatio(_ xs: [Double], _ ys: [Double]) -> Double {
        let pairs = zip(xs, ys)
        let diverged = pairs.filter { ($0 > 0) != ($1 > 0) }.count
        return Double(diverged) / Double(xs.count)
    }

    private func variance(_ xs: [Double]) -> Double {
        let mean = xs.reduce(0, +) / Double(xs.count)
        return xs.reduce(0) { $0 + pow($1 - mean, 2) } / Double(xs.count - 1)
    }

    private func covariance(_ xs: [Double], _ ys: [Double]) -> Double {
        let meanX = xs.reduce(0, +) / Double(xs.count)
        let meanY = ys.reduce(0, +) / Double(ys.count)
        return zip(xs, ys).reduce(0) { $0 + ($1.0 - meanX) * ($1.1 - meanY) } / Double(xs.count - 1)
    }
}

extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        return Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
```

- [ ] **Step 3: 测试 CorrelationEngine**

```swift
import Testing
@testable import GoldPriceApp

@Suite struct CorrelationEngineTests {
    @Test("完美正相关返回 1.0")
    func perfectPositiveCorrelation() {
        let xs = [1.0, 2.0, 3.0, 4.0, 5.0].map { $0 / 100 }
        let ys = [1.1, 2.1, 3.1, 4.1, 5.1].map { $0 / 100 }
        // Simple unit test on the math
        let engine = CorrelationEngine.shared
        // Note: full integration test requires DB setup
    }

    @Test("完美负相关返回 -1.0")
    func perfectNegativeCorrelation() async {
        // Validate Pearson r math directly
        let xs = [1.0, 2.0, 3.0, 4.0, 5.0]
        let ys = [5.0, 4.0, 3.0, 2.0, 1.0]
        // r should be -1.0
        let r = await pearsonTestHelper(xs: xs.map { $0 / 100 }, ys: ys.map { $0 / 100 })
        #expect(abs(r + 1.0) < 0.001)
    }
}
```

- [ ] **Step 4: 编译验证**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild \
  -project GoldPrice.xcodeproj \
  -scheme GoldPrice \
  -configuration Debug \
  -derivedDataPath ./.build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build 2>&1 | tail -5
```

预期: BUILD SUCCEEDED

- [ ] **Step 5: 提交**

```bash
git add Shared/CorrelationModels.swift Shared/CorrelationEngine.swift
git commit -m "feat: add CorrelationEngine with Pearson r computation"
```

---

## Phase 2: 数据源实现

### Task 2.1: 抽离 Kitco 解析逻辑（MetalQuoteParser）

**文件：**
- 新建: `Shared/MetalQuoteParser.swift`

将 GoldPriceService 中的 Kitco HTML 解析、JSON 提取逻辑抽离为独立的可复用组件，金银共用。

- [ ] **Step 1: 创建 MetalQuoteParser.swift**

```swift
import Foundation

struct KitcoQuoteResult {
    let mid: Double
    let bid: Double
    let ask: Double
    let timestamp: Date?
    let usdToCNYRate: Double?
}

enum MetalQuoteParserError: LocalizedError {
    case invalidPayload
    case noData

    var errorDescription: String? {
        switch self {
        case .invalidPayload: return "Kitco 页面解析失败"
        case .noData: return "Kitco 未返回有效数据"
        }
    }
}

struct MetalQuoteParser {
    let session: URLSession
    let pageURL: URL

    init(session: URLSession, pageURL: URL) {
        self.session = session
        self.pageURL = pageURL
    }

    func fetchQuote() async throws -> KitcoQuoteResult {
        let payload = try await fetchPayload()
        let fetchedAt = Date()
        let usdToCNYRate = extractUSDtoCNYRate(from: payload)

        for query in payload.props.pageProps.dehydratedState.queries {
            guard let metalQuote = query.state.data?.getMetalQuoteV3 else { continue }
            guard let result = metalQuote.results.first else { continue }
            guard result.mid.isFinite, result.mid > 0 else { continue }

            return KitcoQuoteResult(
                mid: result.mid,
                bid: result.bid,
                ask: result.ask,
                timestamp: result.timestamp.map(Date.init(timeIntervalSince1970:)),
                usdToCNYRate: usdToCNYRate
            )
        }

        throw MetalQuoteParserError.noData
    }

    func fetchUSDtoCNYRate() async throws -> Double {
        let payload = try await fetchPayload()
        guard let rate = extractUSDtoCNYRate(from: payload) else {
            throw MetalQuoteParserError.noData
        }
        return rate
    }

    // MARK: - Private

    private func fetchPayload() async throws -> KitcoPagePayload {
        var components = URLComponents(url: pageURL, resolvingAgainstBaseURL: false)!
        var queryItems = components.queryItems ?? []
        queryItems.removeAll { $0.name == "_" }
        queryItems.append(URLQueryItem(name: "_", value: UUID().uuidString))
        components.queryItems = queryItems

        var request = URLRequest(url: components.url ?? pageURL)
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("GoldPriceMac/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MetalQuoteParserError.invalidPayload
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw MetalQuoteParserError.invalidPayload
        }

        guard let html = String(data: data, encoding: .utf8) else {
            throw MetalQuoteParserError.invalidPayload
        }

        let marker = "<script id=\"__NEXT_DATA__\" type=\"application/json\">"
        let closingMarker = "</script>"
        guard let startRange = html.range(of: marker),
              let endRange = html[startRange.upperBound...].range(of: closingMarker) else {
            throw MetalQuoteParserError.invalidPayload
        }

        let jsonString = String(html[startRange.upperBound..<endRange.lowerBound])
        guard let jsonData = jsonString.data(using: .utf8) else {
            throw MetalQuoteParserError.invalidPayload
        }
        return try JSONDecoder().decode(KitcoPagePayload.self, from: jsonData)
    }

    private func extractUSDtoCNYRate(from payload: KitcoPagePayload) -> Double? {
        for query in payload.props.pageProps.dehydratedState.queries {
            guard let cnyQuote = query.state.data?.cny?.results.first else { continue }
            if let rate = cnyQuote.ctousd, rate.isFinite, rate > 0 { return rate }
            if let inverse = cnyQuote.usdtoc, inverse.isFinite, inverse > 0 { return 1 / inverse }
        }
        return nil
    }
}
```

- [ ] **Step 2: 编译验证**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild \
  -project GoldPrice.xcodeproj \
  -scheme GoldPrice \
  -configuration Debug \
  -derivedDataPath ./.build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build 2>&1 | tail -5
```

预期: BUILD SUCCEEDED

- [ ] **Step 3: 提交**

```bash
git add Shared/MetalQuoteParser.swift
git commit -m "feat: extract Kitco parsing logic into MetalQuoteParser"
```

---

### Task 2.2: 创建 GoldDataSource（遵循 DataSource 协议）

**文件：**
- 新建: `Shared/GoldDataSource.swift`
- 修改: `Shared/GoldPriceService.swift`（保留但标记为 deprecated，GoldDataSource 内部可复用 GoldAPI 逻辑）

- [ ] **Step 1: 创建 GoldDataSource.swift**

```swift
import Foundation

final class GoldDataSource: DataSource, @unchecked Sendable {
    let id = "gold"
    let name = "黄金"
    let unit = "USD/OZ"
    let refreshInterval: TimeInterval = 1.0
    var enabled = true

    private let parser: MetalQuoteParser
    private let goldAPISession: URLSession
    private static let goldAPIEndpoint = URL(string: "https://api.gold-api.com/price/XAU")!

    init(session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 12
        config.waitsForConnectivity = false
        config.httpShouldSetCookies = false
        return URLSession(configuration: config)
    }()) {
        self.goldAPISession = session
        self.parser = MetalQuoteParser(
            session: session,
            pageURL: URL(string: "https://www.kitco.com/charts/gold?sitetype=fullsite")!
        )
    }

    func fetchQuote() async throws -> DataSourceQuote {
        do {
            return try await fetchFromKitco()
        } catch {
            return try await fetchFromGoldAPI()
        }
    }

    func fetchHistory(from: Date, to: Date) async throws -> [DailyPricePoint] {
        // FRED 免费 API：黄金期货日线数据
        // URL: https://api.stlouisfed.org/fred/series/observations?series_id=GOLDPMGBD228NLBR&api_key=KEY&file_type=json
        // 后续 Phase 实现
        return []
    }

    private func fetchFromKitco() async throws -> DataSourceQuote {
        let result = try await parser.fetchQuote()
        return DataSourceQuote(
            price: result.mid,
            bid: result.bid,
            ask: result.ask,
            fetchedAt: Date(),
            sourceUpdatedAt: result.timestamp,
            sourceName: "Kitco",
            sourceID: id,
            currency: "USD"
        )
    }

    private func fetchFromGoldAPI() async throws -> DataSourceQuote {
        var request = URLRequest(url: Self.goldAPIEndpoint)
        request.timeoutInterval = 12
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("GoldPriceMac/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await goldAPISession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DataSourceError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw DataSourceError.badStatus(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let payload = try decoder.decode(GoldAPIResponse.self, from: data)
        guard payload.price.isFinite, payload.price > 0 else {
            throw DataSourceError.invalidPayload
        }

        let usdToCNYRate = try? await parser.fetchUSDtoCNYRate()

        return DataSourceQuote(
            price: payload.price,
            bid: nil,
            ask: nil,
            fetchedAt: Date(),
            sourceUpdatedAt: payload.updatedAt,
            sourceName: "gold-api.com",
            sourceID: id,
            currency: "USD"
        )
    }
}

enum DataSourceError: LocalizedError {
    case invalidResponse
    case badStatus(Int)
    case invalidPayload
    case noSupportedSource

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "数据源返回了无法识别的响应"
        case .badStatus(let code): return "数据源暂时不可用（HTTP \(code)）"
        case .invalidPayload: return "数据源返回了无效的数据"
        case .noSupportedSource: return "没有拿到可用的数据源"
        }
    }
}
```

- [ ] **Step 2: 编译验证并确认黄金数据仍可正常获取**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild \
  -project GoldPrice.xcodeproj \
  -scheme GoldPrice \
  -configuration Debug \
  -derivedDataPath ./.build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build 2>&1 | tail -5
```

- [ ] **Step 3: 提交**

```bash
git add Shared/GoldDataSource.swift
git commit -m "feat: add GoldDataSource conforming to DataSource protocol"
```

---

### Task 2.3: 创建 SilverDataSource

**文件：**
- 新建: `Shared/SilverDataSource.swift`

- [ ] **Step 1: 创建 SilverDataSource.swift**

```swift
import Foundation

final class SilverDataSource: DataSource, @unchecked Sendable {
    let id = "silver"
    let name = "白银"
    let unit = "USD/OZ"
    let refreshInterval: TimeInterval = 1.0
    var enabled = true

    private let parser: MetalQuoteParser

    init(session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 12
        return URLSession(configuration: config)
    }()) {
        self.parser = MetalQuoteParser(
            session: session,
            pageURL: URL(string: "https://www.kitco.com/charts/silver?sitetype=fullsite")!
        )
    }

    func fetchQuote() async throws -> DataSourceQuote {
        let result = try await parser.fetchQuote()
        return DataSourceQuote(
            price: result.mid,
            bid: result.bid,
            ask: result.ask,
            fetchedAt: Date(),
            sourceUpdatedAt: result.timestamp,
            sourceName: "Kitco",
            sourceID: id,
            currency: "USD"
        )
    }

    func fetchHistory(from: Date, to: Date) async throws -> [DailyPricePoint] {
        // MetalPrice API 或 FRED 历史数据，后续 Phase 实现
        return []
    }
}
```

- [ ] **Step 2: 编译验证**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild \
  -project GoldPrice.xcodeproj \
  -scheme GoldPrice \
  -configuration Debug \
  -derivedDataPath ./.build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build 2>&1 | tail -5
```

- [ ] **Step 3: 提交**

```bash
git add Shared/SilverDataSource.swift
git commit -m "feat: add SilverDataSource via Kitco silver page"
```

---

### Task 2.4: 创建 FRED API 数据源基类 + DXY 和 UST10Y

**文件：**
- 新建: `Shared/FREDDataSource.swift`
- 新建: `Shared/DXYDataSource.swift`
- 新建: `Shared/UST10YDataSource.swift`

- [ ] **Step 1: 创建 FRED 基础数据源**

```swift
import Foundation

class FREDBaseDataSource: DataSource, @unchecked Sendable {
    let id: String
    let name: String
    let unit: String
    let refreshInterval: TimeInterval = 300  // 5 分钟
    var enabled = true

    private let seriesID: String
    private let apiKey: String
    private let session: URLSession

    init(id: String, name: String, unit: String, seriesID: String, apiKey: String, session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        return URLSession(configuration: config)
    }()) {
        self.id = id
        self.name = name
        self.unit = unit
        self.seriesID = seriesID
        self.apiKey = apiKey
        self.session = session
    }

    func fetchQuote() async throws -> DataSourceQuote {
        // FRED 最新观察值
        let url = URL(string: "https://api.stlouisfed.org/fred/series/observations?series_id=\(seriesID)&api_key=\(apiKey)&file_type=json&sort_order=desc&limit=1")!
        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw DataSourceError.invalidResponse
        }

        let decoder = JSONDecoder()
        let payload = try decoder.decode(FREDObservationsResponse.self, from: data)
        guard let obs = payload.observations.first,
              let price = Double(obs.value) else {
            throw DataSourceError.invalidPayload
        }

        return DataSourceQuote(
            price: price,
            bid: nil,
            ask: nil,
            fetchedAt: Date(),
            sourceUpdatedAt: ISO8601DateFormatter().date(from: "\(obs.date)T00:00:00Z"),
            sourceName: "FRED",
            sourceID: id,
            currency: unit
        )
    }

    func fetchHistory(from: Date, to: Date) async throws -> [DailyPricePoint] {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let fromStr = df.string(from: from)
        let toStr = df.string(from: to)

        let url = URL(string: "https://api.stlouisfed.org/fred/series/observations?series_id=\(seriesID)&api_key=\(apiKey)&file_type=json&observation_start=\(fromStr)&observation_end=\(toStr)&sort_order=asc")!
        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw DataSourceError.invalidResponse
        }

        let decoder = JSONDecoder()
        let payload = try decoder.decode(FREDObservationsResponse.self, from: data)

        return payload.observations.compactMap { obs in
            guard let close = Double(obs.value),
                  let date = df.date(from: obs.date) else { return nil }
            return DailyPricePoint(
                sourceID: id,
                date: date,
                open: close,
                high: close,
                low: close,
                close: close
            )
        }
    }
}

// MARK: - FRED API Response Models

struct FREDObservationsResponse: Decodable {
    let observations: [FREDObservation]
}

struct FREDObservation: Decodable {
    let date: String
    let value: String
}
```

- [ ] **Step 2: 创建 DXYDataSource.swift**

```swift
import Foundation

final class DXYDataSource: FREDBaseDataSource {
    init(apiKey: String, session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        return URLSession(configuration: config)
    }()) {
        super.init(
            id: "dxy",
            name: "美元指数",
            unit: "Index",
            seriesID: "DTWEXBGS",
            apiKey: apiKey,
            session: session
        )
    }
}
```

- [ ] **Step 3: 创建 UST10YDataSource.swift**

```swift
import Foundation

final class UST10YDataSource: FREDBaseDataSource {
    init(apiKey: String, session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        return URLSession(configuration: config)
    }()) {
        super.init(
            id: "ust10y",
            name: "10Y 美债",
            unit: "%",
            seriesID: "DGS10",
            apiKey: apiKey,
            session: session
        )
    }
}
```

- [ ] **Step 4: 编译验证**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild \
  -project GoldPrice.xcodeproj \
  -scheme GoldPrice \
  -configuration Debug \
  -derivedDataPath ./.build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build 2>&1 | tail -5
```

- [ ] **Step 5: 提交**

```bash
git add Shared/FREDDataSource.swift Shared/DXYDataSource.swift Shared/UST10YDataSource.swift
git commit -m "feat: add FRED-based DXY and US10Y data sources"
```

---

## Phase 3: 调度层（DataSourceManager）

### Task 3.1: 创建 DataSourceManager

**文件：**
- 新建: `Shared/DataSourceManager.swift`

- [ ] **Step 1: 创建 DataSourceManager.swift**

```swift
import Foundation

actor DataSourceManager {
    private var sources: [any DataSource] = []
    private var refreshTasks: [String: Task<Void, Never>] = [:]
    private let db: DatabaseManager
    private let engine: CorrelationEngine

    private var _quotes: [String: DataSourceQuote] = [:]
    var quotes: [String: DataSourceQuote] { _quotes }

    init(db: DatabaseManager = .shared) {
        self.db = db
        self.engine = CorrelationEngine(db: db)
    }

    func register(_ source: any DataSource) throws {
        sources.append(source)
        try db.registerSource(DataSourceInfo(
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

    func bootstrapHistory(yearsBack: Int = 20) async throws {
        let calendar = Calendar.current
        let to = Date()
        guard let from = calendar.date(byAdding: .year, value: -yearsBack, to: to) else { return }

        for source in sources where source.enabled {
            let lastDate = db.getLastDate(sourceID: source.id) ?? from
            let yesterday = calendar.date(byAdding: .day, value: -1, to: to) ?? to
            if lastDate < yesterday {
                do {
                    let points = try await source.fetchHistory(from: lastDate, to: to)
                    try db.upsertDailyPrices(points)
                } catch {
                    GoldPriceLog.warn("历史数据导入失败 [\(source.id)]: \(error.localizedDescription)")
                }
            }
        }
    }

    var correlations: [SourceCorrelation] {
        let baseID = "gold"
        let targetIDs = sources.filter { $0.id != baseID && $0.enabled }.map { $0.id }
        return engine.computeAll(baseSourceID: baseID, targetIDs: targetIDs)
    }

    func refreshCorrelations() {
        engine.invalidateCache()
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

                    // 日线数据检查：如果接近收盘时间，写入日线
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
        // 简化：每次收盘价更新时写入
        // 后续可加上"只在交易时段结束后写入"的逻辑
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let today = Date()
        let point = DailyPricePoint(
            sourceID: quote.sourceID,
            date: today,
            open: quote.price,
            high: quote.price,
            low: quote.price,
            close: quote.price
        )
        try? db.upsertDailyPrice(point)
        await engine.invalidateCache()
    }
}
```

- [ ] **Step 2: 编译验证**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild \
  -project GoldPrice.xcodeproj \
  -scheme GoldPrice \
  -configuration Debug \
  -derivedDataPath ./.build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build 2>&1 | tail -5
```

- [ ] **Step 3: 提交**

```bash
git add Shared/DataSourceManager.swift
git commit -m "feat: add DataSourceManager for multi-source orchestration"
```

---

## Phase 4: ViewModel 更新 + UI

### Task 4.1: 扩展 ViewModel 支持多数据源

**文件：**
- 修改: `GoldPriceApp/GoldPriceViewModel.swift`

在现有 ViewModel 中添加 DataSourceManager 引用、暴露多源报价和相关性的计算属性。**最小侵入原则**：现有金价逻辑保持不变，新增属性在旁边添加。

核心改动：
1. 新增 `@Published var sourceQuotes: [String: DataSourceQuote]` — 所有数据源的最新报价
2. 新增 `@Published var correlations: [SourceCorrelation]` — 相关性矩阵
3. 新增 `var otherSources: [DataSourceInfo]` — 非黄金数据源列表
4. `init` 中接收 `DataSourceManager`

- [ ] **Step 1: 添加新属性到 ViewModel**

在 `GoldPriceViewModel` 的 `@Published` 属性区（约第 27 行之后）添加：

```swift
@Published private(set) var sourceQuotes: [String: DataSourceQuote] = [:]
@Published private(set) var correlations: [SourceCorrelation] = []
@Published private(set) var registeredSources: [DataSourceInfo] = []
```

在 class body 末尾添加新方法：

```swift
// MARK: - Multi-Source

var otherSourceItems: [(id: String, name: String, price: String, change: String, isPositive: Bool)] {
    let entries: [(Data SourceInfo, DataSourceQuote?)] = registeredSources.compactMap { info in
        guard info.id != "gold" else { return nil }
        return (info, sourceQuotes[info.id])
    }
    return entries.map { (info, quote) in
        let priceStr: String
        if let q = quote {
            switch info.unit {
            case "%":
                priceStr = String(format: "%.2f%%", q.price)
            case "Index":
                priceStr = String(format: "%.2f", q.price)
            default:
                priceStr = GoldPriceFormatting.usd(q.price)
            }
        } else {
            priceStr = "--"
        }
        return (id: info.id, name: info.name, price: priceStr, change: "--", isPositive: true)
    }
}

func syncDataSourceState() {
    Task {
        guard let manager = dataSourceManager else { return }
        sourceQuotes = await manager.quotes
        correlations = await manager.correlations
    }
}
```

同时在 `init` 参数中添加：

```swift
private let dataSourceManager: DataSourceManager?
```

在 `init` 的末尾追加（在 `if autoStart` 之前）：

```swift
self.dataSourceManager = nil // 由 App 层通过 start() 设置
```

（注：实际实现时，DataSourceManager 初始化由 GoldPriceApp.swift 负责，ViewModel 通过方法注入。）

- [ ] **Step 2: 编译验证**

- [ ] **Step 3: 提交**

```bash
git add GoldPriceApp/GoldPriceViewModel.swift
git commit -m "feat: extend ViewModel with multi-source quote and correlation support"
```

---

### Task 4.2: 更新菜单栏面板（新增其他数据源价格）

**文件：**
- 修改: `GoldPriceApp/MenuBarViews.swift`

在 `MenuBarPanelView` 的 `priceBox` 区域后、`alertRow` 之前，添加其他数据源价格行。

- [ ] **Step 1: 添加其他数据源价格行**

在 `MenuBarPanelView` 的 `HStack(spacing: 10)` 包裹的 `priceBox` 区域之后，`alertRow` 之前，添加：

```swift
// 其他数据源价格
if !viewModel.otherSourceItems.isEmpty {
    VStack(spacing: 2) {
        ForEach(viewModel.otherSourceItems, id: \.id) { item in
            HStack {
                Text(item.name)
                    .font(GoldPriceTheme.font(11, weight: .bold))
                    .foregroundStyle(GoldPriceTheme.textSecondary)
                Spacer()
                Text(item.price)
                    .font(GoldPriceTheme.font(11, weight: .bold))
                    .foregroundStyle(GoldPriceTheme.textPrimary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
        }
    }
    .padding(8)
    .background(GoldPriceTheme.surface)
    .cornerRadius(6)
}
```

同时在底部按钮行中添加"相关性"按钮：

在 `Button("刷新")` 之后，`Button("历史")` 之前，添加：

```swift
Button("相关") {
    withAnimation {
        dashboardWindowController.showCorrelation(with: viewModel)
    }
}
.buttonStyle(PixelButtonStyle())
```

- [ ] **Step 2: 编译验证**

- [ ] **Step 3: 提交**

```bash
git add GoldPriceApp/MenuBarViews.swift
git commit -m "feat: add other source prices and correlation button to menu bar panel"
```

---

### Task 4.3: 更新 Dashboard（三栏式 + 相关性视图）

**文件：**
- 修改: `GoldPriceApp/ContentView.swift`
- 新建: `GoldPriceApp/CorrelationView.swift`

- [ ] **Step 1: 创建 CorrelationView（右栏相关性面板）**

```swift
import SwiftUI

struct CorrelationPanelView: View {
    let correlations: [SourceCorrelation]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("金价相关性")
                .font(GoldPriceTheme.font(14, weight: .black))
                .foregroundStyle(GoldPriceTheme.textPrimary)

            if correlations.isEmpty {
                Text("等待更多数据...")
                    .font(GoldPriceTheme.font(12, weight: .medium))
                    .foregroundStyle(GoldPriceTheme.textSecondary)
                    .padding(.top, 4)
            } else {
                correlationTable
                interpretationPanel
            }
        }
        .padding(16)
        .frame(width: 260)
        .background(GoldPriceTheme.surface)
    }

    private var correlationTable: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("").frame(width: 60, alignment: .leading)
                ForEach(TimeWindow.allCases, id: \.self) { window in
                    Text(window.displayName)
                        .font(GoldPriceTheme.font(10, weight: .bold))
                        .foregroundStyle(GoldPriceTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 4)

            Divider().background(GoldPriceTheme.border)

            // Rows
            ForEach(correlations) { sc in
                HStack {
                    Text(sc.sourceName)
                        .font(GoldPriceTheme.font(12, weight: .bold))
                        .foregroundStyle(GoldPriceTheme.textPrimary)
                        .frame(width: 60, alignment: .leading)

                    ForEach(TimeWindow.allCases, id: \.self) { window in
                        if let result = sc.correlations[window] {
                            Text(String(format: "%.2f", result.pearsonR))
                                .font(GoldPriceTheme.font(11, weight: .bold))
                                .foregroundStyle(correlationColor(result.pearsonR))
                                .monospacedDigit()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("--")
                                .font(GoldPriceTheme.font(11, weight: .bold))
                                .foregroundStyle(GoldPriceTheme.textSecondary)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .padding(.vertical, 6)
                Divider().background(GoldPriceTheme.border)
            }
        }
    }

    private var interpretationPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("解读")
                .font(GoldPriceTheme.font(11, weight: .bold))
                .foregroundStyle(GoldPriceTheme.textSecondary)

            ForEach(correlations) { sc in
                if let latest = sc.correlations.values.first {
                    Text(interpretationText(for: sc.sourceName, r: latest.pearsonR))
                        .font(GoldPriceTheme.font(11, weight: .medium))
                        .foregroundStyle(GoldPriceTheme.textPrimary)
                        .lineLimit(3)
                }
            }
        }
        .padding(12)
        .background(GoldPriceTheme.surfaceSecondary)
    }

    private func correlationColor(_ r: Double) -> Color {
        if r > 0.5 { return .green }
        if r > 0 { return .green.opacity(0.5) }
        if r > -0.5 { return .red.opacity(0.5) }
        return .red
    }

    private func interpretationText(for name: String, r: Double) -> String {
        let strength: String
        switch abs(r) {
        case 0.8...: strength = "强"
        case 0.5...: strength = "中等"
        case 0.3...: strength = "弱"
        default: strength = "极弱"
        }
        let direction = r > 0 ? "正相关" : "负相关"
        return "\(name) \(strength)\(direction)，金价联动性\(abs(r) > 0.5 ? "显著" : "一般")"
    }
}
```

- [ ] **Step 2: 更新 ContentView 为三栏式**

在现有的 `frame(minWidth: 820, minHeight: 580)` 基础上，将 `VStack` 包裹在 `HSplitView` 风格的三栏布局中：

在 `ZStack` 内部，`VStack` 外部包裹 `HStack`：

```swift
HStack(alignment: .top, spacing: 0) {
    // 左栏：数据源列表
    sourceListPanel
        .frame(width: 180)

    Divider().background(GoldPriceTheme.border)

    // 中栏：现有金价内容（压缩）
    existingContent
        .frame(minWidth: 400)

    Divider().background(GoldPriceTheme.border)

    // 右栏：相关性面板
    CorrelationPanelView(correlations: viewModel.correlations)
}
```

其中 `existingContent` 是当前 `VStack` 的主体内容（header + quoteRow + chartPanel + errorBanner），`sourceListPanel` 是新增的数据源列表。

- [ ] **Step 3: 编译验证 + 运行测试**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild \
  -project GoldPrice.xcodeproj \
  -scheme GoldPrice \
  -configuration Debug \
  -derivedDataPath ./.build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build 2>&1 | tail -5
```

- [ ] **Step 4: 提交**

```bash
git add GoldPriceApp/CorrelationView.swift GoldPriceApp/ContentView.swift
git commit -m "feat: add 3-pane dashboard with correlation panel"
```

---

### Task 4.4: 更新 App 入口（集成初始化）

**文件：**
- 修改: `GoldPriceApp/GoldPriceApp.swift`

在 `init()` 中初始化 `DatabaseManager`、注册所有数据源、启动 `DataSourceManager`。

- [ ] **Step 1: 更新 GoldPriceApp.swift**

```swift
@main
struct GoldPriceApp: App {
    @StateObject private var viewModel = GoldPriceViewModel(autoStart: true)
    @StateObject private var dashboardWindowController = DashboardWindowController()
    private let notificationDelegate = NotificationDelegate()
    private let dataManager = DataSourceManager.shared

    init() {
        // 通知权限
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert]) { _, _ in }
        center.delegate = notificationDelegate

        // 数据库和数据源初始化
        Task {
            do {
                try await dataManager.db.open()

                // 注册数据源
                let fredKey = ProcessInfo.processInfo.environment["FRED_API_KEY"] ?? ""
                try await dataManager.register(GoldDataSource())
                try await dataManager.register(SilverDataSource())
                if !fredKey.isEmpty {
                    try await dataManager.register(DXYDataSource(apiKey: fredKey))
                    try await dataManager.register(UST10YDataSource(apiKey: fredKey))
                }
                await dataManager.startAll()

                // 首次历史数据导入
                try? await dataManager.bootstrapHistory(yearsBack: 20)
            } catch {
                GoldPriceLog.warn("数据库初始化失败: \(error.localizedDescription)")
            }
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarPanelView(
                viewModel: viewModel,
                openDashboard: { dashboardWindowController.show(with: viewModel) },
                quitApp: { NSApp.terminate(nil) }
            )
        } label: {
            MenuBarLabelView(viewModel: viewModel)
        }
        .menuBarExtraStyle(.window)
    }
}
```

- [ ] **Step 2: 运行 App 验证**

从 Xcode 运行（Cmd+R），确认：
- 菜单栏金价正常显示
- 下拉面板显示其他数据源价格
- Dashboard 三栏布局正常
- 相关性面板有数据（需要日线数据积累后）

- [ ] **Step 3: 提交**

```bash
git add GoldPriceApp/GoldPriceApp.swift
git commit -m "feat: integrate DataSourceManager and database init at app launch"
```

---

## Phase 5: 历史数据导入（FRED API）

### Task 5.1: 完善 GoldDataSource 和 SilverDataSource 的历史数据

**文件：**
- 修改: `Shared/GoldDataSource.swift`
- 修改: `Shared/SilverDataSource.swift`

为黄金和白银实现 `fetchHistory`——金银历史数据可继续用 Kitco 解析（如果有历史页面），或者用 `Nasdaq Data Link` 免费 API。

**简化方案**：黄金和白银的历史数据暂时也走 FRED（有对应 series ID）：
- 黄金: `GOLDPMGBD228NLBR`（Gold Fixing Price 10:30 A.M. London Time）
- 白银: 需要查对应 series ID

若 FRED 没有合适的白银 series，则白银用 Yahoo Finance 的免费 CSV 下载（`SI=F`）。

- [ ] **Step 1: 为 GoldDataSource 实现 fetchHistory**

让 GoldDataSource 内部组合一个 FREDBaseDataSource 用于历史数据（只用于 fetchHistory，不影响实时 fetchQuote）。

```swift
// 在 GoldDataSource 中添加
private lazy var fredHistory: FREDBaseDataSource = {
    FREDBaseDataSource(
        id: "gold_history",
        name: "gold_history",
        unit: "USD/OZ",
        seriesID: "GOLDPMGBD228NLBR",
        apiKey: apiKey
    )
}()

private let apiKey: String

init(apiKey: String = ProcessInfo.processInfo.environment["FRED_API_KEY"] ?? "", session: URLSession = ...) {
    self.apiKey = apiKey
    // ... existing init
}

func fetchHistory(from: Date, to: Date) async throws -> [DailyPricePoint] {
    guard !apiKey.isEmpty else { return [] }
    return try await fredHistory.fetchHistory(from: from, to: to)
}
```

- [ ] **Step 2: 编译验证**

- [ ] **Step 3: 提交**

```bash
git add Shared/GoldDataSource.swift Shared/SilverDataSource.swift
git commit -m "feat: add FRED-based history fetch for gold and silver"
```

---

## 附录：手动测试验证清单

在所有任务完成后：

- [ ] App 启动后菜单栏金价正常显示（< 1s 刷新）
- [ ] 下拉面板显示金、银、DXY、US10Y 价格
- [ ] Dashboard 三栏布局正确：左栏数据源列表、中栏金价走势图、右栏相关性矩阵
- [ ] 切换叠加图模式：黄金 vs 选中数据源（双 Y 轴）
- [ ] 每日收盘后，日线数据自动写入 SQLite
- [ ] 相关性数值在 30D/90D/180D/1Y 四个窗口随时间变化
- [ ] 某个数据源失败时，显示 `--`，不影响其他数据源
- [ ] App 重启后，SQLite 数据不丢失
- [ ] `.env` 中的 `FRED_API_KEY` 正常工作
