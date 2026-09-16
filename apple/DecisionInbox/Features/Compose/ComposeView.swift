import SwiftUI

/// The composer, built to `Flows · Thread & Compose / 03–06`.
///
/// Reply, reply-all, forward and new differ only in who is addressed and what
/// is quoted underneath, so they are one screen rather than four.
///
/// Sending is immediate with an undo window rather than a "Send?" dialog. A
/// dialog taxes everybody every time to catch the few who change their mind;
/// an undo charges nothing until you actually use it.
struct ComposeView: View {
    enum Intent: String, Identifiable {
        case reply, replyAll, forward, new
        var id: String { rawValue }

        var subjectPrefix: String? {
            switch self {
            case .reply, .replyAll: return "Re:"
            case .forward: return "Fwd:"
            case .new: return nil
            }
        }
    }

    let intent: Intent
    var message: Message?
    /// Somebody's address, tapped in a thread. An email address in a message
    /// is a person to write to, not a page to visit.
    var prefilledTo: String?

    @Environment(FeedStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @FocusState private var bodyFocused: Bool

    @State private var to = ""
    @State private var subject = ""
    @State private var text = ""
    @State private var suggestion: String?
    @State private var attachments: [Attachment] = []

    /// Gmail's ceiling. Naming it here rather than in a string keeps the copy
    /// and the rule from drifting apart.
    private static let attachmentLimit = 25 * 1_000_000

    var body: some View {
        VStack(spacing: 0) {
            header
            Rule()

            field("TO", text: $to, keyboard: .emailAddress)
            Rule()
            field("SUBJECT", text: $subject, keyboard: .default)
            Rule()

            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    TextEditor(text: $text)
                        .typeStyle(Style.body)
                        .foregroundStyle(Ink.primary)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 88)
                        .focused($bodyFocused)
                        .padding(.horizontal, -5)

                    if let suggestion { suggestedDraft(suggestion) }
                    if let message, intent != .new { quoted(message) }
                    ForEach(attachments) { attachment in
                        attachmentRow(attachment)
                    }
                }
                .padding(Space.xl)
            }
            .scrollIndicators(.hidden)
        }
        .background(Ink.surface)
        .task { prefill() }
    }

    // MARK: Chrome

    private var header: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .typeStyle(Style.body)
                .foregroundStyle(Ink.secondary)
                .buttonStyle(.plain)

            Spacer(minLength: 0)

            Button(action: send) {
                Text("Send")
                    .typeStyle(Style.button)
                    .foregroundStyle(canSend ? Ink.onInverse : Ink.secondary)
                    .padding(.horizontal, Space.lg)
                    .padding(.vertical, Space.sm)
                    .background(canSend ? Ink.inverse : Ink.border, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .animation(Move.crisp, value: canSend)
        }
        .padding(.horizontal, Space.xl - 4)
        .padding(.vertical, Space.lg + 6)
    }

    private func field(
        _ label: String,
        text binding: Binding<String>,
        keyboard: UIKeyboardType
    ) -> some View {
        HStack(spacing: 0) {
            Text(label)
                .typeStyle(Style.fieldLabel)
                .foregroundStyle(Ink.secondary)
                .frame(width: 70, alignment: .leading)
            TextField("", text: binding)
                .typeStyle(Style.body)
                .foregroundStyle(Ink.primary)
                .tint(Ink.primary)
                .keyboardType(keyboard)
                .textInputAutocapitalization(keyboard == .emailAddress ? .never : .sentences)
                .autocorrectionDisabled(keyboard == .emailAddress)
        }
        .padding(.horizontal, Space.xl - 4)
        .padding(.vertical, Space.md + 2)
    }

    // MARK: Blocks

    /// The model's draft, and the label is the whole point of it: yours to
    /// edit, yours to send. Nothing here goes out because the model wrote it.
    private func suggestedDraft(_ draft: String) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text("SUGGESTED \u{2014} YOURS TO EDIT, YOURS TO SEND")
                .typeStyle(Style.chip)
                .foregroundStyle(Ink.secondary)

            Text("\u{201C}\(draft)\u{201D}")
                .typeStyle(Style.draft)
                .foregroundStyle(Ink.primary)
                .fixedSize(horizontal: false, vertical: true)

            Button("Use this") {
                text = draft
                suggestion = nil
                bodyFocused = true
            }
            .typeStyle(Style.quoted)
            .foregroundStyle(Ink.primary)
            .buttonStyle(.plain)
            .padding(.top, Space.xs)
        }
        .padding(.leading, Space.md)
        .overlay(alignment: .leading) {
            Rectangle().fill(Ink.border).frame(width: 1)
        }
    }

    /// The original, greyed and unedited — the same shape a quote-tweet takes
    /// in the feed, for the same reason.
    private func quoted(_ message: Message) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text("\(message.sender.displayName.uppercased()) \u{00B7} \(message.receivedAt.threadStamp.uppercased())")
                .typeStyle(Style.chip)
                .foregroundStyle(Ink.secondary)
            Text(message.snippet)
                .typeStyle(Style.quoted)
                .foregroundStyle(Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.lg)
        .background(Ink.surfaceTertiary, in: RoundedRectangle(cornerRadius: Corner.md, style: .continuous))
    }

    /// Too large is drawn with a heavier black border, not a red one. The
    /// product has no colour to spend on alarm, and weight carries it fine.
    private func attachmentRow(_ attachment: Attachment) -> some View {
        let oversized = attachment.byteCount > Self.attachmentLimit
        return HStack(spacing: Space.md) {
            Image(systemName: "doc.text")
                .font(.system(size: 16))
                .foregroundStyle(Ink.primary)

            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.filename)
                    .typeStyle(Style.quoted)
                    .foregroundStyle(Ink.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(oversized
                     ? "\(attachment.sizeLabel.uppercased()) \u{00B7} GMAIL STOPS AT 25 MB\nSEND A LINK INSTEAD, OR REMOVE IT"
                     : "\(attachment.sizeLabel.uppercased()) \u{00B7} \(attachment.kindLabel)")
                    .typeStyle(Style.fileMeta)
                    .foregroundStyle(Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Space.sm)

            Button {
                attachments.removeAll { $0.id == attachment.id }
            } label: {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 16))
                    .foregroundStyle(Ink.primary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(attachment.filename)")
        }
        .padding(.horizontal, Space.md + 2)
        .padding(.vertical, Space.md)
        .overlay(
            RoundedRectangle(cornerRadius: Corner.md, style: .continuous)
                .strokeBorder(oversized ? Ink.primary : Ink.border, lineWidth: oversized ? 2 : 1)
        )
    }

    // MARK: Behaviour

    private var canSend: Bool {
        !to.trimmingCharacters(in: .whitespaces).isEmpty
            && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !attachments.contains { $0.byteCount > Self.attachmentLimit }
    }

    private func prefill() {
        // An address tapped in a thread fills the TO field and puts the cursor
        // in the body — the recipient is the one thing already decided.
        if let prefilledTo, to.isEmpty {
            to = prefilledTo
            bodyFocused = true
        }
        guard let message else {
            if prefilledTo == nil { bodyFocused = true }
            return
        }
        if let prefix = intent.subjectPrefix {
            subject = message.subject.hasPrefix(prefix) ? message.subject : "\(prefix) \(message.subject)"
        }
        switch intent {
        case .reply, .replyAll:
            to = message.sender.address
            // Offered, never inserted. A draft that types itself into the body
            // is one careless tap away from being sent as though you wrote it.
            Task { suggestion = try? await store.suggestReply(to: message) }
        case .forward:
            if case .carousel(let items) = message.shape { attachments = items }
        case .new:
            break
        }
        bodyFocused = true
    }

    /// Dismisses at once. The send sits behind the undo window and its result
    /// arrives as a receipt over the feed, so the composer is never a waiting
    /// room.
    private func send() {
        store.queueSend(.init(
            to: to.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) },
            subject: subject,
            body: text,
            threadID: intent == .forward ? nil : message?.threadID,
            inReplyTo: intent == .forward ? nil : message?.id
        ), from: message?.mailboxID)
        dismiss()
    }
}

extension Attachment {
    var kindLabel: String {
        (filename as NSString).pathExtension.uppercased()
    }
}
