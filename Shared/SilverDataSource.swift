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
        // Phase 5 implementation
        return []
    }
}
