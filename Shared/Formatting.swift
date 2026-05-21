import Foundation

enum GoldPriceLog {
    private static let logURL: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("com.goldprice.app")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("goldprice.log")
    }()

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm:ss.SSS"
        return f
    }()

    private static let startTime = Date()

    private static var logFile: FileHandle? = {
        let url = logURL
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        let h = try? FileHandle(forWritingTo: url)
        h?.seekToEndOfFile()
        return h
    }()

    private static let queue = DispatchQueue(label: "com.goldprice.log")

    static var logPath: String { logURL.path }

    private static func write(_ level: String, _ msg: String) {
        let elapsed = String(format: "%.1f", Date().timeIntervalSince(startTime))
        let line = "[+\(elapsed)s] [\(level)] \(msg)\n"
        queue.async {
            if let data = line.data(using: .utf8) {
                logFile?.write(data)
            }
        }
    }

    // MARK: - Public API

    static func appStart() {
        write("INFO", "App started — log: \(logPath)")
    }

    static func refreshStart(source: String) {
        write("DEBUG", "Refresh start | source=\(source)")
    }

    static func refreshSuccess(source: String, price: Double, cny: Double?) {
        let cnyStr = cny.map { String(format: "%.2f", $0) } ?? "nil"
        write("DEBUG", "Refresh OK | source=\(source) usd=\(String(format: "%.2f", price)) cny/g=\(cnyStr)")
    }

    static func refreshError(_ error: Error, source: String) {
        write("ERROR", "Refresh failed | source=\(source) error=\(error.localizedDescription)")
    }

    static func refreshSkipped(reason: String) {
        write("DEBUG", "Refresh skipped | \(reason)")
    }

    static func alertSet(price: Double, currency: String) {
        write("INFO", "Alert SET | target=\(String(format: "%.2f", price)) currency=\(currency)")
    }

    static func alertCleared() {
        write("INFO", "Alert CLEARED")
    }

    static func alertCheck(previous: Double?, current: Double, target: Double, currency: String) {
        guard let prev = previous else {
            write("DEBUG", "Alert check | NO BASELINE, recording curr=\(String(format: "%.2f", current))")
            return
        }
        let crossed = (prev - target) * (current - target) <= 0
        let diff = abs(current - target)
        write("DEBUG", "Alert check | prev=\(String(format: "%.2f", prev)) curr=\(String(format: "%.2f", current)) target=\(String(format: "%.2f", target)) crossed=\(crossed) diff=\(String(format: "%.4f", diff))")
    }

    static func alertTriggered(price: Double, currency: String) {
        write("ALERT", "★★★★★ TRIGGERED ★★★★★ | price=\(String(format: "%.2f", price)) currency=\(currency)")
    }

    static func alertDismissed() {
        write("INFO", "Alert dismissed by user")
    }

    static func sourceChanged(from: String, to: String) {
        write("INFO", "Source changed | \(from) -> \(to)")
    }

    static func currencyToggled(to: String) {
        write("INFO", "Currency toggled | now=\(to)")
    }

    static func currentPriceInfo(usd: Double, cnyPerGram: Double?, source: String, alert: Double?) {
        let cnyStr = cnyPerGram.map { String(format: "%.3f", $0) } ?? "nil"
        let alertStr = alert.map { String(format: "%.2f", $0) } ?? "none"
        write("DEBUG", "Tick | usd=\(String(format: "%.2f", usd)) cny/g=\(cnyStr) source=\(source) alert=\(alertStr)")
    }

    static func debug(_ msg: String) {
        write("DEBUG", msg)
    }

    static func warn(_ msg: String) {
        write("WARN", msg)
    }
}

enum GoldPriceFormatting {
    static let gramsPerTroyOunce = 31.1034768

    static func usd(_ value: Double, fractionDigits: Int = 2) -> String {
        currency(value, code: "USD", fractionDigits: fractionDigits)
    }

    static func cny(_ value: Double, fractionDigits: Int = 2) -> String {
        currency(value, code: "CNY", fractionDigits: fractionDigits)
    }

    static func rmb(_ value: Double, fractionDigits: Int = 2) -> String {
        "RMB \(plain(value, fractionDigits: fractionDigits))"
    }

    static func currency(_ value: Double, code: String, fractionDigits: Int = 2) -> String {
        value.formatted(
            .currency(code: code)
                .precision(.fractionLength(fractionDigits))
        )
    }

    static func plain(_ value: Double, fractionDigits: Int = 2) -> String {
        value.formatted(
            .number
                .grouping(.automatic)
                .precision(.fractionLength(fractionDigits))
        )
    }

    static func menuBarPrice(_ value: Double) -> String {
        "$\(plain(value))"
    }

    static func menuBarCNYPrice(_ value: Double) -> String {
        "¥\(plain(value))"
    }

    static func menuBarUSDPerGram(_ value: Double) -> String {
        "$\(plain(value))"
    }

    static func shortTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    static func fullTime(_ date: Date) -> String {
        date.formatted(date: .numeric, time: .shortened)
    }

    static func sessionMoveText(from firstValue: Double, to lastValue: Double) -> String {
        let delta = lastValue - firstValue
        let percent = (delta / firstValue) * 100
        let sign = delta >= 0 ? "+" : ""
        return "\(sign)\(usd(delta))  (\(sign)\(percent.formatted(.number.precision(.fractionLength(2))))%)"
    }

    static func signedPercent(from firstValue: Double, to lastValue: Double) -> Double {
        ((lastValue - firstValue) / firstValue) * 100
    }
}
