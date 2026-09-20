import SwiftUI

/// Mail from people, as conversations.
///
/// Built to `DirectMessages`. An email to one person is a direct message — it
/// has a sender, a recipient, a back-and-forth and a history, everything a DM
/// has. The only reason mail clients do not present it that way is an
/// inherited metaphor from paper. In a feed sorted by arrival, a reply from
/// someone you know sits under everything a retailer sent that morning.
///
/// The unit of this surface is the person, not the message.
struct DirectMessagesView: View {
    @Environment(FeedStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var open: Conversation?
    @State private var profile: Sender?
    @State private var contactPhotos = ContactPhotoStore.shared
    @State private var identities = SenderIdentityStore.shared
    @AppStorage("people.dismissPhotoPrompt") private var dismissPhotoPrompt = false

    private var waiting: Int {
        store.peopleUnreadCount
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                    masthead
                    if !contactPhotos.enabled && !dismissPhotoPrompt
                        && !(identities.googlePhotosEnabled && store.auth.accounts.contains(where: { identities.hasGooglePhotoAccess(for: $0.id) })) {
                        HStack(spacing: Space.sm) {
                            Button {
                                Task {
                                    _ = await contactPhotos.setEnabled(true)
                                    dismissPhotoPrompt = true
                                }
                            } label: {
                                Label("Add personal contact photos", systemImage: "person.crop.circle")
                                    .typeStyle(Style.body)
                            }
                            Spacer()
                            Button { dismissPhotoPrompt = true } label: {
                                Image(systemName: "xmark").frame(width: Metric.tapTarget, height: Metric.tapTarget)
                            }
                            .accessibilityLabel("Dismiss contact photo suggestion")
                        }
                        .padding(.horizontal, Metric.gutter)
                        .foregroundStyle(Ink.secondary)
                        Rule()
                    }

                    if let failure = store.conversationsFailure {
                        VStack(alignment: .leading, spacing: Space.sm) {
                            Text(failure).typeStyle(Style.body).foregroundStyle(Ink.secondary)
                            Button("Try again") { Task { await store.loadConversations() } }
                                .frame(minHeight: Metric.tapTarget)
                        }
                        .padding(Metric.gutter)
                    }
                    if store.conversations.isEmpty && store.conversationsFailure == nil {
                        EmptyStateView(
                            headline: store.conversationsLoaded && store.conversationsHistoryComplete
                                ? "No one has written."
                                : "Reading your mail\u{2026}",
                            detail: store.conversationsLoaded && store.conversationsHistoryComplete
                                ? "MAIL FROM A PERSON APPEARS HERE. COMPANIES STAY IN THE FEED."
                                : "LOOKING FOR THE PEOPLE IN YOUR MAILBOX."
                        )
                        .frame(height: 320)
                    } else {
                        ForEach(store.conversations) { conversation in
                            Button { open = conversation } label: {
                                ConversationRow(conversation: conversation,
                                                onProfile: { profile = $0 })
                            }
                            .buttonStyle(.plain)
                            Rule()
                        }
                    }
                    if store.conversationsNextCursor != nil {
                        Button(store.conversationsLoading ? "Loading…" : "See older conversations") {
                            Task { await store.loadMoreConversations() }
                        }
                        .typeStyle(Style.body)
                        .frame(maxWidth: .infinity, minHeight: Metric.tapTarget)
                        .disabled(store.conversationsLoading)
                        .padding(Metric.gutter)
                    }
                    if store.conversationsLoaded && !store.conversationsHistoryComplete {
                        VStack(alignment: .leading, spacing: Space.sm) {
                            Text(store.conversationsSyncState == "failed"
                                 ? "Older mail hasn’t finished importing."
                                 : (store.conversationsSyncState == "indexing"
                                    ? "Finding your conversations. Those found so far appear above."
                                    : "Older mail is still importing. These are the conversations found so far."))
                                .typeStyle(Style.monoCaption)
                                .foregroundStyle(Ink.secondary)
                            Button("Refresh history") { Task { await store.loadConversations() } }
                                .frame(minHeight: Metric.tapTarget)
                                .disabled(store.conversationsLoading)
                        }
                        .padding(Metric.gutter)
                    }
                }
                .safeAreaPadding(.bottom, Space.xxxl + Space.xl)
            }
            .scrollIndicators(.hidden)
            .feedEdges()
            .background(Ink.surface)
            .navigationBarHidden(true)
            .navigationDestination(item: $open) { DirectThreadView(conversation: $0) }
            .navigationDestination(item: $profile) { SenderProfileView(sender: $0) }
            .task(id: scenePhase == .active && open == nil && profile == nil) {
                guard scenePhase == .active, open == nil, profile == nil else { return }
                await store.loadConversations(preservingLoaded: true)
                while !Task.isCancelled && !store.conversationsHistoryComplete {
                    do { try await Task.sleep(for: .seconds(store.conversationsFailure == nil ? 3 : 8)) }
                    catch { return }
                    guard !Task.isCancelled else { return }
                    await store.loadConversations(preservingLoaded: true)
                }
            }
            .refreshable { await store.loadConversations() }
        }
    }

    private var masthead: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text("PEOPLE")
                .typeStyle(Style.sectionHeader)
                .foregroundStyle(Ink.tertiary)

            HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                // An em dash until the list has loaded. A zero here is an
                // assertion about someone's mailbox before it has been read —
                // the same rule the feed's masthead follows.
                Text(store.conversationsLoaded ? "\(waiting)" : "\u{2014}")
                    .typeStyle(Style.tickCount)
                    .foregroundStyle(store.conversationsLoaded ? Ink.primary : Ink.tertiary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(store.conversationsLoaded ? (store.conversationsHistoryComplete ? "UNREAD CONVERSATIONS" : "UNREAD LOADED") : "READING")
                    .typeStyle(Style.kicker)
                    .foregroundStyle(store.conversationsLoaded ? Ink.primary : Ink.tertiary)
            }
        }
        .padding(.horizontal, Metric.gutter)
        .padding(.top, Space.xl)
        .padding(.bottom, Space.lg)
    }
}

struct ConversationRow: View {
    let conversation: Conversation
    /// The row opens the conversation; the avatar opens the person. An
    /// ancestor tap beats a descendant one, so this has to be claimed at high
    /// priority or the row swallows it.
    var onProfile: (Sender) -> Void = { _ in }

    var body: some View {
        HStack(spacing: Space.md) {
            GroupAvatar(participants: conversation.participants, size: 52)
                .contentShape(.circle)
                .highPriorityGesture(TapGesture().onEnded {
                    guard !conversation.isGroup,
                          let one = conversation.participants.first else { return }
                    onProfile(one)
                })

            VStack(alignment: .leading, spacing: 3) {
                Text(conversation.title)
                    .typeStyle(Style.body)
                    .foregroundStyle(Ink.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                // Mono for the preview, sans for the name. The name is a
                // person; the preview is a line lifted out of their mail, and
                // the two voices stay apart the way they do everywhere else.
                Text(preview)
                    .typeStyle(Style.monoCaption)
                    .foregroundStyle(conversation.unread ? Ink.primary : Ink.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: Space.sm) {
                Text(conversation.lastAt.feedStamp)
                    .typeStyle(Style.monoMicro)
                    .foregroundStyle(Ink.tertiary)

                // Unread is a filled dot, never a colour. Everything here
                // carries state in weight, fill and shape; a blue dot would be
                // the only hue in the product.
                Circle()
                    .fill(conversation.unread ? Ink.primary : .clear)
                    .frame(width: 7, height: 7)
            }
        }
        .padding(.horizontal, Metric.gutter)
        .padding(.vertical, Space.md)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibility)
    }

    private var preview: String {
        conversation.lastFromMe ? "You: \(conversation.preview)" : conversation.preview
    }

    private var accessibility: String {
        var parts = [conversation.title]
        if conversation.unread { parts.append("unread") }
        parts.append(preview)
        parts.append(conversation.lastAt.spokenStamp)
        return parts.joined(separator: ". ")
    }
}
