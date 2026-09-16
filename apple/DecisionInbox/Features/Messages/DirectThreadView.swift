import SwiftUI

/// One conversation with one person, or with one set of people.
///
/// Built to `DirectThread`. The participant set is the conversation: adding
/// someone would not change this thread, it would open a different one with
/// all of you in it — the same model as iMessage and every group text. That
/// is not a simplification of email either; a reply-all with a new address on
/// it already forks the thread, and mail clients merely hide the fork and let
/// both branches wear the same subject line.
struct DirectThreadView: View {
    let conversation: Conversation

    @Environment(FeedStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var messages: [ConversationMessage] = []
    @State private var loaded = false

    var body: some View {
        ScrollView {
                LazyVStack(alignment: .leading, spacing: Space.sm + 2) {
                    if messages.isEmpty {
                        // Two different facts, and they were rendering as the
                        // same blank screen. The first open of a thread now
                        // fetches each message's body from Gmail, which takes
                        // a few seconds — long enough that saying nothing
                        // reads as "there is nothing here".
                        Text(loaded ? "NOTHING YET" : "READING\u{2026}")
                            .typeStyle(Style.monoMicro)
                            .foregroundStyle(Ink.tertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 160)
                    }

                    ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                        // A stamp when the gap since the last message is long
                        // enough that the reader has lost the thread of when.
                        if let stamp = stamp(before: index) {
                            Text(stamp)
                                .typeStyle(Style.monoMicro)
                                .foregroundStyle(Ink.tertiary)
                                .frame(maxWidth: .infinity)
                                .padding(.top, Space.lg)
                        }

                        MessageBubble(
                            message: message,
                            // In a group every bubble names its sender —
                            // the one thing a one-to-one thread never needs
                            // and a group always does.
                            showsSender: conversation.isGroup && !message.mine
                        )
                        .id(message.id)
                    }
                }
                .padding(.horizontal, Metric.gutter)
                .padding(.vertical, Space.xl)
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
        .task {
            messages = await store.messages(in: conversation)
            loaded = true
        }
    }

    private var header: some View {
        HStack(spacing: Space.md) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Ink.primary)
                    .frame(width: 40, height: 40)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")

            GroupAvatar(participants: conversation.participants, size: 34)

            Text(conversation.title)
                .typeStyle(Style.body)
                .foregroundStyle(Ink.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, Space.sm)
        .padding(.trailing, Metric.gutter)
        .padding(.bottom, Space.md)
        .background {
            Ink.surface
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Ink.border).frame(height: Metric.hairline)
                }
                .ignoresSafeArea(edges: .top)
        }
    }

    /// Only when the gap is long enough to be worth saying. A stamp between
    /// every pair of messages is noise; one after four hours of silence is
    /// the fact that the silence happened.
    private func stamp(before index: Int) -> String? {
        guard index < messages.count else { return nil }
        let message = messages[index]
        guard index > 0 else { return message.receivedAt.spokenStamp.uppercased() }
        let gap = message.receivedAt.timeIntervalSince(messages[index - 1].receivedAt)
        guard gap > 4 * 60 * 60 else { return nil }
        return message.receivedAt.spokenStamp.uppercased()
    }
}

/// One turn, in a bubble.
///
/// Bubbles are the second containerised thing in this product, after an
/// attachment, and they earn it on the system's own test: an utterance is a
/// discrete object with a boundary and an author.
struct MessageBubble: View {
    let message: ConversationMessage
    var showsSender = false

    var body: some View {
        VStack(alignment: message.mine ? .trailing : .leading, spacing: Space.xs) {
            if showsSender {
                Text(message.sender.displayName.uppercased())
                    .typeStyle(Style.monoMicro)
                    .foregroundStyle(Ink.tertiary)
            }

            // Email has a field chat does not. Dropping it entirely would lose
            // something real, but it is theirs — so it sits above their words
            // rather than becoming a header we invented.
            if let subject = message.subject {
                Text(subject.uppercased())
                    .typeStyle(Style.monoMicro)
                    .foregroundStyle(Ink.tertiary)
                    .lineLimit(1)
            }

            VStack(alignment: .leading, spacing: Space.sm) {
                ForEach(message.attachments) { attachment in
                    AttachmentChip(attachment: attachment, onDark: message.mine)
                }

                if !message.body.isEmpty {
                    Text(message.body)
                        .typeStyle(Style.body)
                        .foregroundStyle(message.mine ? Ink.surface : Ink.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, Space.lg - 2)
            .padding(.vertical, Space.md - 2)
            .background(
                message.mine ? Ink.primary : Ink.surfaceTertiary,
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
            // Capped, never stretched to the gutter: a line of text running
            // the full width of a phone is not a message, it is a paragraph.
            .frame(maxWidth: 286, alignment: message.mine ? .trailing : .leading)
        }
        .frame(maxWidth: .infinity, alignment: message.mine ? .trailing : .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(message.mine ? "You" : message.sender.displayName): \(message.body)"
        )
    }
}

/// A file inside a bubble, reusing the tile's vocabulary — the same object
/// should not look like two different things depending on where it appears.
struct AttachmentChip: View {
    let attachment: Attachment
    var onDark = false

    var body: some View {
        HStack(spacing: Space.sm + 2) {
            Text(kind)
                .typeStyle(Style.monoMicro)
                .foregroundStyle(onDark ? Ink.surface.opacity(0.8) : Ink.secondary)
                .frame(width: 40, height: 40)
                .background(
                    onDark ? Ink.surface.opacity(0.16) : Ink.surfaceTertiary,
                    in: RoundedRectangle(cornerRadius: Corner.sm, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 1) {
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
    }

    private var kind: String {
        attachment.filename.split(separator: ".").last
            .map { String($0).uppercased() } ?? "FILE"
    }
}
