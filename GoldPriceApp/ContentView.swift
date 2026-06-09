import Charts
import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: GoldPriceViewModel

    var body: some View {
        ZStack {
            GoldPriceTheme.canvas.ignoresSafeArea()

            HStack(alignment: .top, spacing: 0) {
                // Left: data source list (with status)
                sourceListPanel

                // Center: gold chart + quotes
                VStack(alignment: .leading, spacing: 16) {
                    header
                    quoteRow
                    chartPanel

                    if let errorMessage = viewModel.errorMessage {
                        errorBanner(errorMessage)
                    }
                }
                .padding(20)

                // Right: correlation panel only
                CorrelationPanelView(
                    correlations: viewModel.correlations,
                    pointCounts: viewModel.dataPointCounts,
                    isBackfilling: viewModel.isBackfilling,
                    selectedWindow: $viewModel.correlationWindow,
                    isCustomDateRange: $viewModel.isCustomDateRange,
                    startDate: $viewModel.correlationStartDate,
                    endDate: $viewModel.correlationEndDate,
                    onRefresh: {
                        Task { await viewModel.refreshCorrelations() }
                    }
                )
            }
        }
        .frame(minWidth: 1080, minHeight: 580)
    }

    private var sourceListPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("行情数据")
                .font(GoldPriceTheme.font(10, weight: .bold))
                .foregroundStyle(GoldPriceTheme.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 12)

            sourceCard(
                symbol: "Au", name: "黄金", unit: "¥/克",
                price: viewModel.latestPerGramCNYText,
                sourceID: "gold", symbolColor: GoldPriceTheme.accentStrong
            )
            sourceCard(
                symbol: "Ag", name: "白银", unit: "¥/克",
                price: viewModel.otherSourceItems.first(where: { $0.id == "silver" })?.priceText ?? "--",
                sourceID: "silver", symbolColor: GoldPriceTheme.textSecondary
            )
            sourceCard(
                symbol: "WTI", name: "原油", unit: "USD/桶",
                price: viewModel.otherSourceItems.first(where: { $0.id == "oil" })?.priceText ?? "--",
                sourceID: "oil", symbolColor: GoldPriceTheme.textPrimary
            )
            sourceCard(
                symbol: "¥/$", name: "汇率", unit: "CNY/USD",
                price: viewModel.otherSourceItems.first(where: { $0.id == "usdcny" })?.priceText ?? "--",
                sourceID: "usdcny", symbolColor: GoldPriceTheme.textSecondary
            )
            sourceCard(
                symbol: "DXY", name: "美元指数", unit: "指数",
                price: viewModel.otherSourceItems.first(where: { $0.id == "dxy" })?.priceText ?? "--",
                sourceID: "dxy", symbolColor: GoldPriceTheme.textPrimary
            )
            sourceCard(
                symbol: "US10Y", name: "10Y美债", unit: "年化收益率",
                price: viewModel.otherSourceItems.first(where: { $0.id == "ust10y" })?.priceText ?? "--",
                sourceID: "ust10y", symbolColor: GoldPriceTheme.textPrimary
            )

            Spacer()
        }
        .frame(width: 160)
        .background(GoldPriceTheme.surface)
    }

    private func sourceCard(symbol: String, name: String, unit: String, price: String, sourceID: String, symbolColor: Color) -> some View {
        let stat = viewModel.dataSourceStats.first(where: { $0.id == sourceID })
        let isSelected = viewModel.selectedChartSource == sourceID
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(symbol)
                    .font(GoldPriceTheme.font(11, weight: .black))
                    .foregroundStyle(symbolColor)
                    .frame(width: 28, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(GoldPriceTheme.font(11, weight: .bold))
                        .foregroundStyle(GoldPriceTheme.textPrimary)
                    Text(unit)
                        .font(GoldPriceTheme.font(9, weight: .medium))
                        .foregroundStyle(GoldPriceTheme.textSecondary)
                }

                Spacer()
            }

            Text(price)
                .font(GoldPriceTheme.font(16, weight: .black))
                .foregroundStyle(GoldPriceTheme.textPrimary)
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .padding(.leading, 34)

            // 数据状态行
            HStack(spacing: 4) {
                Circle()
                    .fill((stat?.isStale ?? true) ? Color.orange : Color.green)
                    .frame(width: 5, height: 5)
                if let s = stat {
                    Text(s.earliestDateText)
                        .font(GoldPriceTheme.font(9, weight: .bold))
                        .foregroundStyle(GoldPriceTheme.textSecondary)
                    Text(" → \(s.latestDateText)")
                        .font(GoldPriceTheme.font(9, weight: .regular))
                        .foregroundStyle(GoldPriceTheme.textSecondary.opacity(0.7))
                } else {
                    Text("--")
                        .font(GoldPriceTheme.font(9, weight: .medium))
                        .foregroundStyle(GoldPriceTheme.textSecondary)
                }
            }
            .padding(.leading, 34)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(isSelected ? GoldPriceTheme.accentStrong.opacity(0.12) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.selectChartSource(sourceID)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(GoldPriceTheme.border.opacity(0.15))
                .frame(height: 1)
                .padding(.horizontal, 6)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 18) {
            PixelPanel(fill: GoldPriceTheme.surfaceStrong, padding: 16) {
                HStack(alignment: .center, spacing: 12) {
                    PixelCoinGlyph(size: 28)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("国际金价")
                            .font(GoldPriceTheme.font(28, weight: .black))
                            .foregroundStyle(GoldPriceTheme.textPrimary)

                        Text("实时金价面板")
                            .font(GoldPriceTheme.font(11, weight: .bold))
                            .foregroundStyle(GoldPriceTheme.textSecondary)

                        Text("\(viewModel.sourceName) / 秒级刷新 / 4 分钟窗口")
                            .font(GoldPriceTheme.font(12, weight: .medium))
                            .foregroundStyle(GoldPriceTheme.textSecondary)
                    }
                }
            }

            PixelPanel(fill: GoldPriceTheme.surface, padding: 12) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("数据源")
                        .font(GoldPriceTheme.font(11, weight: .bold))
                        .foregroundStyle(GoldPriceTheme.textSecondary)

                    HStack(spacing: 8) {
                        ForEach(GoldPriceSourcePreference.allCases) { source in
                            Button(source.displayName) {
                                Task {
                                    await viewModel.changeSource(to: source)
                                }
                            }
                            .buttonStyle(PixelToggleButtonStyle(selected: source == viewModel.selectedSource))
                        }
                    }
                    .frame(maxWidth: .infinity)

                    HStack(spacing: 8) {
                        Button("手动刷新") {
                            Task {
                                await viewModel.refresh()
                            }
                        }
                        .buttonStyle(PixelButtonStyle(prominent: true))

                        Button(viewModel.preferredCurrency == .usdPerOunce ? "💲 切换人民币 ¥" : "¥ 切换美元 💲") {
                            viewModel.toggleCurrency()
                        }
                        .buttonStyle(PixelButtonStyle())
                    }
                }
            }
            .frame(width: 312)
        }
    }

    private var quoteRow: some View {
        HStack(alignment: .top, spacing: 18) {
            quoteBlock(
                title: "美元/盎司",
                value: viewModel.latestPriceText,
                detail: "≈ \(viewModel.latestPerGramText) / G"
            )

            quoteBlock(
                title: "人民币/克",
                value: viewModel.latestPerGramCNYText,
                detail: "≈ \(viewModel.latestPriceCNYText) / 盎司"
            )
        }
    }

    private var chartPanel: some View {
        let isRealtime = viewModel.chartTimeRange == .realtime
        let isGold = viewModel.selectedChartSource == "gold"
        let points = (isRealtime && isGold) ? viewModel.chartHistory : viewModel.chartDailyPoints
        let chartName = viewModel.chartSourceName
        let title = isRealtime && isGold ? "最近 4 分钟" : "\(chartName)走势 · \(viewModel.chartTimeRange.rawValue)"
        let subtitle = isRealtime && isGold ? "Kitco / Gold API 实时走势" : "每日收盘价"
        @ViewBuilder
        var timeRangePicker: some View {
            HStack(spacing: 3) {
                ForEach(GoldPriceViewModel.ChartTimeRange.allCases) { range in
                    Button(range.rawValue) {
                        viewModel.chartTimeRange = range
                        UserDefaults.standard.set(range.rawValue, forKey: "chart_time_range")
                        Task { await viewModel.refreshCorrelations() }
                    }
                    .buttonStyle(PixelCorrelationChipStyle(selected: range == viewModel.chartTimeRange))
                }
            }
        }

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(GoldPriceTheme.font(16, weight: .black))
                        .foregroundStyle(GoldPriceTheme.textPrimary)

                    Text(subtitle)
                        .font(GoldPriceTheme.font(11, weight: .bold))
                        .foregroundStyle(GoldPriceTheme.textSecondary)
                }

                Spacer()

                HStack(spacing: 8) {
                    infoTag("资产", viewModel.chartSourceName)
                    infoTag("点数", "\(points.count)")
                }
            }

            timeRangePicker

            if points.count > 1 {
                Chart(points) { point in
                    LineMark(
                        x: .value("时间", point.timestamp),
                        y: .value("价格", yValue(for: point))
                    )
                    .foregroundStyle(GoldPriceTheme.accentStrong)
                    .lineStyle(.init(lineWidth: isRealtime ? 2.4 : 1.5, lineCap: .square, lineJoin: .miter))

                    if isRealtime, isGold, let alertY = viewModel.alertPriceY {
                        RuleMark(y: .value("提醒价", alertY))
                            .foregroundStyle(GoldPriceTheme.negative)
                            .lineStyle(.init(lineWidth: 1.5, dash: [5, 4]))
                    }
                }
                .chartYScale(domain: chartDomain(for: points))
                .chartXAxis {
                    AxisMarks(values: xTickValues) { _ in
                        AxisValueLabel(format: xTickFormat)
                            .foregroundStyle(GoldPriceTheme.textSecondary)
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(GoldPriceTheme.border.opacity(0.15))
                    }
                }
                .chartYAxis {
                    AxisMarks(values: .automatic) { value in
                        AxisValueLabel {
                            if let price = value.as(Double.self) {
                                let prefix = viewModel.chartYLabel
                                Text("\(prefix)\(viewModel.chartYValueFormat(price))")
                                    .font(.system(size: 11))
                                    .foregroundStyle(GoldPriceTheme.textSecondary)
                            }
                        }
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(GoldPriceTheme.border.opacity(0.15))
                    }
                }
                .frame(height: 250)
                .background(GoldPriceTheme.surfaceSecondary)
            } else if !isRealtime && points.isEmpty {
                Text("加载历史数据中...")
                    .font(GoldPriceTheme.font(13, weight: .bold))
                    .foregroundStyle(GoldPriceTheme.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 200, alignment: .center)
                    .background(GoldPriceTheme.surfaceSecondary)
            } else {
                Text("正在采集价格数据...")
                    .font(GoldPriceTheme.font(13, weight: .bold))
                    .foregroundStyle(GoldPriceTheme.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 200, alignment: .center)
                    .background(GoldPriceTheme.surfaceSecondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(GoldPriceTheme.surface)
        .overlay {
            Rectangle()
                .stroke(GoldPriceTheme.border, lineWidth: 2)
        }
    }

    private func quoteBlock(title: String, value: String, detail: String) -> some View {
        PixelPanel(fill: GoldPriceTheme.surface, padding: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(GoldPriceTheme.font(12, weight: .black))
                    .foregroundStyle(GoldPriceTheme.textSecondary)

                Text(value)
                    .font(GoldPriceTheme.font(38, weight: .black))
                    .foregroundStyle(GoldPriceTheme.textPrimary)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)

                Text(detail)
                    .font(GoldPriceTheme.font(12, weight: .medium))
                    .foregroundStyle(GoldPriceTheme.textSecondary)
            }
        }
    }

    private func infoTag(_ title: String, _ value: String) -> some View {
        PixelPanel(fill: GoldPriceTheme.surfaceSecondary, padding: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(GoldPriceTheme.font(10, weight: .bold))
                    .foregroundStyle(GoldPriceTheme.textSecondary)

                Text(value)
                    .font(GoldPriceTheme.font(11, weight: .bold))
                    .foregroundStyle(GoldPriceTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }

    private func errorBanner(_ message: String) -> some View {
        PixelPanel(fill: GoldPriceTheme.negative.opacity(0.18), padding: 12) {
            Text("错误 / \(message)")
                .font(GoldPriceTheme.font(12, weight: .bold))
                .foregroundStyle(GoldPriceTheme.textPrimary)
        }
    }

    private var xTickFormat: Date.FormatStyle {
        switch viewModel.chartTimeRange {
        case .realtime: return .dateTime.hour().minute().second()
        case .days7, .days30, .days90: return .dateTime.month(.defaultDigits).day()
        case .year1: return .dateTime.month(.abbreviated).year(.twoDigits)
        case .all: return .dateTime.year()
        }
    }

    private var xTickValues: AxisMarkValues {
        switch viewModel.chartTimeRange {
        case .realtime, .days7, .days30: return .automatic
        case .days90: return .automatic(desiredCount: 8)
        case .year1: return .automatic(desiredCount: 6)
        case .all: return .automatic(desiredCount: 8)
        }
    }

    private func yValue(for point: GoldPricePoint) -> Double {
        guard viewModel.selectedChartSource == "gold",
              viewModel.preferredCurrency == .cnyPerGram,
              let rate = viewModel.usdToCNYRate, rate > 0 else {
            return point.pricePerOunce
        }
        return point.pricePerOunce * rate / GoldPriceFormatting.gramsPerTroyOunce
    }

    private func chartDomain(for points: [GoldPricePoint]) -> ClosedRange<Double> {
        let values = points.map { yValue(for: $0) }
        guard let minValue = values.min(), let maxValue = values.max(), minValue < maxValue else {
            let fallback = values.first ?? 0
            return (fallback - 10)...(fallback + 10)
        }

        var lower = minValue
        var upper = maxValue
        if viewModel.chartTimeRange == .realtime, let alertY = viewModel.alertPriceY {
            lower = min(lower, alertY)
            upper = max(upper, alertY)
        }

        let spread = max(upper - lower, upper * 0.0008)
        let padding = spread * 0.12
        return (lower - padding)...(upper + padding)
    }
}
