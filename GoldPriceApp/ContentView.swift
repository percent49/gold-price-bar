import Charts
import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: GoldPriceViewModel

    var body: some View {
        ZStack {
            GoldPriceTheme.canvas.ignoresSafeArea()

            HStack(alignment: .top, spacing: 0) {
                // Left: data source list
                sourceListPanel

                // Main content (existing)
                VStack(alignment: .leading, spacing: 20) {
                    header
                    quoteRow
                    chartPanel

                    if let errorMessage = viewModel.errorMessage {
                        errorBanner(errorMessage)
                    }
                }
                .padding(24)

                // Right: correlation panel
                CorrelationPanelView(
                    correlations: viewModel.correlations,
                    pointCounts: viewModel.dataPointCounts,
                    isBackfilling: viewModel.isBackfilling
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
                .padding(.vertical, 16)

            sourceCard(
                symbol: "Au", name: "黄金", unit: "¥/克",
                price: viewModel.latestPerGramCNYText,
                change: viewModel.sessionMove ?? "--",
                symbolColor: GoldPriceTheme.accentStrong
            )
            sourceCard(
                symbol: "Ag", name: "白银", unit: "¥/克",
                price: viewModel.otherSourceItems.first(where: { $0.id == "silver" })?.priceText ?? "--",
                change: "--",
                symbolColor: GoldPriceTheme.textSecondary
            )
            sourceCard(
                symbol: "DXY", name: "美元指数", unit: "指数",
                price: viewModel.otherSourceItems.first(where: { $0.id == "dxy" })?.priceText ?? "--",
                change: "--",
                symbolColor: GoldPriceTheme.textPrimary
            )
            sourceCard(
                symbol: "US10Y", name: "10Y美债", unit: "年化收益率",
                price: viewModel.otherSourceItems.first(where: { $0.id == "ust10y" })?.priceText ?? "--",
                change: "--",
                symbolColor: GoldPriceTheme.textPrimary
            )

            Spacer()
        }
        .frame(width: 160)
        .background(GoldPriceTheme.surface)
    }

    private func sourceCard(symbol: String, name: String, unit: String, price: String, change: String, symbolColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(symbol)
                    .font(GoldPriceTheme.font(11, weight: .black))
                    .foregroundStyle(symbolColor)
                    .frame(width: 32, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(GoldPriceTheme.font(11, weight: .bold))
                        .foregroundStyle(GoldPriceTheme.textPrimary)
                    Text(unit)
                        .font(GoldPriceTheme.font(9, weight: .medium))
                        .foregroundStyle(GoldPriceTheme.textSecondary)
                }
            }

            Text(price)
                .font(GoldPriceTheme.font(16, weight: .black))
                .foregroundStyle(GoldPriceTheme.textPrimary)
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .padding(.leading, 38)

            Text(change)
                .font(GoldPriceTheme.font(10, weight: .bold))
                .foregroundStyle(GoldPriceTheme.textSecondary)
                .padding(.leading, 38)
        }
        .frame(height: 76)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(GoldPriceTheme.border.opacity(0.15))
                .frame(height: 1)
                .padding(.horizontal, 8)
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
        PixelPanel(fill: GoldPriceTheme.surface, padding: 16) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("最近 4 分钟")
                            .font(GoldPriceTheme.font(16, weight: .black))
                            .foregroundStyle(GoldPriceTheme.textPrimary)

                        Text("Kitco / Gold API 实时走势")
                            .font(GoldPriceTheme.font(11, weight: .bold))
                            .foregroundStyle(GoldPriceTheme.textSecondary)
                    }

                    Spacer()

                    HStack(spacing: 8) {
                        infoTag("来源", viewModel.sourceName)
                        if let latestUpdatedText = viewModel.latestUpdatedText {
                            infoTag("更新", latestUpdatedText)
                        }
                        infoTag("波动", viewModel.sessionMove ?? "--")
                    }
                }

                if viewModel.chartHistory.count > 1, let domain = chartDomain {
                    Chart(viewModel.chartHistory) { point in
                        LineMark(
                            x: .value("时间", point.timestamp),
                            y: .value("价格", point.pricePerOunce)
                        )
                        .foregroundStyle(GoldPriceTheme.accentStrong)
                        .lineStyle(.init(lineWidth: 2.4, lineCap: .square, lineJoin: .miter))
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    .chartYScale(domain: domain)
                    .chartPlotStyle { plot in
                        plot
                            .background(GoldPriceTheme.surfaceSecondary)
                            .overlay {
                                Rectangle()
                                    .stroke(GoldPriceTheme.border, lineWidth: 2)
                            }
                    }
                    .frame(height: 250)
                } else {
                    PixelPanel(fill: GoldPriceTheme.surfaceSecondary, padding: 16) {
                        Text("正在采集价格数据...")
                            .font(GoldPriceTheme.font(13, weight: .bold))
                            .foregroundStyle(GoldPriceTheme.textSecondary)
                            .frame(maxWidth: .infinity, minHeight: 214, alignment: .leading)
                    }
                }
            }
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

    private var chartDomain: ClosedRange<Double>? {
        let values = viewModel.chartHistory.map(\.pricePerOunce)
        guard let minValue = values.min(), let maxValue = values.max() else {
            return nil
        }

        let spread = max(maxValue - minValue, maxValue * 0.0008)
        let padding = spread * 0.22
        return (minValue - padding)...(maxValue + padding)
    }
}
