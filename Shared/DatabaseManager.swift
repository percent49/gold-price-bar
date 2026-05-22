import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

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
            throw DatabaseError.openFailed(errorMessage)
        }
        try createSchema()
    }

    func close() {
        guard db != nil else { return }
        sqlite3_close(db)
        db = nil
    }

    private var errorMessage: String {
        db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
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
            PRIMARY KEY (source_id, date)
        );

        CREATE INDEX IF NOT EXISTS idx_daily_date ON daily_prices(date);
        """
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw DatabaseError.schemaFailed(errorMessage)
        }
    }

    // MARK: - Write

    func registerSource(_ info: DataSourceInfo) throws {
        let sql = "INSERT OR IGNORE INTO data_sources (id, name, unit, enabled) VALUES (?, ?, ?, ?);"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(errorMessage)
        }
        guard let stmt else { throw DatabaseError.prepareFailed("statement is nil") }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, info.id, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, info.name, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, info.unit, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 4, info.enabled ? 1 : 0)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.insertFailed(errorMessage)
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
            throw DatabaseError.prepareFailed(errorMessage)
        }
        guard let stmt else { throw DatabaseError.prepareFailed("statement is nil") }
        defer { sqlite3_finalize(stmt) }

        let dateStr = Self.dateFormatter.string(from: point.date)
        sqlite3_bind_text(stmt, 1, point.sourceID, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, dateStr, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(stmt, 3, point.open)
        sqlite3_bind_double(stmt, 4, point.high)
        sqlite3_bind_double(stmt, 5, point.low)
        sqlite3_bind_double(stmt, 6, point.close)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.insertFailed(errorMessage)
        }
    }

    func upsertDailyPrices(_ points: [DailyPricePoint]) throws {
        execute("BEGIN TRANSACTION;")
        do {
            for point in points {
                try upsertDailyPrice(point)
            }
            execute("COMMIT;")
        } catch {
            execute("ROLLBACK;")
            throw error
        }
    }

    // MARK: - Read

    func getPrices(sourceID: String, from: Date, to: Date) -> [DailyPricePoint] {
        let sql = """
        SELECT date, open, high, low, close
        FROM daily_prices
        WHERE source_id = ? AND date >= ? AND date <= ?
        ORDER BY date ASC;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        guard let stmt else { return [] }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, sourceID, -1, SQLITE_TRANSIENT)
        let df = Self.dateFormatter
        sqlite3_bind_text(stmt, 2, df.string(from: from), -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, df.string(from: to), -1, SQLITE_TRANSIENT)

        var result: [DailyPricePoint] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let point = rowToDailyPrice(stmt, sourceID: sourceID) {
                result.append(point)
            }
        }
        return result
    }

    func getLatestPrice(sourceID: String) -> DailyPricePoint? {
        let sql = """
        SELECT date, open, high, low, close
        FROM daily_prices
        WHERE source_id = ? ORDER BY date DESC LIMIT 1;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        guard let stmt else { return nil }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, sourceID, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return rowToDailyPrice(stmt, sourceID: sourceID)
    }

    func getLastDate(sourceID: String) -> Date? {
        getLatestPrice(sourceID: sourceID)?.date
    }

    func getAllSources() -> [DataSourceInfo] {
        let sql = "SELECT id, name, unit, enabled FROM data_sources;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        guard let stmt else { return [] }
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

    private func rowToDailyPrice(_ stmt: OpaquePointer, sourceID: String) -> DailyPricePoint? {
        guard let dateStr = sqlite3_column_text(stmt, 0).map({ String(cString: $0) }),
              let date = Self.dateFormatter.date(from: dateStr) else { return nil }
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
