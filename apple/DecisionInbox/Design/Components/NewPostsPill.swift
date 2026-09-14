import SwiftUI

/// The X/Twitter new-posts capsule.
///
/// Its real job is not engagement — it is a stability guarantee. The list never
/// reorders under your thumb, and arrival becomes a deferred, user-controlled
/// event. A finite inbox needs that more than Twitter does, because the worst
/// failure of "you're caught up" is mail landing mid-triage and pushing the
/// end invisibly further away.
///
/// Deliberately silent: no haptic, no badge, no sound. The user did not cause
/// this, and the frequency is unbounded.
struct NewPostsPill: View {
    let senders: [Sender]
    let count: Int
    let action: () -> Void

    /// The pill gets physically heavier as the batch grows, so weight carries
    /// urgency in a system with no colour to spend.
    private var heavy: Bool { count >= 3 }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.sm) {
                AvatarStack(
                    senders: senders,
                    size: Metric.avatarPill,
                    ringColor: heavy ? Ink.inverse : Ink.surface
                )
                Text("\(count) NEW")
                    .typeStyle(Style.kicker)
                    .foregroundStyle(heavy ? Ink.onInverse : Ink.primary)
                    // Tabular mono, so the count never jitters the width.
                    .monospacedDigit()
            }
            .padding(.leading, 6)
            .padding(.trailing, Space.md + 2)
            .padding(.vertical, 6)
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
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
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

    var body: some View {
        HStack(spacing: Space.md) {
            VStack(alignment: .leading, spacing: 3) {
                Text(message)
                    .typeStyle(Style.bodySmall)
                    .foregroundStyle(Ink.onInverse)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail)
                        .typeStyle(Style.chip)
                        .foregroundStyle(Ink.onInverseSecondary)
                }
            }
            Spacer(minLength: 0)
            if let actionLabel, let action {
                Button(actionLabel, action: action)
                    .typeStyle(Style.bodySmall)
                    .foregroundStyle(Ink.onInverse)
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Space.lg)
        .padding(.vertical, Space.md + 2)
        .background(Ink.inverse, in: RoundedRectangle(cornerRadius: Corner.xl, style: .continuous))
        .padding(.horizontal, Metric.gutter)
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
