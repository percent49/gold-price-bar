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
        let fromUnix = Int(from.timeIntervalSince1970)
        let toUnix = Int(to.timeIntervalSince1970)
        let urlStr = "https://query1.finance.yahoo.com/v7/finance/download/SI=F?period1=\(fromUnix)&period2=\(toUnix)&interval=1d&events=history"
        guard let url = URL(string: urlStr) else { return [] }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        let session = URLSession(configuration: config)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            return []
        }

        guard let csv = String(data: data, encoding: .utf8) else { return [] }
        let lines = csv.components(separatedBy: "\n").dropFirst()

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"

        var points: [DailyPricePoint] = []
        for line in lines {
            let cols = line.components(separatedBy: ",")
            guard cols.count >= 5,
                  let date = df.date(from: cols[0]),
                  let close = Double(cols[4]),
                  let open = Double(cols[1]),
                  let high = Double(cols[2]),
                  let low = Double(cols[3]) else { continue }
            points.append(DailyPricePoint(
                sourceID: id,
                date: date,
                open: open,
                high: high,
                low: low,
                close: close
            ))
        }
        return points
    }
}
