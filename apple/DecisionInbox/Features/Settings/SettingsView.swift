import SwiftUI

/// `01 · Settings`.
///
/// Grouped by what the user is deciding, not by which subsystem owns it: which
/// mailboxes there are, what the app does with them, what you keep.
///
/// Every value on the right of a row is computed from something the app
/// actually knows. None of them is a stored preference dressed up as a fact,
/// and no row on this screen leads to a switch that does nothing — five of
/// those shipped here before, two of them privacy settings, and a privacy
/// switch that does nothing is worse than no switch at all.
struct SettingsView: View {
    @Environment(FeedStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var route: Route?
    @State private var notifications: NotificationState = .unknown

    private enum Route: String, Identifiable, Hashable {
        case mailboxes, feed, ai, notifications, senders, privacy, about
        var id: String { rawValue }
    }

    var body: some View {
        SettingsScreen(title: "Settings", showsActivity: true) {
            SettingsGroup("MAILBOXES")
            Rule()
            mailboxes
            ListRow(
                title: store.auth.isConnecting ? "Connecting mailbox…" : "Add a mailbox",
                subtitle: "NO LIMIT",
                action: { Task { await store.add() } },
                trailing: { RowArrow() }
            )
            .disabled(store.auth.isConnecting)
            ConnectionFeedback(auth: store.auth)
            Rule()

            SettingsGroup("THE APP")
            Rule()
            SettingsLink(title: "Feed", value: feedValue) { route = .feed }
            Rule()
            SettingsLink(title: "AI") { route = .ai }
            Rule()
            SettingsLink(title: "Notifications", value: notifications.label) {
                route = .notifications
            }
            Rule()
            SettingsLink(title: "Senders", value: sendersValue) { route = .senders }
            Rule()

            SettingsGroup("YOUR DATA")
            Rule()
            SettingsLink(title: "Privacy and data") { route = .privacy }
            Rule()
            SettingsLink(title: "About", value: Self.version) { route = .about }
            Rule()

            Text("Connected mail is synced and interpreted on our server. Sending, archiving and unsubscribing begin with your action. Privacy and data explains what is stored.")
                .typeStyle(Style.bodySmall)
                .foregroundStyle(Ink.tertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Metric.gutter)
                .padding(.top, Space.xxl)
        }
        .task { notifications = await NotificationState.current() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { notifications = await NotificationState.current() } }
        }
        .navigationDestination(item: $route) { route in
            switch route {
            case .mailboxes: MailboxesView()
            case .feed: SettingsFeedView()
            case .ai: SettingsAIView()
            case .notifications: SettingsNotificationsView()
            case .senders: SettingsSendersView()
            case .privacy: SettingsPrivacyView()
            case .about: AboutView()
            }
        }
    }

    // MARK: Mailboxes
    //
    // Under four they are listed; past that the group collapses to one row with
    // stacked tags and a count, per the scale board. Nothing is hidden at
    // either size — the collapsed row leads to the full list.

    @ViewBuilder
    private var mailboxes: some View {
        if store.mailboxes.count > 3 {
            ListRow(
                title: "\(store.mailboxes.count) mailboxes",
                subtitle: collapsedState,
                action: { route = .mailboxes },
                leading: { MailboxTagStack(mailboxes: store.mailboxes) },
                trailing: { RowArrow() }
            )
            Rule()
        } else {
            ForEach(store.mailboxes) { mailbox in
                ListRow(
                    title: mailbox.address,
                    subtitle: mailbox.stateLabel,
                    action: { route = .mailboxes },
                    leading: { MailboxTag(mailbox.tag, size: Metric.avatarRow) },
                    trailing: { RowArrow() }
                )
                Rule()
            }
        }
    }

    private var collapsedState: String {
        let broken = store.needsReconnect.count
        if broken == 0 { return "ALL CONNECTED" }
        return broken == 1 ? "1 NEEDS RECONNECTING" : "\(broken) NEED RECONNECTING"
    }

    // MARK: Values
    //
    // Derived, never stored. A settings value that is a preference the app
    // never reads is the same lie as a switch that does nothing, just quieter.

    /// How many mailboxes the feed is actually drawing from — which is exactly
    /// what `FeedStore.messages()` filters on.
    private var feedValue: String? {
        let total = store.mailboxes.count
        guard total > 1 else { return nil }
        let showing = store.mailboxes.count(where: \.includeInUnifiedFeed)
        return showing == total ? "ALL MAILBOXES" : "\(showing) OF \(total)"
    }

    /// Attempts recorded for the connected mailboxes, regardless of outcome.
    private var sendersValue: String? {
        let runs = store.unsubscribes.count
        return runs == 0 ? nil : "\(runs) ATTEMPTS"
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        return info?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}

// MARK: - Stacked tags

/// The collapsed mailboxes row. Four tiles overlapping by a third, each ringed
/// in the colour of the ground behind it — without the ring the overlap reads
/// as mud.
struct MailboxTagStack: View {
    let mailboxes: [Mailbox]

    var body: some View {
        HStack(spacing: Metric.avatarStackOverlap) {
            ForEach(mailboxes.prefix(4)) { mailbox in
                MailboxTag(mailbox.tag, size: Metric.avatarCompact)
                    .overlay(
                        RoundedRectangle(cornerRadius: Corner.sm, style: .continuous)
                            .strokeBorder(Ink.surface, lineWidth: 2)
                    )
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - About

/// Version, and the two sentences that say what the product is for. Nothing
/// here is a link to a marketing site the app does not have.
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SettingsScreen(title: "About", onBack: { dismiss() }) {
            SettingsGroup("THIS BUILD")
            Rule()
            SettingsFact(title: "Version", value: Self.version)
            Rule()
            SettingsFact(title: "Build", value: Self.build)
            Rule()

            SettingsGroup("WHAT IT IS")
            SettingsParagraph("Decision Inbox reads your mail as it lands and tells you what each message wants from you, so the deciding happens before you open anything.")
            SettingsParagraph("The quote on a post is verbatim from the email. The line under it is ours. That difference is the whole product, and it is why one is set in sans and the other in mono.")
        }
    }

    private static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}

// MARK: - Mailbox state

extension Mailbox {
    /// The row sub-label. A stamp, so upper-case mono is right here — and the
    /// time is the last successful sync, not the age of the newest email.
    var stateLabel: String {
        switch status {
        case .active(let synced):
            return "SYNCED \(synced.formatted(.dateTime.hour().minute()))"
        case .needsReconnect:
            return "NEEDS RECONNECTING"
        case .paused:
            return "PAUSED"
        }
    }
}

#Preview {
    NavigationStack { SettingsView() }
        .environment(FeedStore(sample: true))
}
