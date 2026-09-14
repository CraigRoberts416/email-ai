import Foundation
import Observation

@Observable
final class FeedStore {
    var mailboxes: [Mailbox] = Sample.mailboxes
    var messages: [Message] = Sample.messages
    var condition: FeedCondition = .normal

    /// Messages that arrived while the user was scrolled away. The feed set is
    /// frozen at mount and this is the only path anything joins it by — which
    /// is what makes the list stable under the thumb.
    var pending: [Message] = []

    var saved: [Message] { messages.filter { $0.isSaved } }

    var needsReconnect: [Mailbox] { mailboxes.filter { !$0.isHealthy } }

    var waitingCount: Int {
        messages.filter { $0.kicker == .needsYou }.count
    }

    // MARK: Actions — optimistic, with undo. No confirmation dialogs.

    func archive(_ message: Message) {
        messages.removeAll { $0.id == message.id }
    }

    func markRead(_ message: Message) {
        guard let i = messages.firstIndex(where: { $0.id == message.id }) else { return }
        messages[i].isRead = true
    }

    func toggleSaved(_ message: Message) {
        guard let i = messages.firstIndex(where: { $0.id == message.id }) else { return }
        messages[i].isSaved.toggle()
    }

    /// Admits the pending batch at the top. Called only from the new-posts pill.
    func admitPending() {
        guard !pending.isEmpty else { return }
        messages.insert(contentsOf: pending, at: 0)
        pending.removeAll()
    }

    func messages(groupedBy calendar: Calendar = .current) -> [(String, [Message])] {
        let groups = Dictionary(grouping: messages) { message -> String in
            if calendar.isDateInToday(message.receivedAt) { return "TODAY" }
            if calendar.isDateInYesterday(message.receivedAt) { return "YESTERDAY" }
            return "EARLIER"
        }
        return ["TODAY", "YESTERDAY", "EARLIER"].compactMap { key in
            guard let items = groups[key], !items.isEmpty else { return nil }
            return (key, items.sorted { $0.receivedAt > $1.receivedAt })
        }
    }
}

// MARK: - Sample data
//
// Stands in until the Gmail sync is wired. Shapes match the server's /feed
// payload so swapping the source is a decode, not a refactor.

enum Sample {
    static let mailboxes: [Mailbox] = [
        Mailbox(id: "mb1", address: "craig@gmail.com", provider: "Gmail",
                status: .active(lastSynced: .now), tag: "GM",
                includeInUnifiedFeed: true, notificationsEnabled: true),
        Mailbox(id: "mb2", address: "craig@northwind.co", provider: "Outlook",
                status: .active(lastSynced: .now), tag: "WORK",
                includeInUnifiedFeed: true, notificationsEnabled: true),
    ]

    static let priya = Sender(name: "Priya Raman", address: "priya@northwind.co", kind: .person, logoURL: nil)
    static let delta = Sender(name: "Delta Air Lines SkyMiles", address: "no-reply@delta.com", kind: .brand, logoURL: nil)
    static let marcus = Sender(name: "Marcus Hill", address: "marcus@acme.io", kind: .person, logoURL: nil)
    static let figma = Sender(name: "Figma", address: "news@figma.com", kind: .brand, logoURL: nil)
    static let chase = Sender(name: "Chase Security", address: "alerts@chase-secure-verify.net", kind: .brand, logoURL: nil)
    static let nike = Sender(name: "Nike", address: "news@nike.com", kind: .brand, logoURL: nil)
    static let ramp = Sender(name: "Ramp", address: "alerts@ramp.com", kind: .brand, logoURL: nil)

    static let messages: [Message] = [
        Message(
            id: "m1", threadID: "t1", mailboxID: "mb2", sender: priya,
            subject: "Design review moved",
            snippet: "Hey — had to shuffle things around this week.",
            receivedAt: .now.addingTimeInterval(-12 * 60),
            quote: "Can you do Thursday at 2?",
            summary: "She needs a yes or no before she books the room.",
            actionLabel: nil, actionURL: nil,
            kicker: .needsYou, density: .standard, shape: .text,
            isRead: false, threadCount: 4, unsubscribeURL: nil, isInterpreting: false
        ),
        Message(
            id: "m2", threadID: "t2", mailboxID: "mb1", sender: ramp,
            subject: "Card declined",
            snippet: "A vendor charge failed this morning.",
            receivedAt: .now.addingTimeInterval(-40 * 60),
            quote: "Card ending 4417 was declined",
            summary: "A vendor charge failed this morning. Nothing retries on its own.",
            actionLabel: "Update payment method",
            actionURL: URL(string: "https://ramp.com/settings/billing"),
            kicker: .needsYou, density: .lead, shape: .text,
            isRead: false, threadCount: 1, unsubscribeURL: nil, isInterpreting: false
        ),
        Message(
            id: "m3", threadID: "t3", mailboxID: "mb1", sender: delta,
            subject: "Your upcoming flight to Miami",
            snippet: "This is an important reminder that your upcoming flight DL204…",
            receivedAt: .now.addingTimeInterval(-2 * 3600),
            quote: "Departure moved to 8:15 AM",
            summary: "DL204 now leaves 55 minutes earlier than booked.",
            actionLabel: "Add ticket to Apple Wallet", actionURL: nil,
            kicker: .fyi, density: .lead, shape: .text,
            isRead: false, threadCount: 2, unsubscribeURL: nil, isInterpreting: false
        ),
        Message(
            id: "m4", threadID: "t4", mailboxID: "mb1", sender: chase,
            subject: "Urgent: verify your account",
            snippet: "Your account will be locked.",
            receivedAt: .now.addingTimeInterval(-3 * 3600),
            quote: "Your account will be locked in 24 hours",
            summary: "The domain is not chase.com. Real banks never ask you to verify through a link.",
            actionLabel: nil, actionURL: nil,
            kicker: .possibleScam, density: .standard, shape: .text,
            isRead: false, threadCount: 1, unsubscribeURL: nil, isInterpreting: false
        ),
        Message(
            id: "m5", threadID: "t5", mailboxID: "mb1", sender: nike,
            subject: "Members get early access",
            snippet: "48 hours of early access.",
            receivedAt: .now.addingTimeInterval(-5 * 3600),
            quote: nil, summary: "Sale ends Sunday",
            actionLabel: nil, actionURL: nil,
            kicker: .promotion, density: .compact, shape: .text,
            isRead: false, threadCount: 1,
            unsubscribeURL: URL(string: "https://nike.com/unsubscribe"), isInterpreting: false
        ),
        Message(
            id: "m6", threadID: "t6", mailboxID: "mb1", sender: figma,
            subject: "Config 2026",
            snippet: "Tickets go on sale Tuesday.",
            receivedAt: .now.addingTimeInterval(-6 * 3600),
            quote: nil, summary: nil, actionLabel: nil, actionURL: nil,
            kicker: .promotion, density: .standard, shape: .text,
            isRead: false, threadCount: 1,
            unsubscribeURL: URL(string: "https://figma.com/unsubscribe"), isInterpreting: true
        ),
        Message(
            id: "m7", threadID: "t7", mailboxID: "mb2", sender: marcus,
            subject: "Signed contract",
            snippet: "Sent the signed contract over.",
            receivedAt: .now.addingTimeInterval(-3 * 86400),
            quote: "Sent the signed contract over",
            summary: "Contract is done. Forward to legal when you get a minute.",
            actionLabel: nil, actionURL: nil,
            kicker: .handled, density: .standard,
            shape: .carousel([
                Attachment(id: "a1", filename: "Contract-final.pdf", byteCount: 2_400_000,
                           preview: .document(pages: 11)),
                Attachment(id: "a2", filename: "Schedule-4.pdf", byteCount: 380_000,
                           preview: .document(pages: 2)),
            ]),
            isRead: true, threadCount: 6, unsubscribeURL: nil, isInterpreting: false
        ),
    ]
}
