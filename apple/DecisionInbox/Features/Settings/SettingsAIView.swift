import SwiftUI

/// `03 · Settings · AI`.
///
/// Interpretation runs on the server, before a card ever reaches this phone.
/// There is therefore nothing here to switch off, and this screen says so
/// instead of drawing five switches that write a preference no part of the app
/// reads. What it offers instead is the true state: how many posts the model
/// has read, how many it is reading, and how many it could not read at all.
///
/// The last of those is the important one. A feed with no `COULDN'T READ` cards
/// in it looks identical whether the model understood everything or was never
/// asked, and a number is the only honest way to tell the difference.
struct SettingsAIView: View {
    @Environment(FeedStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var showingStorage = false

    var body: some View {
        SettingsScreen(title: "AI", onBack: { dismiss() }) {
            SettingsGroup(
                "INTERPRETATION",
                caption: "A model interprets feed posts on our server. Older email history can appear as original text before interpretation, so you can read it without waiting."
            )
            Rule()
            SettingsFact(title: "Posts in this feed session", value: "\(visible.count)")
            Rule()
            SettingsFact(title: "Read by the model", value: "\(read)")
            Rule()
            if reading > 0 {
                SettingsFact(title: "Being read now", value: "\(reading)")
                Rule()
            }
            SettingsFact(title: "We couldn\u{2019}t read", value: "\(unread)")
            Rule()

            SettingsParagraph("These counts describe the current feed session, not the whole mailbox. Older original-text messages may not have been interpreted.")

            SettingsGroup("WHAT IT IS ALLOWED TO DO")
            SettingsParagraph("It writes the quote and the summary on a card, and it drafts a reply when you ask for one. A draft is a draft: every email that leaves this app is one you pressed send on.")
            SettingsParagraph("Turn your phone off and you still have a working mailbox. Nothing the model does stands between you and mail that already exists on your server \u{2014} when it fails, the card falls back to the raw sender, subject and first line.")

            SettingsGroup("WHERE IT GOES")
            Rule()
            SettingsLink(
                title: "What we store",
                subtitle: "WHAT LEAVES YOUR PHONE, AND WHAT STAYS",
                action: { showingStorage = true }
            )
            Rule()
        }
        .navigationDestination(isPresented: $showingStorage) { StorageView() }
    }

    /// The same array the feed renders, not the raw store. Counting the
    /// unfiltered set here would put "42" on a screen sitting above a feed of
    /// twelve — the exact mismatch the masthead was caught doing.
    private var visible: [Message] {
        store.messages().flatMap(\.1)
    }

    private var read: Int {
        visible.count { ($0.summary?.isEmpty == false) && !$0.isInterpreting }
    }

    private var reading: Int {
        visible.count(where: \.isInterpreting)
    }

    private var unread: Int {
        visible.count { $0.kicker == .notRead }
    }
}

#Preview {
    NavigationStack { SettingsAIView() }
        .environment(FeedStore(sample: true))
}
