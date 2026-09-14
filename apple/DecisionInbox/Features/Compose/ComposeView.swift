import SwiftUI

/// Reply, reply-all, forward and new, which differ only in who is addressed
/// and what is quoted underneath — so they are one screen, not four.
///
/// Sending is immediate with an 8-second undo rather than a "Send?" dialog.
/// A dialog asks everybody every time to catch the few who change their mind;
/// undo charges nothing until you actually do.
struct ComposeView: View {
    enum Intent: String, Identifiable {
        case reply, replyAll, forward, new
        var id: String { rawValue }

        var title: String {
            switch self {
            case .reply: return "Reply"
            case .replyAll: return "Reply all"
            case .forward: return "Forward"
            case .new: return "New message"
            }
        }
    }

    let intent: Intent
    var message: Message?

    @Environment(FeedStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @FocusState private var bodyFocused: Bool

    @State private var to = ""
    @State private var subject = ""
    @State private var text = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                field("To", text: $to)
                Rule()
                field("Subject", text: $subject)
                Rule()

                TextEditor(text: $text)
                    .typeStyle(Style.body)
                    .foregroundStyle(Ink.primary)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, Metric.gutter - 5)
                    .padding(.top, Space.md)
                    .focused($bodyFocused)

                if let message, intent != .new {
                    quotedOriginal(message)
                }
            }
            .background(Ink.surface)
            .navigationTitle(intent.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Ink.secondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: send) {
                        Text("Send")
                            .typeStyle(Style.sender)
                            .foregroundStyle(canSend ? Ink.primary : Ink.tertiary)
                    }
                    .disabled(!canSend)
                }
            }
            .task { prefill() }
        }
    }

    private var canSend: Bool {
        !to.trimmingCharacters(in: .whitespaces).isEmpty && !text.isEmpty
    }

    private func field(_ label: String, text binding: Binding<String>) -> some View {
        HStack(spacing: Space.md) {
            Text(label.uppercased())
                .typeStyle(Style.kicker)
                .foregroundStyle(Ink.secondary)
                .frame(width: 60, alignment: .leading)
            TextField("", text: binding)
                .typeStyle(Style.body)
                .foregroundStyle(Ink.primary)
                .textInputAutocapitalization(label == "To" ? .never : .sentences)
                .autocorrectionDisabled(label == "To")
                .keyboardType(label == "To" ? .emailAddress : .default)
        }
        .padding(.horizontal, Metric.gutter)
        .padding(.vertical, Space.md)
    }

    /// The original sits below the cursor, greyed and unedited — the same
    /// shape a quote-tweet takes in the feed.
    private func quotedOriginal(_ message: Message) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Rule()
            Text("\(message.sender.displayName) \u{00B7} \(message.receivedAt.feedStamp)")
                .typeStyle(Style.chip)
                .foregroundStyle(Ink.secondary)
            Text(message.snippet)
                .typeStyle(Style.bodySmall)
                .foregroundStyle(Ink.secondary)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Metric.gutter)
        .padding(.vertical, Space.md)
    }

    private func prefill() {
        guard let message else {
            bodyFocused = true
            return
        }
        switch intent {
        case .reply, .replyAll:
            to = message.sender.address
            subject = message.subject.hasPrefix("Re:") ? message.subject : "Re: \(message.subject)"
        case .forward:
            subject = message.subject.hasPrefix("Fwd:") ? message.subject : "Fwd: \(message.subject)"
            text = "\n\n\u{2014}\u{2014} Forwarded \u{2014}\u{2014}\n\(message.sender.displayName): \(message.snippet)"
        case .new:
            break
        }
        bodyFocused = true
    }

    /// Dismisses at once. The send itself sits behind the undo window, and its
    /// result arrives as a receipt over the feed — so the composer never
    /// becomes a waiting room.
    private func send() {
        store.queueSend(.init(
            to: to.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) },
            subject: subject,
            body: text,
            threadID: intent == .forward ? nil : message?.threadID,
            inReplyTo: intent == .forward ? nil : message?.id
        ))
        dismiss()
    }
}
