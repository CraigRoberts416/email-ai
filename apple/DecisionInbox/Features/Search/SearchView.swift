import SwiftUI

struct SearchView: View {
    @Environment(FeedStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var query = ""
    @State private var open: Message?
    @State private var initialComposeIntent: ComposeView.Intent?
    @State private var focusDiscussion = false
    @State private var profile: Sender?

    /// Searches what is on the device: the sender, the subject, and every line
    /// the model wrote. Searching the quote is the point — you remember what an
    /// email asked you long after you have forgotten its subject line.
    private var searchQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var searchable: [Message] {
        Array(Dictionary((store.messages + store.saved).map { ($0.feedKey, $0) }, uniquingKeysWith: { _, newer in newer }).values)
            .sorted { $0.receivedAt > $1.receivedAt }
    }
    private var results: [Message] {
        guard !searchQuery.isEmpty else { return [] }
        let q = searchQuery.lowercased()
        return searchable.filter {
            $0.sender.displayName.lowercased().contains(q)
                || $0.sender.address.lowercased().contains(q)
                || $0.snippet.lowercased().contains(q)
                || $0.subject.lowercased().contains(q)
                || ($0.quote ?? "").lowercased().contains(q)
                || ($0.summary ?? "").lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if searchQuery.isEmpty {
                    EmptyStateView(
                        headline: "Search loaded mail.",
                        detail: "SEARCH LOADED FEED AND SAVED EMAILS. FULL BODIES AND UNLOADED HISTORY ARE NOT SEARCHED."
                    )
                } else if results.isEmpty {
                    // Not an error — the query ran and returned nothing.
                    EmptyStateView(
                        headline: "Nothing for \u{201C}\(query)\u{201D}.",
                        detail: "SEARCHED LOADED FEED AND SAVED EMAILS. OTHER MAIL MAY NOT BE LOADED."
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(results, id: \.feedKey) { message in
                                PostView(
                                    message: message,
                                    tag: store.showsMailboxTags ? store.mailbox(message.mailboxID)?.tag : nil,
                                    onOpen: { initialComposeIntent = nil; focusDiscussion = false; open = message },
                                    onReply: { initialComposeIntent = .reply; focusDiscussion = false; open = message },
                                    onDiscuss: { initialComposeIntent = nil; focusDiscussion = true; open = message },
                                    onForward: { initialComposeIntent = .forward; focusDiscussion = false; open = message },
                                    onSave: { store.toggleSaved(message) },
                                    onArchive: { withAnimation(Move.resolved(Move.layout, reduceMotion)) { store.archive(message) } },
                                    onUnsubscribe: { store.unsubscribe(from: message) },
                                    // A found post behaves like a feed post.
                                    // The avatar was inert here only because
                                    // this call site never passed the handler.
                                    onProfile: { profile = message.sender },
                                    onReact: { store.react(message, $0) }
                                )
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .background(Ink.surface)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { ActivityToolbarButton() } }
            .navigationTitle("Search")
            .searchable(text: $query, prompt: "Search loaded mail")
            .safeAreaInset(edge: .top) {
                Text("\(searchable.count) loaded feed + saved emails · all connected mailboxes")
                    .typeStyle(Style.monoMicro).foregroundStyle(Ink.secondary).padding(.vertical, Space.sm)
                    .frame(maxWidth: .infinity).background(Ink.surface)
            }
            // A sheet everywhere, so a thread opened from here is the same
        // object as one opened from the feed.
        .sheet(item: $open) {
            ThreadView(message: $0, initialComposeIntent: initialComposeIntent, focusDiscussion: focusDiscussion)
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
                .presentationBackground(.clear)
        }
            .navigationDestination(item: $profile) { SenderProfileView(sender: $0) }
        }
    }
}
