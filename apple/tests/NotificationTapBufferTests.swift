import Foundation

@main struct NotificationTapBufferTests {
    static var checks = 0
    static func check(_ condition: @autoclosure () -> Bool, _ reason: String) {
        precondition(condition(), reason)
        checks += 1
    }

    @MainActor static func main() {
        let buffer = NotificationTapBuffer()
        var opened: [NotificationOpenRequest] = []
        let cold = NotificationOpenRequest(userInfo: ["messageId": "same", "userId": "second"])
        buffer.receive(cold)
        check(opened.isEmpty, "Cold-launch tap waits until the UI handler exists")
        buffer.install { opened.append($0) }
        check(opened == [cold], "Handler installation immediately replays the buffered tap")
        buffer.install { opened.append($0) }
        check(opened.count == 1, "Attaching the handler again does not reopen a consumed tap")

        let repeatTap = NotificationOpenRequest(userInfo: ["messageId": "same", "userId": "second"])
        buffer.receive(repeatTap)
        check(opened.count == 2 && repeatTap.id != cold.id, "A second real tap on the same email opens again")
        check(opened.last == repeatTap, "Warm tap is routed synchronously without waiting for refresh")

        let mailboxes: Set<String> = ["first", "second"]
        check(cold.matches(messageID: "same", mailboxID: "second", connectedMailboxIDs: mailboxes), "Exact connected account opens")
        check(!cold.matches(messageID: "same", mailboxID: "first", connectedMailboxIDs: mailboxes), "An equal Gmail ID in another account cannot open")
        check(!cold.matches(messageID: "different", mailboxID: "second", connectedMailboxIDs: mailboxes), "Account match alone cannot select another message")
        check(!cold.matches(messageID: "same", mailboxID: "second", connectedMailboxIDs: ["first"]), "Disconnected mailbox notifications cannot open retained data")

        let legacy = NotificationOpenRequest(userInfo: ["messageId": "same"])
        check(legacy.matches(messageID: "same", mailboxID: "first", connectedMailboxIDs: ["first"]), "Legacy notification works with one unambiguous account")
        check(!legacy.matches(messageID: "same", mailboxID: "first", connectedMailboxIDs: mailboxes), "Legacy notification never guesses between accounts")
        let invalid = NotificationOpenRequest(userInfo: ["messageId": "", "userId": 3])
        check(!invalid.matches(messageID: "", mailboxID: "first", connectedMailboxIDs: ["first"]), "Invalid payload cannot match empty message IDs")

        let anotherColdLaunch = NotificationTapBuffer()
        anotherColdLaunch.receive(cold)
        anotherColdLaunch.receive(repeatTap)
        var replayed: [NotificationOpenRequest] = []
        anotherColdLaunch.install { replayed.append($0) }
        check(replayed == [repeatTap], "Latest cold-launch intent wins instead of presenting multiple sheets")
        print("\(checks) notification routing checks passed")
    }
}
