import SwiftUI

struct SavedView: View {
    @Environment(FeedStore.self) private var store
    @State private var open: Message?

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
                            ForEach(store.saved) { message in
                                PostView(
                                    message: message,
                                    tag: store.showsMailboxTags ? store.mailbox(message.mailboxID)?.tag : nil,
                                    onOpen: { open = message },
                                    onSave: { store.toggleSaved(message) },
                                    onArchive: { withAnimation(Move.layout) { store.archive(message) } },
                                    onUnsubscribe: { store.unsubscribe(from: message) }
                                )
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .background(Ink.surface)
            .navigationTitle("Saved")
            .navigationDestination(item: $open) { ThreadView(message: $0) }
        }
    }
}
