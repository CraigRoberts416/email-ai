import Foundation

// Platform doubles let this macOS executable run the production delegate
// extension. It does not request notification permission or contact APNs.
protocol UNUserNotificationCenterDelegate {}
final class UNUserNotificationCenter {}
struct UNNotificationPresentationOptions: OptionSet {
    let rawValue: Int
    static let banner = Self(rawValue: 1)
    static let sound = Self(rawValue: 2)
    static let badge = Self(rawValue: 4)
    static let list = Self(rawValue: 8)
}
struct UNNotificationContent { let userInfo: [AnyHashable: Any] }
struct UNNotificationRequest { let content: UNNotificationContent }
struct UNNotification { let request: UNNotificationRequest }
struct UNNotificationResponse { let notification: UNNotification }
final class AppDelegate {
    @MainActor static var onMailboxUpdate: (@MainActor () async -> Void)?
    @MainActor static let notificationTaps = NotificationTapBuffer()
}

@main struct NotificationDelegateTests {
    @MainActor static var events: [String] = []
    @MainActor static var refreshFinished = false
    @MainActor static var done = false
    @MainActor static var checks = 0

    @MainActor static func check(_ condition: @autoclosure () -> Bool, _ reason: String) {
        precondition(condition(), reason)
        checks += 1
    }

    @MainActor static func finishIfReady() {
        guard events.contains("presentation"), events.contains("tap-completion"), events.contains("refresh") else { return }
        check(events.filter { $0 == "presentation" }.count == 1, "Presentation completes once")
        check(events.filter { $0 == "tap-completion" }.count == 1, "Tap completes once")
        check(!refreshFinished, "Delegate completion does not wait for network refresh")
        done = true
    }

    @MainActor static func main() {
        AppDelegate.notificationTaps.install { request in
            check(Thread.isMainThread, "Tap routing runs on the main thread")
            check(request.messageID == "message" && request.mailboxID == "mailbox", "Payload keeps account-scoped identity")
            events.append("routed")
        }
        AppDelegate.onMailboxUpdate = {
            check(Thread.isMainThread, "Mailbox refresh starts on the main thread")
            check(events.contains("presentation"), "Foreground presentation completes before refresh starts")
            events.append("refresh")
            finishIfReady()
            try? await Task.sleep(for: .seconds(10))
            refreshFinished = true
        }

        // Mirror the real failure: the system may invoke either delegate
        // callback off the main thread. The app must choose where it completes.
        DispatchQueue.global().async {
            precondition(!Thread.isMainThread)
            let delegate = AppDelegate()
            let center = UNUserNotificationCenter()
            let notification = UNNotification(request: .init(content: .init(userInfo: ["messageId": "message", "userId": "mailbox"])))
            delegate.userNotificationCenter(center, willPresent: notification) { options in
                precondition(Thread.isMainThread, "Presentation completion must run on the main thread")
                MainActor.assumeIsolated {
                    check(options == [.banner, .sound, .badge, .list], "Presentation options are preserved")
                    events.append("presentation")
                    finishIfReady()
                }
            }
            delegate.userNotificationCenter(center, didReceive: .init(notification: notification)) {
                precondition(Thread.isMainThread, "Tap completion must run on the main thread")
                MainActor.assumeIsolated {
                    check(events.contains("routed"), "Tap is buffered or routed before UIKit completion")
                    events.append("tap-completion")
                    finishIfReady()
                }
            }
        }
        let deadline = Date().addingTimeInterval(3)
        while !done && Date() < deadline {
            _ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        check(done, "Both callbacks complete without waiting for mailbox work")
        print("\(checks) notification delegate checks passed")
    }
}
