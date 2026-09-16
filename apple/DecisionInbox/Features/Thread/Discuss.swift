import Observation
import SwiftUI

/// Discuss, from `02 · Discuss`.
///
/// Asking about the thread in front of you rather than about mail in general.
/// Your question comes back as a light bubble — the same grey as a quoted
/// message, because both are things already said — and the answer is set in
/// plain white on the sheet, unboxed. The model does not get a card here; a
/// card would make its reply look like a message from a person.
@MainActor
@Observable
final class DiscussModel {
    struct Turn: Identifiable {
        let id = UUID()
        let question: String
        var answer: String?
        var failed = false
    }

    var turns: [Turn] = []
    var isAsking = false

    func ask(_ question: String, about message: Message, using store: FeedStore) {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isAsking else { return }
        turns.append(Turn(question: trimmed))
        isAsking = true

        Task {
            let index = turns.count - 1
            do {
                let answer = try await store.discuss(question: trimmed, about: message)
                turns[index].answer = answer
            } catch {
                turns[index].failed = true
                turns[index].answer = error.localizedDescription
            }
            isAsking = false
        }
    }
}

struct DiscussSection: View {
    let model: DiscussModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            ForEach(model.turns) { turn in
                VStack(alignment: .leading, spacing: Space.lg) {
                    Text(turn.question)
                        .typeStyle(Style.body)
                        .foregroundStyle(Ink.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(Space.lg)
                        .background(Ink.border, in: RoundedRectangle(cornerRadius: Corner.lg, style: .continuous))
                        .frame(maxWidth: 255, alignment: .trailing)
                        .frame(maxWidth: .infinity, alignment: .trailing)

                    if let answer = turn.answer {
                        Text(answer)
                            .typeStyle(Style.body)
                            .foregroundStyle(turn.failed ? Ink.onSheetSecondary : Ink.onSheet)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Caret(tint: Ink.onSheet)
                    }
                }
            }
        }
        .padding(.horizontal, Space.lg)
        .padding(.top, model.turns.isEmpty ? 0 : Space.xxl)
    }
}

// MARK: - Input

struct DiscussInput: View {
    let message: Message
    let model: DiscussModel
    /// The sheet's own colour. The composer is this screen's chrome, not the
    /// email's content — and the email below it can be any colour at all, so a
    /// field tinted to sit on "whatever is behind" disappeared the moment the
    /// message turned out to be a white retail template.
    var sheetColor: Color = Ink.sheet

    @Environment(FeedStore.self) private var store
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        // One pill holding both, the way ChatGPT, iMessage and Instagram all
        // build it. The send button used to sit outside the capsule as a bare
        // glyph on the blur, which read as a loose arrow floating at the edge
        // of the screen rather than a control belonging to the field.
        HStack(alignment: .bottom, spacing: Space.sm) {
            TextField("", text: $text, prompt: placeholder, axis: .vertical)
                .typeStyle(Style.body)
                .foregroundStyle(Ink.onSheet)
                .tint(Ink.onSheet)
                .lineLimit(1...5)
                .focused($focused)
                .padding(.leading, Space.lg)
                .padding(.vertical, Space.sm + 4)
                .onSubmit(send)

            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(canSend ? Ink.sheet : Ink.onSheetSecondary)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle().fill(canSend ? Ink.onSheet : Ink.onSheet.opacity(0.12))
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
        // The field separates from the blurred strip behind it. Two materials
        // of similar weight stacked on each other read as one surface, and it
        // vanished into the blur it was meant to be sitting on.
        // Liquid Glass. Not `.interactive()` — the field and the send button
        // own their own touches, and interactive glass eats them. That is the
        // bug that killed every back button in this app once.
        .glassControl(fallback: sheetColor.opacity(0.9), in: Capsule())
        // A tint under the glass, because the message behind it can be a white
        // retail template and clear glass on white is not a control. The
        // composer is the screen's chrome, so it wears the sheet's colour.
        .background(
            Capsule()
                .fill(sheetColor.opacity(0.55))
                .overlay(Capsule().strokeBorder(Ink.onSheet.opacity(0.16),
                                                lineWidth: Metric.hairline))
        )
    }

    private var placeholder: Text {
        // The field is a light material now, so the placeholder has to read
        // against that rather than against the dark sheet it used to sit on.
        Text("Ask about the thread")
            .foregroundColor(Ink.onSheet.opacity(0.55))
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !model.isAsking
    }

    private func send() {
        guard canSend else { return }
        model.ask(text, about: message, using: store)
        text = ""
        focused = false
    }
}
