import SwiftUI

/// Navigation scaffold. A connected mailbox gates the app; once one exists the
/// user lands in the tabbed feed. The single full-screen block in the whole
/// product is "no mailbox connected" — everything else degrades quietly.
struct RootView: View {
    @State private var auth = AuthService()
    @State private var store: FeedStore?

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
                .task(id: auth.accounts.count) { await store.start() }
            } else {
                OnboardingFlow(auth: auth)
            }
        }
        // One store for the life of the session. Rebuilding it on sign-in
        // would throw away the feed every time a mailbox is added.
        .task { store = FeedStore(auth: auth) }
    }
}
