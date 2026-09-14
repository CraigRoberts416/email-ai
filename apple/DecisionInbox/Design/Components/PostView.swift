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
            HStack(alignment: .top, spacing: 0) {
                // Unread is a 2pt leading bar plus a heavier sender. Never a
                // faded ground — opacity dies under Increase Contrast.
                Rectangle()
                    .fill(message.isRead ? .clear : Ink.primary)
                    .frame(width: Metric.unreadBar)

                content
            }

            Rule()
        }
        .background(pressed ? Ink.surfaceTertiary : Ink.surface)
        .contentShape(.rect)
        .onTapGesture(perform: onOpen)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
    }

    // MARK: Content

    private var content: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            header

            if case .compact = message.density {
                compactBody
            } else {
                switch message.shape {
                case .html(let url):       htmlBody(url)
                case .media(let urls):     mediaBody(urls)
                case .carousel(let items): carouselBody(items)
                case .quoted(let quoted):  quotedBody(quoted)
                case .degraded:            degradedBody
                case .text:                textBody
                }
            }

            if message.density != .compact {
                ActionRow(
                    message: message,
                    onReply: onReply, onDiscuss: onDiscuss, onForward: onForward,
                    onSave: onSave, onArchive: onArchive, onUnsubscribe: onUnsubscribe
                )
                .padding(.horizontal, Metric.gutter)
            }
        }
        .padding(.vertical, message.density == .compact ? Space.md : Metric.postPaddingY)
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
                Text(message.sender.displayName)
                    .typeStyle(message.isRead ? Style.senderRead : Style.sender)
                    .foregroundStyle(message.isRead ? Ink.secondary : Ink.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text("·").typeStyle(Style.meta).foregroundStyle(Ink.tertiary)
                Text(message.receivedAt.feedStamp)
                    .typeStyle(Style.meta).foregroundStyle(Ink.secondary)

                if message.threadCount > 1 {
                    Text("·").typeStyle(Style.meta).foregroundStyle(Ink.tertiary)
                    Text("\(message.threadCount)")
                        .typeStyle(Style.meta).foregroundStyle(Ink.secondary)
                }
                Spacer(minLength: 0)
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
                    .foregroundStyle(message.isRead ? Ink.secondary : Ink.primary)
                    .lineLimit(3)
                    // Hangs the opening mark so the card keeps one left axis.
                    .padding(.leading, -8)
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
                        .padding(.leading, -8)
                }
            }
            .padding(.horizontal, Metric.gutter)

            // The one place the gutter breaks.
            AsyncImage(url: urls[0]) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Rectangle().fill(Ink.surfaceTertiary)
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

    private func carouselBody(_ items: [Attachment]) -> some View {
        VStack(alignment: .leading, spacing: Space.md) {
            VStack(alignment: .leading, spacing: Space.sm) {
                KickerLabel(message.kicker)
                if let quote = message.quote {
                    Text("\u{201C}\(quote)\u{201D}")
                        .typeStyle(Style.display)
                        .foregroundStyle(Ink.primary)
                        .lineLimit(3)
                        .padding(.leading, -8)
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
                        .padding(.leading, -8)
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

    private var compactBody: some View {
        HStack(spacing: Space.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(message.sender.displayName.uppercased())
                    .typeStyle(Style.chip)
                    .foregroundStyle(Ink.secondary)
                Text(message.summary ?? message.subject)
                    .typeStyle(Style.body)
                    .foregroundStyle(Ink.primary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button(action: onSave) {
                Image(systemName: message.isSaved ? "bookmark.fill" : "bookmark")
            }
            Button(action: onArchive) { Image(systemName: "archivebox") }
        }
        .font(.system(size: 15))
        .foregroundStyle(Ink.secondary)
        .buttonStyle(.plain)
        .padding(.horizontal, Metric.gutter)
        .padding(.leading, Metric.avatarCompact + Space.md)
    }

    private var accessibilityLabel: String {
        var parts = [message.sender.displayName, message.kicker.rawValue]
        if let quote = message.quote { parts.append(quote) }
        if let summary = message.summary { parts.append(summary) }
        parts.append("\(message.threadCount) in thread, \(message.receivedAt.feedStamp)")
        return parts.joined(separator: ", ")
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
        Text(kicker.rawValue)
            .typeStyle(Style.kicker)
            .foregroundStyle(kicker == .reading || kicker == .notRead ? Ink.secondary : Ink.primary)
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
