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

    var body: some View {
        Group {
            if auth.isAuthenticated || store.isSample {
                TabView(selection: $tab) {
                    Tab("Feed", systemImage: "house", value: 0) {
                        FeedView(scrollTopSignal: scrollTop, notificationRequest: notificationRequest)
                    }
                    // People sit beside the feed rather than inside it. The
                    // feed answers what arrived; this answers who you are
                    // talking to, and a reply from someone you know should not
                    // have to win a sort against everything a retailer sent.
                    Tab("People", systemImage: "bubble.left.and.bubble.right", value: 1) {
                        DirectMessagesView()
                    }
                    Tab("Saved", systemImage: "bookmark", value: 2) {
                        SavedView()
                    }
                    Tab("You", systemImage: "person.crop.circle", value: 3) {
                        NavigationStack { SettingsView() }
                    }
                    Tab("Search", systemImage: "magnifyingglass", value: 4, role: .search) {
                        SearchView()
                    }
                }
                .tint(Ink.primary)
                // Tapping Feed while already on Feed returns to the top —
                // the one gesture every feed on the phone shares.
                .onChange(of: tab) { previous, current in
                    if previous == 0 && current == 0 { scrollTop += 1 }
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
                        if !store.isSample { await push.requestIfUndecided() }
                    }
                    ContactPhotoStore.shared.refreshAuthorization()
                }
                .environment(store)
                .task(id: auth.accounts.count) {
                    guard !store.isSample else { return }
                    await store.start()
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
                    // Asked here and not a moment earlier: the prompt is a
                    // one-shot, so it is spent once the feed has loaded and
                    // the user can see what they would be saying yes to.
                    await push.requestIfUndecided()
                }
            } else {
                // The primer links to "What we store", which is the one thing
                // worth reading before consenting and was previously only
                // reachable after connecting — behind the decision it informs.
                NavigationStack { OnboardingFlow(auth: auth) }
            }
        }
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
        if ProcessInfo.processInfo.arguments.contains("-sampleFeed") || ProcessInfo.processInfo.arguments.contains("-sampleFeedZero") {
            store = FeedStore(sample: true)
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
