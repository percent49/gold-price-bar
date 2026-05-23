import AppKit
import SwiftUI
import UserNotifications

// MARK: - Notification Delegate

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list])
    }
}

// MARK: - App

@main
struct GoldPriceApp: App {
    @StateObject private var viewModel = GoldPriceViewModel(autoStart: true)
    @StateObject private var dashboardWindowController = DashboardWindowController()
    private let notificationDelegate = NotificationDelegate()

    init() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert]) { _, _ in }
        center.delegate = notificationDelegate

        Task {
            let fredKey = ProcessInfo.processInfo.environment["FRED_API_KEY"] ?? ""
            do {
                try await DataSourceManager.shared.db.open()
                try await DataSourceManager.shared.register(GoldDataSource(apiKey: fredKey))
                try await DataSourceManager.shared.register(SilverDataSource())
                try await DataSourceManager.shared.register(OilDataSource())
                if !fredKey.isEmpty {
                    try await DataSourceManager.shared.register(ExchangeRateDataSource(apiKey: fredKey))
                    try await DataSourceManager.shared.register(DXYDataSource(apiKey: fredKey))
                    try await DataSourceManager.shared.register(UST10YDataSource(apiKey: fredKey))
                }
                await DataSourceManager.shared.startAll()
                await DataSourceManager.shared.startProgressiveBackfill(yearsBack: 20)
            } catch {
                print("DataSource init error: \(error.localizedDescription)")
            }
        }
    }

    private func dismissMenuBar() {
        for window in NSApp.windows where window.level == .popUpMenu {
            window.close()
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarPanelView(
                viewModel: viewModel,
                openDashboard: {
                    dashboardWindowController.show(with: viewModel)
                    dismissMenuBar()
                },
                quitApp: {
                    NSApp.terminate(nil)
                },
                dismissMenu: { dismissMenuBar() }
            )
        } label: {
            MenuBarLabelView(viewModel: viewModel)
        }
        .menuBarExtraStyle(.window)
    }
}
