import Foundation

enum GoldPriceLog {
    private static let logDir: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("com.goldprice.app")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static let logURL: URL = logDir.appendingPathComponent("goldprice.log")
    private static let maxLogSize: Int64 = 5 * 1_024 * 1_024  // 5 MB
    private static let maxRotations = 3                       // 保留 3 个历史文件

    private static let startTime = Date()
    private static let queue = DispatchQueue(label: "com.goldprice.log")

    /// 低频心跳：Tick / Refresh 等高频事件至少间隔 60s 才写一次
    private static let heartbeatInterval: TimeInterval = 60
    private static var lastHeartbeat: [String: Date] = [:]

    private static var logFile: FileHandle? = {
        rotateIfNeeded()
        let url = logURL
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        let h = try? FileHandle(forWritingTo: url)
        h?.seekToEndOfFile()
        return h
    }()

    static var logPath: String { logURL.path }

    // MARK: - Rotation

    private static func rotateIfNeeded() {
        let url = logURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64,
              size >= maxLogSize else { return }

        // 关闭旧句柄
        logFile?.closeFile()
        logFile = nil

        // 轮转: .2 → .3, .1 → .2, current → .1
        let ext = ".log"
        for i in stride(from: maxRotations - 1, through: 1, by: -1) {
            let oldURL = logDir.appendingPathComponent("goldprice.\(i)\(ext)")
            let newURL = logDir.appendingPathComponent("goldprice.\(i + 1)\(ext)")
            try? FileManager.default.removeItem(at: newURL)
            try? FileManager.default.moveItem(at: oldURL, to: newURL)
        }
        let backupURL = logDir.appendingPathComponent("goldprice.1\(ext)")
        try? FileManager.default.removeItem(at: backupURL)
        try? FileManager.default.moveItem(at: url, to: backupURL)

        GoldPriceLog.logFile = nil  // 下次 write 会重新 open
    }

    private static func ensureLogFile() {
        if logFile == nil {
            let url = logURL
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            let h = try? FileHandle(forWritingTo: url)
            h?.seekToEndOfFile()
            logFile = h
        }
    }

    // MARK: - Write

    private static func write(_ level: String, _ msg: String) {
        let elapsed = String(format: "%.1f", Date().timeIntervalSince(startTime))
        let line = "[+\(elapsed)s] [\(level)] \(msg)\n"
        queue.async {
            ensureLogFile()
            if let data = line.data(using: .utf8) {
                logFile?.write(data)
            }
        }
    }

    /// 低频写：同 key 在 heartbeatInterval 秒内只写第一次，之后跳过
    private static func throttled(_ key: String, _ level: String, _ msg: String) {
        let now = Date()
        if let last = lastHeartbeat[key], now.timeIntervalSince(last) < heartbeatInterval {
            return
        }
        lastHeartbeat[key] = now
        write(level, msg)
    }

    // MARK: - Public API

    static func appStart() {
        write("INFO", "App started — log: \(logPath)")
    }

    static func refreshStart(source: String) {
        throttled("refreshStart", "DEBUG", "刷新中 | source=\(source)")
    }

    static func refreshSuccess(source: String, price: Double, cny: Double?) {
        let cnyStr = cny.map { String(format: "%.2f", $0) } ?? "nil"
        throttled("refreshSuccess", "DEBUG", "✅ 价格 | \(source) usd=\(String(format: "%.2f", price)) cny/g=\(cnyStr)")
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
        // 只在穿越时写，日常 tick 不写
        guard let prev = previous else { return }
        let crossed = (prev - target) * (current - target) <= 0
            && abs(current - target) < max(target * 0.02, 1.0)
        guard crossed else { return }
        write("DEBUG", "⚠️ 提醒价位接近 | price=\(String(format: "%.2f", current)) target=\(String(format: "%.2f", target))")
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
        throttled("tick", "DEBUG", "💰 \(source) $\(String(format: "%.2f", usd)) ¥\(cnyStr)/g alert=\(alertStr)")
    }

    static func debug(_ msg: String) {
        write("DEBUG", msg)
    }

    static func warn(_ msg: String) {
        write("WARN", msg)
    }

    /// 手动触发轮转（测试用）
    static func forceRotate() {
        rotateIfNeeded()
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
