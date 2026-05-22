import Foundation

// MARK: - Yahoo Finance v8 Chart API

struct YahooChartResponse: Decodable {
    let chart: Chart

    struct Chart: Decodable {
        let result: [Result]?

        struct Result: Decodable {
            let timestamp: [Int]?
            let indicators: Indicators?

            struct Indicators: Decodable {
                let quote: [Quote]?

                struct Quote: Decodable {
                    let `open`: [Double?]?
                    let high: [Double?]?
                    let low: [Double?]?
                    let close: [Double?]?
                }
            }
        }
    }
}

func fetchYahooHistory(symbol: String, sourceID: String, from: Date, to: Date) async throws -> [DailyPricePoint] {
    let fromUnix = Int(from.timeIntervalSince1970)
    let toUnix = Int(to.timeIntervalSince1970)

    let urlStr = "https://query2.finance.yahoo.com/v8/finance/chart/\(symbol)?period1=\(fromUnix)&period2=\(toUnix)&interval=1d"
    guard let url = URL(string: urlStr) else { return [] }

    var request = URLRequest(url: url)
    request.timeoutInterval = 15
    request.cachePolicy = .reloadIgnoringLocalCacheData
    request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

    let config = URLSessionConfiguration.ephemeral
    config.timeoutIntervalForRequest = 15
    let session = URLSession(configuration: config)

    let (data, response) = try await session.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse,
          (200..<300).contains(httpResponse.statusCode) else {
        return []
    }

    let decoder = JSONDecoder()
    let payload = try decoder.decode(YahooChartResponse.self, from: data)

    guard let result = payload.chart.result?.first,
          let timestamps = result.timestamp,
          let quote = result.indicators?.quote?.first else {
        return []
    }

    let opens = quote.open ?? []
    let highs = quote.high ?? []
    let lows = quote.low ?? []
    let closes = quote.close ?? []

    var points: [DailyPricePoint] = []
    for i in 0..<timestamps.count {
        guard i < closes.count, let close = closes[i] else { continue }
        let date = Date(timeIntervalSince1970: TimeInterval(timestamps[i]))
        let open = i < opens.count ? opens[i] ?? close : close
        let high = i < highs.count ? highs[i] ?? close : close
        let low = i < lows.count ? lows[i] ?? close : close
        points.append(DailyPricePoint(
            sourceID: sourceID,
            date: date,
            open: open,
            high: high,
            low: low,
            close: close
        ))
    }
    return points
}
