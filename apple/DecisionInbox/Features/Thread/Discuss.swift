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
    var turns: [DiscussionTurn] = []
    var draft = ""
    var isAsking = false
    var saved = true
    var focusRequested = false
    var scrollRequested = 0
    private var key = ""
    private var mailboxID = ""
    private var generation = 0

    func restore(for message: Message) {
        guard key != message.feedKey else { return }
        key = message.feedKey
        mailboxID = message.mailboxID
        generation = DiscussionStore.generation(for: mailboxID)
        if let record = DiscussionStore.load(key) {
            turns = record.turns.map { turn in
                var turn = turn
                if turn.answer == nil { turn.failed = true; turn.answer = "This answer was interrupted. Try again." }
                return turn
            }
            draft = record.draft
        }
    }

    func persist() {
        guard !key.isEmpty else { return }
        saved = DiscussionStore.save(.init(mailboxID: mailboxID, turns: turns, draft: draft), key: key, generation: generation)
    }

    func retry(_ turn: DiscussionTurn, about message: Message, using store: FeedStore) {
        guard !isAsking else { return }
        turns.removeAll { $0.id == turn.id }
        ask(turn.question, about: message, using: store)
    }

    func ask(_ question: String, about message: Message, using store: FeedStore) {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isAsking else { return }
        restore(for: message)
        let history = turns.filter { !$0.failed && $0.answer != nil }.suffix(6).flatMap { turn in
            [APIClient.DiscussionInput(role: "user", content: turn.question),
             APIClient.DiscussionInput(role: "assistant", content: turn.answer!)]
        }
        let turn = DiscussionTurn(question: trimmed)
        turns.append(turn)
        draft = ""
        isAsking = true
        scrollRequested += 1
        persist()
        Task {
            defer { isAsking = false; persist() }
            do {
                let answer = try await store.discuss(question: trimmed, about: message, history: history)
                guard let index = turns.firstIndex(where: { $0.id == turn.id }) else { return }
                turns[index].answer = answer.answer
                turns[index].scope = answer.scope?.description ?? "One email · source coverage not reported · attachments not read"
            } catch {
                guard let index = turns.firstIndex(where: { $0.id == turn.id }) else { return }
                turns[index].failed = true
                turns[index].answer = "Couldn’t answer. Your question is kept; try again."
            }
        }
    }
}

struct DiscussSection: View {
    let model: DiscussModel
    let message: Message
    @Environment(FeedStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            Text("DISCUSS THIS EMAIL · AI ANSWERS · KEPT ON THIS DEVICE").typeStyle(Style.monoMicro).foregroundStyle(Ink.onSheetSecondary)
            if !model.saved { Text("Couldn’t save this discussion on the device.").foregroundStyle(Ink.onSheetSecondary) }
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
                        if let scope = turn.scope { Text(scope).typeStyle(Style.monoMicro).foregroundStyle(Ink.onSheetSecondary) }
                        if turn.failed { Button("Try again") { model.retry(turn, about: message, using: store) }.disabled(model.isAsking).tint(Ink.onSheet) }
                    } else {
                        Caret(tint: Ink.onSheet)
                    }
                }
                .animation(Move.resolved(Move.crossfade, reduceMotion), value: turn.answer)
                .id(turn.id)
            }
        }
        .padding(.horizontal, Space.lg)
        .padding(.top, model.turns.isEmpty ? 0 : Space.xxl)
        .onChange(of: model.turns.last?.answer) {
            if model.turns.last?.answer != nil && UIAccessibility.isVoiceOverRunning {
                UIAccessibility.post(notification: .announcement, argument: model.turns.last?.failed == true ? "Question needs attention. Try again is available." : "Answer ready. View latest answer is available.")
            }
        }
    }
}

// MARK: - Input

struct DiscussInput: View {
    let message: Message
    @Bindable var model: DiscussModel
    /// The sheet's own colour. The composer is this screen's chrome, not the
    /// email's content — and the email below it can be any colour at all, so a
    /// field tinted to sit on "whatever is behind" disappeared the moment the
    /// message turned out to be a white retail template.
    var sheetColor: Color = Ink.sheet

    @Environment(FeedStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focused: Bool

    var body: some View {
        // One pill holding both, the way ChatGPT, iMessage and Instagram all
        // build it. The send button used to sit outside the capsule as a bare
        // glyph on the blur, which read as a loose arrow floating at the edge
        // of the screen rather than a control belonging to the field.
        VStack(alignment: .leading, spacing: Space.xs) {
        if model.draft.count > 2000 {
            Text("Use 2,000 characters or fewer. Your draft is kept.").typeStyle(Style.bodySmall).foregroundStyle(Ink.primary)
        }
        HStack(alignment: .bottom, spacing: Space.sm) {
            TextField("", text: $model.draft, prompt: placeholder, axis: .vertical)
                .typeStyle(Style.body)
                .foregroundStyle(Ink.primary)
                .tint(Ink.primary)
                .lineLimit(1...5)
                .focused($focused)
                .padding(.leading, Space.lg)
                .padding(.vertical, Space.sm + 4)
                .onSubmit(send)

            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(canSend ? Ink.surface : Ink.tertiary)
                    .frame(width: Metric.tapTarget, height: Metric.tapTarget)
                    .background(
                        Circle().fill(canSend ? Ink.primary : Ink.surfaceTertiary)
                    )
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .animation(Move.resolved(Move.crisp, reduceMotion), value: canSend)
            .padding(.trailing, Space.xs + 2)
            .padding(.bottom, Space.xs + 2)
            .accessibilityLabel("Send")
        }
        }
        // The field separates from the blurred strip behind it. Two materials
        // of similar weight stacked on each other read as one surface, and it
        // vanished into the blur it was meant to be sitting on.
        // Liquid Glass, light, with black text on it.
        //
        // Not `.interactive()` — the field and the send button own their own
        // touches, and interactive glass eats them. That is the bug that
        // killed every back button in this app once.
        //
        // Light rather than tinted to the sheet: this is a text field, and a
        // text field is where somebody writes. iOS makes these light glass
        // with dark text everywhere it ships one — Settings' search, Spotlight
        // — because what you type has to be the most legible thing on screen,
        // and the sheet's colour is whatever was extracted from a photograph.
        .onChange(of: model.draft) { model.persist() }
        .onChange(of: model.focusRequested) { if model.focusRequested { focused = true; model.focusRequested = false } }
        .task { if model.focusRequested { focused = true; model.focusRequested = false } }
        .glassControl(fallback: Ink.surface, in: Capsule())
        .background(
            Capsule()
                .fill(Ink.surface.opacity(0.72))
                .overlay(Capsule().strokeBorder(Ink.border.opacity(0.6),
                                                lineWidth: Metric.hairline))
        )
    }

    private var placeholder: Text {
        // Grey on the light field, the way a placeholder reads everywhere
        // else in the app.
        Text("Ask about this email")
            .foregroundColor(Ink.tertiary)
    }

    private var canSend: Bool {
        !model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && model.draft.count <= 2000 && !model.isAsking
    }

    private func send() {
        guard canSend else { return }
        model.ask(model.draft, about: message, using: store)
    }
}
