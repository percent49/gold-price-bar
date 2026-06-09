import Foundation

final class GoldDataSource: DataSource, @unchecked Sendable {
    let id = "gold"
    let name = "黄金"
    let unit = "USD/OZ"
    let refreshInterval: TimeInterval = 1.0
    var enabled = true

    private let parser: MetalQuoteParser
    private let apiKey: String
    private static let goldAPIEndpoint = URL(string: "https://api.gold-api.com/price/XAU")!

    /// 绕过系统代理（Clash）避免 TLS 错误
    private static let goldAPISession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [:]
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 15
        config.waitsForConnectivity = false
        config.httpShouldSetCookies = false
        return URLSession(configuration: config)
    }()

    init(apiKey: String = ProcessInfo.processInfo.environment["FRED_API_KEY"] ?? "",
         session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 12
        config.waitsForConnectivity = false
        config.httpShouldSetCookies = false
        return URLSession(configuration: config)
    }()) {
        self.apiKey = apiKey
        self.parser = MetalQuoteParser(
            session: session,
            pageURL: URL(string: "https://www.kitco.com/charts/gold?sitetype=fullsite")!
        )
    }

    func fetchQuote() async throws -> DataSourceQuote {
        do {
            return try await fetchFromKitco()
        } catch {
            return try await fetchFromGoldAPI()
        }
    }

    func fetchHistory(from: Date, to: Date) async throws -> [DailyPricePoint] {
        return try await fetchYahooHistory(symbol: "GC=F", sourceID: id, from: from, to: to)
    }

    private func fetchFromKitco() async throws -> DataSourceQuote {
        let result = try await parser.fetchQuote()
        return DataSourceQuote(
            price: result.mid,
            bid: result.bid,
            ask: result.ask,
            fetchedAt: Date(),
            sourceUpdatedAt: result.timestamp,
            sourceName: "Kitco",
            sourceID: id,
            currency: "USD",
            usdToCNYRate: result.usdToCNYRate
        )
    }

    private func fetchFromGoldAPI() async throws -> DataSourceQuote {
        var request = URLRequest(url: Self.goldAPIEndpoint)
        request.timeoutInterval = 12
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("GoldPriceMac/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await Self.goldAPISession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DataSourceError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw DataSourceError.badStatus(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let payload = try decoder.decode(GoldAPIResponse.self, from: data)
        guard payload.price.isFinite, payload.price > 0 else {
            throw DataSourceError.invalidPayload
        }

        // CNY 汇率多级降级：Kitco（已失败才到这里，但仍试一次）→ DB 最新汇率 → 硬兜底
        let cnyRate = await resolveCNYFallback()

        return DataSourceQuote(
            price: payload.price,
            bid: nil,
            ask: nil,
            fetchedAt: Date(),
            sourceUpdatedAt: payload.updatedAt,
            sourceName: "gold-api.com",
            sourceID: id,
            currency: "USD",
            usdToCNYRate: cnyRate
        )
    }

    /// CNY 汇率降级链：Kitco（尝试一次）→ 数据库 FRED 最新值 → 7.25 硬兜底
    private func resolveCNYFallback() async -> Double? {
        if let rate = try? await parser.fetchUSDtoCNYRate(), rate > 0 {
            return rate
        }
        if let dbRate = await DatabaseManager.shared.getLatestPrice(sourceID: "usdcny")?.close, dbRate > 0 {
            GoldPriceLog.warn("CNY 汇率降级至数据库: \(String(format: "%.4f", dbRate))")
            return dbRate
        }
        GoldPriceLog.warn("CNY 汇率降级至硬兜底 7.25")
        return 7.25
    }
}

enum DataSourceError: LocalizedError {
    case invalidResponse
    case badStatus(Int)
    case invalidPayload
    case noSupportedSource

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "数据源返回了无法识别的响应"
        case .badStatus(let code): return "数据源暂时不可用（HTTP \(code)）"
        case .invalidPayload: return "数据源返回了无效的数据"
        case .noSupportedSource: return "没有拿到可用的数据源"
        }
    }
}
