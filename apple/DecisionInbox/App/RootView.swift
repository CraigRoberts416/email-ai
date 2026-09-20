import SwiftUI

/// Navigation scaffold. A connected mailbox gates the app; once one exists the
/// user lands in the tabbed feed. The single full-screen block in the whole
/// product is "no mailbox connected" — everything else degrades quietly.
struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    // StateObject constructs this owner once. Creating observable services in
    // every View.init reset the shared identity cache during rendering and
    // produced an AttributeGraph update cycle before the feed could load.
    @StateObject private var context = AppContext()
    private var auth: AuthService { context.auth }
    private var store: FeedStore { context.store }
    private var push: PushService { context.push }
    @State private var tab = 0
    @State private var scrollTop = 0
    @State private var notificationRequest: NotificationOpenRequest?
    @State private var leftApp = false

    private var showsMainApp: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-sampleOnboarding") { return false }
        #endif
        return auth.isAuthenticated || store.isSample
    }

    private var tabs: some View {
        TabView(selection: Binding(get: { tab }, set: { next in
            if next == 0 && tab == 0 { scrollTop += 1 }
            tab = next
        })) {
            Tab("Feed", systemImage: "house", value: 0) {
                FeedView(scrollTopSignal: scrollTop, notificationRequest: notificationRequest)
                    .safeAreaInset(edge: .bottom, spacing: 0) { GlobalActivityTray() }
            }
            // People sit beside the feed rather than inside it. The
            // feed answers what arrived; this answers who you are
            // talking to, and a reply from someone you know should not
            // have to win a sort against everything a retailer sent.
            Tab("People", systemImage: "bubble.left.and.bubble.right", value: 1) {
                DirectMessagesView()
                    .safeAreaInset(edge: .bottom, spacing: 0) { GlobalActivityTray() }
            }
            .badge(store.peopleUnreadCount)
            Tab("Saved", systemImage: "bookmark", value: 2) {
                SavedView()
                    .safeAreaInset(edge: .bottom, spacing: 0) { GlobalActivityTray() }
            }
            Tab("You", systemImage: "person.crop.circle", value: 3) {
                NavigationStack { SettingsView() }
                    .safeAreaInset(edge: .bottom, spacing: 0) { GlobalActivityTray() }
            }
            Tab("Search", systemImage: "magnifyingglass", value: 4, role: .search) {
                SearchView()
                    .safeAreaInset(edge: .bottom, spacing: 0) { GlobalActivityTray() }
            }
        }
    }

    private var mainTabs: some View {
        tabs
        .tint(Ink.primary)
        .sheet(isPresented: Binding(get: { store.activityPresented }, set: { store.activityPresented = $0 })) {
            ActivityView().environment(store)
        }
        // Tapping Feed while already on Feed returns to the top —
        // the one gesture every feed on the phone shares.
        .onChange(of: tab) { previous, current in
            if previous != 0 && current == 0 {
                store.beginFeedSession()
                Task { await store.refresh() }
            }
        }
        // Coming back to the app is the single most common moment
        // somebody wants to know what arrived, and until now it was
        // the one moment nothing was fetched.
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { leftApp = true }
            guard phase == .active, leftApp else { return }
            leftApp = false
            store.beginFeedSession()
            Task {
                await store.resume()
                if !store.isSample { await push.registerIfAuthorized() }
            }
            ContactPhotoStore.shared.refreshAuthorization()
        }
        .environment(store)
        // Keep People’s last known conversation count available from any tab.
        .task(id: "\(scenePhase == .active):\(auth.accounts.map(\.id).joined(separator: ","))") {
            guard scenePhase == .active else { return }
            repeat {
                await store.loadConversations(preservingLoaded: true)
                do { try await Task.sleep(for: .seconds(30)) }
                catch { return }
            } while !Task.isCancelled
        }
        .task(id: auth.accounts.count) {
            guard !store.isSample else { return }
            await store.start()
            if let token = AppDelegate.lastToken { await push.submit(deviceToken: token) }
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-verifyFeedPagination") {
                for _ in 0..<3 where !store.hasMoreFeed && !store.feedEndVerified {
                    try? await Task.sleep(for: .seconds(3))
                    guard !Task.isCancelled else { return }
                    await store.refresh()
                }
                let before = store.sessionMessages.count
                await store.loadMoreFeed()
                print("[verification] live pagination before=\(before) after=\(store.sessionMessages.count) more=\(store.hasMoreFeed) failed=\(store.paginationFailure != nil)")
            }
            #endif
            // Register only an existing grant. The explanatory
            // notification choice remains in Settings.
            await push.registerIfAuthorized()
        }
    }

    @ViewBuilder private var presentation: some View {
        if showsMainApp { mainTabs }
        else { NavigationStack { OnboardingFlow(auth: auth) } }
    }

    var body: some View {
        presentation
        #if DEBUG
        .transformEnvironment(\.dynamicTypeSize) { value in
            if ProcessInfo.processInfo.arguments.contains("-sampleLargeText") { value = .accessibility5 }
        }
        #endif
        // Token callbacks are attached after presentation; the store already
        // exists so cached mail can be shown in the first render.
        .task {
            guard !store.isSample else { return }
            AppDelegate.onToken = { token in
                Task { await push.submit(deviceToken: token) }
            }
            AppDelegate.onMailboxUpdate = { await store.refresh() }
            AppDelegate.notificationTaps.install { request in
                tab = 0
                notificationRequest = request
                // Open cached mail immediately. FeedView also retries when
                // refreshed cards arrive, without waiting for recap/badges.
                Task { await store.refresh() }
            }
            if let token = AppDelegate.lastToken { await push.submit(deviceToken: token) }
        }
    }

}

@MainActor
private final class AppContext: ObservableObject {
    let auth: AuthService
    let store: FeedStore
    let push: PushService

    init() {
        let auth = AuthService()
        self.auth = auth
        // Cache hydration stays synchronous, before the first visible frame.
        #if DEBUG
        if ["-sampleFeed", "-sampleFeedZero", "-sampleActivity", "-sampleOnboarding"].contains(where: ProcessInfo.processInfo.arguments.contains) {
            store = FeedStore(sample: true)
            if ProcessInfo.processInfo.arguments.contains("-sampleActivity") {
                let account = store.mailboxes.first?.id ?? "sample@example.com"
                let now = Date.now.timeIntervalSince1970 * 1000
                let handoff = UnsubscribeRun(messageId: "sample-handoff", senderName: "Weekend Journal",
                    status: "needs_you", message: "The sender asks you to choose which editions to stop.",
                    index: nil, total: nil, fieldIndex: nil, fieldTotal: nil,
                    mailboxID: account, runId: "sample-run", attemptId: "sample-attempt", updatedAt: now,
                    sourceURL: "https://example.com", handoffURL: "https://example.com",
                    history: [.init(status: "navigating", message: "Opened the sender’s page", at: now - 3000),
                              .init(status: "needs_you", message: "A personal choice is required", at: now)])
                let sent = UnsubscribeRun(messageId: "sample-request", senderName: "City Notes",
                    status: "done", message: nil, index: nil, total: nil, fieldIndex: nil, fieldTotal: nil,
                    mailboxID: account, runId: "sample-request-run", updatedAt: now - 5000,
                    outcome: "request_sent", evidence: "The provider accepted the request email.")
                store.unsubscribes = [handoff.id: handoff, sent.id: sent]
                store.isActivityTrayVisible = true
                if ProcessInfo.processInfo.arguments.contains("-sampleActivityExpanded") { store.activityPresented = true }
            }
            if ProcessInfo.processInfo.arguments.contains("-sampleFeedZero") {
                store.messages = store.messages.map { message in
                    var read = message
                    read.isRead = true
                    return read
                }
                store.beginFeedSession()
            }
        } else {
            store = FeedStore(auth: auth)
        }
        #else
        store = FeedStore(auth: auth)
        #endif
        push = PushService(auth: auth, baseURL: URL(string: "https://email-ai-server.onrender.com")!)
    }
}
