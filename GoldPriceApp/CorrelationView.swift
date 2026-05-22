import SwiftUI

struct CorrelationPanelView: View {
    let correlations: [SourceCorrelation]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("金价相关性")
                .font(GoldPriceTheme.font(14, weight: .black))
                .foregroundStyle(GoldPriceTheme.textPrimary)

            if correlations.isEmpty {
                Text("积累数据中...")
                    .font(GoldPriceTheme.font(12, weight: .medium))
                    .foregroundStyle(GoldPriceTheme.textSecondary)
                    .padding(.top, 4)
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
