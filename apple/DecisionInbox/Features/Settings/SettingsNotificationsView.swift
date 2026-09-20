import SwiftUI
import UIKit
import UserNotifications

/// Notifications.
///
/// The one control on this screen is the only one that decides anything: iOS's
/// own permission. What gets pushed is chosen on the server, per message, and
/// no preference set on this phone is read when that choice is made — so the
/// per-mailbox switches and the quiet-hours switch the design called for are
/// not drawn. The paragraph says what actually arrives instead.
struct SettingsNotificationsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @State private var state: NotificationState = .unknown

    @State private var permissionError: String?
    @State private var requesting = false
    @State private var delivery = PushDeliveryStatus.shared
    @State private var alerts = "CHECKING"
    @State private var badges = "CHECKING"

    var body: some View {
        SettingsScreen(title: "Notifications", onBack: { dismiss() }) {
            SettingsGroup("ON THIS DEVICE")
            Rule()
            SettingsFact(title: "Permission", value: state.label ?? "CHECKING")
            if state == .notAsked {
                ConsequenceRow(title: requesting ? "Requesting permission…" : "Allow notifications",
                    sentence: "Ask iOS to allow alerts, sounds and badges for mail that needs your attention.",
                    action: requestPermission)
                    .disabled(requesting)
            } else if state == .unknown {
                SettingsParagraph(state.sentence)
                SettingsLink(title: "Check permission again", action: { Task { await refresh() } })
            } else {
                SettingsParagraph(state.sentence)
                SettingsFact(title: "Alerts", value: alerts)
                SettingsFact(title: "Badges", value: badges)
                SettingsLink(title: "Change this in iOS Settings", action: openSystemSettings)
            }
            if let permissionError { SettingsParagraph(permissionError) }
            Rule()
            SettingsGroup("DEVICE REGISTRATION")
            if let error = delivery.registrationError {
                SettingsParagraph(error)
                SettingsLink(title: "Try device registration again", action: {
                    UIApplication.shared.registerForRemoteNotifications()
                })
            } else {
                SettingsParagraph(delivery.isRegistering ? "Registering this device…"
                    : delivery.registeredAccounts.isEmpty ? "No device registration has been confirmed in this session."
                    : "This device is registered for \(delivery.registeredAccounts.count) \(delivery.registeredAccounts.count == 1 ? "mailbox" : "mailboxes"). Permission and registration do not confirm delivery; Focus and notification summaries can still affect alerts.")
            }
            SettingsGroup("WHAT WE SEND")
            SettingsParagraph("Alerts are considered after a message is interpreted and identified as needing your attention. Messages without that signal remain silent. Delivery also depends on your system settings and connection.")
            SettingsGroup("APP ICON")
            SettingsParagraph("The badge counts unread email across all connected mailboxes, including mail outside the feed. Reading a message lowers it; zero clears it. Badges can be changed separately in iOS Settings.")
        }
        .task { await refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refresh() } }
        }
    }

    private func refresh() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        state = NotificationState.from(settings.authorizationStatus)
        alerts = settings.alertSetting == .enabled ? "ALLOWED" : "OFF"
        badges = settings.badgeSetting == .enabled ? "ALLOWED" : "OFF"
    }

    private func requestPermission() {
        guard !requesting else { return }
        requesting = true
        permissionError = nil
        Task {
            defer { requesting = false }
            do {
                let allowed = try await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .sound, .badge])
                if allowed { UIApplication.shared.registerForRemoteNotifications() }
            } catch { permissionError = "iOS could not complete this request. Try again." }
            await refresh()
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }
}

// MARK: - System permission

/// What iOS says, rather than what we would like to be true.
enum NotificationState: Equatable {
    case unknown
    case notAsked
    case authorized
    case denied
    case provisional
    case ephemeral

    static func current() async -> NotificationState {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return from(settings.authorizationStatus)
    }

    static func from(_ status: UNAuthorizationStatus) -> NotificationState {
        switch status {
        case .notDetermined: return .notAsked
        case .denied: return .denied
        case .authorized: return .authorized
        case .provisional: return .provisional
        case .ephemeral: return .ephemeral
        @unknown default: return .unknown
        }
    }

    /// A row value, so upper-case mono is right: it is a state, not a sentence.
    var label: String? {
        switch self {
        case .unknown: return nil
        case .notAsked: return "NOT ASKED"
        case .authorized: return "ALLOWED"
        case .provisional: return "QUIETLY ALLOWED"
        case .ephemeral: return "TEMPORARILY ALLOWED"
        case .denied: return "OFF"
        }
    }

    var sentence: String {
        switch self {
        case .authorized: return "iOS allows notifications. Individual alert, sound and badge settings still apply."
        case .provisional: return "iOS allows quiet notifications. Change this in Settings if you want prominent alerts."
        case .ephemeral: return "iOS has granted temporary notification permission."
        case .denied: return "Notifications are off in iOS. You can change this in Settings."
        case .notAsked: return "You have not been asked for notification permission yet."
        case .unknown: return "Notification permission has not been checked yet."
        }
    }

}

#Preview {
    NavigationStack { SettingsNotificationsView() }
        .environment(FeedStore(sample: true))
}
