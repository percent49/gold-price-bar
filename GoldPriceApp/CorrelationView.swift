import SwiftUI

struct CorrelationPanelView: View {
    let correlations: [SourceCorrelation]
    let pointCounts: [String: Int]
    let isBackfilling: Bool

    private let sourceNames = ["silver": "白银", "oil": "原油", "usdcny": "汇率", "dxy": "美元指数", "ust10y": "10Y美债"]
    private let sourceOrder = ["silver", "oil", "usdcny", "dxy", "ust10y"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("金价相关性")
                .font(GoldPriceTheme.font(14, weight: .black))
                .foregroundStyle(GoldPriceTheme.textPrimary)

            if correlations.isEmpty {
                // 显示采集状态，让用户知道系统是活的
                dataCollectionStatus
            } else {
                ForEach(correlations) { sc in
                    correlationRow(sc)
                }
                interpretationPanel
            }
        }
        .padding(16)
        .frame(width: 260)
        .background(GoldPriceTheme.surface)
    }

    // MARK: - Data Collection Status

    private var dataCollectionStatus: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 状态指示
            HStack(spacing: 6) {
                Circle()
                    .fill(isBackfilling ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                Text(isBackfilling ? "数据采集中" : "等待数据...")
                    .font(GoldPriceTheme.font(12, weight: .bold))
                    .foregroundStyle(GoldPriceTheme.textPrimary)
            }

            // 各数据源采集进度
            VStack(spacing: 4) {
                ForEach(sourceOrder, id: \.self) { sourceID in
                    let name = sourceNames[sourceID] ?? sourceID
                    let count = pointCounts[sourceID] ?? 0
                    HStack {
                        Text(name)
                            .font(GoldPriceTheme.font(11, weight: .medium))
                            .foregroundStyle(GoldPriceTheme.textSecondary)
                            .frame(width: 60, alignment: .leading)

                        // 迷你进度条
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Rectangle()
                                    .fill(GoldPriceTheme.surfaceSecondary)
                                    .frame(height: 4)
                                Rectangle()
                                    .fill(count > 0 ? GoldPriceTheme.accent : Color.gray)
                                    .frame(width: min(CGFloat(count) / 365.0, 1.0) * geo.size.width, height: 4)
                            }
                        }
                        .frame(height: 4)

                        Text("\(count)天")
                            .font(GoldPriceTheme.font(10, weight: .bold))
                            .foregroundStyle(GoldPriceTheme.textSecondary)
                            .monospacedDigit()
                            .frame(width: 32, alignment: .trailing)
                    }
                }
            }

            // 需要多少天才能有相关性
            Text("至少需要 5 个交易日数据才能计算 30 日相关性")
                .font(GoldPriceTheme.font(10, weight: .medium))
                .foregroundStyle(GoldPriceTheme.textSecondary)
                .padding(.top, 4)
        }
        .padding(10)
        .background(GoldPriceTheme.surfaceSecondary)
    }

    // MARK: - Correlation Display

    private func correlationRow(_ sc: SourceCorrelation) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(sc.sourceName)
                .font(GoldPriceTheme.font(12, weight: .bold))
                .foregroundStyle(GoldPriceTheme.textPrimary)

            HStack(spacing: 12) {
                ForEach(TimeWindow.allCases, id: \.self) { window in
                    if let result = sc.correlations[window] {
                        VStack(spacing: 2) {
                            Text(window.displayName)
                                .font(GoldPriceTheme.font(9, weight: .medium))
                                .foregroundStyle(GoldPriceTheme.textSecondary)
                            Text(String(format: "%+.2f", result.pearsonR))
                                .font(GoldPriceTheme.font(11, weight: .bold))
                                .foregroundStyle(correlationColor(result.pearsonR))
                                .monospacedDigit()
                        }
                    } else {
                        Text("--")
                            .font(GoldPriceTheme.font(11, weight: .bold))
                            .foregroundStyle(GoldPriceTheme.textSecondary)
                    }
                }
            }
        }
        .padding(8)
        .background(GoldPriceTheme.surfaceSecondary)
    }

    private var interpretationPanel: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("解读")
                .font(GoldPriceTheme.font(11, weight: .bold))
                .foregroundStyle(GoldPriceTheme.textSecondary)
            ForEach(correlations) { sc in
                if let latest = sc.correlations.values.first {
                    Text(interpretation(sc.sourceName, latest.pearsonR))
                        .font(GoldPriceTheme.font(11, weight: .medium))
                        .foregroundStyle(GoldPriceTheme.textPrimary)
                }
            }
        }
        .padding(8)
        .background(GoldPriceTheme.surfaceSecondary)
    }

    private func correlationColor(_ r: Double) -> Color {
        if r > 0.5 { return .green }
        if r > 0 { return .green.opacity(0.5) }
        if r > -0.5 { return .red.opacity(0.5) }
        return .red
    }

    private func interpretation(_ name: String, _ r: Double) -> String {
        let strength = abs(r) > 0.7 ? "强" : abs(r) > 0.4 ? "中等" : "弱"
        let dir = r > 0 ? "正相关" : "负相关"
        return "\(name) \(strength)\(dir)"
    }
}
