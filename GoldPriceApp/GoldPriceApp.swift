import AppKit
import SwiftUI
import UserNotifications

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list])
    }
}

@main
struct GoldPriceApp: App {
    @StateObject private var viewModel = GoldPriceViewModel(autoStart: true)
    @StateObject private var dashboardWindowController = DashboardWindowController()
    private let notificationDelegate = NotificationDelegate()

    init() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert]) { _, _ in }
        center.delegate = notificationDelegate
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarPanelView(
                viewModel: viewModel,
                openDashboard: {
                    dashboardWindowController.show(with: viewModel)
                },
                quitApp: {
                    NSApp.terminate(nil)
                }
            )
        } label: {
            MenuBarLabelView(viewModel: viewModel)
        }
        .menuBarExtraStyle(.window)
    }
}
