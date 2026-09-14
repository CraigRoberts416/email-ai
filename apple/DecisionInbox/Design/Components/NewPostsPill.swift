import SwiftUI

/// The X/Twitter new-posts capsule.
///
/// Its real job is not engagement — it is a stability guarantee. The list never
/// reorders under your thumb, and arrival becomes a deferred, user-controlled
/// event. A finite inbox needs that more than Twitter does, because the worst
/// failure of "you're caught up" is mail landing mid-triage and pushing the
/// end invisibly further away.
///
/// Its **appearance** is deliberately silent: no haptic, no badge, no sound.
/// The user did not cause it, and the frequency is unbounded. Its **tap** is
/// the one place `Haptics.announce()` fires — the lightest cue in the set on
/// the heaviest visual event in the product.
struct NewPostsPill: View {
    let senders: [Sender]
    let count: Int
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    /// The pill gets physically heavier as the batch grows, so weight carries
    /// urgency in a system with no colour to spend.
    private var heavy: Bool { count >= Move.Pill.maxAvatars }
    /// Three avatars plus "3 NEW" exceeds the screen at accessibility sizes.
    /// The count is the information; the faces are the flavour, so the faces
    /// are what goes.
    private var showsAvatars: Bool { typeSize < .accessibility2 }

    var body: some View {
        Button {
            // H6 — the feed is about to change wholesale AND the viewport is
            // about to move several hundred points. The lightest cue on the
            // heaviest visual event, fired at touch-down so it arrives with the
            // decision rather than after it.
            Haptics.announce()
            action()
        } label: {
            HStack(spacing: Space.sm) {
                if showsAvatars {
                    AvatarStack(
                        senders: senders,
                        size: Metric.avatarPill,
                        ringColor: heavy ? Ink.inverse : Ink.surface,
                        staggered: true
                    )
                }
                Text("\(count) NEW")
                    .typeStyle(Style.kicker)
                    .foregroundStyle(heavy ? Ink.onInverse : Ink.primary)
                    // Tabular mono, so the count never jitters the width.
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .padding(.leading, showsAvatars ? 6 : Space.md + 2)
            .padding(.trailing, Space.md + 2)
            .padding(.vertical, 6)
            .frame(minHeight: Metric.tapTarget)
            .background {
                Capsule()
                    .fill(heavy ? Ink.inverse : Ink.surface)
                    .overlay(
                        Capsule().strokeBorder(heavy ? .clear : Ink.border, lineWidth: 1)
                    )
                    .shadow(
                        color: .black.opacity(heavy ? 0.18 : 0.10),
                        radius: heavy ? 16 : 12,
                        y: heavy ? 6 : 4
                    )
            }
        }
        .buttonStyle(TapStyle())
        .accessibilityLabel(accessibilityLabel)
        // The action now moves the viewport, and the old label did not say so.
        .accessibilityHint("Scrolls to the top and shows them")
        .accessibilityAddTraits(.isButton)
    }

    private var accessibilityLabel: String {
        let names = senders.prefix(2).map(\.displayName).joined(separator: ", ")
        let rest = count - min(2, senders.count)
        return rest > 0
            ? "\(count) new emails, from \(names) and \(rest) more"
            : "\(count) new emails, from \(names)"
    }
}

// MARK: - Degraded patterns
//
// P1 — a passive strip. No icon, no dismiss, no action, because there is
// nothing for the user to do. A freshness stamp is true in every one of these
// states, so one component replaces five error messages.

struct StatusStrip: View {
    let state: String
    let freshness: String

    var body: some View {
        HStack(spacing: Space.xs + 2) {
            Text(state).typeStyle(Style.chip).foregroundStyle(Ink.secondary)
            Text("·").typeStyle(Style.chip).foregroundStyle(Ink.tertiary)
            Text(freshness).typeStyle(Style.chip).foregroundStyle(Ink.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Metric.gutter)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity)
        .background(Ink.surfaceTertiary)
    }
}

/// P2 — one sentence, exactly one affirmative verb, and it never blocks the
/// feed. Never shown during a provider outage: asking someone to reconnect
/// when the provider is down burns trust permanently.
struct ActionBarView: View {
    let message: String
    let verb: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: Space.md) {
            Text(message)
                .typeStyle(Style.bodySmall)
                .foregroundStyle(Ink.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(verb, action: action)
                .typeStyle(Style.bodySmall)
                .foregroundStyle(Ink.primary)
                .buttonStyle(.plain)
        }
        .padding(.horizontal, Metric.gutter)
        .padding(.vertical, Space.lg)
        .frame(maxWidth: .infinity)
        .background(Ink.border)
    }
}

/// P5 — an action receipt. Failures never auto-dismiss under six seconds, and
/// a send whose result is unknown offers no retry: a duplicate send is worse
/// than ambiguity.
struct ToastView: View {
    let message: String
    var detail: String?
    var actionLabel: String?
    var action: (() -> Void)?
    /// Swiping a receipt away is fine — unless it is carrying the only undo
    /// there is, in which case the escape hatch would be spent invisibly.
    var onDismiss: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drag: CGFloat = 0

    private var carriesUndo: Bool { actionLabel != nil && action != nil }

    var body: some View {
        // The message and the action cannot share one row at accessibility
        // sizes — the message gets squeezed to nothing — so the action moves
        // beneath it rather than competing with it.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Space.md) { copy; Spacer(minLength: 0); undoButton }
            VStack(alignment: .leading, spacing: Space.md) {
                copy
                undoButton.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, Space.lg)
        .padding(.vertical, Space.md + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Ink.inverse, in: RoundedRectangle(cornerRadius: Corner.xl, style: .continuous))
        .padding(.horizontal, Metric.gutter)
        .offset(y: drag)
        .gesture(dismissDrag)
    }

    @ViewBuilder private var copy: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(message)
                .typeStyle(Style.bodySmall)
                .foregroundStyle(Ink.onInverse)
                .fixedSize(horizontal: false, vertical: true)
            if let detail {
                Text(detail)
                    .typeStyle(Style.chip)
                    .foregroundStyle(Ink.onInverseSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private var undoButton: some View {
        if let actionLabel, let action {
            Button(actionLabel) {
                // H5 — the user reversed a committed state. Same class of
                // event as the commit itself, so the same cue.
                Haptics.commit()
                action()
            }
            .typeStyle(Style.bodySmall)
            .foregroundStyle(Ink.onInverse)
            .buttonStyle(TapStyle())
            .frame(minHeight: Metric.tapTarget)
        }
    }

    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: Move.Swipe.axisLatch)
            .onChanged { value in
                guard value.translation.height > 0 else { return }
                // While a receipt carries an Undo it rubber-bands back rather
                // than dismissing. The window is short; the escape hatch is
                // not the user's to throw away by accident.
                drag = carriesUndo
                    ? value.translation.height * Move.Swipe.rubberBand
                    : value.translation.height
            }
            .onEnded { value in
                if !carriesUndo, value.translation.height > Move.Swipe.dismissAt {
                    // Exits are decisive; the user has moved on.
                    withAnimation(Move.resolved(Move.exit, reduceMotion)) { onDismiss?() }
                } else {
                    withAnimation(Move.resolved(Move.settle, reduceMotion)) { drag = 0 }
                }
            }
    }
}

#Preview {
    VStack(spacing: Space.xl) {
        NewPostsPill(senders: [Sample.priya, Sample.delta, Sample.marcus], count: 3) {}
        NewPostsPill(senders: [Sample.priya], count: 1) {}
        StatusStrip(state: "OFFLINE", freshness: "LAST SYNCED 14:02")
        ActionBarView(message: "Gmail needs reconnecting. Other mailboxes are fine.", verb: "Reconnect") {}
        ToastView(message: "Sending — result unknown",
                  detail: "WE WILL NOT RESEND UNTIL WE KNOW",
                  actionLabel: "Undo", action: {})
    }
    .padding(.vertical)
}
