import Foundation

enum GoldPriceServiceError: LocalizedError {
    case invalidResponse
    case badStatus(Int)
    case invalidPayload
    case noSupportedSource

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "金价服务返回了无法识别的响应。"
        case .badStatus(let statusCode):
            return "金价服务暂时不可用（HTTP \(statusCode)）。"
        case .invalidPayload:
            return "金价服务返回了无效的数据。"
        case .noSupportedSource:
            return "没有拿到可用的金价源。"
        }
    }
}

struct GoldPriceService {
    private static let goldAPIEndpoint = URL(string: "https://api.gold-api.com/price/XAU")!
    private static let kitcoGoldPage = URL(string: "https://www.kitco.com/charts/gold?sitetype=fullsite")!
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
    private static let defaultSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 12
        configuration.waitsForConnectivity = false
        configuration.httpShouldSetCookies = false
        return URLSession(configuration: configuration)
    }()

    /// 绕过系统代理（Clash）避免 TLS 错误
    private static let goldAPISession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [:]
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 15
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    let session: URLSession

    init(session: URLSession = GoldPriceService.defaultSession) {
        self.session = session
    }

    func fetchQuote(preferredSource: GoldPriceSourcePreference = .automatic) async throws -> GoldQuote {
        switch preferredSource {
        case .automatic:
            do {
                return try await fetchFromKitco()
            } catch {
                return try await fetchFromGoldAPI()
            }
        case .kitco:
            return try await fetchFromKitco()
        case .goldAPI:
            return try await fetchFromGoldAPI()
        }
    }

    private func fetchFromKitco() async throws -> GoldQuote {
        let payload = try await fetchKitcoPayload()
        let fetchedAt = Date()
        let usdToCNYRate = extractUSDtoCNYRate(from: payload)

        for query in payload.props.pageProps.dehydratedState.queries {
            guard let metalQuote = query.state.data?.getMetalQuoteV3 else {
                continue
            }

            guard let result = metalQuote.results.first else {
                continue
            }

            guard result.mid.isFinite, result.mid > 0 else {
                continue
            }

            return GoldQuote(
                pricePerOunce: result.mid,
                fetchedAt: fetchedAt,
                sourceUpdatedAt: result.timestamp.map(Date.init(timeIntervalSince1970:)),
                sourceName: "Kitco",
                bidPerOunce: result.bid,
                askPerOunce: result.ask,
                usdToCNYRate: usdToCNYRate
            )
        }

        throw GoldPriceServiceError.noSupportedSource
    }

    private func fetchFromGoldAPI() async throws -> GoldQuote {
        async let kitcoRate = fetchUSDtoCNYRateSafely()

        var request = URLRequest(url: Self.goldAPIEndpoint)
        request.timeoutInterval = 12
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("GoldPriceMac/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")

        // gold-api.com 也绕代理避免 TLS 错误
        let (data, response) = try await Self.goldAPISession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GoldPriceServiceError.invalidResponse
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            GoldPriceLog.warn("GoldAPI HTTP error \(httpResponse.statusCode)")
            throw GoldPriceServiceError.badStatus(httpResponse.statusCode)
        }

        let payload = try Self.decoder.decode(GoldAPIResponse.self, from: data)

        guard payload.price.isFinite, payload.price > 0 else {
            GoldPriceLog.warn("GoldAPI invalid price=\(payload.price)")
            throw GoldPriceServiceError.invalidPayload
        }
        let fetchedAt = Date()

        // CNY 汇率降级：Kitco → 数据库 → 硬兜底
        let usdToCNYRate = await resolveCNYRate(kitcoRate: await kitcoRate)

        return GoldQuote(
            pricePerOunce: payload.price,
            fetchedAt: fetchedAt,
            sourceUpdatedAt: payload.updatedAt,
            sourceName: "gold-api.com",
            bidPerOunce: nil,
            askPerOunce: nil,
            usdToCNYRate: usdToCNYRate
        )
    }

    /// CNY 汇率降级链
    private func resolveCNYRate(kitcoRate: Double?) async -> Double? {
        if let rate = kitcoRate, rate > 0 { return rate }
        if let dbRate = await DatabaseManager.shared.getLatestPrice(sourceID: "usdcny")?.close, dbRate > 0 {
            GoldPriceLog.warn("CNY 汇率降级至数据库: \(String(format: "%.4f", dbRate))")
            return dbRate
        }
        GoldPriceLog.warn("CNY 汇率降级至硬兜底 7.25")
        return 7.25
    }

    private func fetchKitcoPayload() async throws -> KitcoPagePayload {
        let request = makeKitcoRequest()

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GoldPriceServiceError.invalidResponse
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            throw GoldPriceServiceError.badStatus(httpResponse.statusCode)
        }

        guard let html = String(data: data, encoding: .utf8) else {
            GoldPriceLog.warn("Kitco payload is not valid HTML")
            throw GoldPriceServiceError.invalidPayload
        }

        let marker = "<script id=\"__NEXT_DATA__\" type=\"application/json\">"
        let closingMarker = "</script>"

        guard
            let startRange = html.range(of: marker),
            let endRange = html[startRange.upperBound...].range(of: closingMarker)
        else {
            throw GoldPriceServiceError.invalidPayload
        }

        let jsonString = String(html[startRange.upperBound..<endRange.lowerBound])
        guard let jsonData = jsonString.data(using: .utf8) else {
            throw GoldPriceServiceError.invalidPayload
        }

        return try JSONDecoder().decode(KitcoPagePayload.self, from: jsonData)
    }

    private func makeKitcoRequest() -> URLRequest {
        var components = URLComponents(url: Self.kitcoGoldPage, resolvingAgainstBaseURL: false)!
        var queryItems = components.queryItems ?? []
        queryItems.removeAll { $0.name == "_" }
        queryItems.append(URLQueryItem(name: "_", value: UUID().uuidString))
        components.queryItems = queryItems

        var request = URLRequest(url: components.url ?? Self.kitcoGoldPage)
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("GoldPriceMac/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        return request
    }

    private func fetchUSDtoCNYRateFromKitco() async throws -> Double {
        let payload = try await fetchKitcoPayload()

        guard let rate = extractUSDtoCNYRate(from: payload) else {
            throw GoldPriceServiceError.invalidPayload
        }

        return rate
    }

    private func fetchUSDtoCNYRateSafely() async -> Double? {
        try? await fetchUSDtoCNYRateFromKitco()
    }

    private func extractUSDtoCNYRate(from payload: KitcoPagePayload) -> Double? {
        for query in payload.props.pageProps.dehydratedState.queries {
            guard let cnyQuote = query.state.data?.cny?.results.first else {
                continue
            }

            if let rate = cnyQuote.ctousd, rate.isFinite, rate > 0 {
                return rate
            }

            if let inverse = cnyQuote.usdtoc, inverse.isFinite, inverse > 0 {
                return 1 / inverse
            }
        }

        return nil
    }
}
