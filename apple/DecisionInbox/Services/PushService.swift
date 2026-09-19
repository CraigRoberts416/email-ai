import UIKit
import UserNotifications

/// Push.
///
/// Permission is never asked for on launch. The prompt is a one-shot — decline
/// it once and the only way back is Settings — so it is spent at the first
/// moment the answer is obviously yes: after the feed has loaded and the user
/// has seen what the product actually does.
///
/// What arrives is also narrow on purpose. The server only pushes mail it has
/// already decided needs the user. A notification for a receipt is how an
/// inbox app teaches people to turn notifications off.
@MainActor
final class PushService: NSObject {
    private let auth: AuthService
    private let baseURL: URL

    init(auth: AuthService, baseURL: URL) {
        self.auth = auth
        self.baseURL = baseURL
        super.init()
    }

    /// Asks only if the system has not already been asked.
    func requestIfUndecided() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .notDetermined else {
            if [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) { register() }
            return
        }
        let granted = (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        if granted { register() }
    }

    private func register() {
        UIApplication.shared.registerForRemoteNotifications()
    }

    /// Every connected mailbox gets the same device token — the server pushes
    /// per user, and one device can be several users here.
    func submit(deviceToken: Data) async {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        for account in auth.accounts {
            guard let access = try? await auth.validAccessToken(for: account.id) else { continue }
            var request = URLRequest(url: baseURL.appending(path: "/auth/push-token"))
            request.httpMethod = "POST"
            request.setValue("Bearer \(access)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: ["pushToken": token])
            _ = try? await URLSession.shared.data(for: request)
        }
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    /// Shown while the app is open too. Mail that needs you does not become
    /// less urgent because you happen to be looking at a different tab.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        Task { @MainActor in await AppDelegate.onMailboxUpdate?() }
        return [.banner, .sound, .badge, .list]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let request = NotificationOpenRequest(userInfo: response.notification.request.content.userInfo)
        await AppDelegate.notificationTaps.receive(request)
    }
}

/// Bridges the two UIKit callbacks SwiftUI has no equivalent for.
final class AppDelegate: NSObject, UIApplicationDelegate {
    static var onToken: ((Data) -> Void)?
    static var lastToken: Data?
    static var onMailboxUpdate: (@MainActor () async -> Void)?
    @MainActor static let notificationTaps = NotificationTapBuffer()

    func application(_ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Install before SwiftUI builds RootView so a notification that
        // launches the process can reach the buffer immediately.
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Self.lastToken = deviceToken
        Self.onToken?(deviceToken)
    }

    func application(_ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        Task { @MainActor in
            guard let refresh = Self.onMailboxUpdate else { completionHandler(.noData); return }
            await refresh()
            completionHandler(.newData)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        // Silent: the feed works without push, and there is nothing the user
        // could do about an APNs registration failure anyway.
    }
}
