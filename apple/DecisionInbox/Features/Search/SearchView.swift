import SwiftUI

struct SearchView: View {
    @Environment(FeedStore.self) private var store
    @State private var query = ""
    @State private var open: Message?
    @State private var profile: Sender?

    /// Searches what is on the device: the sender, the subject, and every line
    /// the model wrote. Searching the quote is the point — you remember what an
    /// email asked you long after you have forgotten its subject line.
    private var results: [Message] {
        guard !query.isEmpty else { return [] }
        let q = query.lowercased()
        return store.messages.filter {
            $0.sender.displayName.lowercased().contains(q)
                || $0.subject.lowercased().contains(q)
                || ($0.quote ?? "").lowercased().contains(q)
                || ($0.summary ?? "").lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if query.isEmpty {
                    EmptyStateView(
                        headline: "Search your mail.",
                        detail: "SENDERS, SUBJECTS, AND EVERY LINE THE AI PULLED OUT."
                    )
                } else if results.isEmpty {
                    // Not an error — the query ran and returned nothing.
                    EmptyStateView(
                        headline: "Nothing for \u{201C}\(query)\u{201D}.",
                        detail: "SEARCHED EVERY INTERPRETED EMAIL IN YOUR FEED."
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(results) { message in
                                PostView(
                                    message: message,
                                    tag: store.showsMailboxTags ? store.mailbox(message.mailboxID)?.tag : nil,
                                    onOpen: { open = message },
                                    onSave: { store.toggleSaved(message) },
                                    onArchive: { withAnimation(Move.layout) { store.archive(message) } },
                                    onUnsubscribe: { store.unsubscribe(from: message) },
                                    // A found post behaves like a feed post.
                                    // The avatar was inert here only because
                                    // this call site never passed the handler.
                                    onProfile: { profile = message.sender }
                                )
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .background(Ink.surface)
            .navigationTitle("Search")
            .searchable(text: $query, prompt: "Find an email")
            .navigationDestination(item: $open) { ThreadView(message: $0) }
            .navigationDestination(item: $profile) { SenderProfileView(sender: $0) }
        }
    }
}
