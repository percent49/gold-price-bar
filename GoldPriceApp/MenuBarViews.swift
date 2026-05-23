import Charts
import SwiftUI

struct MenuBarLabelView: View {
    @ObservedObject var viewModel: GoldPriceViewModel

    var body: some View {
        Text(alertText)
            .font(GoldPriceTheme.font(12, weight: .black))
            .foregroundStyle(viewModel.alertTriggered ? .yellow : GoldPriceTheme.textPrimary)
            .monospacedDigit()
    }

    private var alertText: String {
        guard viewModel.alertTriggered else {
            if viewModel.alertPrice != nil {
                return "🔔\(viewModel.menuBarTitle)"
            }
            return viewModel.menuBarTitle
        }
        return viewModel.alertFlashOn ? viewModel.menuBarTitle : "! 金价到了 !"
    }
}

struct MenuBarPanelView: View {
    @ObservedObject var viewModel: GoldPriceViewModel
    let openDashboard: () -> Void
    let quitApp: () -> Void
    let dismissMenu: () -> Void

    @State private var alertInput = ""
    @State private var showHistory = false
    @FocusState private var alertFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let msg = viewModel.alertTriggeredMessage {
                PixelPanel(fill: GoldPriceTheme.accentStrong.opacity(0.25), padding: 12) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(msg.components(separatedBy: "\n"), id: \.self) { line in
                                Text("🔔 \(line)")
                                    .font(GoldPriceTheme.font(line.hasPrefix("触发时间") ? 12 : 14, weight: .black))
                                    .foregroundStyle(line.hasPrefix("触发时间") ? GoldPriceTheme.textSecondary : GoldPriceTheme.accentStrong)
                            }
                        }

                        Spacer()

                        Button("知道了") {
                            viewModel.dismissTriggeredAlert()
                        }
                        .buttonStyle(PixelButtonStyle(prominent: true))
                    }
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("国际金价")
                    .font(GoldPriceTheme.font(15, weight: .black))
                    .foregroundStyle(GoldPriceTheme.textPrimary)

                Text(appVersion)
                    .font(GoldPriceTheme.font(10, weight: .bold))
                    .foregroundStyle(GoldPriceTheme.textSecondary)
            }
            .padding(.top, 4)

            Text("\(viewModel.sourceName) / LIVE PANEL")
                .font(GoldPriceTheme.font(10, weight: .bold))
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

                Button(viewModel.preferredCurrency == .usdPerOunce ? "💲切换¥" : "¥切换💲") {
                    viewModel.toggleCurrency()
                }
                .buttonStyle(PixelButtonStyle(prominent: viewModel.preferredCurrency == .cnyPerGram))
            }
            .frame(maxWidth: .infinity)

            HStack(alignment: .top, spacing: 10) {
                priceBox(title: "美元/盎司", value: viewModel.latestPriceText)
                priceBox(title: "人民币/克", value: viewModel.latestPerGramCNYText)
            }

            // Other data sources
            if !viewModel.otherSourceItems.isEmpty {
                VStack(spacing: 2) {
                    ForEach(viewModel.otherSourceItems) { item in
                        HStack {
                            Text("\(item.name) (\(item.unit))")
                                .font(GoldPriceTheme.font(10, weight: .bold))
                                .foregroundStyle(GoldPriceTheme.textSecondary)
                            Spacer()
                            Text(item.priceText)
                                .font(GoldPriceTheme.font(12, weight: .bold))
                                .foregroundStyle(GoldPriceTheme.textPrimary)
                                .monospacedDigit()
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                    }
                }
                .padding(8)
                .background(GoldPriceTheme.surface)
                .overlay(Rectangle().stroke(GoldPriceTheme.border, lineWidth: 1))
            }

            alertRow

            if viewModel.compactHistory.count > 1, let domain = chartDomain {
                PixelPanel(fill: GoldPriceTheme.surfaceSecondary, padding: 10) {
                    Chart(viewModel.compactHistory) { point in
                        LineMark(
                            x: .value("时间", point.timestamp),
                            y: .value("价格", point.pricePerOunce)
                        )
                        .foregroundStyle(GoldPriceTheme.accentStrong)
                        .lineStyle(.init(lineWidth: 2, lineCap: .square, lineJoin: .miter))

                        if let alertUSD = viewModel.alertPriceInUSD {
                            RuleMark(y: .value("提醒价", alertUSD))
                                .foregroundStyle(GoldPriceTheme.negative)
                                .lineStyle(.init(lineWidth: 1.2, dash: [4, 3]))
                        }
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    .chartYScale(domain: domain)
                    .chartPlotStyle { plot in
                        plot.background(GoldPriceTheme.surfaceSecondary)
                    }
                    .frame(height: 84)
                }
            }

            HStack(spacing: 8) {
                if let latestUpdatedText = viewModel.latestUpdatedText {
                    infoChip("更新 \(latestUpdatedText)")
                }
                infoChip(viewModel.sessionMove ?? "--")
            }

            HStack(spacing: 8) {
                Button("详情") {
                    openDashboard()
                    dismissMenu()
                }
                .buttonStyle(PixelButtonStyle(prominent: true))

                Button("刷新") {
                    Task {
                        await viewModel.refresh()
                    }
                    dismissMenu()
                }
                .buttonStyle(PixelButtonStyle())

                Button("历史") {
                    showHistory.toggle()
                }
                .buttonStyle(PixelButtonStyle())

                Button("退出", action: quitApp)
                    .buttonStyle(PixelButtonStyle())
            }
            .popover(isPresented: $showHistory) {
                alertHistoryList
            }

            if let errorMessage = viewModel.errorMessage {
                PixelPanel(fill: GoldPriceTheme.negative.opacity(0.18), padding: 10) {
                    Text(errorMessage)
                        .font(GoldPriceTheme.font(11, weight: .bold))
                        .foregroundStyle(GoldPriceTheme.textPrimary)
                        .lineLimit(2)
                }
            }
        }
        .padding(14)
        .frame(width: 348, alignment: .leading)
        .background(GoldPriceTheme.canvas)
    }

    private var alertRow: some View {
        PixelPanel(fill: GoldPriceTheme.surface, padding: 10) {
            if let alertDesc = viewModel.alertDescription {
                HStack {
                    Text("🔔 \(alertDesc)")
                        .font(GoldPriceTheme.font(12, weight: .bold))
                        .foregroundStyle(GoldPriceTheme.textPrimary)

                    Spacer()

                    Button("取消") {
                        viewModel.clearAlert()
                    }
                    .buttonStyle(PixelButtonStyle())
                }
            } else {
                HStack(spacing: 6) {
                    Text("提醒价")
                        .font(GoldPriceTheme.font(11, weight: .bold))
                        .foregroundStyle(GoldPriceTheme.textSecondary)

                    Text("¥/克")
                        .font(GoldPriceTheme.font(10, weight: .bold))
                        .foregroundStyle(GoldPriceTheme.textSecondary.opacity(0.6))

                    TextField("输入价格", text: $alertInput)
                        .focused($alertFieldFocused)
                        .textFieldStyle(.plain)
                        .font(GoldPriceTheme.font(13, weight: .bold))
                        .foregroundStyle(GoldPriceTheme.textPrimary)
                        .onSubmit { commitAlert() }

                    Button("设定") {
                        commitAlert()
                    }
                    .buttonStyle(PixelButtonStyle(prominent: true))
                }
            }
        }
    }

    private func commitAlert() {
        guard let price = Double(alertInput.trimmingCharacters(in: .whitespaces)), price > 0 else {
            return
        }
        viewModel.setAlert(price: price)
        alertInput = ""
        alertFieldFocused = false
    }

    private func priceBox(title: String, value: String) -> some View {
        PixelPanel(fill: GoldPriceTheme.surface, padding: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(GoldPriceTheme.font(10, weight: .bold))
                    .foregroundStyle(GoldPriceTheme.textSecondary)

                Text(value)
                    .font(GoldPriceTheme.font(20, weight: .black))
                    .foregroundStyle(GoldPriceTheme.textPrimary)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
        }
    }

    private func infoChip(_ text: String) -> some View {
        PixelPanel(fill: GoldPriceTheme.surfaceSecondary, padding: 8) {
            Text(text)
                .font(GoldPriceTheme.font(10, weight: .bold))
                .foregroundStyle(GoldPriceTheme.textPrimary)
                .lineLimit(1)
        }
    }

    private var alertHistoryList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("提醒历史")
                .font(GoldPriceTheme.font(14, weight: .black))
                .foregroundStyle(GoldPriceTheme.textPrimary)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            Divider()

            if viewModel.alertHistory.isEmpty {
                Text("暂无提醒记录")
                    .font(GoldPriceTheme.font(12, weight: .medium))
                    .foregroundStyle(GoldPriceTheme.textSecondary)
                    .padding(24)
                    .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(viewModel.alertHistory) { record in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("目标 \(GoldPriceFormatting.rmb(record.targetPrice)) → 到达 \(GoldPriceFormatting.rmb(record.triggeredPrice))")
                                    .font(GoldPriceTheme.font(12, weight: .bold))
                                    .foregroundStyle(GoldPriceTheme.textPrimary)

                                Text(GoldPriceFormatting.fullTime(record.timestamp))
                                    .font(GoldPriceTheme.font(11, weight: .medium))
                                    .foregroundStyle(GoldPriceTheme.textSecondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Divider()
                        }
                    }
                }
            }
        }
        .frame(width: 340, height: 400)
        .background(GoldPriceTheme.canvas)
    }

    private var appVersion: String {
        let marketing = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        return "v\(marketing)"
    }

    private var chartDomain: ClosedRange<Double>? {
        let values = viewModel.compactHistory.map(\.pricePerOunce)
        guard let minValue = values.min(), let maxValue = values.max() else {
            return nil
        }

        var lower = minValue
        var upper = maxValue
        if let alertUSD = viewModel.alertPriceInUSD {
            lower = min(lower, alertUSD)
            upper = max(upper, alertUSD)
        }

        let spread = max(upper - lower, upper * 0.0006)
        let padding = spread * 0.22
        return (lower - padding)...(upper + padding)
    }
}
