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

func fetchFREDLatest(seriesID: String, apiKey: String, sourceID: String) async throws -> DataSourceQuote {
    let url = URL(string: "https://api.stlouisfed.org/fred/series/observations?series_id=\(seriesID)&api_key=\(apiKey)&file_type=json&sort_order=desc&limit=1")!
    let (data, response) = try await URLSession.shared.data(from: url)

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
        sourceUpdatedAt: nil,
        sourceName: "FRED",
        sourceID: sourceID,
        currency: ""
    )
}

func fetchFREDHistory(seriesID: String, apiKey: String, sourceID: String, from: Date, to: Date, session: URLSession) async throws -> [DailyPricePoint] {
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
            sourceID: sourceID,
            date: date,
            open: close,
            high: close,
            low: close,
            close: close
        )
    }
}
