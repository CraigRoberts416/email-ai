import SwiftUI

/// Everything one sender has ever said to you.
///
/// Built the way a social profile is built, because that is the shape the
/// question already has: who is this, how much of my attention do they take,
/// and what is outstanding between us. An email client normally answers that
/// with a search results page, which answers none of it.
///
/// The banner is the sender's own generated image. It is the one place in the
/// product where a picture is the point rather than decoration — a mailbox is
/// mostly brands, and a brand is faster to recognise than to read.
struct SenderProfileView: View {
    let sender: Sender

    @Environment(FeedStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lane: Lane = .emails
    @Namespace private var laneMotion
    @State private var open: Message?
    @State private var initialComposeIntent: ComposeView.Intent?
    @State private var focusDiscussion = false
    @State private var thread: Conversation?
    /// The conversation's own messages. The lanes below were built when a
    /// profile could only be reached from the feed, so all three read
    /// `store.messages(from:)` — and somebody you only ever talk to has none
    /// of those. Her PDFs were in the thread the whole time.
    @State private var chatMessages: [ConversationMessage] = []
    @State private var loadingConversation = false
    /// Opens a file from the Docs lane. A paperclip tab that opens the thread
    /// instead of the document makes the user find the file twice.
    @State private var opener = AttachmentOpener()
    @State private var presentedImage: MediaEntry?
    @State private var lastOpenedFile: Attachment?
    @State private var identities = SenderIdentityStore.shared
    @State private var history: SenderHistoryStore?
    @State private var historyFooterVisible = false

    /// `emails`, not `messages`. This is a mail client — the thing on screen
    /// is an email, and calling it a message borrows a word from chat apps
    /// where it means something slightly different.
    enum Lane: String, CaseIterable, Identifiable {
        case emails, media, docs
        var id: String { rawValue }
        var label: String { rawValue.uppercased() }

        /// Carries the tab on its own when the tab is closed, so each has to
        /// be unambiguous without its label.
        var symbol: String {
            switch self {
            case .emails:   return "tray.full"
            case .media:    return "photo.on.rectangle"
            case .docs:     return "paperclip"
            }
        }
    }

    private var all: [Message] { store.messages(from: sender.address) }
    private var threads: [Message] { all.filter { $0.threadCount > 1 } }

    /// Both entry points use the same post component. Conversation messages
    /// supply their original words; they do not receive invented summaries.
    private var posts: [Message] {
        if let history, history.hasReceivedHistory || !history.messages.isEmpty {
            return history.messages.map { source in
                var message = source
                let current = store.currentVersion(of: source)
                message.isRead = source.isRead || current.isRead
                message.isSaved = current.isSaved
                message.reaction = current.reaction
                return message
            }.sorted(by: FeedSession.newer)
        }
        var result = all
        var ids = Set(all.map(\.id))
        // Conversation loading is currently scoped to the first account.
        // A newer feed post may belong to another connected mailbox.
        let mailboxID = store.auth.accounts.first?.id ?? store.mailboxes.first?.id ?? ""
        for message in chatMessages where !message.mine
            && message.sender.address.caseInsensitiveCompare(sender.address) == .orderedSame {
            guard ids.insert(message.id).inserted else { continue }
            result.append(Message(
                id: message.id,
                threadID: nil,
                mailboxID: mailboxID,
                sender: message.sender,
                subject: message.subject ?? "",
                snippet: message.body,
                receivedAt: message.receivedAt,
                quote: message.body.isEmpty ? nil : message.body,
                summary: nil,
                actionLabel: nil,
                actionURL: nil,
                kicker: .notRead,
                shape: .text,
                heroImageURL: nil,
                heroBackground: nil,
                senderDescription: nil,
                imageURL: nil,
                attachments: message.attachments,
                isRead: true,
                threadCount: 1,
                unsubscribeURL: nil,
                isInterpreting: false
            ))
        }
        return result.map { store.currentVersion(of: $0) }
            .sorted { $0.receivedAt > $1.receivedAt }
    }

    /// However many emails the EMAILS lane is showing.
    private var emailCount: Int? { history?.totalCount }

    /// Their chat thread, which lives in the archive rather than the feed.
    private var chat: Conversation? { store.conversation(with: sender.address) }

    /// One file they sent, wherever it came from.
    private struct FileEntry: Identifiable {
        let id: String
        let file: Attachment
        let receivedAt: Date
    }

    private struct MediaEntry: Identifiable {
        let id: String
        let url: URL
        let filename: String?
        let file: Attachment?
    }
    private var replies: [Message] { all.filter { $0.kicker == .waitingOnThem } }

    /// Every picture this sender has sent: the email's own image, plus any
    /// image they attached. Never the generated hero — it is not a photograph
    /// of anything that happened, and a grid is a claim that these are.
    private var media: [MediaEntry] {
        var entries: [MediaEntry] = []
        for message in posts {
            var imageURLs = Set<URL>()
            for attachment in message.attachments {
                if case .image(let url) = attachment.preview {
                    imageURLs.insert(url)
                    entries.append(MediaEntry(id: "\(message.feedKey)/\(attachment.id)", url: url,
                                              filename: attachment.filename, file: attachment))
                }
            }
            if let picture = message.imageURL, !imageURLs.contains(picture) {
                entries.append(MediaEntry(id: "\(message.feedKey)/body-image", url: picture,
                                          filename: nil, file: nil))
            }
        }
        return entries
    }

    /// Everything they attached that is not a picture.
    private var docs: [FileEntry] {
        let isDocument: (Attachment) -> Bool = {
            if case .document = $0.preview { return true } else { return false }
        }
        return posts.flatMap { message in
            message.attachments.filter(isDocument).map {
                FileEntry(id: "\(message.feedKey)/\($0.id)", file: $0,
                          receivedAt: message.receivedAt)
            }
        }
    }

    private var identity: SenderIdentityStore.Profile? { identities.profile(for: sender.address) }
    private var banner: URL? { identity?.heroImageUrl ?? all.compactMap(\.heroImageURL).first }
    private var ground: Color { .sheet(fromHex: identity?.heroImageBgColor ?? all.compactMap(\.heroBackground).first) }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                header
                lanePicker
                Rule()

                switch lane {
                case .media:   mediaGrid
                case .docs:    docsGrid
                case .emails:  emailList
                }
                historyFooter
                    .onScrollVisibilityChange(threshold: 0.1) { historyFooterVisible = $0 }
                    .onChange(of: "\(history?.messages.count ?? 0):\(history?.hasMore ?? false):\(history?.isLoading ?? false):\(historyFooterVisible)") {
                        if historyFooterVisible, let history, history.hasMore, !history.isLoading, history.failure == nil {
                            // Publishing page contents must not cancel the
                            // same request's remaining source inspection.
                            Task { await history.loadMore() }
                        }
                    }
            }
            .safeAreaPadding(.bottom, Space.xxxl + Space.xl)
        }
        .scrollIndicators(.hidden)
        .clearHeroHeader()
        .task(id: sender.address) {
            if history == nil { history = SenderHistoryStore(auth: store.auth, sender: sender, sample: store.isSample, seed: all) }
            await history?.start()
        }
        .ignoresSafeArea(edges: .top)
        .background(Ink.surface)
        .task(id: sender.address + identities.authorizationVersion) {
            identities.remember(messages: all)
            await identities.load(for: sender)
        }
        .sheet(item: $opener.previewing) { QuickLookView(url: $0.url).ignoresSafeArea() }
        .sheet(item: $presentedImage) { entry in
            NavigationStack {
                ZStack {
                    Ink.inverse.ignoresSafeArea()
                    AsyncImage(url: entry.url) { phase in
                        switch phase {
                        case .success(let image): image.resizable().scaledToFit()
                        case .failure:
                            Text("This picture could not be loaded.").foregroundStyle(Ink.onInverse)
                        default: ProgressView().tint(Ink.onInverse)
                        }
                    }
                    .accessibilityLabel(entry.filename ?? "Email image")
                }
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { presentedImage = nil }
                    }
                }
            }
        }
        .alert("Could not open file", isPresented: Binding(
            get: { if case .failed = opener.state { return true }; return false },
            set: { if !$0 { opener.state = .idle } }
        )) {
            if let lastOpenedFile {
                Button("Try again") { openFile(lastOpenedFile) }
            }
            Button("Cancel", role: .cancel) { opener.state = .idle }
        } message: {
            if case .failed(let reason) = opener.state { Text(reason) }
        }
        .task(id: chat?.id) {
            guard let chat else { return }
            // Disk first so the lanes are populated before the first frame,
            // then the network. Same order the thread itself uses.
            chatMessages = store.cachedMessages(in: chat)
            loadingConversation = true
            defer { loadingConversation = false }
            let received = await store.messages(in: chat)
            guard !Task.isCancelled else { return }
            // Keep useful cached content when the network returns no records.
            if !received.isEmpty || chatMessages.isEmpty { chatMessages = received }
        }
        .toolbar { ToolbarItem(placement: .topBarTrailing) { ActivityToolbarButton() } }
        .safeAreaInset(edge: .bottom) {
            if openingFile { HStack { ProgressView("Opening file…"); Spacer(); Button("Cancel") { opener.cancel() } }.padding().background(Ink.surface) }
        }
        .onDisappear { opener.cancel() }
        .backNavigation { dismiss() }
        .toolbar(.hidden, for: .tabBar)
        // A sheet everywhere, so a thread opened from here is the same
        // object as one opened from the feed.
        .sheet(item: $open) {
            ThreadView(message: $0, initialComposeIntent: initialComposeIntent, focusDiscussion: focusDiscussion)
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
                .presentationBackground(.clear)
        }
        // Wrapped in its own stack: the chat thread pushes a profile of its
        // own, and a sheet supplies no stack to push onto.
        .sheet(item: $thread) { conversation in
            NavigationStack { DirectThreadView(conversation: conversation) }
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
        }
    }

    // MARK: Header
    //
    // Built to `SenderProfile`. The Twitter shape, in this product's system:
    // banner, chrome floating on it, avatar crossing the seam, identity
    // descending loudest to quietest, counts, two actions.

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The banner, or the sender's own ground if no image has been
            // generated yet. Never a placeholder pattern — an empty band of
            // their colour is honest and still recognisably theirs.
            Group {
                if let banner {
                    CachedRemoteImage(url: banner, cacheKey: identities.imageKey(for: sender.address, role: "hero")) {
                        ground
                    }
                } else {
                    ground
                }
            }
            // 180, and the depth was never the problem — the chrome position
            // was. The back control and the avatar both sit on the 16pt
            // gutter, so they stack on one vertical line: the banner has to
            // clear the status bar, the control, a real gap, and the part of
            // the avatar above the seam. Deepening it without moving the
            // control just moved the collision down.
            .frame(height: 180)
            .frame(maxWidth: .infinity)
            .clipped()

            VStack(alignment: .leading, spacing: Space.xs) {
                // Crosses the seam, ringed in the page ground — the one shape
                // on this screen belonging to both bands.
                // The white ring separates it from the banner; the hairline
                // outside that separates it from the page. Only the ring was
                // there, and it was drawn OVER the avatar's own hairline — so
                // a mark on a white ground, sitting on a white page, had no
                // visible edge at all below the seam. Both bands need an edge,
                // and they are different edges.
                AvatarView(sender: sender, size: 84)
                    .padding(4)
                    .background(Ink.surface, in: Circle())
                    .overlay(Circle().strokeBorder(Ink.border, lineWidth: 1))
                    .padding(.top, -34)
                    .padding(.bottom, Space.md)

                Text(sender.displayName)
                    .typeStyle(Style.quote)
                    .foregroundStyle(Ink.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(history?.scope == "domain" ? (history?.scopeKey ?? sender.address) : sender.address)
                    .typeStyle(Style.monoCaption)
                    .foregroundStyle(Ink.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                // Where a profile carries a bio: who this sender is.
                //
                // Not a summary of their mail. The counts directly below
                // already report volume and what has been asked of you, and
                // saying that again in prose spends the one line that could
                // tell you something you did not already know.
                //
                // Absent rather than invented when the model does not
                // recognise the sender: a blank is a missing sentence, a guess
                // is a false claim about a real company on the one screen whose
                // whole job is identification.
                if let description = senderDescription {
                    Text(description)
                        .typeStyle(Style.gloss)
                        .foregroundStyle(Ink.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, Space.sm)
                }

                metaRow
                    .padding(.top, Space.sm)

                stats
                    .padding(.top, Space.md)

                actions
                    .padding(.top, Space.lg)
            }
            .padding(.horizontal, Metric.gutter)
            .padding(.bottom, Space.lg)
        }
    }

    private var senderDescription: String? {
        identity?.senderDescription ?? all.compactMap(\.senderDescription).first
    }

    /// What Twitter fills with a location and a join date.
    private var metaRow: some View {
        HStack(spacing: Space.lg) {
            if history?.isExhausted == true, let first = posts.last {
                Label {
                    Text(first.receivedAt.formatted(.dateTime.month(.abbreviated).year()).uppercased())
                        .typeStyle(Style.monoMicro)
                } icon: {
                    Image(systemName: "calendar").font(.system(size: 11))
                }
                .foregroundStyle(Ink.tertiary)
            }
            if let domain = sender.address.split(separator: "@").last {
                Label {
                    Text(String(domain))
                        .typeStyle(Style.monoMicro)
                        .lineLimit(1)
                } icon: {
                    Image(systemName: "link").font(.system(size: 11))
                }
                .foregroundStyle(Ink.tertiary)
            }
        }
    }

    /// Where Twitter has Message and Follow. Following a sender is not a thing
    /// a mailbox can offer — their mail arrives whether you want it or not —
    /// so the second slot is the one action that actually changes that.
    private var actions: some View {
        HStack(spacing: Space.md) {
            Button {
                if let chat { thread = chat } else { open = posts.first }
            } label: {
                Text("Open conversation")
                    .typeStyle(Style.body)
                    .foregroundStyle(Ink.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .overlay(Capsule().strokeBorder(Ink.border, lineWidth: 1))
            }
            .buttonStyle(TapStyle())
            .disabled(chat == nil && posts.isEmpty)

            if let promo = all.first(where: { $0.isPromotion }) {
                Button { store.unsubscribe(from: promo) } label: {
                    Text("Unsubscribe")
                        .typeStyle(Style.body)
                        .foregroundStyle(Ink.surface)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Ink.primary, in: Capsule())
                }
                .buttonStyle(TapStyle())
            }
        }
    }

    // MARK: Lanes

    /// People and companies share exactly the feed's post rendering and actions.
    @ViewBuilder private var emailList: some View {
        if posts.isEmpty {
            if history?.isExhausted == true {
                EmptyStateView(headline: "No emails from this sender.", detail: "CHECKED YOUR COMPLETE EMAIL HISTORY.")
                    .frame(height: 240)
            }
        } else {
            ForEach(posts, id: \.feedKey) { message in
                PostView(
                    message: message,
                    onOpen: { openPost(message) },
                    onReply: { initialComposeIntent = .reply; focusDiscussion = false; open = message },
                    onDiscuss: { initialComposeIntent = nil; focusDiscussion = true; open = message },
                    onForward: { initialComposeIntent = .forward; focusDiscussion = false; open = message },
                    onSave: { store.toggleSaved(message) },
                    onArchive: { store.archive(message) },
                    onUnsubscribe: { store.unsubscribe(from: message) },
                    onProfile: {},
                    onReact: { store.react(message, $0) }
                )
            }
        }
    }

    private func openPost(_ message: Message) {
        initialComposeIntent = nil; focusDiscussion = false
        if let chat, chatMessages.contains(where: { $0.id == message.id }) {
            thread = chat
        } else {
            open = message
        }
    }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 1), count: 3)
    }

    private var openingFile: Bool {
        if case .loading = opener.state { return true }
        return false
    }

    private func openFile(_ file: Attachment) {
        lastOpenedFile = file
        Task { await opener.open(file, authorization: nil) }
    }

    /// Photos and documents share a three-column, square, edge-to-edge grid.
    /// Cropping belongs to this overview only; opening retains the original.
    @ViewBuilder private var mediaGrid: some View {
        if media.isEmpty {
            if history?.sourcesComplete == true {
                EmptyStateView(headline: "No pictures.", detail: "NOTHING THIS SENDER WROTE CARRIED ONE.")
                    .frame(height: 240)
            }
        } else {
            LazyVGrid(columns: gridColumns, spacing: 1) {
                ForEach(media) { entry in
                    Button {
                        if let file = entry.file, file.fileURL != nil {
                            openFile(file)
                        } else {
                            presentedImage = entry
                        }
                    } label: {
                        Ink.surfaceTertiary
                            .aspectRatio(1, contentMode: .fit)
                            .overlay {
                                GeometryReader { geometry in
                                    AsyncImage(url: entry.url,
                                               transaction: Transaction(animation: reduceMotion ? nil : Move.crossfade)) { phase in
                                        if case .success(let image) = phase {
                                            image.resizable().scaledToFill()
                                        } else {
                                            Image(systemName: "photo")
                                                .foregroundStyle(Ink.secondary)
                                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                        }
                                    }
                                    .frame(width: geometry.size.width, height: geometry.size.height)
                                }
                            }
                            .overlay {
                                if let file = entry.file, case .loading(file.id) = opener.state {
                                    ProgressView().tint(Ink.primary)
                                        .padding(Space.sm)
                                        .background(Ink.surface, in: Circle())
                                }
                            }
                            .clipped()
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .disabled(openingFile)
                    .accessibilityLabel(entry.filename ?? "Email image")
                    .accessibilityHint("Opens the full image")
                }
            }
            .padding(.top, 1)
        }
    }

    /// File names and types are the covers. A document remains identifiable
    /// without pretending a generated image is a preview of its contents.
    @ViewBuilder private var docsGrid: some View {
        if docs.isEmpty {
            if history?.sourcesComplete == true {
                EmptyStateView(headline: "No files.", detail: "THIS SENDER HAS NOT ATTACHED ANYTHING.")
                    .frame(height: 240)
            }
        } else {
            LazyVGrid(columns: gridColumns, spacing: 1) {
                ForEach(docs) { entry in
                    Button { openFile(entry.file) } label: {
                        Ink.surfaceTertiary
                            .aspectRatio(1, contentMode: .fit)
                            .overlay(alignment: .leading) {
                                VStack(alignment: .leading, spacing: Space.xs) {
                                    Image(systemName: "doc")
                                        .font(.system(size: 24, weight: .regular))
                                        .foregroundStyle(Ink.secondary)
                                        .accessibilityHidden(true)
                                    Spacer(minLength: Space.xs)
                                    Text(entry.file.filename)
                                        .typeStyle(Style.monoCaption)
                                        .foregroundStyle(Ink.primary)
                                        .lineLimit(2)
                                        .truncationMode(.middle)
                                        .multilineTextAlignment(.leading)
                                    Text(entry.file.sizeLabel)
                                        .typeStyle(Style.monoMicro)
                                        .foregroundStyle(Ink.secondary)
                                        .lineLimit(1)
                                }
                                .padding(Space.md)
                            }
                            .overlay {
                                if case .loading(entry.file.id) = opener.state {
                                    ProgressView().tint(Ink.primary)
                                        .padding(Space.sm)
                                        .background(Ink.surface, in: Circle())
                                }
                            }
                            .clipped()
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .disabled(openingFile)
                    .accessibilityLabel("\(entry.file.filename), \(entry.file.sizeLabel), \(entry.receivedAt.formatted(date: .abbreviated, time: .omitted))")
                    .accessibilityHint("Opens the document")
                }
            }
            .padding(.top, 1)
        }
    }

    /// Counts, not engagement. How much of your attention this sender takes is
    /// a fact worth knowing; a follower count would be a fiction.
    private var stats: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
            Text(emailCount.map { $0.formatted() } ?? "…")
                .typeStyle(Style.countInline).monospacedDigit()
            Text(emailCount == 1 ? "EMAIL" : "EMAILS")
                .typeStyle(Style.monoMicro).foregroundStyle(Ink.tertiary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(emailCount.map { "\($0) emails in complete history" } ?? "Email history count loading")
    }

    @ViewBuilder private var historyFooter: some View {
        VStack(spacing: Space.sm) {
            if let failure = history?.failure {
                Text(failure).typeStyle(Style.body).foregroundStyle(Ink.secondary)
                Button("Try again") { Task { await history?.start() } }
                    .frame(minHeight: Metric.tapTarget)
            } else if history?.isExhausted == true {
                if !posts.isEmpty { Text("All emails loaded.").typeStyle(Style.body).foregroundStyle(Ink.secondary) }
            } else {
                ProgressView("Loading email history…")
                if history?.hasMore == true {
                    Button("Load older emails") { Task { await history?.loadMore() } }
                        .frame(minHeight: Metric.tapTarget)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(Metric.gutter)
    }

    private func stat(_ count: Int, _ label: String) -> some View {
        HStack(spacing: Space.xs) {
            Text("\(count)")
                .typeStyle(Style.meta)
                .foregroundStyle(Ink.primary)
                .monospacedDigit()
            Text(label)
                .typeStyle(Style.meta)
                .foregroundStyle(Ink.tertiary)
        }
    }

    // MARK: Lanes

    /// Underline, not a pill. A filled segment would be the only soft
    /// container in the product, and the rule already does the job.
    /// Full width, icon alone when closed, icon and name when open.
    ///
    /// Three labels across 390pt forces either truncation or 10pt type, and
    /// neither is worth paying when the icon already says which is which. The
    /// name appears on the tab you are actually in, where there is room for it
    /// — which is also the only tab whose name you need.
    private var lanePicker: some View {
        HStack(spacing: 0) {
            ForEach(Lane.allCases) { option in laneButton(option) }
        }
        .animation(Move.resolved(Move.crisp, reduceMotion), value: lane)
        .padding(.top, Space.xl)
    }

    private func laneButton(_ option: Lane) -> some View {
        Button { lane = option } label: {
            VStack(spacing: Space.sm + 2) {
                HStack(spacing: Space.xs + 2) {
                    Image(systemName: option.symbol).font(.system(size: 17))
                    if lane == option { Text(option.label).typeStyle(Style.kicker) }
                }
                .foregroundStyle(lane == option ? Ink.primary : Ink.tertiary)
                .frame(minHeight: 22)
                laneMarker(option)
            }
            .frame(maxWidth: .infinity, minHeight: Metric.tapTarget)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.label.capitalized)
        .accessibilityAddTraits(lane == option ? [.isSelected, .isButton] : .isButton)
    }

    @ViewBuilder private func laneMarker(_ option: Lane) -> some View {
        ZStack {
            Color.clear.frame(height: 2)
            if lane == option {
                if reduceMotion { Rectangle().fill(Ink.primary).frame(height: 2) }
                else { Rectangle().fill(Ink.primary).frame(height: 2).matchedGeometryEffect(id: "profile-lane", in: laneMotion) }
            }
        }
    }
}
