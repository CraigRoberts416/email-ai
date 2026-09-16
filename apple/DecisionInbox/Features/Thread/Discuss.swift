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

    @Environment(FeedStore.self) private var store
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: Space.md) {
            TextField("", text: $text, prompt: placeholder, axis: .vertical)
                .typeStyle(Style.body)
                .foregroundStyle(Ink.onSheet)
                .tint(Ink.onSheet)
                .lineLimit(1...4)
                .focused($focused)
                .padding(.horizontal, Space.lg)
                .padding(.vertical, 9)
                // Opaque enough to sit on top of something. At 10% the
                // email's own headline read straight through the field, which
                // is the one place a control must not look like part of the
                // page behind it.
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .overlay(Capsule().fill(Ink.onSheet.opacity(0.08)))
                        .overlay(Capsule().strokeBorder(Ink.onSheet.opacity(0.14),
                                                        lineWidth: Metric.hairline))
                )
                .onSubmit(send)

            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(canSend ? Ink.primary : Ink.onSheetSecondary)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(canSend ? Ink.onSheet : Ink.onSheet.opacity(0.10)))
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .animation(Move.crisp, value: canSend)
        }
    }

    private var placeholder: Text {
        Text("Ask about the thread")
            .foregroundColor(Ink.onSheetSecondary)
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
