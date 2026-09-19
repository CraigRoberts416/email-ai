import SwiftUI

struct SavedView: View {
    @Environment(FeedStore.self) private var store
    @State private var open: Message?
    @State private var profile: Sender?

    var body: some View {
        NavigationStack {
            Group {
                if store.saved.isEmpty {
                    EmptyStateView(
                        headline: "Nothing kept yet.",
                        detail: "TAP THE BOOKMARK ON ANY CARD AND IT LANDS HERE."
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(store.saved, id: \.feedKey) { message in
                                PostView(
                                    message: message,
                                    tag: store.showsMailboxTags ? store.mailbox(message.mailboxID)?.tag : nil,
                                    onOpen: { open = message },
                                    onSave: { store.toggleSaved(message) },
                                    onArchive: { withAnimation(Move.layout) { store.archive(message) } },
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
            .navigationTitle("Saved")
            .navigationDestination(item: $profile) { SenderProfileView(sender: $0) }
            // A sheet everywhere, so a thread opened from here is the same
        // object as one opened from the feed.
        .sheet(item: $open) {
            ThreadView(message: $0)
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
                .presentationBackground(.clear)
        }
        }
    }
}
