import SwiftUI

/// The agent working, built to `Feature · Unsubscribe agent / 02–03`.
///
/// One tray, never three toasts. A headless browser is opening the sender's
/// own page and filling in their form, which is a strange thing to be told is
/// happening — so the tray reports position rather than reassurance, and the
/// segments let you read progress without reading the words at all.
///
/// The per-sender log is not here. It lives one tap away behind the chevron,
/// because a feed is not the place to watch a machine think out loud.
struct UnsubscribeTray: View {
    let runs: [SSEClient.UnsubscribeStatus]
    var onOpenLog: () -> Void = {}

    private var working: [SSEClient.UnsubscribeStatus] { runs.filter { !$0.step.isTerminal } }
    private var current: SSEClient.UnsubscribeStatus? { working.first ?? runs.last }
    private var isBatch: Bool { runs.count > 1 }

    var body: some View {
        VStack(spacing: Space.md) {
            HStack(spacing: 10) {
                AvatarStack(
                    senders: runs.compactMap(\.sender),
                    size: 20,
                    ringColor: Ink.inverse
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .typeStyle(Style.navAction)
                        .foregroundStyle(Ink.onSheet)
                        .lineLimit(1)

                    Text(statusLine)
                        .typeStyle(Style.status)
                        .foregroundStyle(Ink.onInverseSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if isBatch {
                    Text("\(resolved)/\(runs.count)")
                        .typeStyle(Style.meta)
                        .foregroundStyle(Ink.onSheet)
                        .monospacedDigit()
                }

                Image(systemName: "chevron.up")
                    .font(.system(size: 13))
                    .foregroundStyle(Ink.onInverseSecondary)
            }

            if isBatch { segments }
        }
        .padding(.horizontal, Space.lg)
        .padding(.vertical, 14)
        .background(Ink.inverse, in: RoundedRectangle(cornerRadius: Corner.xl, style: .continuous))
        .contentShape(.rect)
        .onTapGesture(perform: onOpenLog)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(statusLine)")
        .accessibilityHint("Opens the run log")
    }

    /// The channel you can read without reading. One segment per sender:
    /// white when it resolved, grey for the one being worked, near-black for
    /// work not started.
    private var segments: some View {
        HStack(spacing: 3) {
            ForEach(Array(runs.enumerated()), id: \.element.messageId) { index, run in
                Capsule()
                    .fill(
                        run.step.isTerminal ? Ink.onSheet
                            : (index == resolved ? Ink.onInverseSecondary : Ink.pending)
                    )
                    .frame(height: 2)
            }
        }
    }

    private var resolved: Int { runs.count { $0.step.isTerminal } }

    private var title: String {
        if let done = terminalHeadline { return done }
        guard let current else { return "Unsubscribing" }
        return isBatch
            ? "Unsubscribing from \(runs.count) senders"
            : "Unsubscribing from \(current.senderName ?? "them")"
    }

    /// Once everything has resolved the tray stops describing an activity and
    /// states the outcome — including the outcomes that are not success.
    private var terminalHeadline: String? {
        guard working.isEmpty else { return nil }
        let failed = runs.count { $0.step == .failed || $0.step == .noLink }
        let needsYou = runs.count { $0.step == .needsYou }
        if needsYou > 0 { return needsYou == 1 ? "One needs you" : "\(needsYou) need you" }
        if failed > 0 { return failed == 1 ? "One couldn\u{2019}t be done" : "\(failed) couldn\u{2019}t be done" }
        return runs.count == 1 ? "Done" : "All \(runs.count) done"
    }

    /// `STEP · COUNTER · SENTENCE`, upper-cased as a whole. The step and the
    /// counter are ours and deterministic; the sentence is the model's.
    private var statusLine: String {
        guard let current else { return "" }
        var parts = [current.step.label]
        if isBatch, let name = current.senderName { parts.append(name) }
        if let counter = current.counter { parts.append(counter) }
        parts.append(current.message ?? current.step.fallback(sender: current.senderName))
        return parts.joined(separator: "  \u{00B7}  ").uppercased()
    }
}

// MARK: - The closed set

/// Eleven steps, and `error` is not one of them. A failure that is retryable,
/// a page with nothing to click, a CAPTCHA that needs a human, and a sender
/// who confirmed and then wrote anyway are four different facts, and calling
/// them all "error" throws away the only useful thing the agent learned.
enum UnsubscribeStep: String {
    case queued, navigating, analyzing, filling, clicking, verifying
    case done
    case noLink = "no_link"
    case needsYou = "needs_you"
    case failed
    case stillSending = "still_sending"

    init(_ raw: String) {
        // The server still says `error`; it means retryable failure.
        self = UnsubscribeStep(rawValue: raw) ?? (raw == "error" ? .failed : .queued)
    }

    var isTerminal: Bool {
        switch self {
        case .done, .noLink, .needsYou, .failed, .stillSending: return true
        default: return false
        }
    }

    var label: String {
        switch self {
        case .queued: return "Queued"
        case .navigating: return "Opening"
        case .analyzing: return "Reading"
        case .filling: return "Filling the form"
        case .clicking: return "Submitting"
        case .verifying: return "Verifying"
        case .done: return "Done"
        case .noLink: return "No link"
        case .needsYou: return "Needs you"
        case .failed: return "Couldn\u{2019}t finish"
        case .stillSending: return "Still sending"
        }
    }

    /// Used only when the model is slow, rate-limited or offline. Deliberately
    /// plain: a fallback that tries to be charming reads as a bug the moment
    /// it repeats.
    func fallback(sender: String?) -> String {
        let them = sender ?? "them"
        switch self {
        case .queued: return "Lining this one up"
        case .navigating: return "Opening \(them)\u{2019}s page"
        case .analyzing: return "Reading \(them)\u{2019}s page"
        case .filling: return "Filling in their form"
        case .clicking: return "Confirming"
        case .verifying: return "Checking it took"
        case .done: return "\(them) confirmed it"
        case .noLink: return "Nothing on the page to click"
        case .needsYou: return "Their page wants a person"
        case .failed: return "Their page didn\u{2019}t answer"
        case .stillSending: return "\(them) wrote again after confirming"
        }
    }
}

extension SSEClient.UnsubscribeStatus {
    var step: UnsubscribeStep { UnsubscribeStep(status) }

    var sender: Sender? {
        guard let senderName else { return nil }
        return Sender(name: senderName, address: senderName, kind: .brand, logoURL: nil)
    }

    /// The counter switches from sites to fields while filling, because that
    /// is what is visibly happening. Analyzing has none — nobody cares how
    /// many elements were scanned.
    var counter: String? {
        switch step {
        case .filling:
            guard let i = fieldIndex, let n = fieldTotal else { return nil }
            return "field \(i) of \(n)"
        case .navigating, .clicking, .verifying:
            guard let i = index, let n = total, n > 1 else { return nil }
            return "site \(i) of \(n)"
        default:
            return nil
        }
    }

    var isTerminal: Bool { step.isTerminal }
}

#Preview {
    VStack(spacing: Space.lg) {
        UnsubscribeTray(runs: [
            .init(messageId: "1", senderName: "Nike", status: "filling",
                  message: "\u{201C}Why are you leaving?\u{201D}",
                  index: 1, total: 1, fieldIndex: 2, fieldTotal: 4),
        ])
        UnsubscribeTray(runs: [
            .init(messageId: "1", senderName: "Nike", status: "done", message: nil,
                  index: 1, total: 3, fieldIndex: nil, fieldTotal: nil),
            .init(messageId: "2", senderName: "Everlane", status: "analyzing",
                  message: "Reading their page", index: 2, total: 3,
                  fieldIndex: nil, fieldTotal: nil),
            .init(messageId: "3", senderName: "Figma", status: "queued", message: nil,
                  index: 3, total: 3, fieldIndex: nil, fieldTotal: nil),
        ])
    }
    .padding(Space.lg)
    .background(Ink.surfaceTertiary)
}
