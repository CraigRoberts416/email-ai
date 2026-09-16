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
    @State private var messages: [ConversationMessage] = []
    @State private var seeded = false
    @State private var opener = AttachmentOpener()
    @State private var link: LinkTarget?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ThreadProfileStub(conversation: conversation, count: messages.count)

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
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .toolbar(.hidden, for: .navigationBar)
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
        .task {
            let fresh = await store.messages(in: conversation)
            // An empty result is how a failed request looks too, and wiping a
            // thread the reader is looking at is worse than showing it a
            // minute stale.
            if !fresh.isEmpty { messages = fresh }
        }
        // A link in a message is part of reading the message. Following one
        // should not throw the reader out of the app and lose their place in
        // the thread.
        .environment(\.openURL, OpenURLAction { url in
            link = LinkTarget(url: url)
            return .handled
        })
        .sheet(item: $link) { SafariView(url: $0.url).ignoresSafeArea() }
        .sheet(item: $opener.previewing) { QuickLookView(url: $0.url).ignoresSafeArea() }
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

    private var header: some View {
        HStack(spacing: Space.sm + 2) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Ink.primary)
                    .frame(width: 40, height: 40)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")

            GroupAvatar(participants: conversation.participants, size: 32)

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
        .padding(.leading, Space.sm)
        .padding(.trailing, Metric.gutter)
        .padding(.bottom, Space.sm + 2)
        .background {
            Ink.surface
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Ink.border).frame(height: Metric.hairline)
                }
                .ignoresSafeArea(edges: .top)
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

    var body: some View {
        VStack(spacing: Space.xs + 2) {
            GroupAvatar(participants: conversation.participants, size: 64)

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
            Text(count > 0 ? "\(count) EMAIL\(count == 1 ? "" : "S")" : "\u{2014}")
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
                // The files first, each its own object. An attachment is not a
                // strip glued to the top of a sentence — it is a discrete
                // thing with a boundary and a name, which is exactly the test
                // this system uses to decide what gets a container.
                ForEach(message.attachments) { attachment in
                    AttachmentBubble(
                        attachment: attachment,
                        isOpening: opener?.state == .loading(attachment.id)
                    ) {
                        Task { await opener?.open(attachment, authorization: nil) }
                    }
                    .frame(maxWidth: .infinity, alignment: group.mine ? .trailing : .leading)
                }

                if !message.body.isEmpty {
                    MessageBubble(message: message)
                        .frame(maxWidth: .infinity, alignment: group.mine ? .trailing : .leading)
                }
            }

            Text(stamp)
                .typeStyle(Style.monoMicro)
                .foregroundStyle(Ink.tertiary)
                .padding(.horizontal, Space.xs + 2)
                .padding(.top, 3)
        }
        .frame(maxWidth: .infinity, alignment: group.mine ? .trailing : .leading)
    }

    private var stamp: String {
        group.last.receivedAt.clockStamp.uppercased()
    }
}

/// One message, in a bubble.
///
/// Bubbles are the second containerised thing in this product, after an
/// attachment, and they earn it on the system's own test: an utterance is a
/// discrete object with a boundary and an author.
///
/// The subject line used to sit above every one of these. It came off: no chat
/// app labels each turn, and on a calendar invite it rendered as
/// `UPDATED INVITATION: TFH CHAT WITH NADIA (CRAIG ROBERTS) @…` over a bubble
/// that already said the same thing. Email has a field chat does not, and the
/// honest place for it is the card in the feed, not once per line here.
struct MessageBubble: View {
    let message: ConversationMessage

    /// Capped, never stretched to the gutter: a line of text running the full
    /// width of a phone is not a message, it is a paragraph. Below the cap the
    /// bubble hugs, which is what keeps "Thank you!!" a pill.
    private let maxBubbleWidth: CGFloat = 272

    var body: some View {
        Text(Self.linked(message.body))
            .typeStyle(Style.body)
            .foregroundStyle(message.mine ? Ink.surface : Ink.primary)
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
                "\(message.mine ? "You" : message.sender.displayName): \(message.body)"
            )
    }

    /// The body with its URLs marked up, so they are tappable.
    ///
    /// `NSDataDetector` and not a regular expression: it is the same detector
    /// Mail and Messages use, so what counts as a link here is what counts as
    /// one everywhere else on the phone, including the trailing-punctuation
    /// cases a hand-written pattern always gets wrong.
    ///
    /// Underlined rather than coloured. Every other state in this product is
    /// carried by weight, fill, rule or shape, and a link is not the place to
    /// introduce the only hue in the app.
    static func linked(_ body: String) -> AttributedString {
        var text = AttributedString(body)
        guard let detector = try? NSDataDetector(
            types: NSTextCheckingResult.CheckingType.link.rawValue
        ) else { return text }

        let ns = body as NSString
        let matches = detector.matches(in: body, range: NSRange(location: 0, length: ns.length))
        for match in matches {
            guard let url = match.url,
                  let range = Range(match.range, in: body),
                  let lower = AttributedString.Index(range.lowerBound, within: text),
                  let upper = AttributedString.Index(range.upperBound, within: text)
            else { continue }
            text[lower..<upper].link = url
            text[lower..<upper].underlineStyle = .single
        }
        return text
    }
}

/// A file, as its own bubble.
///
/// Fiverr, Grok and Quo all give an attachment its own boundary rather than
/// nesting it in the text bubble. Outlined instead of filled, so a file never
/// reads as something a person typed.
struct AttachmentBubble: View {
    let attachment: Attachment
    var isOpening = false
    var onOpen: () -> Void = {}

    var body: some View {
        Button(action: onOpen) { tile }
            .buttonStyle(.plain)
            .disabled(attachment.fileURL == nil)
    }

    private var tile: some View {
        HStack(spacing: Space.sm + 2) {
            Text(isOpening ? "\u{2026}" : kind)
                .typeStyle(Style.monoMicro)
                .foregroundStyle(Ink.secondary)
                .frame(width: 38, height: 38)
                .background(
                    Ink.surfaceTertiary,
                    in: RoundedRectangle(cornerRadius: Corner.sm, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.filename)
                    .typeStyle(Style.monoCaption)
                    .foregroundStyle(Ink.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(attachment.sizeLabel.uppercased())
                    .typeStyle(Style.monoMicro)
                    .foregroundStyle(Ink.tertiary)
            }
        }
        .padding(.leading, Space.sm + 2)
        .padding(.trailing, Space.lg)
        .padding(.vertical, Space.sm + 2)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Ink.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Ink.border, lineWidth: Metric.hairline)
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
