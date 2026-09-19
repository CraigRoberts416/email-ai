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

    var body: some View {
        SettingsScreen(title: "Notifications", onBack: { dismiss() }) {
            SettingsGroup("ON THIS PHONE")
            Rule()
            if state == .authorized {
                SettingsFact(title: "Notifications", value: "ON")
                Rule()
                SettingsLink(title: "Change this in iOS Settings", action: openSystemSettings)
                Rule()
            } else {
                ConsequenceRow(
                    title: "Turn notifications on",
                    sentence: state.sentence,
                    action: openSystemSettings
                )
                Rule()
            }

            SettingsGroup("WHAT WE SEND")
            SettingsParagraph("We push a message only when the model has already decided it needs an answer from you. Receipts, promotions and newsletters stay silent.")
            SettingsGroup("APP ICON")
            SettingsParagraph("The badge counts unread email across all connected mailboxes, including mail outside the feed. Reading a message lowers it; zero clears it. You can turn badges on or off separately in iOS Settings.")
        }
        .task { state = await NotificationState.current() }
        .onChange(of: scenePhase) { _, phase in
            // Coming back from iOS Settings is the one moment this can change
            // under us, and a stale "off" here would be a lie about the thing
            // the user just went and fixed.
            guard phase == .active else { return }
            Task { state = await NotificationState.current() }
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

    static func current() async -> NotificationState {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: return .notAsked
        case .denied: return .denied
        case .authorized, .provisional, .ephemeral: return .authorized
        @unknown default: return .unknown
        }
    }

    /// A row value, so upper-case mono is right: it is a state, not a sentence.
    var label: String? {
        switch self {
        case .unknown: return nil
        case .notAsked: return "NOT ASKED"
        case .authorized: return "ON"
        case .denied: return "OFF"
        }
    }

    var sentence: String {
        switch self {
        case .authorized:
            return "iOS is letting notifications through."
        case .denied:
            return "iOS is holding them back, so nothing we send reaches you. This opens the Decision Inbox page in iOS Settings, where you can let them through."
        case .notAsked, .unknown:
            return "You haven\u{2019}t been asked yet. This opens the Decision Inbox page in iOS Settings, where you can let them through."
        }
    }
}

#Preview {
    NavigationStack { SettingsNotificationsView() }
        .environment(FeedStore(sample: true))
}
