import SwiftUI

/// Settings.
///
/// Grouped by what the user is deciding, not by which subsystem owns it:
/// what reaches me, what the AI is allowed to do, what you keep. "What we
/// store" is a screen rather than a paragraph in a policy, because a product
/// that reads your mail has to be able to answer that question plainly.
struct SettingsView: View {
    @Environment(FeedStore.self) private var store
    @AppStorage("feed.groupPromotions") private var groupPromotions = true
    @AppStorage("feed.showTags") private var showTags = true
    @AppStorage("ai.interpretOnArrival") private var interpretOnArrival = true
    @AppStorage("ai.blockRemoteImages") private var blockRemoteImages = true
    @AppStorage("notify.onlyNeedsYou") private var onlyNeedsYou = true

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                Section("MAILBOXES") {
                    NavigationLink {
                        MailboxesView()
                    } label: {
                        SettingsRowLabel(
                            title: store.mailboxes.count == 1
                                ? store.mailboxes.first?.address ?? "Mailboxes"
                                : "\(store.mailboxes.count) mailboxes",
                            detail: detail
                        )
                    }
                    .buttonStyle(.plain)
                }

                Section("THE FEED") {
                    SettingsToggle(
                        title: "Group promotions",
                        detail: "Broadcast mail collapses to one line each.",
                        isOn: $groupPromotions
                    )
                    Rule()
                    SettingsToggle(
                        title: "Show mailbox tags",
                        detail: "Only appears when you have more than one mailbox.",
                        isOn: $showTags
                    )
                }

                Section("THE AI") {
                    SettingsToggle(
                        title: "Read mail as it arrives",
                        detail: "Off means nothing is interpreted until you open the app.",
                        isOn: $interpretOnArrival
                    )
                    Rule()
                    SettingsToggle(
                        title: "Block remote images",
                        detail: "Images in email are read receipts. This stops them firing.",
                        isOn: $blockRemoteImages
                    )
                    Rule()
                    NavigationLink { StorageView() } label: {
                        SettingsRowLabel(
                            title: "What we store",
                            detail: "Exactly what leaves your phone, and for how long."
                        )
                    }
                    .buttonStyle(.plain)
                }

                Section("NOTIFICATIONS") {
                    SettingsToggle(
                        title: "Only what needs you",
                        detail: "Receipts, promotions and newsletters stay silent.",
                        isOn: $onlyNeedsYou
                    )
                }

                Section("ABOUT") {
                    SettingsRow(title: "Version", value: Self.version)
                }

                Text("DECISION INBOX READS YOUR MAIL SO YOU DO NOT HAVE TO. IT NEVER SENDS ANYTHING WITHOUT YOU.")
                    .typeStyle(Style.chip)
                    .foregroundStyle(Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Metric.gutter)
                    .padding(.top, Space.xxl)
                    .padding(.bottom, Space.xxxl)
            }
        }
        .scrollIndicators(.hidden)
        .background(Ink.surface)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var detail: String {
        let broken = store.needsReconnect.count
        if broken > 0 { return "\(broken) needs reconnecting" }
        return store.mailboxes.count == 1 ? "Connected" : "All connected"
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }
}

// MARK: - Section
//
// A mono label above a hairline-bounded block. Deliberately not `List`: the
// feed has no inset rounded rows and settings should not teach a second
// vocabulary for the same product.

private struct Section<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .typeStyle(Style.kicker)
                .foregroundStyle(Ink.secondary)
                .padding(.horizontal, Metric.gutter)
                .padding(.top, Space.xl)
                .padding(.bottom, Space.sm)
            Rule()
            content
            Rule()
        }
    }
}

private struct SettingsRowLabel: View {
    let title: String
    var detail: String?

    var body: some View {
        HStack(spacing: Space.md) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .typeStyle(Style.body)
                    .foregroundStyle(Ink.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let detail {
                    Text(detail)
                        .typeStyle(Style.bodySmall)
                        .foregroundStyle(Ink.secondary)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 13))
                .foregroundStyle(Ink.tertiary)
        }
        .padding(.horizontal, Metric.gutter)
        .padding(.vertical, Space.md + 2)
        .contentShape(.rect)
    }
}

// MARK: - What we store

/// Written as answers, not as policy. Each line is a thing a reasonable person
/// would want to know before handing over a mailbox.
struct StorageView: View {
    private let facts: [(String, String)] = [
        ("Your mail", "Subject, sender and a short snippet are stored so the feed can exist offline. Full bodies are fetched when you open one and are not kept."),
        ("What the AI reads", "The cleaned text of an email, once, to write the quote and the summary. It is not used to train anything."),
        ("Your tokens", "Held in the iOS Keychain on this device and on the sync server, so mail can be read while the app is closed. Disconnecting a mailbox deletes them."),
        ("Unsubscribing", "The agent visits the sender's own page and fills in their form using the address that received the mail. Nothing else is shared."),
        ("What we never do", "Send, delete, or reply to anything on your behalf. Every send in this app is one you pressed."),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(facts.enumerated()), id: \.offset) { _, fact in
                    VStack(alignment: .leading, spacing: Space.sm) {
                        Text(fact.0.uppercased())
                            .typeStyle(Style.kicker)
                            .foregroundStyle(Ink.secondary)
                        Text(fact.1)
                            .typeStyle(Style.body)
                            .foregroundStyle(Ink.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Metric.gutter)
                    .padding(.vertical, Space.xl)
                    Rule()
                }
            }
        }
        .scrollIndicators(.hidden)
        .background(Ink.surface)
        .navigationTitle("What we store")
        .navigationBarTitleDisplayMode(.inline)
    }
}
