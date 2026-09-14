import SwiftUI

/// Mailboxes.
///
/// No cap, and no primary. Every address is peer to every other — the moment
/// one is "the main one" a second address becomes a second-class citizen and
/// people go back to the stock client for it.
///
/// Scale changes the shape, not the rules: under five, rows carry the address
/// and its state; past that the list gains a search field, and past a dozen it
/// groups by provider. Nothing is hidden at any size.
struct MailboxesView: View {
    @Environment(FeedStore.self) private var store
    @State private var query = ""
    @State private var editing: Mailbox?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                header

                if store.mailboxes.count >= 5 {
                    SearchField(text: $query)
                    Rule()
                }

                ForEach(filtered) { mailbox in
                    MailboxRow(mailbox: mailbox, showsAddress: store.mailboxes.count < 12) {
                        editing = mailbox
                    }
                    Rule()
                }

                if filtered.isEmpty && !query.isEmpty {
                    Text("NO MAILBOX MATCHES \u{201C}\(query.uppercased())\u{201D}")
                        .typeStyle(Style.chip)
                        .foregroundStyle(Ink.secondary)
                        .padding(.horizontal, Metric.gutter)
                        .padding(.vertical, Space.xl)
                }

                Button { Task { await store.add() } } label: {
                    HStack(spacing: Space.md) {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .medium))
                            .frame(width: Metric.avatar, height: Metric.avatar)
                            .overlay(
                                RoundedRectangle(cornerRadius: Corner.md, style: .continuous)
                                    .strokeBorder(Ink.primary, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            )
                        Text("Add a mailbox")
                            .typeStyle(Style.body)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(Ink.primary)
                    .padding(.horizontal, Metric.gutter)
                    .padding(.vertical, Space.lg)
                }
                .buttonStyle(.plain)
                .disabled(store.auth.isConnecting)

                Text("EACH MAILBOX KEEPS ITS OWN CONNECTION. REMOVING ONE LEAVES THE REST UNTOUCHED.")
                    .typeStyle(Style.chip)
                    .foregroundStyle(Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Metric.gutter)
                    .padding(.top, Space.md)
            }
        }
        .scrollIndicators(.hidden)
        .background(Ink.surface)
        .navigationTitle("Mailboxes")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { mailbox in
            MailboxDetailView(mailbox: mailbox)
        }
    }

    private var filtered: [Mailbox] {
        guard !query.isEmpty else { return store.mailboxes }
        return store.mailboxes.filter {
            $0.address.localizedCaseInsensitiveContains(query)
                || $0.tag.localizedCaseInsensitiveContains(query)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(store.mailboxes.count == 1
                 ? "One mailbox."
                 : "\(store.mailboxes.count) mailboxes, one feed.")
                .typeStyle(Style.display)
                .foregroundStyle(Ink.primary)
            if store.mailboxes.count > 1 {
                Text("Posts carry a tag so you can tell them apart without opening anything.")
                    .typeStyle(Style.body)
                    .foregroundStyle(Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, Metric.gutter)
        .padding(.top, Space.lg)
        .padding(.bottom, Space.xl)
    }
}

// MARK: - Row

private struct MailboxRow: View {
    let mailbox: Mailbox
    let showsAddress: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.md) {
                MailboxTag(mailbox.tag, size: Metric.avatar)

                VStack(alignment: .leading, spacing: 3) {
                    if showsAddress {
                        Text(mailbox.address)
                            .typeStyle(Style.body)
                            .foregroundStyle(Ink.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else {
                        Text(mailbox.tag)
                            .typeStyle(Style.sender)
                            .foregroundStyle(Ink.primary)
                    }
                    Text(state)
                        .typeStyle(Style.chip)
                        .foregroundStyle(Ink.secondary)
                }

                Spacer(minLength: 0)

                if !mailbox.includeInUnifiedFeed {
                    Text("NOT IN FEED")
                        .typeStyle(Style.chip)
                        .foregroundStyle(Ink.secondary)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 13))
                    .foregroundStyle(Ink.tertiary)
            }
            .padding(.horizontal, Metric.gutter)
            .padding(.vertical, Space.md + 2)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private var state: String {
        switch mailbox.status {
        case .active(let synced): return "SYNCED \(synced.formatted(.dateTime.hour().minute()))"
        case .needsReconnect(let reason): return reason.uppercased()
        case .paused: return "PAUSED"
        }
    }
}

/// The tag tile. A rounded rect, never a circle — a circle is a person, and a
/// mailbox is a place.
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
            .frame(width: size, height: size)
            .background(Ink.surfaceTertiary, in: RoundedRectangle(cornerRadius: Corner.sm, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Corner.sm, style: .continuous)
                    .strokeBorder(Ink.border, lineWidth: 1)
            )
    }
}

// MARK: - Search

struct SearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: Space.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(Ink.secondary)
            TextField("Filter", text: $text)
                .typeStyle(Style.body)
                .foregroundStyle(Ink.primary)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Ink.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Metric.gutter)
        .padding(.vertical, Space.md)
    }
}
