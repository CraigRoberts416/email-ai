import SwiftUI

/// Navigation scaffold. A connected mailbox gates the app; once one exists the
/// user lands in the tabbed feed. The single full-screen block in the whole
/// product is "no mailbox connected" — everything else degrades quietly.
struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var auth = AuthService()
    @State private var store: FeedStore?
    @State private var push: PushService
    @State private var tab = 0
    @State private var scrollTop = 0

    var body: some View {
        Group {
            if let store, auth.isAuthenticated || store.isSample {
                TabView(selection: $tab) {
                    Tab("Feed", systemImage: "house", value: 0) {
                        FeedView(scrollTopSignal: scrollTop)
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
                }
                // Coming back to the app is the single most common moment
                // somebody wants to know what arrived, and until now it was
                // the one moment nothing was fetched.
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    Task { await store.resume() }
                }
                .environment(store)
                .task(id: auth.accounts.count) {
                    await store.start()
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
        // One store for the life of the session. Rebuilding it on sign-in
        // would throw away the feed every time a mailbox is added.
        .task {
            #if DEBUG
            // Lets the feed be driven in a simulator without credentials —
            // the keychain refuses writes in an unsigned build, so sign-in
            // cannot complete there and the UI was untestable by hand.
            if ProcessInfo.processInfo.arguments.contains("-sampleFeed") {
                store = FeedStore(sample: true)
                return
            }
            #endif
            store = FeedStore(auth: auth)
            AppDelegate.onToken = { token in
                Task { await push.submit(deviceToken: token) }
            }
        }
    }

    init() {
        let auth = AuthService()
        _auth = State(initialValue: auth)
        _push = State(initialValue: PushService(
            auth: auth,
            baseURL: URL(string: "https://email-ai-server.onrender.com")!
        ))
    }
}
