import Foundation

// MARK: - FRED API Response Models

struct FREDObservationsResponse: Decodable {
    let observations: [FREDObservation]
}

struct FREDObservation: Decodable {
    let date: String
    let value: String
}

// MARK: - FRED API Helpers

/// 绕过系统代理的 URLSession，避免 Clash 等代理工具导致 TLS 错误
private let fredSession: URLSession = {
    let config = URLSessionConfiguration.ephemeral
    config.connectionProxyDictionary = [:]
    config.timeoutIntervalForRequest = 15
    return URLSession(configuration: config)
}()

func fetchFREDLatest(seriesID: String, apiKey: String, sourceID: String) async throws -> DataSourceQuote {
    let url = URL(string: "https://api.stlouisfed.org/fred/series/observations?series_id=\(seriesID)&api_key=\(apiKey)&file_type=json&sort_order=desc&limit=1")!
    var request = URLRequest(url: url)
    request.setValue("GoldPrice/1.0", forHTTPHeaderField: "User-Agent")
    let (data, response) = try await fredSession.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse,
          (200..<300).contains(httpResponse.statusCode) else {
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        let body = String(data: data, encoding: .utf8) ?? "<nil>"
        GoldPriceLog.warn("FRED [\(sourceID)] HTTP \(statusCode): \(body.prefix(200))")
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
        sourceUpdatedAt: nil,
        sourceName: "FRED",
        sourceID: sourceID,
        currency: ""
    )
}

func fetchFREDHistory(seriesID: String, apiKey: String, sourceID: String, from: Date, to: Date, session: URLSession = fredSession) async throws -> [DailyPricePoint] {
    let df = DateFormatter()
    df.dateFormat = "yyyy-MM-dd"
    let fromStr = df.string(from: from)
    let toStr = df.string(from: to)

    let url = URL(string: "https://api.stlouisfed.org/fred/series/observations?series_id=\(seriesID)&api_key=\(apiKey)&file_type=json&observation_start=\(fromStr)&observation_end=\(toStr)&sort_order=asc")!
    let (data, response) = try await fredSession.data(from: url)

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
            sourceID: sourceID,
            date: date,
            open: close,
            high: close,
            low: close,
            close: close
        )
    }
}
