import UIKit
import UserNotifications
import Observation

@MainActor @Observable
final class PushDeliveryStatus {
    static let shared = PushDeliveryStatus()
    var registrationError: String?
    var registeredAccounts: Set<String> = []
    var isRegistering = false
}

/// Settings owns the explicit first-permission request. Launch and foreground
/// resume registration only when the reader has already granted access.
/// OS permission, server registration and actual delivery are separate facts.
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

    /// Foregrounding refreshes an existing grant; it does not spend the
    /// one-time permission prompt before the reader chooses to ask.
    func registerIfAuthorized() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        if [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) { register() }
    }

    private func register() {
        UIApplication.shared.registerForRemoteNotifications()
    }

    /// Every connected mailbox gets the same device token — the server pushes
    /// per user, and one device can be several users here.
    func submit(deviceToken: Data) async {
        let status = PushDeliveryStatus.shared
        status.isRegistering = true
        status.registrationError = nil
        defer { status.isRegistering = false }
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        for account in auth.accounts {
            do {
            let access = try await auth.validAccessToken(for: account.id)
            var request = URLRequest(url: baseURL.appending(path: "/auth/push-token"))
            request.httpMethod = "POST"
            request.setValue("Bearer \(access)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: ["pushToken": token])
            request.timeoutInterval = 15
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw APIError.transport
            }
            guard auth.accounts.contains(where: { $0.id == account.id }) else { continue }
            status.registeredAccounts.insert(account.id)
            } catch {
                status.registeredAccounts.remove(account.id)
                guard auth.accounts.contains(where: { $0.id == account.id }) else { continue }
                status.registrationError = "This device could not register for every mailbox. Open the app while online to try again."
            }
        }
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    /// Shown while the app is open too. Mail that needs you does not become
    /// less urgent because you happen to be looking at a different tab.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        Task { @MainActor in
            completionHandler([.banner, .sound, .badge, .list])
            Task { @MainActor in await AppDelegate.onMailboxUpdate?() }
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let request = NotificationOpenRequest(userInfo: response.notification.request.content.userInfo)
        Task { @MainActor in
            AppDelegate.notificationTaps.receive(request)
            completionHandler()
        }
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
        Task { @MainActor in
            PushDeliveryStatus.shared.registrationError = "Apple notification registration is unavailable. Your feed still works; open the app while online to try again."
        }
    }
}
