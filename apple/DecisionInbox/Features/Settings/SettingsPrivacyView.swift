import SwiftUI
import Contacts

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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
    @State private var exportURL: URL?
    @State private var preparingExport = false
    @State private var exportFeedback: String?
    @State private var clearFeedback: String?

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
                                await store.reconnect(account.id, includeGooglePhotos: true)
                                await identities.refreshGooglePhotos(force: true)
                            }
                        })
                        .disabled(store.auth.isConnecting)
                    }
                    if let failure = identities.photoFailures[account.id] {
                        SettingsParagraph(failure)
                        SettingsLink(title: "Try contact photos again", action: {
                            Task { await identities.refreshGooglePhotos(force: true) }
                        })
                    }
                }
            }
            ConnectionFeedback(auth: store.auth)
            SettingsParagraph("Turning Google photos off stops their use here; it does not revoke permissions in your Google Account.")
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
            if contactPermissionDenied || contactsDenied {
                SettingsLink(title: "Allow contacts in iOS Settings", action: {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                })
            }
            Rule()

            if CNContactStore.authorizationStatus(for: .contacts) == .limited {
                SettingsParagraph("Only the contacts you selected in iOS are available. Other people keep their initials or existing avatar.")
            }
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
                title: preparingExport ? "Preparing export…" : "Export your posts",
                subtitle: "\(store.messages.count) POSTS ON THIS PHONE, AS JSON",
                action: export
            )
            .disabled(preparingExport)
            if let exportFeedback { SettingsParagraph(exportFeedback) }
            Rule()
            ConsequenceRow(
                title: "Clear cached mail on this device",
                sentence: "Remove cached posts, opened messages and photos from this device. Saved items, drafts, discussions and task history stay. Your Gmail and stored server records are unchanged; cached mail loads again when needed.",
                confirmTitle: "Clear cached mail",
                destructive: true,
                action: clear
            )
            if let clearFeedback { SettingsParagraph(clearFeedback) }
            Rule()

            SettingsGroup("MODEL TRAINING")
            SettingsParagraph("The app sends email text to a model provider for interpretation, requested drafts and discussions. It does not include its own model-training pipeline.")
            SettingsParagraph("Provider retention and training terms are separate from local storage controls. Clearing this device’s cache does not delete requests already processed by a provider.")
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { contactPhotos.refreshAuthorization() }
        }
        .navigationDestination(isPresented: $showingStorage) { StorageView() }
        .task { contactPhotos.refreshAuthorization() }
        .sheet(item: $exporting, onDismiss: cleanExport) { file in
            ShareSheet(url: file.url) { completed, error in
                exportFeedback = error == nil
                    ? (completed ? "Export handed to the selected app." : "Sharing cancelled. You can export again.")
                    : "Sharing could not finish. Try exporting again."
            }
        }
    }

    // MARK: Export
    //
    // Every post the app is currently holding, written out as it is held. The
    // row says "your feed" and the sub-label counts it, because the file is
    // exactly the loaded feed — calling it "everything" would claim a server
    // export this does not perform.

    private var contactsDenied: Bool {
        _ = contactPhotos.authorizationVersion
        return [.denied, .restricted].contains(CNContactStore.authorizationStatus(for: .contacts))
    }

    private func export() {
        guard !preparingExport else { return }
        preparingExport = true
        exportFeedback = nil
        let posts = store.messages.map { message in
            ExportPost(id: message.id, mailbox: message.mailboxID,
                from: message.sender.displayName, fromAddress: message.sender.address,
                subject: message.subject, snippet: message.snippet, receivedAt: message.receivedAt,
                kicker: message.kicker.rawValue, quoteFromTheEmail: message.quote ?? "",
                ourSummary: message.summary ?? "", read: message.isRead, saved: message.isSaved)
        }
        let mailboxes = store.mailboxes.map { ExportMailbox(address: $0.address, tag: $0.tag) }
        Task {
            defer { preparingExport = false }
            do {
                let url = try await Task.detached(priority: .userInitiated) {
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    encoder.dateEncodingStrategy = .iso8601
                    let data = try encoder.encode(ExportPayload(exportedAt: .now, mailboxes: mailboxes, posts: posts))
                    let url = FileManager.default.temporaryDirectory
                        .appending(path: "decision-inbox-feed-\(UUID().uuidString).json")
                    try data.write(to: url, options: [.atomic, .completeFileProtection])
                    return url
                }.value
                exportURL = url
                exporting = ExportFile(url: url)
                exportFeedback = "Export ready. Choose where to save or share it."
            } catch { exportFeedback = "The export could not be prepared. Check available storage and try again." }
        }
    }

    private func cleanExport() {
        if let exportURL { try? FileManager.default.removeItem(at: exportURL) }
        exportURL = nil
    }

    private struct ExportMailbox: Encodable, Sendable { let address: String; let tag: String }
    private struct ExportPost: Encodable, Sendable {
        let id: String; let mailbox: String; let from: String; let fromAddress: String
        let subject: String; let snippet: String; let receivedAt: Date; let kicker: String
        let quoteFromTheEmail: String; let ourSummary: String; let read: Bool; let saved: Bool
    }
    private struct ExportPayload: Encodable, Sendable {
        let exportedAt: Date; let mailboxes: [ExportMailbox]; let posts: [ExportPost]
    }

    // MARK: Clear
    //
    // Local only, and the sentence under the row says so. What it drops is
    // every interpretation the app is holding; the mail itself is on the
    // provider's server and is not touched by anything here.

    private func clear() {
        withAnimation(Move.resolved(Move.layout, reduceMotion)) { store.clearCachedContent() }
        clearFeedback = "Cached mail cleared on this device. Saved items and work in progress are kept."
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
        ("ON THIS DEVICE", "Feed posts and opened message bodies are cached for up to 7 days. Saved items, recovered drafts, discussions and task history stay until you remove them or disconnect that mailbox. Clearing cached mail preserves that work."),
        ("ON OUR SERVER", "Connected mail is synced in the background. Sender, subject, snippets, message text and generated interpretations are stored on the sync server. Disconnect stops access and removes its credentials; it does not erase these retained records. This screen does not provide server-record deletion or a guaranteed retention period."),
        ("WHAT THE MODEL READS", "Cleaned email text is sent to a model provider for interpretation. Asking for a draft or discussing a message sends relevant message text and your request again. Model-provider data handling is separate from device caching."),
        ("YOUR TOKENS", "Google credentials are held in this device's Keychain and on the sync server so mail can be read while the app is closed. A confirmed disconnect removes both copies and stops new server access. Google's OAuth grant remains in your Google Account until you revoke it there."),
        ("CONTACT PHOTOS", "Optional Google contact permission reads email addresses and photos on this device. Device Contacts is a separate optional permission. Turning photos off here does not revoke Google's grant or change iOS permissions."),
        ("UNSUBSCRIBING", "An unsubscribe you request may open a sender's page, submit their form or send an unsubscribe request with the receiving address. The sender and services on that page can receive that request. Opening a page or sending a request is not confirmation that future mail will stop."),
        ("YOUR ACTIONS", "Sending, replying, archiving and unsubscribing begin with your action. Background mail sync and interpretation run while an account is connected. Disconnecting cannot reverse a message or request already submitted."),
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
