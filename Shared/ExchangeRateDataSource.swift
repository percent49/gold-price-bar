import Foundation

final class ExchangeRateDataSource: DataSource, @unchecked Sendable {
    let id = "usdcny"
    let name = "汇率"
    let unit = "CNY/USD"
    let refreshInterval: TimeInterval = 300
    var enabled = true

    private let apiKey: String

    init(apiKey: String, session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        return URLSession(configuration: config)
    }()) {
        self.apiKey = apiKey
    }

    func fetchQuote() async throws -> DataSourceQuote {
        return try await fetchFREDLatest(seriesID: "DEXCHUS", apiKey: apiKey, sourceID: id)
    }

    func fetchHistory(from: Date, to: Date) async throws -> [DailyPricePoint] {
        let session = URLSession(configuration: .ephemeral)
        return try await fetchFREDHistory(seriesID: "DEXCHUS", apiKey: apiKey, sourceID: id, from: from, to: to, session: session)
    }
}
