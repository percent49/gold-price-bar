import Foundation

final class UST10YDataSource: DataSource, @unchecked Sendable {
    let id = "ust10y"
    let name = "10Y 美债"
    let unit = "%"
    let refreshInterval: TimeInterval = 300
    var enabled = true

    private let seriesID = "DGS10"
    private let apiKey: String
    private let session: URLSession

    init(apiKey: String, session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        return URLSession(configuration: config)
    }()) {
        self.apiKey = apiKey
        self.session = session
    }

    func fetchQuote() async throws -> DataSourceQuote {
        return try await fetchFREDLatest(seriesID: seriesID, apiKey: apiKey, sourceID: id)
    }

    func fetchHistory(from: Date, to: Date) async throws -> [DailyPricePoint] {
        return try await fetchFREDHistory(seriesID: seriesID, apiKey: apiKey, sourceID: id, from: from, to: to, session: session)
    }
}
