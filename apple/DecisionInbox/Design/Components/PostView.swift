import SwiftUI

/// A post in the feed.
///
/// Deliberately decontained: no card fill, no radius, no border. Posts run
/// full width and are separated by an edge-to-edge hairline. That single
/// decision is what turns a catalogue of tiles into a feed — containers made
/// a contract and a receipt look equally important.
///
/// Media breaks the 16pt gutter and runs 0 → full width. It is the only thing
/// that does, and that break is what makes it read as a post rather than an
/// image inside a card.
struct PostView: View {
    let message: Message
    /// Which mailbox this arrived in. Nil with a single mailbox — a tag on
    /// every row when there is only one thing it can mean is pure noise.
    var tag: String?
    var onOpen: () -> Void = {}
    var onReply: () -> Void = {}
    var onDiscuss: () -> Void = {}
    var onForward: () -> Void = {}
    var onSave: () -> Void = {}
    var onArchive: () -> Void = {}
    var onUnsubscribe: () -> Void = {}

    @State private var pressed = false

    var body: some View {
        VStack(spacing: 0) {
            content
            Rule()
        }
        .background(pressed ? Ink.surfaceTertiary : Ink.surface)
        .contentShape(.rect)
        .onTapGesture(perform: onOpen)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
        // Combining children makes the post one readable element and drops
        // every button inside it, so the actions have to be re-offered by
        // hand. This is also the non-gesture route to anything a swipe does.
        .accessibilityActions {
            Button("Open", action: onOpen)
            if message.isPromotion {
                Button("Unsubscribe", action: onUnsubscribe)
            } else {
                Button("Reply", action: onReply)
                Button("Forward", action: onForward)
            }
            Button("Discuss", action: onDiscuss)
            Button(message.isSaved ? "Remove from saved" : "Save", action: onSave)
            Button("Archive", action: onArchive)
        }
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        if case .compact = message.density {
            compactRow
        } else {
            standard
        }
    }

    private var standard: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            header

            Group {
                switch message.shape {
                case .html(let url):       htmlBody(url)
                case .media(let urls):     mediaBody(urls)
                case .carousel(let items): carouselBody(items)
                case .quoted(let quoted):  quotedBody(quoted)
                case .degraded:            degradedBody
                case .text:                textBody
                }
            }

            ActionRow(
                message: message,
                onReply: onReply, onDiscuss: onDiscuss, onForward: onForward,
                onSave: onSave, onArchive: onArchive, onUnsubscribe: onUnsubscribe
            )
            .padding(.horizontal, Metric.gutter)
            // Every internal gap is 16; the action row alone sits 24 off the
            // block above it, which is what keeps it reading as a footer
            // rather than as another line of content.
            .padding(.top, Space.sm)
        }
        .padding(.vertical, Metric.postPaddingY)
    }

    // MARK: Header — one identity line, Twitter-style

    private var header: some View {
        HStack(spacing: Space.md) {
            AvatarView(
                sender: message.sender,
                size: message.density == .compact ? Metric.avatarCompact : Metric.avatar,
                dimmed: message.density == .compact
            )

            HStack(spacing: Space.xs + 2) {
                // Read changes the weight and nothing else. The name stays
                // black — it is the quote that greys out, because what you
                // have already read is the words, not who sent them.
                Text(message.sender.displayName)
                    .typeStyle(message.isRead ? Style.senderRead : Style.sender)
                    .foregroundStyle(Ink.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("·").typeStyle(Style.separator).foregroundStyle(Ink.tertiary)
                Text(message.receivedAt.feedStamp)
                    .typeStyle(Style.meta).foregroundStyle(Ink.tertiary)

                if message.threadCount > 1 {
                    Text("·").typeStyle(Style.separator).foregroundStyle(Ink.tertiary)
                    Text("\(message.threadCount)")
                        .typeStyle(Style.meta).foregroundStyle(Ink.tertiary)
                }
            }

            if let tag {
                Text(tag)
                    .typeStyle(Style.chip)
                    .foregroundStyle(Ink.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .overlay(
                        RoundedRectangle(cornerRadius: Corner.chip, style: .continuous)
                            .strokeBorder(Ink.border, lineWidth: 1)
                    )
            }

            Image(systemName: "ellipsis")
                .font(.system(size: 15))
                .foregroundStyle(Ink.secondary)
        }
        .padding(.horizontal, Metric.gutter)
    }

    // MARK: Bodies

    private var textBody: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            KickerLabel(message.kicker)

            if message.isInterpreting && message.quote == nil {
                StreamingCaret()
            } else if let quote = message.quote {
                Text("\u{201C}\(quote)\u{201D}")
                    .typeStyle(Style.display)
                    .foregroundStyle(message.isRead ? Ink.tertiary : Ink.primary)
                    .lineLimit(3)
            }

            if let summary = message.summary {
                SummaryBlock(text: summary, density: message.density, emphasised: message.kicker == .possibleScam)
            }

            if let label = message.actionLabel {
                CTAButton(label: label) {
                    if let url = message.actionURL { UIApplication.shared.open(url) }
                }
                .padding(.top, Space.xs)
            }
        }
        .padding(.horizontal, Metric.gutter)
    }

    /// Marketing mail is already designed, so the AI steps back and we render
    /// their own first 1:1 section rather than reinterpreting it.
    private func htmlBody(_ url: URL) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            KickerLabel(message.kicker).padding(.horizontal, Metric.gutter)

            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Rectangle().fill(Ink.surfaceTertiary)
            }
            .aspectRatio(Metric.htmlAspect, contentMode: .fill)
            .frame(maxWidth: .infinity)
            .clipped()

            Text("SENDER\u{2019}S OWN LAYOUT  ·  NOT INTERPRETED")
                .typeStyle(Style.chip)
                .foregroundStyle(Ink.secondary)
                .padding(.horizontal, Metric.gutter)
        }
    }

    private func mediaBody(_ urls: [URL]) -> some View {
        VStack(alignment: .leading, spacing: Space.md) {
            VStack(alignment: .leading, spacing: Space.sm) {
                KickerLabel(message.kicker)
                if let quote = message.quote {
                    Text("\u{201C}\(quote)\u{201D}")
                        .typeStyle(Style.display)
                        .foregroundStyle(Ink.primary)
                        .lineLimit(3)
                }
            }
            .padding(.horizontal, Metric.gutter)

            // The one place the gutter breaks.
            AsyncImage(url: urls[0], transaction: Transaction(animation: Move.crossfade)) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    // A missing image is not a broken card. The post drops back
                    // to text rather than showing a placeholder that means
                    // nothing to the reader.
                    Color.clear.frame(height: 0)
                default:
                    // Its own extracted ground, so nothing flashes white.
                    heroGround
                }
            }
            .aspectRatio(Metric.mediaAspect, contentMode: .fill)
            .frame(maxWidth: .infinity)
            .clipped()

            if let summary = message.summary {
                SummaryBlock(text: summary, density: message.density, emphasised: false)
                    .padding(.horizontal, Metric.gutter)
            }
        }
    }

    /// The colour the generator extracted from the image itself, so the space
    /// it will occupy already belongs to that sender before the bytes arrive.
    private var heroGround: some View {
        Rectangle().fill(
            message.heroBackground
                .flatMap { UInt32($0.dropFirst(($0.hasPrefix("#") ? 1 : 0)), radix: 16) }
                .map { Color(hex: $0) } ?? Ink.surfaceTertiary
        )
    }

    private func carouselBody(_ items: [Attachment]) -> some View {
        VStack(alignment: .leading, spacing: Space.md) {
            VStack(alignment: .leading, spacing: Space.sm) {
                KickerLabel(message.kicker)
                if let quote = message.quote {
                    Text("\u{201C}\(quote)\u{201D}")
                        .typeStyle(Style.display)
                        .foregroundStyle(Ink.primary)
                        .lineLimit(3)
                }
                if let summary = message.summary {
                    SummaryBlock(text: summary, density: message.density, emphasised: false)
                }
            }
            .padding(.horizontal, Metric.gutter)

            AttachmentCarousel(attachments: items, onOpenThread: onOpen)
        }
    }

    private func quotedBody(_ quoted: QuotedMessage) -> some View {
        VStack(alignment: .leading, spacing: Space.md) {
            VStack(alignment: .leading, spacing: Space.sm) {
                KickerLabel(message.kicker)
                if let quote = message.quote {
                    Text("\u{201C}\(quote)\u{201D}")
                        .typeStyle(Style.display)
                        .foregroundStyle(Ink.primary)
                        .lineLimit(3)
                }
                if let summary = message.summary {
                    SummaryBlock(text: summary, density: message.density, emphasised: false)
                }
            }
            QuotedCard(quoted: quoted)
        }
        .padding(.horizontal, Metric.gutter)
    }

    /// Interpretation failed. The quote slot is suppressed, never filled with
    /// a guess — and tapping still opens the real message.
    private var degradedBody: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            KickerLabel(.notRead)
            Text(message.subject)
                .typeStyle(Style.body)
                .foregroundStyle(Ink.primary)
                .lineLimit(2)
            Text(message.snippet)
                .typeStyle(Style.bodySmall)
                .foregroundStyle(Ink.secondary)
                .lineLimit(2)
        }
        .padding(.horizontal, Metric.gutter)
    }

    /// A broadcast that asks nothing: one row, a mono sender, one clause, and
    /// the two things you might do with it. No timestamp, no thread count, no
    /// overflow — a receipt does not earn an identity line.
    private var compactRow: some View {
        VStack(spacing: 0) {
            HStack(spacing: Space.md) {
                AvatarView(sender: message.sender, size: Metric.avatarCompact, dimmed: true)

                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text(message.sender.displayName.uppercased())
                        .typeStyle(Style.compactSender)
                        .foregroundStyle(Ink.tertiary)
                        .lineLimit(1)
                    Text(message.summary ?? message.subject)
                        .typeStyle(Style.body)
                        .foregroundStyle(Ink.primary)
                        .lineLimit(1)
                }

                Spacer(minLength: Space.sm)

                // The one place the filing glyphs step down: a compact row is
                // already the quietest thing in the feed and should not carry
                // two black icons.
                compactAction(message.isSaved ? "bookmark.fill" : "bookmark", "Save", onSave)
                compactAction("archivebox", "Archive", onArchive)
            }
            .padding(.horizontal, Metric.gutter)
            .padding(.vertical, Space.md)
        }
    }

    private func compactAction(
        _ symbol: String, _ label: String, _ action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: Metric.iconFile))
                .foregroundStyle(Ink.tertiary)
                .frame(width: Metric.tapTarget * 0.7, height: Metric.tapTarget)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// Spoken in the order it is read, and — crucially — with the quote
    /// announced as a quotation. The verbatim line is the one thing on a post
    /// the AI did not write, and a VoiceOver user has to be able to tell.
    private var accessibilityLabel: String {
        var parts = ["\(message.sender.displayName), \(message.kicker.rawValue.lowercased())"]
        if let quote = message.quote {
            parts.append("They wrote, quote, \(quote), end quote")
        }
        if let summary = message.summary {
            parts.append("Our summary: \(summary)")
        }
        if message.threadCount > 1 {
            parts.append("\(message.threadCount) in thread")
        }
        parts.append(message.receivedAt.spokenStamp)
        return parts.joined(separator: ". ")
    }
}

// MARK: - Kicker
//
// The intent, stated rather than hued. This is what stands in for an accent
// colour: scan the left gutter alone and you can read the feed.

struct KickerLabel: View {
    let kicker: Kicker
    init(_ kicker: Kicker) { self.kicker = kicker }

    var body: some View {
        // Every kicker is black, NOT READ included. The state is carried by
        // the word, which is why there are eleven of them — greying the
        // awkward ones would hide exactly the posts worth noticing.
        Text(kicker.rawValue)
            .typeStyle(Style.kicker)
            .foregroundStyle(Ink.primary)
    }
}

// MARK: - Summary
//
// Mono is the machine's voice. A filled panel at lead density; a margin rule
// everywhere else, because fill plus radius plus even padding reads as a code
// block rather than editorial gloss.

struct SummaryBlock: View {
    let text: String
    let density: Density
    let emphasised: Bool

    var body: some View {
        if density == .lead {
            Text(text)
                .typeStyle(Style.ai)
                .foregroundStyle(Ink.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Space.md)
                .background(Ink.surfaceTertiary, in: RoundedRectangle(cornerRadius: Corner.md, style: .continuous))
        } else {
            Text(text)
                .typeStyle(Style.ai)
                .foregroundStyle(Ink.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, Space.md)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(emphasised ? Ink.primary : Ink.border)
                        .frame(width: emphasised ? 2 : 1)
                }
        }
    }
}

// MARK: - CTA
//
// A black hairline, never grey — a grey outline reads as disabled.

struct CTAButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .typeStyle(Style.sender)
                .foregroundStyle(Ink.primary)
                .padding(.horizontal, Space.lg)
                .padding(.vertical, 9)
                .overlay(
                    Capsule().strokeBorder(Ink.primary, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Streaming
//
// Generation is the substance of the product, so the wait state shows the
// model working rather than a skeleton pretending to be content.

struct StreamingCaret: View {
    @State private var on = false

    var body: some View {
        HStack(spacing: Space.sm) {
            Rectangle()
                .fill(Ink.primary)
                .frame(width: 2, height: 20)
                .opacity(on ? 1 : 0.25)
            Text("Reading this one…")
                .typeStyle(Style.ai)
                .foregroundStyle(Ink.secondary)
        }
        .task {
            // 530ms blink, matched to the caret in the run log.
            while !Task.isCancelled {
                withAnimation(.easeInOut(duration: 0.53)) { on.toggle() }
                try? await Task.sleep(for: .milliseconds(530))
            }
        }
    }
}

// MARK: - Date

extension Date {
    /// What VoiceOver says. "2h" is announced as "two h".
    var spokenStamp: String {
        let seconds = Date.now.timeIntervalSince(self)
        if seconds < 60 { return "just now" }
        if seconds < 3600 {
            let m = Int(seconds / 60)
            return m == 1 ? "1 minute ago" : "\(m) minutes ago"
        }
        if seconds < 86_400 {
            let h = Int(seconds / 3600)
            return h == 1 ? "1 hour ago" : "\(h) hours ago"
        }
        let d = Int(seconds / 86_400)
        return d == 1 ? "yesterday" : "\(d) days ago"
    }

    /// Relative and short. Absolute timestamps are for the thread, not the feed.
    var feedStamp: String {
        let seconds = Date.now.timeIntervalSince(self)
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        if seconds < 86_400 { return "\(Int(seconds / 3600))h" }
        if seconds < 7 * 86_400 { return "\(Int(seconds / 86_400))d" }
        return formatted(.dateTime.month(.abbreviated).day())
    }
}

#Preview {
    ScrollView {
        LazyVStack(spacing: 0) {
            ForEach(Sample.messages) { PostView(message: $0) }
        }
    }
}
