import SwiftUI

/// Mailboxes.
///
/// No cap, and no primary. Every address is peer to every other — the moment
/// one is "the main one" a second address becomes a second-class citizen and
/// people go back to the stock client for it.
///
/// Scale changes the shape, not the rules. Up to six it is a flat list; past
/// that it groups by status and gains a search field, and the mailboxes that
/// need something float to the top. Nothing is hidden at any size.
struct MailboxesView: View {
    @Environment(FeedStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var selected: Mailbox?

    /// Past six, status grouping and search. The threshold is the scale
    /// board's, not a guess.
    private var isLarge: Bool { store.mailboxes.count > 6 }

    var body: some View {
        SettingsScreen(title: "Mailboxes", onBack: { dismiss() }) {
            if isLarge {
                SearchField(text: $query, placeholder: "Filter")
                    .padding(.horizontal, Metric.gutter)
                    .padding(.top, Space.xs)
                    .padding(.bottom, Space.md)
            }

            if isLarge {
                group("NEEDS YOU", mailboxes: filtered.filter { !$0.isHealthy })
                group("ACTIVE", mailboxes: filtered.filter(\.isHealthy).filter { !$0.isPaused })
                group("PAUSED", mailboxes: filtered.filter(\.isPaused))
            } else {
                SettingsGroup("CONNECTED")
                Rule()
                rows(filtered)
            }

            if filtered.isEmpty, !query.isEmpty {
                Text("No mailbox matches \u{201C}\(query)\u{201D}.")
                    .typeStyle(Style.bodySmall)
                    .foregroundStyle(Ink.tertiary)
                    .padding(.horizontal, Metric.gutter)
                    .padding(.vertical, Space.xl)
                Rule()
            }

            SettingsGroup("ADD")
            Rule()
            ListRow(
                title: store.auth.isConnecting ? "Connecting mailbox…" : "Add a mailbox",
                subtitle: "NO LIMIT",
                action: { Task { await store.add() } },
                trailing: { RowArrow() }
            )
            .disabled(store.auth.isConnecting)
            ConnectionFeedback(auth: store.auth)
            Rule()

            VStack(alignment: .leading, spacing: Space.sm) {
                Text(store.mailboxes.count == 1
                     ? "One mailbox, one feed."
                     : "\(store.mailboxes.count) mailboxes, one feed.")
                    .typeStyle(Style.bodyMedium)
                    .foregroundStyle(Ink.primary)
                Text("Each mailbox gets a short tag, and it sits on every post so you can tell streams apart without spending the one colour this product has. Each keeps its own connection \u{2014} removing one leaves the rest untouched.")
                    .typeStyle(Style.bodySmall)
                    .foregroundStyle(Ink.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Metric.gutter)
            .padding(.top, Space.lg)
        }
        .navigationDestination(item: $selected) { mailbox in
            MailboxDetailView(mailbox: mailbox)
        }
    }

    // MARK: Rows

    @ViewBuilder
    private func group(_ title: String, mailboxes: [Mailbox]) -> some View {
        if !mailboxes.isEmpty {
            SettingsGroup("\(title) \u{00B7} \(mailboxes.count)")
            Rule()
            rows(mailboxes)
        }
    }

    @ViewBuilder
    private func rows(_ mailboxes: [Mailbox]) -> some View {
        ForEach(mailboxes) { mailbox in
            ListRow(
                title: mailbox.address,
                subtitle: "\(mailbox.provider.uppercased()) \u{00B7} \(mailbox.stateLabel)",
                // A paused mailbox is the one place a row greys out: it is
                // still connected, so "off" has to be visible without being a
                // failure.
                muted: mailbox.isPaused,
                action: { selected = mailbox },
                leading: {
                    MailboxTag(mailbox.tag, size: Metric.avatarRow)
                        .opacity(mailbox.isPaused ? 0.4 : 1)
                },
                trailing: { RowArrow() }
            )
            Rule()
        }
    }

    private var filtered: [Mailbox] {
        guard !query.isEmpty else { return store.mailboxes }
        return store.mailboxes.filter {
            $0.address.localizedCaseInsensitiveContains(query)
                || $0.tag.localizedCaseInsensitiveContains(query)
        }
    }
}

// MARK: - Tag tile

/// The mailbox mark. A rounded rect, never a circle — a circle is a person,
/// and a mailbox is a place. Two to four characters is all the identity a
/// monochrome product can spend on an address.
struct MailboxTag: View {
    let tag: String
    let size: CGFloat

    init(_ tag: String, size: CGFloat = Metric.avatarRow) {
        self.tag = tag
        self.size = size
    }

    var body: some View {
        Text(tag)
            .typeStyle(Style.chip)
            .foregroundStyle(Ink.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 2)
            .frame(width: size, height: size)
            .background(
                Ink.surfaceTertiary,
                in: RoundedRectangle(cornerRadius: Corner.sm, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Corner.sm, style: .continuous)
                    .strokeBorder(Ink.border, lineWidth: 1)
            )
            .accessibilityHidden(true)
    }
}

extension Mailbox {
    var isPaused: Bool {
        if case .paused = status { return true }
        return false
    }
}

#Preview {
    NavigationStack { MailboxesView() }
        .environment(FeedStore(sample: true))
}
