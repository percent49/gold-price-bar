import Foundation

struct KitcoQuoteResult {
    let mid: Double
    let bid: Double
    let ask: Double
    let timestamp: Date?
    let usdToCNYRate: Double?
}

enum MetalQuoteParserError: LocalizedError {
    case invalidResponse
    case badStatus(Int)
    case invalidPayload
    case noData

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Kitco 返回了无法识别的响应"
        case .badStatus(let code): return "Kitco 暂时不可用（HTTP \(code)）"
        case .invalidPayload: return "Kitco 页面解析失败"
        case .noData: return "Kitco 未返回有效数据"
        }
    }
}

struct MetalQuoteParser {
    let session: URLSession
    let pageURL: URL
    private static let decoder = JSONDecoder()

    init(session: URLSession, pageURL: URL) {
        self.session = session
        self.pageURL = pageURL
    }

    func fetchQuote() async throws -> KitcoQuoteResult {
        let payload = try await fetchPayload()
        let usdToCNYRate = extractUSDtoCNYRate(from: payload)

        for query in payload.props.pageProps.dehydratedState.queries {
            guard let metalQuote = query.state.data?.getMetalQuoteV3 else { continue }
            guard let result = metalQuote.results.first else { continue }
            guard result.mid.isFinite, result.mid > 0 else { continue }

            return KitcoQuoteResult(
                mid: result.mid,
                bid: result.bid,
                ask: result.ask,
                timestamp: result.timestamp.map(Date.init(timeIntervalSince1970:)),
                usdToCNYRate: usdToCNYRate
            )
        }

        throw MetalQuoteParserError.noData
    }

    func fetchUSDtoCNYRate() async throws -> Double {
        let payload = try await fetchPayload()
        guard let rate = extractUSDtoCNYRate(from: payload) else {
            throw MetalQuoteParserError.noData
        }
        return rate
    }

    // MARK: - Private

    private func fetchPayload() async throws -> KitcoPagePayload {
        var components = URLComponents(url: pageURL, resolvingAgainstBaseURL: false)!
        var queryItems = components.queryItems ?? []
        queryItems.removeAll { $0.name == "_" }
        queryItems.append(URLQueryItem(name: "_", value: UUID().uuidString))
        components.queryItems = queryItems

        var request = URLRequest(url: components.url ?? pageURL)
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("GoldPriceMac/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MetalQuoteParserError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw MetalQuoteParserError.badStatus(httpResponse.statusCode)
        }

        guard let html = String(data: data, encoding: .utf8) else {
            throw MetalQuoteParserError.invalidPayload
        }

        let marker = "<script id=\"__NEXT_DATA__\" type=\"application/json\">"
        let closingMarker = "</script>"
        guard let startRange = html.range(of: marker),
              let endRange = html[startRange.upperBound...].range(of: closingMarker) else {
            throw MetalQuoteParserError.invalidPayload
        }

        let jsonString = String(html[startRange.upperBound..<endRange.lowerBound])
        guard let jsonData = jsonString.data(using: .utf8) else {
            throw MetalQuoteParserError.invalidPayload
        }
        return try Self.decoder.decode(KitcoPagePayload.self, from: jsonData)
    }

    private func extractUSDtoCNYRate(from payload: KitcoPagePayload) -> Double? {
        for query in payload.props.pageProps.dehydratedState.queries {
            guard let cnyQuote = query.state.data?.cny?.results.first else { continue }
            if let rate = cnyQuote.ctousd, rate.isFinite, rate > 0 { return rate }
            if let inverse = cnyQuote.usdtoc, inverse.isFinite, inverse > 0 { return 1 / inverse }
        }
        return nil
    }
}
