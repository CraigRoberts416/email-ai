import SwiftUI

struct SavedView: View {
    @Environment(FeedStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var open: Message?
    @State private var initialComposeIntent: ComposeView.Intent?
    @State private var focusDiscussion = false
    @State private var profile: Sender?

    var body: some View {
        NavigationStack {
            Group {
                if store.saved.isEmpty {
                    EmptyStateView(
                        headline: "Nothing kept yet.",
                        detail: "TAP THE BOOKMARK ON ANY CARD AND IT LANDS HERE.",
                        illustration: .reading
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(store.saved, id: \.feedKey) { message in
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
                                    onProfile: { profile = message.sender }
                                )
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .background(Ink.surface)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { ActivityToolbarButton() } }
            .navigationTitle("Saved")
            .navigationDestination(item: $profile) { SenderProfileView(sender: $0) }
            // A sheet everywhere, so a thread opened from here is the same
        // object as one opened from the feed.
        .sheet(item: $open) {
            ThreadView(message: $0, initialComposeIntent: initialComposeIntent, focusDiscussion: focusDiscussion)
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
                .presentationBackground(.clear)
        }
        }
    }
}
