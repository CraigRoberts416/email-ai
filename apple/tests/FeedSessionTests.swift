import Foundation

@main struct FeedSessionTests {
    static var checks = 0
    static func check(_ value: @autoclosure () -> Bool, _ reason: String) {
        precondition(value(), reason); checks += 1
    }
    static func mail(_ id: String, _ date: Date, account: String = "a", read: Bool = false) -> Message {
        Message(id: id, mailboxID: account, sender: Sender(name: "Sender", address: "sender@example.com", kind: .person),
                subject: id, snippet: id, receivedAt: date, kicker: .fyi, shape: .text,
                isRead: read, threadCount: 1, isInterpreting: false)
    }
    static func main() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let now = ISO8601DateFormatter().date(from: "2026-09-19T14:00:00Z")!
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        var session = FeedSession()
        let a = mail("a", now), b = mail("b", yesterday), old = mail("old", yesterday.addingTimeInterval(-1))
        session.restart(with: [old, b, a, a, mail("read", now, read: true)], at: now, calendar: calendar)
        check(session.cards.map(\.id) == ["a", "b", "old"], "Start sorts unread and deduplicates")
        check(session.groups(included: ["a"]).map(\.0) == ["TODAY", "YESTERDAY", "EARLIER"], "Exactly three date sections")
        session.interacted()
        session.update(a.feedKey) { $0.isRead = true }
        check(session.cards.map(\.id) == ["a", "b", "old"], "Read never removes or reorders")
        check(session.cards[0].isRead, "Read state can update while row remains")
        check(session.groups(included: ["a"])[0].1.count == 1, "A zero-unread section keeps its visible card")
        session.append([a, b, old, mail("older", yesterday.addingTimeInterval(-100))])
        check(session.cards.map(\.id) == ["a", "b", "old", "older"], "Pagination appends without resurrecting or duplicating")
        let new = mail("new", now.addingTimeInterval(30))
        session.admit([new, a])
        check(session.cards.map(\.id) == ["new", "a", "b", "old", "older"], "Explicit bubble admission preserves existing order")
        let previous = session.cards
        session.restart(with: previous, at: now, calendar: calendar)
        check(session.cards.map(\.id) == ["new", "b", "old", "older"], "Next session removes read cards only")
        check(!session.hasInteracted, "New visit resets interaction state")
        check(session.section(for: today.addingTimeInterval(-1)) == "YESTERDAY", "Local midnight boundary")
        check(session.section(for: yesterday.addingTimeInterval(-1)) == "EARLIER", "Earlier includes entire older backlog")
        check(session.section(for: now.addingTimeInterval(86400)) == "TODAY", "New mail across midnight does not reshuffle active visit")
        session.restart(with: [a, mail("a", now, account: "b")], at: now, calendar: calendar)
        check(session.cards.count == 2, "Message identity is namespaced by account")
        check(session.groups(included: ["a"])[0].1.count == 1, "Excluded account does not enter feed section")
        session.remove(a.feedKey)
        check(session.cards.count == 1, "Explicit archive removes just its own account record")
        session.restore(a, at: 0)
        check(session.cards.first?.feedKey == a.feedKey, "Undo restores original position")
        var counts = FeedSectionCounts(today: 10, yesterday: 30, earlier: 22_350)
        counts["TODAY"] -= 1
        check(counts.total == 22_389 && counts.yesterday == 30, "Only the read section decrements; full backlog remains counted")
        counts["TODAY"] = -1
        check(counts.today == 0, "Counter cannot go below zero")
        print("\(checks) production session/count checks passed")
    }
}
