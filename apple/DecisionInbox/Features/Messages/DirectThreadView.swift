import SwiftUI

/// One conversation with one person, or with one set of people.
///
/// Built to `DirectThread v2`. The participant set is the conversation: adding
/// someone would not change this thread, it would open a different one with
/// all of you in it — the same model as iMessage and every group text. That
/// is not a simplification of email either; a reply-all with a new address on
/// it already forks the thread, and mail clients merely hide the fork and let
/// both branches wear the same subject line.
///
/// Laid out against X, iMessage and Instagram, which agree on more than they
/// differ: a profile stub before the first message, day separators in the
/// middle, bubbles that hug what was said, consecutive messages grouped, and
/// one timestamp per group rather than one per line.
struct DirectThreadView: View {
    let conversation: Conversation

    @Environment(FeedStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var messages: [ConversationMessage] = []
    @State private var seeded = false
    @State private var nextCursor: String?
    @State private var totalMessages: Int?
    @State private var historyComplete = false
    @State private var historySyncState = "pending"
    @State private var loading = false
    @State private var failure: String?
    @State private var pendingScrollAnchor: String?
    @State private var sourceRefresh = ConversationSourceRefresh()
    @State private var sourceRefreshSignal = 0
    @State private var sourceFailure: String?

    @State private var opener = AttachmentOpener()
    @State private var link: LinkTarget?
    @State private var writeTo: String?
    /// The participant whose avatar was tapped. Pushed rather than presented:
    /// this view is itself pushed inside People's navigation stack, so the
    /// profile joins the same stack and the back chevron means what it says.
    @State private var profile: Sender?

    /// A group avatar is a stack of faces and names no single account, so
    /// tapping one has no honest destination. Only a one-to-one conversation
    /// resolves to a person.
    private var soleParticipant: Sender? {
        conversation.isGroup ? nil : conversation.participants.first
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ThreadProfileStub(conversation: conversation, count: historyComplete ? (totalMessages ?? messages.count) : messages.count,
                                      countComplete: historyComplete,
                                      onProfile: { profile = $0 })

                    if let failure {
                        Text(failure).typeStyle(Style.body).foregroundStyle(Ink.secondary)
                            .padding(.bottom, Space.sm)
                        Button("Try again") { Task { await refresh() } }
                            .frame(minHeight: Metric.tapTarget)
                    }
                    if nextCursor != nil {
                        Button(loading ? "Loading…" : "See older emails") {
                            Task {
                                let anchor = messages.first?.id
                                if await loadOlder() { pendingScrollAnchor = anchor }
                            }
                        }
                        .typeStyle(Style.body)
                        .frame(maxWidth: .infinity, minHeight: Metric.tapTarget)
                        .disabled(loading)
                        .padding(.bottom, Space.md)
                    }
                    if !historyComplete && totalMessages != nil {
                        Text(historySyncState == "failed" ? "Older mail hasn’t finished importing." : "Older mail is still importing.")
                            .typeStyle(Style.monoCaption).foregroundStyle(Ink.tertiary)
                            .frame(maxWidth: .infinity).padding(.bottom, Space.md)
                        Button("Refresh history") { Task { await refresh() } }
                            .frame(maxWidth: .infinity, minHeight: Metric.tapTarget)
                            .disabled(loading)
                    }
                    if loading && messages.isEmpty {
                        ProgressView().frame(maxWidth: .infinity).padding(Space.lg)
                    }
                    if sourceRefresh.hasPending {
                        VStack(spacing: Space.sm) {
                            Text(sourceFailure ?? "Loading original emails and files…")
                                .typeStyle(Style.monoCaption).foregroundStyle(Ink.tertiary)
                            if sourceFailure != nil {
                                Button("Try again") {
                                    sourceFailure = nil
                                    sourceRefresh.retry()
                                    sourceRefreshSignal += 1
                                }
                                .frame(minHeight: Metric.tapTarget)
                            }
                        }
                        .frame(maxWidth: .infinity).padding(.bottom, Space.md)
                    }

                    ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                        if let stamp = daySeparator(before: index) {
                            Text(stamp)
                                .typeStyle(Style.monoMicro)
                                .foregroundStyle(Ink.tertiary)
                                .frame(maxWidth: .infinity)
                                .padding(.top, index == 0 ? Space.sm : Space.lg)
                                .padding(.bottom, Space.md)
                        }

                        MessageGroup(group: group, showsSender: conversation.isGroup, opener: opener)
                            .padding(.top, index == 0 ? 0 : Space.md)
                    }
                }
                .padding(.horizontal, Metric.gutter)
                .padding(.top, Space.lg)
                .padding(.bottom, Space.xl)
            }
            .onChange(of: pendingScrollAnchor) { _, anchor in
                guard let anchor else { return }
                proxy.scrollTo(anchor, anchor: .top)
                pendingScrollAnchor = nil
            }
            .scrollIndicators(.hidden)
            // A conversation opens at the end, where a feed opens at the start:
            // the newest thing said is what you came for.
            //
            // `defaultScrollAnchor` and not a `scrollTo` on appear. Asking a proxy
            // to scroll the last message to `.bottom` does exactly that even when
            // the whole conversation is shorter than the screen — two short
            // bubbles were pushed up out of view and the thread looked empty while
            // the data was sitting right there.
            .defaultScrollAnchor(.bottom)
            .background(Ink.surface)
            .toolbar { ToolbarItem(placement: .principal) { header } }
            // A bottom inset, not an overlay: the scroll view reserves the space,
            // so the last bubble can always be scrolled clear of the pill instead
            // of hiding under it forever.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                ThreadComposer(conversation: conversation, replyingTo: messages.last) {
                    Task { await refresh() }
                }
            }
            .backNavigation { dismiss() }
            .toolbar(.hidden, for: .tabBar)
            // No loading state, because there is nothing to load. What was said
            // last time is read off disk before the first frame, so a thread you
            // have opened before is simply already there; the network then refills
            // it in place.
            //
            // Both halves were needed. The server used to fetch every body from
            // Gmail while the reader watched — that is gone — but a fast request
            // is still a request, and on a sleeping instance still seconds of
            // empty screen.
            .onAppear {
                guard !seeded else { return }
                seeded = true
                messages = store.cachedMessages(in: conversation)
            }
            .task { await refresh() }
            .task(id: "\(sourceRefreshSignal):\(scenePhase == .active):\(profile == nil)") {
                guard scenePhase == .active, profile == nil else { return }
                await refreshSources()
            }
            // A link in a message is part of reading the message. Following one
            // should not throw the reader out of the app and lose their place in
            // the thread.
            //
            // Routed by scheme, because they are not the same thing.
            // `SFSafariViewController` accepts http and https and traps on
            // anything else — handing it the `mailto:` from a signature crashed
            // the app outright. An address is not a page to visit anyway; it is a
            // person to write to.
            .environment(\.openURL, OpenURLAction { url in
                switch url.scheme?.lowercased() {
                case "http", "https":
                    link = LinkTarget(url: url)
                    return .handled
                case "mailto":
                    writeTo = url.emailAddress
                    return .handled
                default:
                    // tel:, maps:, anything a message might carry. The system
                    // knows what to do with these and this app does not.
                    return .systemAction
                }
            })
            .sheet(item: $link) { SafariView(url: $0.url).ignoresSafeArea() }
            .sheet(item: $writeTo) { address in
                ComposeView(intent: .new, prefilledTo: address)
                    .environment(store)
            }
            .sheet(item: $opener.previewing) { QuickLookView(url: $0.url).ignoresSafeArea() }
            .navigationDestination(item: $profile) { SenderProfileView(sender: $0) }
            .overlay(alignment: .bottom) {
                if case .failed(let why) = opener.state {
                    Text(why)
                        .typeStyle(Style.monoCaption)
                        .foregroundStyle(Ink.surface)
                        .padding(.horizontal, Space.lg)
                        .padding(.vertical, Space.md)
                        .background(Ink.primary, in: Capsule())
                        .padding(.bottom, Space.xxl)
                        .task {
                            try? await Task.sleep(for: .seconds(3))
                            opener.state = .idle
                        }
                }
            }
        }
    }

    /// Keeps cached content on failures. A successful response can be empty
    /// when the provider removed the last message.
    private func refresh() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let page = try await store.messagesPage(in: conversation)
            guard !Task.isCancelled else { return }
            // A successful refresh starts a new traversal. New imports can
            // add mail behind a previously exhausted cursor.
            messages = page.messages
            nextCursor = page.nextCursor
            totalMessages = page.totalMessages
            historyComplete = page.historyComplete
            historySyncState = page.historySyncState
            sourceRefresh.clear()
            sourceRefresh.record(cursor: nil, pending: page.sourcesPending)
            sourceFailure = nil
            sourceRefreshSignal += 1
            failure = nil
        } catch is CancellationError { } catch {
            failure = "Couldn’t refresh this conversation. Your saved messages are still here."
        }
    }

    private func loadOlder() async -> Bool {
        guard !loading, let cursor = nextCursor else { return false }
        loading = true
        defer { loading = false }
        do {
            let page = try await store.messagesPage(in: conversation, cursor: cursor)
            guard !Task.isCancelled else { return false }
            let existing = Set(messages.map(\.id))
            messages.insert(contentsOf: page.messages.filter { !existing.contains($0.id) }, at: 0)
            nextCursor = page.nextCursor
            totalMessages = page.totalMessages
            historyComplete = page.historyComplete
            historySyncState = page.historySyncState
            sourceRefresh.record(cursor: cursor, pending: page.sourcesPending)
            sourceFailure = nil
            sourceRefreshSignal += 1
            failure = nil
            return true
        } catch is CancellationError { return false } catch {
            failure = "Couldn’t load older emails. Try again."
            return false
        }
    }

    private func refreshSources() async {
        while !Task.isCancelled && !sourceRefresh.readyPages.isEmpty {
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            for key in sourceRefresh.readyPages {
                guard !Task.isCancelled, sourceRefresh.beginAttempt(key) else { return }
                do {
                    let page = try await store.messagesPage(in: conversation, cursor: key.isEmpty ? nil : key)
                    guard !Task.isCancelled else { return }
                    let updates = Dictionary(page.messages.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
                    // Replace content in place: hydration never resets an older
                    // page, inserts a new arrival, or changes its page cursor.
                    messages = messages.map { updates[$0.id] ?? $0 }
                    sourceRefresh.record(cursor: key.isEmpty ? nil : key, pending: page.sourcesPending)
                    sourceFailure = nil
                } catch is CancellationError { return } catch {
                    guard !Task.isCancelled else { return }
                    sourceFailure = "Couldn’t finish loading original emails and files. Your saved messages are still here."
                    return
                }
            }
        }
        if sourceRefresh.hasPending && !Task.isCancelled {
            sourceFailure = "Some original emails and files are still loading. Try again."
        }
    }

    private var header: some View {
        HStack(spacing: Space.sm + 2) {
            GroupAvatar(participants: conversation.participants, size: 32)
                .contentShape(.circle)
                .highPriorityGesture(TapGesture().onEnded {
                    if let one = soleParticipant { profile = one }
                })
                .accessibilityLabel(soleParticipant.map { "\($0.displayName), open sender" }
                                    ?? conversation.title)

            // Name over address. The address is the one thing that tells you
            // which of two people with the same name this is, and every chat
            // app puts something in this slot — a handle, "Active 4h ago".
            // Ours is the only identifier email actually has.
            VStack(alignment: .leading, spacing: 1) {
                Text(conversation.title)
                    .typeStyle(Style.body)
                    .foregroundStyle(Ink.primary)
                    .lineLimit(1)
                if let one = conversation.participants.first, !conversation.isGroup {
                    Text(one.address)
                        .typeStyle(Style.monoMicro)
                        .foregroundStyle(Ink.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

    }

    // MARK: - Grouping

    /// Consecutive messages from the same person, close together in time.
    ///
    /// The unit a thread reads in is the turn, not the message. Four bubbles
    /// from one person in one minute are one thing somebody said, and stamping
    /// each of them separately is the clutter every chat app removed years ago.
    private var groups: [MessageGroup.Model] {
        var out: [MessageGroup.Model] = []
        for message in messages {
            if var last = out.last,
               last.mine == message.mine,
               last.sender.address == message.sender.address,
               message.receivedAt.timeIntervalSince(last.last.receivedAt) < 5 * 60 {
                last.messages.append(message)
                out[out.count - 1] = last
            } else {
                out.append(.init(messages: [message]))
            }
        }
        return out
    }

    /// Only when the day actually changes.
    ///
    /// This also fired on any four-hour gap, which put YESTERDAY between two
    /// messages sent the same afternoon — a separator saying the wrong thing
    /// about a silence the clock stamps already describe. Now that every group
    /// carries its own time, the separator has exactly one job.
    private func daySeparator(before index: Int) -> String? {
        guard index < groups.count else { return nil }
        let group = groups[index]
        guard index > 0 else { return group.first.receivedAt.threadDayStamp.uppercased() }
        let previous = groups[index - 1].last.receivedAt
        guard !Calendar.current.isDate(previous, inSameDayAs: group.first.receivedAt) else {
            return nil
        }
        return group.first.receivedAt.threadDayStamp.uppercased()
    }
}

/// Who this is, before the first thing they said.
///
/// X and Instagram both open a thread with the person rather than the
/// conversation — avatar, name, handle, when this started. In a mail client
/// that stub is the only place the address appears at readable size, and it is
/// what tells you this is the Nadia you met rather than another one.
struct ThreadProfileStub: View {
    let conversation: Conversation
    let count: Int
    var countComplete = false
    var onProfile: (Sender) -> Void = { _ in }

    var body: some View {
        VStack(spacing: Space.xs + 2) {
            GroupAvatar(participants: conversation.participants, size: 64)
                .contentShape(.circle)
                .highPriorityGesture(TapGesture().onEnded {
                    guard !conversation.isGroup,
                          let one = conversation.participants.first else { return }
                    onProfile(one)
                })

            Text(conversation.title)
                .typeStyle(Style.body)
                .foregroundStyle(Ink.primary)

            if !conversation.isGroup, let one = conversation.participants.first {
                Text(one.address)
                    .typeStyle(Style.monoCaption)
                    .foregroundStyle(Ink.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            // An em dash until the messages have loaded. A count of zero here
            // would be an assertion about a correspondence before it has been
            // read, which is the same rule the mastheads follow.
            Text(countComplete ? "\(count) EMAIL\(count == 1 ? "" : "S")" : (count > 0 ? "\(count) LOADED" : "\u{2014}"))
                .typeStyle(Style.monoMicro)
                .foregroundStyle(Ink.tertiary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Space.sm)
        .padding(.bottom, Space.xl)
        .accessibilityElement(children: .combine)
    }
}

/// One turn: everything somebody said before the other person answered.
struct MessageGroup: View {
    struct Model: Identifiable {
        var messages: [ConversationMessage]
        var id: String { messages.first?.id ?? UUID().uuidString }
        var first: ConversationMessage { messages[0] }
        var last: ConversationMessage { messages[messages.count - 1] }
        var mine: Bool { first.mine }
        var sender: Sender { first.sender }
    }

    let group: Model
    var showsSender = false
    var opener: AttachmentOpener?

    var body: some View {
        VStack(alignment: group.mine ? .trailing : .leading, spacing: 3) {
            // In a group every turn names its sender — the one thing a
            // one-to-one thread never needs and a group always does.
            if showsSender && !group.mine {
                Text(group.sender.displayName.uppercased())
                    .typeStyle(Style.monoMicro)
                    .foregroundStyle(Ink.tertiary)
                    .padding(.leading, Space.xs)
                    .padding(.bottom, 2)
            }

            ForEach(group.messages) { message in
                VStack(alignment: group.mine ? .trailing : .leading, spacing: 3) {
                    // Files first, each its own object. An attachment is not a
                    // strip glued to the top of a sentence — it is a discrete
                    // thing with a boundary and a name, which is exactly the test
                    // this system uses to decide what gets a container.
                    ForEach(message.attachments) { attachment in
                        // Never `onDark`. A card is a sibling of the bubble, not
                        // a thing inside it — it sits on the page whichever side
                        // it is aligned to. Tinting it for the black bubble drew a
                        // white-on-white card that read as a gap in the thread.
                        AttachmentBubble(
                            attachment: attachment,
                            isOpening: opener?.state == .loading(attachment.id)
                        ) {
                            Task { await opener?.open(attachment, authorization: nil) }
                        }
                        .frame(maxWidth: .infinity, alignment: group.mine ? .trailing : .leading)
                    }

                    let split = MessageBubble.split(message.body)

                    if !split.text.isEmpty {
                        MessageBubble(message: message, body: split.text)
                            .frame(maxWidth: .infinity, alignment: group.mine ? .trailing : .leading)
                    }

                    // A link on its own line is a thing somebody sent, not a word
                    // in a sentence — so it gets the same treatment as a file.
                    // Messages does exactly this, which is why a 90-character
                    // tracking URL never appears as text there.
                    ForEach(split.links, id: \.absoluteString) { url in
                        LinkCard(url: url)
                            .frame(maxWidth: .infinity, alignment: group.mine ? .trailing : .leading)
                    }
                }
                .id(message.id)
            }

            Text(group.last.receivedAt.clockStamp.uppercased())
                .typeStyle(Style.monoMicro)
                .foregroundStyle(Ink.tertiary)
                .padding(.horizontal, Space.xs + 2)
                .padding(.top, 3)
        }
        .frame(maxWidth: .infinity, alignment: group.mine ? .trailing : .leading)
    }
}

/// One message, in a bubble.
///
/// Bubbles are one of the few containerised things in this product, and they
/// earn it on the system's own test: an utterance is a discrete object with a
/// boundary and an author.
///
/// The subject line used to sit above every one of these. It came off: no chat
/// app labels each turn, and on a calendar invite it rendered as
/// `UPDATED INVITATION: TFH CHAT WITH NADIA (CRAIG ROBERTS) @…` over a bubble
/// that already said the same thing.
struct MessageBubble: View {
    let message: ConversationMessage
    /// The words, with any standalone links already lifted out into cards.
    var body_: String

    init(message: ConversationMessage, body: String? = nil) {
        self.message = message
        self.body_ = body ?? message.body
    }

    /// Capped, never stretched to the gutter: a line of text running the full
    /// width of a phone is not a message, it is a paragraph. Below the cap the
    /// bubble hugs, which is what keeps "Thank you!!" a pill.
    private let maxBubbleWidth: CGFloat = 272

    var body: some View {
        Text(linked)
            .typeStyle(Style.body)
            .foregroundStyle(message.mine ? Ink.surface : Ink.primary)
            .tint(message.mine ? Ink.surface : Ink.primary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Space.lg - 2)
            .padding(.vertical, Space.md - 2)
            .background(
                message.mine ? Ink.primary : Ink.surfaceTertiary,
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
            .frame(maxWidth: maxBubbleWidth, alignment: message.mine ? .trailing : .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                "\(message.mine ? "You" : message.sender.displayName): \(body_)"
            )
    }

    /// The remaining inline links, marked up.
    ///
    /// The colour is set on the run and not left to `foregroundStyle`, which
    /// does not reach link runs: in the sent bubble the links rendered in the
    /// default tint on a black fill and were, in practice, invisible.
    ///
    /// Underlined rather than coloured. Every other state in this product is
    /// carried by weight, fill, rule or shape, and a link is not the place to
    /// introduce the only hue in the app.
    private var linked: AttributedString {
        var text = AttributedString(body_)
        let ink: Color = message.mine ? Ink.surface : Ink.primary
        for (range, url) in Self.detect(in: body_) {
            guard let lower = AttributedString.Index(range.lowerBound, within: text),
                  let upper = AttributedString.Index(range.upperBound, within: text)
            else { continue }
            text[lower..<upper].link = url
            text[lower..<upper].underlineStyle = .single
            text[lower..<upper].foregroundColor = ink
        }
        return text
    }

    /// Words and links, separated.
    ///
    /// A link alone on its line is something sent; a link inside a sentence is
    /// part of the sentence, and lifting it out would leave a hole in what
    /// somebody wrote. So only the standalone ones become cards.
    static func split(_ body: String) -> (text: String, links: [URL]) {
        var kept: [String] = []
        var links: [URL] = []
        for line in body.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let matches = detect(in: trimmed)
            if matches.count == 1,
               let (range, url) = matches.first,
               trimmed[range] == trimmed[trimmed.startIndex...].prefix(trimmed.count),
               url.scheme == "http" || url.scheme == "https" {
                if !links.contains(url) { links.append(url) }
            } else {
                kept.append(line)
            }
        }
        let text = kept.joined(separator: "\n")
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (text, links)
    }

    /// `NSDataDetector` and not a regular expression: it is the same detector
    /// Mail and Messages use, so what counts as a link here is what counts as
    /// one everywhere else on the phone, including the trailing-punctuation
    /// cases a hand-written pattern always gets wrong.
    static func detect(in body: String) -> [(Range<String.Index>, URL)] {
        guard !body.isEmpty, let detector = try? NSDataDetector(
            types: NSTextCheckingResult.CheckingType.link.rawValue
        ) else { return [] }
        let ns = body as NSString
        return detector
            .matches(in: body, range: NSRange(location: 0, length: ns.length))
            .compactMap { match in
                guard let url = match.url, let range = Range(match.range, in: body)
                else { return nil }
                return (range, url)
            }
    }
}

/// A file, as its own bubble — or, when it is a picture, as the picture.
///
/// Messages does not put a photo in a chip with a filename on it; the photo is
/// the message. A document does get the chip, because there is nothing to show
/// and a drawn page would be a picture of a file rather than the file.
struct AttachmentBubble: View {
    let attachment: Attachment
    var onDark = false
    var isOpening = false
    var onOpen: () -> Void = {}

    var body: some View {
        Button(action: onOpen) {
            if case .image(let url) = attachment.preview {
                photo(url)
            } else {
                tile
            }
        }
        .buttonStyle(.plain)
    }

    private func photo(_ url: URL) -> some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            case .failure:
                tile
            default:
                Rectangle().fill(Ink.surfaceTertiary)
            }
        }
        .frame(maxWidth: 240, maxHeight: 280)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .opacity(isOpening ? 0.55 : 1)
        .accessibilityLabel("Photo, \(attachment.filename)")
        .accessibilityHint("Opens the image")
    }

    private var tile: some View {
        HStack(spacing: Space.sm + 2) {
            Text(isOpening ? "\u{2026}" : kind)
                .typeStyle(Style.monoMicro)
                .foregroundStyle(onDark ? Ink.surface.opacity(0.75) : Ink.secondary)
                .frame(width: 38, height: 38)
                .background(
                    onDark ? Ink.surface.opacity(0.14) : Ink.surfaceTertiary,
                    in: RoundedRectangle(cornerRadius: Corner.sm, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.filename)
                    .typeStyle(Style.monoCaption)
                    .foregroundStyle(onDark ? Ink.surface : Ink.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(attachment.sizeLabel.uppercased())
                    .typeStyle(Style.monoMicro)
                    .foregroundStyle(onDark ? Ink.surface.opacity(0.7) : Ink.tertiary)
            }
        }
        .padding(.leading, Space.sm + 2)
        .padding(.trailing, Space.lg)
        .padding(.vertical, Space.sm + 2)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(onDark ? Ink.surface.opacity(0.10) : Ink.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(onDark ? Ink.surface.opacity(0.18) : Ink.border,
                                      lineWidth: Metric.hairline)
                )
        )
        .frame(maxWidth: 272, alignment: .leading)
        .contentShape(.rect)
        .opacity(isOpening ? 0.55 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Attachment, \(attachment.filename), \(attachment.sizeLabel)")
        .accessibilityHint("Opens the file")
    }

    private var kind: String {
        attachment.filename.split(separator: ".").last
            .map { String($0).uppercased() } ?? "FILE"
    }
}
