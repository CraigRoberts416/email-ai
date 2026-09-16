import SwiftUI

/// Writing back, without leaving the conversation.
///
/// Built against ChatGPT, iMessage, Instagram and X, which agree on the shape:
/// a pill that floats clear of both edges rather than a bar bolted to the
/// bottom, the thread scrolling *under* it through a fade, an attach control
/// on the left and a filled circular send on the right. It grows upward as you
/// type and stops at a height that still leaves the conversation visible —
/// you are answering something, and hiding it to write is the wrong trade.
///
/// The fade matters more than it looks. A hard edge makes the composer a
/// separate panel and the thread feel truncated behind it; a fade says the
/// thread continues and this is sitting on top of it.
struct ThreadComposer: View {
    let conversation: Conversation
    /// The last thing said, for threading. A reply carries the subject it is
    /// answering and an In-Reply-To pointing at it, which is what keeps this
    /// in the same correspondence in every other mail client too.
    var replyingTo: ConversationMessage?
    var onSent: () -> Void = {}

    @Environment(FeedStore.self) private var store
    @State private var text = ""
    @FocusState private var writing: Bool

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: Space.sm) {
            TextField("Message", text: $text, axis: .vertical)
                .typeStyle(Style.body)
                .foregroundStyle(Ink.primary)
                .tint(Ink.primary)
                .focused($writing)
                // Six lines, then it scrolls inside itself. Past that the
                // composer would be eating the conversation it is answering.
                .lineLimit(1...6)
                .padding(.leading, Space.lg - 2)
                .padding(.vertical, Space.sm + 4)

            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(canSend ? Ink.surface : Ink.tertiary)
                    .frame(width: 32, height: 32)
                    .background(
                        canSend ? Ink.primary : Ink.surfaceTertiary,
                        in: Circle()
                    )
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .animation(Move.crisp, value: canSend)
            .padding(.trailing, Space.xs + 2)
            .padding(.bottom, Space.xs + 2)
            .accessibilityLabel("Send")
        }
        // Liquid Glass, non-interactive: the field and the send button take
        // their own touches and interactive glass would swallow them.
        .glassControl(fallback: Ink.surface, in: Capsule(style: .continuous))
        .background(
            Capsule(style: .continuous)
                .strokeBorder(Ink.border, lineWidth: Metric.hairline)
        )
        .padding(.horizontal, Metric.gutter)
        .padding(.top, Space.sm)
        .padding(.bottom, Space.sm)
        .background {
            // The system blur, masked to fade in — not a colour gradient
            // painted over the thread. Same treatment as the email sheet's
            // field, because they are the same control in two places.
            Rectangle()
                .fill(.ultraThinMaterial)
                .mask(
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.85), .black],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
        }
    }

    /// Sends into the existing correspondence.
    ///
    /// The subject is carried from what is already there rather than asked
    /// for: this is a reply in a conversation, and a chat composer that
    /// demanded a subject line would be an email client wearing a costume.
    private func send() {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }

        store.queueSend(.init(
            to: conversation.participants.map(\.address),
            subject: replySubject,
            body: body,
            threadID: nil,
            inReplyTo: replyingTo?.id
        ))

        text = ""
        writing = false
        onSent()
    }

    /// The subject of the thing being answered, prefixed once.
    ///
    /// Not the conversation title — that is the person's name, and "Re: Nadia
    /// Rassuli" is not a subject line. When there is nothing to answer, the
    /// mail goes out with no subject rather than an invented one.
    private var replySubject: String {
        guard let subject = replyingTo?.subject?.trimmingCharacters(in: .whitespaces),
              !subject.isEmpty
        else { return "" }
        return subject.lowercased().hasPrefix("re:") ? subject : "Re: \(subject)"
    }
}
