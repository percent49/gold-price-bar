import Foundation

actor CorrelationEngine {
    private let db: DatabaseManager
    private var cache: [String: [TimeWindow: CorrelationResult]] = [:]

    init(db: DatabaseManager = .shared) {
        self.db = db
    }

    func compute(baseSourceID: String, targetSourceID: String, window: TimeWindow) -> CorrelationResult? {
        let calendar = Calendar.current
        let to = Date()
        guard let from = calendar.date(byAdding: .day, value: -window.days, to: to) else {
            return nil
        }

        let basePrices = db.getPrices(sourceID: baseSourceID, from: from, to: to)
        let targetPrices = db.getPrices(sourceID: targetSourceID, from: from, to: to)

        let targetByDate = Dictionary(grouping: targetPrices) { Calendar.current.startOfDay(for: $0.date) }
            .compactMapValues { $0.first?.close }

        var baseReturns: [Double] = []
        var targetReturns: [Double] = []

        for i in 1..<basePrices.count {
            let prev = basePrices[i - 1]
            let curr = basePrices[i]
            let day = Calendar.current.startOfDay(for: curr.date)
            guard let targetClose = targetByDate[day],
                  prev.close > 0, curr.close > 0, targetClose > 0 else {
                continue
            }
            baseReturns.append(log(curr.close / prev.close))
            let prevDay = Calendar.current.startOfDay(for: prev.date)
            let prevTargetClose = targetByDate[prevDay] ?? targetClose
            targetReturns.append(log(targetClose / prevTargetClose))
        }

        guard baseReturns.count >= 5 else { return nil }

        let r = pearsonR(baseReturns, targetReturns)
        let beta = computeBeta(baseReturns, targetReturns)
        let divergence = computeDivergenceRatio(baseReturns, targetReturns)

        let result = CorrelationResult(
            pearsonR: r,
            beta: beta,
            divergenceRatio: divergence,
            dataPoints: baseReturns.count,
            window: window,
            computedAt: Date()
        )

        cache["\(baseSourceID)_\(targetSourceID)_\(window.rawValue)"] = result
        return result
    }

    func computeAll(baseSourceID: String, targetSourceIDs: [String]) -> [SourceCorrelation] {
        return targetSourceIDs.compactMap { targetID in
            var correlations: [TimeWindow: CorrelationResult] = [:]
            for window in TimeWindow.allCases {
                if let result = compute(baseSourceID: baseSourceID, targetSourceID: targetID, window: window) {
                    correlations[window] = result
                }
            }
            guard !correlations.isEmpty else { return nil }
            return SourceCorrelation(sourceID: targetID, sourceName: targetID, correlations: correlations)
        }
    }

    func invalidateCache() {
        cache.removeAll()
    }

    // MARK: - Math

    private func pearsonR(_ xs: [Double], _ ys: [Double]) -> Double {
        let n = Double(xs.count)
        let sumX = xs.reduce(0, +)
        let sumY = ys.reduce(0, +)
        let sumXY = zip(xs, ys).reduce(0) { $0 + $1.0 * $1.1 }
        let sumX2 = xs.reduce(0) { $0 + $1 * $1 }
        let sumY2 = ys.reduce(0) { $0 + $1 * $1 }

        let numerator = n * sumXY - sumX * sumY
        let denominator = sqrt((n * sumX2 - sumX * sumX) * (n * sumY2 - sumY * sumY))

        guard denominator != 0 else { return 0 }
        let r = numerator / denominator
        return min(max(r, -1.0), 1.0)
    }

    private func computeBeta(_ xs: [Double], _ ys: [Double]) -> Double {
        let varX = variance(xs)
        guard varX != 0 else { return 0 }
        return covariance(xs, ys) / varX
    }

    private func computeDivergenceRatio(_ xs: [Double], _ ys: [Double]) -> Double {
        let pairs = zip(xs, ys)
        let diverged = pairs.filter { ($0 > 0) != ($1 > 0) }.count
        return Double(diverged) / Double(max(xs.count, 1))
    }

    private func variance(_ xs: [Double]) -> Double {
        let mean = xs.reduce(0, +) / Double(xs.count)
        return xs.reduce(0) { $0 + pow($1 - mean, 2) } / Double(xs.count - 1)
    }

    private func covariance(_ xs: [Double], _ ys: [Double]) -> Double {
        let meanX = xs.reduce(0, +) / Double(xs.count)
        let meanY = ys.reduce(0, +) / Double(ys.count)
        return zip(xs, ys).reduce(0) { $0 + ($1.0 - meanX) * ($1.1 - meanY) } / Double(xs.count - 1)
    }
}
