import SwiftUI

/// One mailbox.
///
/// Facts first, then the one behaviour that is really a behaviour, then the
/// irreversible thing last. The order is deliberate, and so is the treatment
/// of the last one: no red, a weight step on the title, a second tap to
/// commit, and the sentence about what actually happens set in sentence case
/// where it can be read.
///
/// That sentence — "Nothing is deleted. Your mail stays where it is" — is the
/// highest-stakes fact in the product. It used to be 10pt upper-case mono,
/// which is this system's mark for a machine label or a count, not for a human
/// reassurance about an irreversible choice.
struct MailboxDetailView: View {
    let mailbox: Mailbox

    @Environment(FeedStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var tag: String
    @FocusState private var editingTag: Bool

    init(mailbox: Mailbox) {
        self.mailbox = mailbox
        _tag = State(initialValue: mailbox.tag)
    }

    private var live: Mailbox { store.mailbox(mailbox.id) ?? mailbox }

    var body: some View {
        SettingsScreen(title: live.address, onBack: { dismiss() }) {
            SettingsGroup("MAILBOX")
            Rule()
            SettingsFact(title: "Provider", value: live.provider.uppercased())
            Rule()
            // One row, because "Last synced" over "NEEDS RECONNECTING" is a
            // label that does not describe its own value.
            SettingsFact(title: "Status", value: live.stateLabel)
            Rule()
            tagEditor
            Rule()

            SettingsGroup("BEHAVIOUR")
            Rule()
            SettingsToggle(
                title: "Include in this feed",
                subtitle: "OFF HIDES ITS MAIL",
                isOn: Binding(
                    get: { live.includeInUnifiedFeed },
                    set: { store.setIncluded(mailbox.id, $0) }
                )
            )
            Rule()
            SettingsParagraph("Notifications are decided per message on the server, not per mailbox on this phone, so there is no switch here for them. What arrives is on the Notifications screen.")

            SettingsGroup("TROUBLE")
            Rule()
            if case .needsReconnect = live.status {
                ConsequenceRow(
                    title: "Reconnect this mailbox",
                    sentence: "The connection to this mailbox expired. Reconnecting takes one tap, and your other mailboxes keep working through it.",
                    action: { Task { await store.reconnect(mailbox.id) } }
                )
                Rule()
            }
            ConsequenceRow(
                title: "Disconnect this mailbox",
                sentence: "Nothing is deleted. Your mail stays where it is \u{2014} this only ends our access to it.",
                confirmTitle: "Tap again to disconnect",
                destructive: true,
                action: {
                    store.remove(mailbox.id)
                    dismiss()
                }
            )
            Rule()
        }
        .onChange(of: editingTag) { _, focused in
            if !focused { commitTag() }
        }
        .onDisappear { commitTag() }
    }

    // MARK: Tag
    //
    // Two to four characters, and editable because the generated tag is a
    // guess — the user is the one who knows which of their addresses is HOME.
    // A collision is refused rather than resolved with an appended counter:
    // two mailboxes sharing a tag makes the feed unreadable, which is the one
    // thing the tag exists to prevent.

    private var normalised: String {
        String(tag.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(4))
    }

    private var collision: Mailbox? {
        guard normalised.count >= 2 else { return nil }
        return store.mailboxes.first { $0.id != mailbox.id && $0.tag == normalised }
    }

    private var suggestions: [String] {
        guard collision != nil else { return [] }
        // Drawn from the address itself rather than invented: a tag the user
        // cannot trace back to the mailbox is no better than a counter.
        let parts = live.address.split(separator: "@", maxSplits: 1)
        let local = (parts.first.map(String.init) ?? "").uppercased()
            .filter { $0.isLetter || $0.isNumber }
        let domain = (parts.count > 1 ? String(parts[1]) : "").uppercased()
            .filter { $0.isLetter || $0.isNumber }
        let taken = Set(store.mailboxes.filter { $0.id != mailbox.id }.map(\.tag))
        let candidates = [
            normalised + "2",
            String(local.prefix(4)),
            String(domain.prefix(4)),
        ]
        var seen: Set<String> = []
        return candidates.filter { candidate in
            guard candidate.count >= 2, !taken.contains(candidate),
                  candidate != normalised, seen.insert(candidate).inserted
            else { return false }
            return true
        }
    }

    private func commitTag() {
        guard normalised.count >= 2, collision == nil, normalised != live.tag else { return }
        store.rename(mailbox.id, tag: normalised)
    }

    private var tagEditor: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text("Tag")
                    .typeStyle(Style.bodyMedium)
                    .foregroundStyle(Ink.primary)
                Text("SHOWN ON EVERY POST FROM THIS MAILBOX")
                    .typeStyle(Style.monoMicro)
                    .foregroundStyle(Ink.tertiary)
            }

            HStack(spacing: Space.md) {
                TextField("", text: $tag)
                    .typeStyle(Style.tagInput)
                    .foregroundStyle(Ink.primary)
                    .tint(Ink.primary)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .focused($editingTag)
                    .accessibilityLabel("Mailbox tag, two to four letters")
                    .onChange(of: tag) { _, new in
                        let clean = String(new.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(4))
                        if clean != new { tag = clean }
                    }
                    .onSubmit { commitTag() }
                Text("\(normalised.count) / 4")
                    .typeStyle(Style.monoCaption)
                    .foregroundStyle(Ink.tertiary)
            }
            .padding(.horizontal, Metric.gutter)
            .padding(.vertical, 14)
            .overlay(
                RoundedRectangle(cornerRadius: Corner.md, style: .continuous)
                    // The error is carried by a heavier black border and the
                    // explanation below it. There is no red in this product,
                    // and inventing one for a two-letter clash would make it
                    // the loudest thing on the screen.
                    .strokeBorder(Ink.primary, lineWidth: collision == nil ? 1 : 2)
                    .opacity(collision == nil ? 0.15 : 1)
            )

            if let collision {
                VStack(alignment: .leading, spacing: Space.xs + 2) {
                    Text("ALREADY TAKEN")
                        .typeStyle(Style.chip)
                        .foregroundStyle(Ink.primary)
                    Text("\(collision.address) is using \(normalised). Two mailboxes with the same tag makes the feed unreadable, which is the one thing the tag exists to prevent.")
                        .typeStyle(Style.bodyMedium)
                        .foregroundStyle(Ink.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.leading, Space.md)
                .overlay(alignment: .leading) {
                    Rectangle().fill(Ink.primary).frame(width: 2)
                }

                HStack(spacing: Space.sm) {
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button { tag = suggestion } label: {
                            Text(suggestion)
                                .typeStyle(Style.tagChip)
                                .foregroundStyle(Ink.primary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, Space.sm)
                                .overlay(Capsule().strokeBorder(Ink.primary, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, Metric.gutter)
        .padding(.vertical, Space.lg)
    }
}

#Preview {
    NavigationStack {
        MailboxDetailView(mailbox: Sample.mailboxes[0])
    }
    .environment(FeedStore(sample: true))
}
