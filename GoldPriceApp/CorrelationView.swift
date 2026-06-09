import SwiftUI

struct CorrelationPanelView: View {
    let correlations: [SourceCorrelation]
    let pointCounts: [String: Int]
    let isBackfilling: Bool
    @Binding var selectedWindow: TimeWindow
    @Binding var isCustomDateRange: Bool
    @Binding var startDate: Date
    @Binding var endDate: Date
    var onRefresh: (() -> Void)?

    private let sourceNames = ["silver": "白银", "oil": "原油", "usdcny": "汇率", "dxy": "美元指数", "ust10y": "10Y美债"]
    private let sourceOrder = ["silver", "oil", "usdcny", "dxy", "ust10y"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Text("金价相关性")
                    .font(GoldPriceTheme.font(14, weight: .black))
                    .foregroundStyle(GoldPriceTheme.textPrimary)
                Spacer()
            }

            timeWindowPicker
            dateRangePicker

            if correlations.isEmpty {
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

    // MARK: - Time Window Picker

    private var timeWindowPicker: some View {
        HStack(spacing: 4) {
            ForEach(TimeWindow.allCases, id: \.self) { window in
                Button(window.displayName) {
                    selectedWindow = window
                    UserDefaults.standard.set(window.rawValue, forKey: "correlation_window")
                }
                .buttonStyle(PixelCorrelationChipStyle(selected: window == selectedWindow))
            }
        }
    }

    // MARK: - Date Range Picker

    private var dateRangePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 复选框
            HStack(spacing: 4) {
                Toggle("", isOn: $isCustomDateRange)
                    .toggleStyle(.checkbox)
                    .scaleEffect(0.7)
                    .onChange(of: isCustomDateRange) { newValue in
                        UserDefaults.standard.set(newValue, forKey: "correlation_custom_range")
                    }
                Text("自定义日期范围")
                    .font(GoldPriceTheme.font(10, weight: .bold))
                    .foregroundStyle(GoldPriceTheme.textSecondary)
            }

            if isCustomDateRange {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("起始")
                            .font(GoldPriceTheme.font(9, weight: .medium))
                            .foregroundStyle(GoldPriceTheme.textSecondary)
                        DatePicker("", selection: $startDate, displayedComponents: .date)
                            .datePickerStyle(.field)
                            .font(.system(size: 10))
                            .labelsHidden()
                            .onChange(of: startDate) { newDate in
                                UserDefaults.standard.set(newDate, forKey: "correlation_start_date")
                            }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("终止")
                            .font(GoldPriceTheme.font(9, weight: .medium))
                            .foregroundStyle(GoldPriceTheme.textSecondary)
                        DatePicker("", selection: $endDate, displayedComponents: .date)
                            .datePickerStyle(.field)
                            .font(.system(size: 10))
                            .labelsHidden()
                            .onChange(of: endDate) { newDate in
                                UserDefaults.standard.set(newDate, forKey: "correlation_end_date")
                            }
                    }
                }

                Button("重新计算") {
                    onRefresh?()
                }
                .buttonStyle(PixelButtonStyle(prominent: true))
                .font(GoldPriceTheme.font(11, weight: .bold))
                .frame(maxWidth: .infinity)
            }
        }
        .padding(8)
        .background(GoldPriceTheme.surfaceSecondary)
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
        let matched = sc.correlations[selectedWindow]
        return VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(sc.sourceName)
                    .font(GoldPriceTheme.font(12, weight: .bold))
                    .foregroundStyle(GoldPriceTheme.textPrimary)
                Spacer()
                if let result = matched {
                    Text(String(format: "%+.3f", result.pearsonR))
                        .font(GoldPriceTheme.font(13, weight: .black))
                        .foregroundStyle(correlationColor(result.pearsonR))
                        .monospacedDigit()
                } else {
                    Text("--")
                        .font(GoldPriceTheme.font(11, weight: .bold))
                        .foregroundStyle(GoldPriceTheme.textSecondary)
                }
            }

            // 迷你条（视觉化相关强度）
            if let r = matched?.pearsonR {
                GeometryReader { geo in
                    ZStack(alignment: .center) {
                        Rectangle().fill(GoldPriceTheme.surfaceSecondary).frame(height: 3)
                        Rectangle()
                            .fill(correlationColor(r))
                            .frame(width: min(abs(CGFloat(r)) * geo.size.width, geo.size.width), height: 3)
                            .frame(maxWidth: .infinity, alignment: r >= 0 ? .trailing : .leading)
                        Rectangle().fill(GoldPriceTheme.textSecondary).frame(width: 1, height: 3)
                    }
                }
                .frame(height: 3)
            }

            // 数据条数
            if let n = matched?.dataPoints {
                Text("\(n) 个数据点")
                    .font(GoldPriceTheme.font(9, weight: .regular))
                    .foregroundStyle(GoldPriceTheme.textSecondary.opacity(0.6))
            }
        }
        .padding(8)
        .background(GoldPriceTheme.surfaceSecondary)
    }

    private var interpretationPanel: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("解读 · \(selectedWindow.displayName)")
                .font(GoldPriceTheme.font(10, weight: .bold))
                .foregroundStyle(GoldPriceTheme.textSecondary)
            ForEach(correlations) { sc in
                if let result = sc.correlations[selectedWindow] {
                    Text(interpretation(sc.sourceName, result.pearsonR, result.dataPoints))
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

    private func interpretation(_ name: String, _ r: Double, _ n: Int) -> String {
        let strength = abs(r) > 0.7 ? "强" : abs(r) > 0.4 ? "中等" : "弱"
        let dir = r > 0 ? "正相关" : "负相关"
        return "\(name) \(strength)\(dir)（\(n)点）"
    }
}

// MARK: - Correlation Chip Button Style

struct PixelCorrelationChipStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(GoldPriceTheme.font(10, weight: selected ? .black : .medium))
            .foregroundStyle(selected ? .white : GoldPriceTheme.textSecondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(selected ? GoldPriceTheme.accentStrong : GoldPriceTheme.surfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
    }
}