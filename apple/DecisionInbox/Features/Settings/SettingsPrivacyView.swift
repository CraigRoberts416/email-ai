import SwiftUI

/// `04 · Settings · Privacy`.
///
/// Two controls, and both of them do the thing their label says. Retention and
/// usage analytics were drawn here too; neither is reachable from this phone —
/// there is no analytics pipeline to switch off and no retention endpoint to
/// call — so neither is offered. A privacy switch that writes a preference
/// nothing reads is worse than no switch at all: it buys the trust without
/// doing the work.
struct SettingsPrivacyView: View {
    @Environment(FeedStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    /// Off, and off is the honest default.
    ///
    /// A rich link card is drawn from the destination's own page, which means
    /// this phone has to ask for it — and asking tells that site somebody
    /// opened the mail. Everywhere else the server fetches so a sender learns
    /// nothing. This is the one place the reader can hand that back, so it is
    /// theirs to switch on knowingly rather than ours to switch on quietly.
    @AppStorage("links.richPreviews") private var richPreviews = false

    @State private var contactPhotos = ContactPhotoStore.shared
    @State private var identities = SenderIdentityStore.shared
    @State private var contactPermissionDenied = false
    @State private var showingStorage = false
    @State private var exporting: ExportFile?

    var body: some View {
        SettingsScreen(title: "Privacy and data", onBack: { dismiss() }) {
            SettingsGroup("WHAT WE HOLD")
            Rule()
            SettingsLink(
                title: "What we store",
                subtitle: "WHAT LEAVES YOUR PHONE, AND WHAT STAYS",
                action: { showingStorage = true }
            )
            Rule()

            SettingsGroup("PERSONAL PHOTOS")
            Rule()
            SettingsToggle(
                title: "Google contact photos",
                subtitle: "SAVED CONTACTS AND OTHER CONTACTS · READ ONLY",
                isOn: Binding(get: { identities.googlePhotosEnabled }, set: { enabled in
                    identities.setGooglePhotosEnabled(enabled)
                    if enabled { Task { await identities.refreshGooglePhotos(force: true) } }
                })
            )
            SettingsParagraph("Match photos by exact email address using Google People. Only email addresses and photos are read on this phone; your address book is never sent to our server. Google may not provide every photo shown in Gmail.")
            if identities.googlePhotosEnabled && !store.isSample {
                ForEach(store.auth.accounts) { account in
                    if !identities.hasAllGooglePhotoAccess(for: account.id) {
                        SettingsLink(title: "Connect photos for \(account.id)", subtitle: "ALLOW READ-ONLY CONTACT ACCESS IN GOOGLE", action: {
                            Task {
                                await store.reconnect(account.id)
                                await identities.refreshGooglePhotos(force: true)
                            }
                        })
                    }
                    if let failure = identities.photoFailures[account.id] {
                        SettingsParagraph(failure)
                        SettingsLink(title: "Try contact photos again", action: {
                            Task { await identities.refreshGooglePhotos(force: true) }
                        })
                    }
                }
            }
            Rule()
            SettingsToggle(
                title: "Photos from this phone",
                subtitle: "MATCH PEOPLE BY THEIR EMAIL ADDRESS",
                isOn: Binding(get: { contactPhotos.enabled && contactPhotos.permitted }, set: { enabled in
                    Task {
                        let allowed = await contactPhotos.setEnabled(enabled)
                        contactPermissionDenied = enabled && !allowed
                    }
                })
            )
            SettingsParagraph("Use photos from the contacts you allow. Your address book stays on this phone. People without a photo keep their initials or existing avatar.")
            if contactPermissionDenied {
                SettingsLink(title: "Allow contacts in iOS Settings", action: {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                })
            }
            Rule()

            SettingsGroup("CONTROLS")
            Rule()
            SettingsToggle(
                title: "Rich link previews",
                subtitle: "OFF: A LINK SHOWS ITS ADDRESS AND NOTHING IS FETCHED",
                isOn: $richPreviews
            )
            SettingsParagraph("On, a link in a message is drawn the way Messages draws one \u{2014} picture, headline, site. Building that means this phone loads the page, which tells whoever runs it that you opened the mail. Known trackers are never loaded either way.")
            Rule()
            SettingsLink(
                title: "Export your posts",
                subtitle: "\(store.messages.count) POSTS ON THIS PHONE, AS JSON",
                action: export
            )
            Rule()
            ConsequenceRow(
                title: "Clear what we\u{2019}ve interpreted here",
                sentence: "Your mail is untouched. This removes cached posts and opened messages from this phone. They load again when you next open or refresh them.",
                confirmTitle: "Tap again to clear",
                destructive: true,
                action: clear
            )
            Rule()

            SettingsGroup("MODEL TRAINING")
            SettingsParagraph("We don\u{2019}t use your mail to train anything, and that isn\u{2019}t a setting because it isn\u{2019}t negotiable.")
            SettingsParagraph("The model that writes your summaries is run by someone else, so what they do with it is their promise rather than ours \u{2014} the one thing on this screen you are taking on trust.")
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { contactPhotos.refreshAuthorization() }
        }
        .navigationDestination(isPresented: $showingStorage) { StorageView() }
        .sheet(item: $exporting) { file in
            ShareSheet(url: file.url)
        }
    }

    // MARK: Export
    //
    // Every post the app is currently holding, written out as it is held. The
    // row says "your feed" and the sub-label counts it, because the file is
    // exactly the loaded feed — calling it "everything" would claim a server
    // export this does not perform.

    private func export() {
        let iso = ISO8601DateFormatter()
        let posts: [[String: Any]] = store.messages.map { message in
            [
                "id": message.id,
                "mailbox": store.mailbox(message.mailboxID)?.address ?? message.mailboxID,
                "from": message.sender.displayName,
                "fromAddress": message.sender.address,
                "subject": message.subject,
                "snippet": message.snippet,
                "receivedAt": iso.string(from: message.receivedAt),
                "kicker": message.kicker.rawValue,
                "quoteFromTheEmail": message.quote ?? "",
                "ourSummary": message.summary ?? "",
                "read": message.isRead,
                "saved": message.isSaved,
            ]
        }
        let payload: [String: Any] = [
            "exportedAt": iso.string(from: .now),
            "mailboxes": store.mailboxes.map { ["address": $0.address, "tag": $0.tag] },
            "posts": posts,
        ]
        guard let data = try? JSONSerialization.data(
            withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]
        ) else { return }

        let url = FileManager.default.temporaryDirectory
            .appending(path: "decision-inbox-feed.json")
        guard (try? data.write(to: url, options: .atomic)) != nil else { return }
        exporting = ExportFile(url: url)
    }

    // MARK: Clear
    //
    // Local only, and the sentence under the row says so. What it drops is
    // every interpretation the app is holding; the mail itself is on the
    // provider's server and is not touched by anything here.

    private func clear() {
        withAnimation(Move.layout) { store.clearCachedContent() }
    }
}

// MARK: - What we store

/// Written as answers, not as policy. Each line is a thing a reasonable person
/// would want to know before handing over a mailbox — and each one is scoped to
/// what the code actually does, including the parts that are less flattering
/// than the first draft of this screen claimed.
struct StorageView: View {
    @Environment(\.dismiss) private var dismiss

    private let facts: [(String, String)] = [
        (
            "YOUR MAIL",
            "Subject, sender, snippets, and opened message bodies are cached on this device for up to 7 days so previously opened mail can appear without waiting. Clearing local data removes these copies; disconnecting a mailbox removes its copies."
        ),
        (
            "WHAT THE MODEL READS",
            "The cleaned text of an email, to write the quote and the summary. If you ask a question about an email or ask for a draft reply, that email goes to the model again \u{2014} only then, and only that one."
        ),
        (
            "YOUR TOKENS",
            "Held in the iOS Keychain on this device and on the sync server, so mail can be read while the app is closed. Disconnecting a mailbox deletes them."
        ),
        (
            "UNSUBSCRIBING",
            "The agent opens the sender\u{2019}s own page and fills in their form using the address that received the mail. Nothing else is shared, and it only ever runs on a sender you tapped Unsubscribe on."
        ),
        (
            "WHAT WE NEVER DO",
            "We never send, delete or reply to mail for you. Every email that leaves this app is one you pressed send on. The one thing we do act on is an unsubscribe, and only the one you tapped."
        ),
    ]

    var body: some View {
        SettingsScreen(title: "What we store", onBack: { dismiss() }) {
            ForEach(Array(facts.enumerated()), id: \.offset) { _, fact in
                VStack(alignment: .leading, spacing: Space.sm) {
                    Text(fact.0)
                        .typeStyle(Style.sectionHeader)
                        .foregroundStyle(Ink.tertiary)
                    Text(fact.1)
                        .typeStyle(Style.body)
                        .foregroundStyle(Ink.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Metric.gutter)
                .padding(.vertical, Space.xl)
                .accessibilityElement(children: .combine)
                Rule()
            }
        }
    }
}

#Preview {
    NavigationStack { SettingsPrivacyView() }
        .environment(FeedStore(sample: true))
}
