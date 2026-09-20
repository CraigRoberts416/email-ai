import Foundation

/// A visit owns its visible cards. Provider read state can change without
/// changing this ordered snapshot; only a new visit discards read cards.
struct FeedSession {
    private(set) var cards: [Message] = []
    private(set) var startedAt = Date()
    private(set) var generation = 0
    private(set) var hasInteracted = false
    private var calendar = Calendar.current
    var timeZone: TimeZone { calendar.timeZone }

    static func key(_ message: Message) -> String { message.mailboxID + ":" + message.id }

    mutating func restart(with messages: [Message], at date: Date = .now, calendar: Calendar = .current) {
        generation += 1
        startedAt = date
        self.calendar = calendar
        hasInteracted = false
        var known: Set<String> = []
        cards = messages.filter { !$0.isRead && $0.isFeedEligible && known.insert(Self.key($0)).inserted }
            .sorted(by: Self.newer)
    }

    mutating func interacted() { hasInteracted = true }

    /// Explicit new-mail admission may insert at the top. It never reorders
    /// the cards the reader already had in front of them.
    mutating func admit(_ messages: [Message]) {
        let known = Set(cards.map(Self.key))
        let fresh = messages.filter { !known.contains(Self.key($0)) && !$0.isRead }
        cards.insert(contentsOf: fresh.sorted(by: Self.newer), at: 0)
    }

    /// Pagination only appends. A duplicate read card stays in the session.
    mutating func append(_ messages: [Message]) {
        var known = Set(cards.map(Self.key))
        cards.append(contentsOf: messages.sorted(by: Self.newer).filter {
            !$0.isRead && known.insert(Self.key($0)).inserted
        })
    }

    mutating func update(_ key: String, _ change: (inout Message) -> Void) {
        guard let index = cards.firstIndex(where: { Self.key($0) == key }) else { return }
        change(&cards[index])
    }

    /// Archive is a deliberate removal, separate from marking a post read.
    mutating func remove(_ key: String) { cards.removeAll { Self.key($0) == key } }
    mutating func restore(_ message: Message, at index: Int) {
        guard !cards.contains(where: { Self.key($0) == Self.key(message) }) else { return }
        cards.insert(message, at: min(max(0, index), cards.count))
    }

    func section(for date: Date) -> String {
        let today = calendar.startOfDay(for: startedAt)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        return date >= today ? "TODAY" : (date >= yesterday ? "YESTERDAY" : "EARLIER")
    }

    func groups(included: Set<String>) -> [(String, [Message])] {
        let groups = Dictionary(grouping: cards.filter { included.contains($0.mailboxID) }) { section(for: $0.receivedAt) }
        return ["TODAY", "YESTERDAY", "EARLIER"].compactMap { name in
            guard let items = groups[name], !items.isEmpty else { return nil }
            return (name, items)
        }
    }

    static func newer(_ lhs: Message, _ rhs: Message) -> Bool {
        lhs.receivedAt == rhs.receivedAt ? key(lhs) > key(rhs) : lhs.receivedAt > rhs.receivedAt
    }
}

struct FeedSectionCounts: Codable, Equatable {
    var today: Int
    var yesterday: Int
    var earlier: Int
    var total: Int { today + yesterday + earlier }
    var isValid: Bool { today >= 0 && yesterday >= 0 && earlier >= 0 }

    subscript(_ section: String) -> Int {
        get { section == "TODAY" ? today : (section == "YESTERDAY" ? yesterday : earlier) }
        set {
            switch section {
            case "TODAY": today = max(0, newValue)
            case "YESTERDAY": yesterday = max(0, newValue)
            default: earlier = max(0, newValue)
            }
        }
    }
}

extension Message { var feedKey: String { FeedSession.key(self) } }

/// Durable evidence of an accepted read. No email body or sender data is needed
/// to finish this write after a tab change, suspension, or process restart.
struct FeedReadIntent: Codable {
    let id: String
    let mailboxID: String
    let receivedAt: Date
    let isFeedEligible: Bool
    var key: String { mailboxID + ":" + id }
    init(_ message: Message) {
        id = message.id; mailboxID = message.mailboxID
        receivedAt = message.receivedAt; isFeedEligible = message.isFeedEligible
    }
}

/// A display baseline, never authority for inbox zero or the application badge.
/// Keep it only while its date bands still mean the same thing. A session can
/// span midnight, so aggregate buckets cannot safely be split into new days.
struct FeedProgressSnapshot: Codable {
    let date: Date
    let timeZone: String
    let sections: [String: FeedSectionCounts]

    func rebased(at date: Date, calendar: Calendar = .current) -> [String: FeedSectionCounts] {
        guard calendar.timeZone.identifier == timeZone,
              calendar.isDate(self.date, inSameDayAs: date) else { return [:] }
        return sections.filter { $0.value.isValid }
    }
}
