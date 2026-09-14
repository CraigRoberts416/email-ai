import SwiftUI

/// The agent working.
///
/// A headless browser is opening the sender's site and filling in their form.
/// That is a strange thing to be told is happening, so the tray shows the work
/// rather than a spinner: each step is a line in a log, in mono, and it stays
/// on screen afterwards so the outcome is legible.
///
/// The split throughout: **the enum is fixed, the sentence is free.** Step
/// names are a closed set the UI can reason about; the words are written per
/// run by the model. `UnsubscribeCopy` below is the fallback for when the
/// server sends a status with no sentence attached.
struct UnsubscribeTray: View {
    let runs: [SSEClient.UnsubscribeStatus]
    var onDismiss: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            HStack(spacing: Space.md) {
                Text(headline)
                    .typeStyle(Style.sender)
                    .foregroundStyle(Ink.onInverse)
                Spacer(minLength: 0)
                if runs.allSatisfy(\.isTerminal) {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Ink.onInverseSecondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss")
                }
            }

            VStack(alignment: .leading, spacing: Space.md) {
                ForEach(runs, id: \.messageId) { run in
                    RunLine(run: run)
                }
            }
        }
        .padding(Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Ink.inverse, in: RoundedRectangle(cornerRadius: Corner.lg, style: .continuous))
        .padding(.horizontal, Metric.gutter)
        .accessibilityElement(children: .combine)
    }

    private var headline: String {
        let active = runs.filter { !$0.isTerminal }.count
        if active == 0 {
            let failed = runs.count { $0.status == "error" }
            return failed > 0 ? "\(failed) couldn\u{2019}t be done" : "Done"
        }
        return runs.count == 1 ? "Unsubscribing" : "Unsubscribing from \(runs.count)"
    }
}

/// One sender's run. The step counter is the honest part — "filling out form
/// 2/3" tells you where you are in a process you cannot see.
private struct RunLine: View {
    let run: SSEClient.UnsubscribeStatus

    var body: some View {
        HStack(alignment: .top, spacing: Space.md) {
            marker
                .frame(width: 14, height: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(run.message ?? UnsubscribeCopy.sentence(for: run.status, sender: run.senderName))
                    .typeStyle(Style.monoSmall)
                    .foregroundStyle(Ink.onInverse)
                    .fixedSize(horizontal: false, vertical: true)

                if let step = UnsubscribeCopy.step(for: run.status) {
                    Text("\(run.senderName?.uppercased() ?? "SENDER")  \u{00B7}  STEP \(step)/\(UnsubscribeCopy.totalSteps)")
                        .typeStyle(Style.chip)
                        .foregroundStyle(Ink.onInverseSecondary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder private var marker: some View {
        switch run.status {
        case "done":
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Ink.onInverse)
        case "error":
            Image(systemName: "exclamationmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Ink.onInverse)
        default:
            WorkingCaret()
        }
    }
}

/// 530ms, matched to the caret on an interpreting card — the same signal for
/// the same thing: a machine is mid-sentence.
private struct WorkingCaret: View {
    @State private var on = false

    var body: some View {
        Rectangle()
            .fill(Ink.onInverse)
            .frame(width: 2, height: 13)
            .opacity(on ? 1 : 0.2)
            .task {
                while !Task.isCancelled {
                    withAnimation(.easeInOut(duration: 0.53)) { on.toggle() }
                    try? await Task.sleep(for: .milliseconds(530))
                }
            }
    }
}

// MARK: - Copy
//
// The server writes these sentences per run, generated from `prompts/tone.md`,
// so no two unsubscribes read identically. These are the fallbacks — used only
// when a status arrives without one, which happens on reconnect when the tray
// replays statuses it missed.

enum UnsubscribeCopy {
    static let totalSteps = 4

    /// The closed set of steps. Anything outside it is treated as working.
    static func step(for status: String) -> Int? {
        switch status {
        case "navigating": return 1
        case "analyzing": return 2
        case "filling": return 3
        case "clicking", "verifying": return 4
        default: return nil
        }
    }

    static func sentence(for status: String, sender: String?) -> String {
        let name = sender ?? "them"
        switch status {
        case "queued":     return "Getting ready\u{2026}"
        case "navigating": return "Opening \(name)\u{2019}s site\u{2026}"
        case "analyzing":  return "Finding the unsubscribe form\u{2026}"
        case "filling":    return "Filling it out\u{2026}"
        case "clicking":   return "Submitting it\u{2026}"
        case "verifying":  return "Checking it took\u{2026}"
        case "done":       return "Unsubscribed from \(name)."
        case "error":      return "Couldn\u{2019}t finish this one. Nothing was sent."
        default:           return "Working\u{2026}"
        }
    }
}

extension SSEClient.UnsubscribeStatus {
    var isTerminal: Bool { status == "done" || status == "error" }
}

#Preview {
    VStack(spacing: Space.lg) {
        UnsubscribeTray(runs: [
            .init(messageId: "1", senderName: "Nike", status: "filling",
                  message: "Filling out their form \u{2014} it wants the address twice."),
            .init(messageId: "2", senderName: "Figma", status: "navigating", message: nil),
        ])
        UnsubscribeTray(runs: [
            .init(messageId: "1", senderName: "Nike", status: "done",
                  message: "Done. Nike won\u{2019}t email you again."),
        ])
    }
    .padding(.vertical)
    .background(Ink.surfaceTertiary)
}
