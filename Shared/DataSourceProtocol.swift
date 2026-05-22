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
