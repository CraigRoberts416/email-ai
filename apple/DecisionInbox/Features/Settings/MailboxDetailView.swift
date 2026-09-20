import SwiftUI

/// Facts and preferences precede connection recovery and disconnect.
/// The confirmation explains exactly which access and data are removed.
struct MailboxDetailView: View {
    let mailbox: Mailbox

    @Environment(FeedStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var tag: String
    @State private var disconnecting = false
    @State private var disconnectError: String?
    @State private var tagFeedback: String?
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
                    title: store.auth.isConnecting ? "Reconnecting…" : "Reconnect this mailbox",
                    sentence: "Choose this address in Google to restore its connection. Your other mailboxes keep working.",
                    action: { Task { await store.reconnect(mailbox.id) } }
                )
                .disabled(store.auth.isConnecting || disconnecting)
                Rule()
            }
            ConsequenceRow(
                title: disconnecting ? "Disconnecting…" : "Disconnect this mailbox",
                sentence: "Stop syncing this mailbox on our server and remove its credentials and local data. Your Gmail messages remain. Stored mail records on our server are retained. This does not revoke Google's account grant.",
                confirmTitle: "Disconnect mailbox",
                destructive: true,
                action: {
                    disconnecting = true
                    disconnectError = nil
                    Task {
                        defer { disconnecting = false }
                        do { try await store.remove(mailbox.id); dismiss() }
                        catch { disconnectError = "Disconnect was not confirmed. Your local account is still here so you can retry. Server access may already have stopped." }
                    }
                }
            )
            .disabled(disconnecting || store.auth.isConnecting)
            if disconnecting { SettingsParagraph("Stopping access and finishing work already in progress. You can leave this screen; this does not cancel the request.") }
            if let disconnectError { SettingsParagraph(disconnectError) }
            ConnectionFeedback(auth: store.auth)
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
        AuthService.normalizedTag(tag)
    }

    private var collision: Mailbox? {
        guard normalised.count >= 2 else { return nil }
        return store.mailboxes.first { $0.id != mailbox.id && $0.tag == normalised }
    }

    private var suggestions: [String] {
        guard collision != nil else { return [] }
        let taken = Set(store.mailboxes.filter { $0.id != mailbox.id }.map(\.tag))
        return AccountConnectionPolicy.tagSuggestions(normalised, address: live.address, taken: taken)
    }

    private func commitTag() {
        guard normalised.count >= 2 else { tagFeedback = "Use two to four letters or numbers. Your previous tag is unchanged."; return }
        guard collision == nil else { tagFeedback = "Choose a tag another mailbox is not using."; return }
        guard normalised != live.tag else { return }
        store.rename(mailbox.id, tag: normalised)
        tagFeedback = "Tag saved."
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
                    .accessibilityLabel("Mailbox tag, two to four letters or numbers")
                    .onChange(of: tag) { _, new in
                        tagFeedback = nil
                        let clean = AuthService.normalizedTag(new)
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
            Text(tagFeedback ?? "Use two to four letters or numbers. Changes save when you finish editing.")
                .typeStyle(Style.bodySmall)
                .foregroundStyle(Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)

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
                        Button { tag = suggestion; commitTag() } label: {
                            Text(suggestion)
                                .typeStyle(Style.tagChip)
                                .foregroundStyle(Ink.primary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, Space.sm)
                                .frame(minHeight: 44)
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
