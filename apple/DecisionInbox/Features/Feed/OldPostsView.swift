import SwiftUI

/// History is a deliberate visit. Scrolling here never changes read state.
struct OldPostsView: View {
    @Environment(FeedStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var posts: [Message] = []
    @State private var cursors: [String: Int] = [:]
    @State private var loaded = false
    @State private var loading = false
    @State private var failed = false
    @State private var open: Message?
    @State private var profile: Sender?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(posts, id: \.feedKey) { message in
                        PostView(message: store.currentVersion(of: message),
                            tag: store.showsMailboxTags ? store.mailbox(message.mailboxID)?.tag : nil,
                            onOpen: { open = message }, onReply: { open = message },
                            onDiscuss: { open = message }, onForward: { open = message },
                            onSave: { store.toggleSaved(message) },
                            onArchive: { store.archive(message) },
                            onUnsubscribe: { store.unsubscribe(from: message) },
                            onProfile: { profile = message.sender },
                            onReact: { store.react(message, $0) })
                    }
                    if failed {
                        EmptyStateView(headline: "Couldn’t load older posts.", detail: "YOUR MAIL IS STILL THERE.",
                            actionLabel: "Try again", action: { Task { await loadMore() } })
                    } else if loading {
                        ProgressView().padding(Space.xl).accessibilityLabel("Loading old posts")
                    } else if loaded && posts.isEmpty && cursors.isEmpty {
                        EmptyStateView(headline: "No old posts yet.", detail: "POSTS YOU’VE SEEN WILL BE HERE.")
                    }
                    if !cursors.isEmpty && !loading {
                        Button("Load more") { Task { await loadMore() } }
                            .frame(minHeight: Metric.tapTarget).padding(Space.lg)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let receipt = store.receipt {
                    ToastView(message: receipt.message, detail: receipt.detail,
                        actionLabel: receipt.undo == nil ? nil : "Undo",
                        action: {
                            switch receipt.undo {
                            case .archive(let message, let index): store.undoArchive(message, at: index)
                            case .send: store.undoSend()
                            case .none: break
                            }
                        }, onDismiss: { store.dismissReceipt() })
                }
            }
            .background(Ink.surface)
            .navigationTitle("Old posts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .navigationDestination(item: $profile) { SenderProfileView(sender: $0) }
            .sheet(item: $open) { ThreadView(message: $0).presentationDetents([.large]) }
            .task { if !loaded { await loadMore() } }
        }
    }

    private func loadMore() async {
        guard !loading else { return }
        loading = true
        failed = false
        defer { loading = false }
        let mailboxes = store.mailboxes.filter(\.includeInUnifiedFeed)
        do {
            for mailbox in mailboxes where !loaded || cursors[mailbox.id] != nil {
                let result = try await store.oldPosts(accountID: mailbox.id, cursor: cursors[mailbox.id])
                let known = Set(posts.map { $0.mailboxID + ":" + $0.id })
                posts.append(contentsOf: result.posts.filter { !known.contains($0.mailboxID + ":" + $0.id) })
                cursors[mailbox.id] = result.cursor
            }
            posts.sort { $0.receivedAt > $1.receivedAt }
            loaded = true
        } catch { failed = true }
    }
}
