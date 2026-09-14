import SwiftUI

/// One mailbox.
///
/// Three switches and a disconnect, and the order is deliberate: the two
/// reversible choices come first, the irreversible one is last and has to be
/// confirmed by typing nothing — just a second tap that says what it removes.
struct MailboxDetailView: View {
    let mailbox: Mailbox

    @Environment(FeedStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var tag: String
    @State private var confirmingRemoval = false

    init(mailbox: Mailbox) {
        self.mailbox = mailbox
        _tag = State(initialValue: mailbox.tag)
    }

    private var live: Mailbox { store.mailbox(mailbox.id) ?? mailbox }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: Space.sm) {
                        Text(mailbox.address)
                            .typeStyle(Style.display)
                            .foregroundStyle(Ink.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(status.uppercased())
                            .typeStyle(Style.chip)
                            .foregroundStyle(Ink.secondary)
                    }
                    .padding(.horizontal, Metric.gutter)
                    .padding(.top, Space.lg)
                    .padding(.bottom, Space.xl)

                    Rule()

                    tagEditor
                    Rule()

                    SettingsToggle(
                        title: "Show in the feed",
                        detail: "Off keeps the mailbox connected but leaves its mail out of here.",
                        isOn: Binding(
                            get: { live.includeInUnifiedFeed },
                            set: { store.setIncluded(mailbox.id, $0) }
                        )
                    )
                    Rule()

                    SettingsToggle(
                        title: "Notify me",
                        detail: "Only for mail this mailbox receives that actually needs you.",
                        isOn: Binding(
                            get: { live.notificationsEnabled },
                            set: { store.setNotifications(mailbox.id, $0) }
                        )
                    )
                    Rule()

                    if case .needsReconnect = live.status {
                        SettingsRow(title: "Reconnect", detail: "Google needs you to say yes again.") {
                            Task { await store.reconnect(mailbox.id) }
                        }
                        Rule()
                    }

                    removal
                }
            }
            .scrollIndicators(.hidden)
            .background(Ink.surface)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.foregroundStyle(Ink.primary)
                }
            }
        }
    }

    private var status: String {
        switch live.status {
        case .active(let synced): return "Synced \(synced.formatted(.dateTime.hour().minute()))"
        case .needsReconnect(let reason): return reason
        case .paused: return "Paused"
        }
    }

    /// Two to four characters. Editing is allowed because the auto-generated
    /// tag is a guess, and the user knows which of their addresses is "HOME".
    private var tagEditor: some View {
        HStack(spacing: Space.md) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Tag")
                    .typeStyle(Style.body)
                    .foregroundStyle(Ink.primary)
                Text("SHOWN ON POSTS FROM THIS MAILBOX")
                    .typeStyle(Style.chip)
                    .foregroundStyle(Ink.secondary)
            }
            Spacer(minLength: 0)
            TextField("", text: $tag)
                .typeStyle(Style.chip)
                .foregroundStyle(Ink.primary)
                .multilineTextAlignment(.center)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .frame(width: Metric.avatar, height: Metric.avatar)
                .background(Ink.surfaceTertiary, in: RoundedRectangle(cornerRadius: Corner.sm, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Corner.sm, style: .continuous)
                        .strokeBorder(Ink.border, lineWidth: 1)
                )
                .onChange(of: tag) { _, new in
                    if new.count > 4 { tag = String(new.prefix(4)) }
                }
                .onSubmit { store.rename(mailbox.id, tag: tag) }
        }
        .padding(.horizontal, Metric.gutter)
        .padding(.vertical, Space.md)
    }

    /// Disconnecting is the one destructive thing here, so it says exactly what
    /// goes and what stays. No mail is deleted — this only drops our access.
    private var removal: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Button {
                if confirmingRemoval {
                    store.remove(mailbox.id)
                    dismiss()
                } else {
                    withAnimation(Move.crisp) { confirmingRemoval = true }
                }
            } label: {
                Text(confirmingRemoval ? "Tap again to disconnect" : "Disconnect this mailbox")
                    .typeStyle(Style.body)
                    .foregroundStyle(confirmingRemoval ? Ink.onInverse : Ink.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Metric.gutter)
                    .padding(.vertical, Space.lg)
                    .background(confirmingRemoval ? Ink.inverse : Ink.surface)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)

            Text("NOTHING IS DELETED. YOUR MAIL STAYS WHERE IT IS \u{2014} THIS ONLY ENDS OUR ACCESS TO IT.")
                .typeStyle(Style.chip)
                .foregroundStyle(Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Metric.gutter)
        }
        .padding(.top, Space.xl)
        .padding(.bottom, Space.xxl)
    }
}

// MARK: - Settings primitives

struct SettingsToggle: View {
    let title: String
    var detail: String?
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: Space.md) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .typeStyle(Style.body)
                    .foregroundStyle(Ink.primary)
                if let detail {
                    Text(detail)
                        .typeStyle(Style.bodySmall)
                        .foregroundStyle(Ink.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Space.md)
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(Ink.primary)
        }
        .padding(.horizontal, Metric.gutter)
        .padding(.vertical, Space.md + 2)
        .accessibilityElement(children: .combine)
    }
}

struct SettingsRow: View {
    let title: String
    var detail: String?
    var value: String?
    var action: (() -> Void)?

    var body: some View {
        Button {
            action?()
        } label: {
            HStack(spacing: Space.md) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .typeStyle(Style.body)
                        .foregroundStyle(Ink.primary)
                    if let detail {
                        Text(detail)
                            .typeStyle(Style.bodySmall)
                            .foregroundStyle(Ink.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: Space.md)
                if let value {
                    Text(value)
                        .typeStyle(Style.meta)
                        .foregroundStyle(Ink.secondary)
                }
                if action != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13))
                        .foregroundStyle(Ink.tertiary)
                }
            }
            .padding(.horizontal, Metric.gutter)
            .padding(.vertical, Space.md + 2)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
    }
}
