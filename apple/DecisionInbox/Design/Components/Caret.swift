import SwiftUI

/// The product's loading language, in one place.
///
/// Decision Inbox has no spinners. Generation is the substance of the product,
/// so every wait state shows the machine at the position it is writing from —
/// a caret — rather than a grey ring that could be anything, or a skeleton
/// pretending to be content that has not been written yet.
///
/// This replaces three near-identical implementations of the same signal that
/// had drifted into three files (the interpreting post, the unsubscribe run
/// log, the Discuss placeholder). One component means Reduce Motion is handled
/// once, and the blink cannot be retuned in one place and not the others.
///
/// The caret is `accessibilityHidden` — it is a rendering of a status, not the
/// status itself — so **every parent must carry the status in its own label or
/// value**, and announce only terminal states.
struct Caret: View {
    /// Matched to the leading of the line it sits beside.
    var height: CGFloat = 20
    var tint: Color = Ink.primary

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.motionIsActive) private var motionIsActive
    @State private var on = false
    @State private var visible = true
    private var animating: Bool { !reduceMotion && motionIsActive && visible && scenePhase == .active }

    var body: some View {
        Rectangle()
            .fill(tint)
            .frame(width: Metric.unreadBar, height: height)
            // Reduced motion is an alternate direction, not a speed of zero.
            // A static 55% bar still marks the position a machine is writing
            // at; the sentence beside it ("Reading this one…", "Filling it
            // out…") carries the rest.
            .opacity(animating ? (on ? 1 : 0.25) : 0.55)
            .onAppear { visible = true }
            .onDisappear { visible = false }
            .onScrollVisibilityChange(threshold: 0.01) { visible = $0 }
            .task(id: animating) {
                guard animating else { return }
                while !Task.isCancelled {
                    withAnimation(Move.caretRamp) { on.toggle() }
                    do { try await Task.sleep(for: .seconds(Move.caretHold)) }
                    catch { return }
                }
            }
            .accessibilityHidden(true)
    }
}

/// The caret with the sentence that explains it. The pairing is the whole
/// signal — a bare bar is a rendering artefact until something names it.
struct CaretLine: View {
    let label: String
    var height: CGFloat = 20

    var body: some View {
        HStack(spacing: Space.sm) {
            Caret(height: height)
            Text(label)
                .typeStyle(Style.ai)
                .foregroundStyle(Ink.secondary)
        }
        // The caret is hidden from accessibility, so the pair speaks as the
        // sentence alone.
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: Space.xl) {
        CaretLine(label: "Reading this one\u{2026}")
        CaretLine(label: "Filling it out\u{2026}")
        Caret(height: 14)
    }
    .padding()
}


/// Ancestors can suspend decorative motion behind sheets or inactive tabs.
private struct MotionIsActiveKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var motionIsActive: Bool {
        get { self[MotionIsActiveKey.self] }
        set { self[MotionIsActiveKey.self] = newValue }
    }
}
