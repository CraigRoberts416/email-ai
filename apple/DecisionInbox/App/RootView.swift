import SwiftUI

/// Navigation scaffold. A connected mailbox gates the app; once one exists the
/// user lands in the tabbed feed. The single full-screen block in the whole
/// product is "no mailbox connected" — everything else degrades quietly.
struct RootView: View {
    @State private var auth = AuthService()
    @State private var store: FeedStore?
    @State private var push: PushService

    var body: some View {
        Group {
            if let store, auth.isAuthenticated {
                TabView {
                    Tab("Feed", systemImage: "house") {
                        FeedView()
                    }
                    Tab("Saved", systemImage: "bookmark") {
                        SavedView()
                    }
                    Tab("You", systemImage: "person.crop.circle") {
                        NavigationStack { SettingsView() }
                    }
                    Tab("Search", systemImage: "magnifyingglass", role: .search) {
                        SearchView()
                    }
                }
                .tint(Ink.primary)
                .environment(store)
                .task(id: auth.accounts.count) {
                    await store.start()
                    // Asked here and not a moment earlier: the prompt is a
                    // one-shot, so it is spent once the feed has loaded and
                    // the user can see what they would be saying yes to.
                    await push.requestIfUndecided()
                }
            } else {
                OnboardingFlow(auth: auth)
            }
        }
        // One store for the life of the session. Rebuilding it on sign-in
        // would throw away the feed every time a mailbox is added.
        .task {
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
