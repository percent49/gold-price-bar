import Foundation

final class OilDataSource: DataSource, @unchecked Sendable {
    let id = "oil"
    let name = "原油"
    let unit = "USD/桶"
    let refreshInterval: TimeInterval = 300
    var enabled = true

    private let session: URLSession

    init(session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        return URLSession(configuration: config)
    }()) {
        self.session = session
    }

    func fetchQuote() async throws -> DataSourceQuote {
        let urlStr = "https://query2.finance.yahoo.com/v8/finance/chart/CL=F?range=1d&interval=5m"
        guard let url = URL(string: urlStr) else { throw DataSourceError.invalidResponse }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw DataSourceError.invalidResponse
        }

        let decoder = JSONDecoder()
        let payload = try decoder.decode(YahooChartResponse.self, from: data)

        guard let result = payload.chart.result?.first,
              let quote = result.indicators?.quote?.first,
              let closes = quote.close,
              let lastClose = closes.last(where: { $0 != nil }) as? Double else {
            throw DataSourceError.invalidPayload
        }

        return DataSourceQuote(
            price: lastClose,
            bid: nil,
            ask: nil,
            fetchedAt: Date(),
            sourceUpdatedAt: Date(),
            sourceName: "Yahoo Finance",
            sourceID: id,
            currency: "USD"
        )
    }

    func fetchHistory(from: Date, to: Date) async throws -> [DailyPricePoint] {
        return try await fetchYahooHistory(symbol: "CL=F", sourceID: id, from: from, to: to)
    }
}
