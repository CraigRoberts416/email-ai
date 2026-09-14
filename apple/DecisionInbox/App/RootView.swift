import SwiftUI

/// Navigation scaffold. Onboarding gates the app; once a mailbox exists the
/// user lands in the tabbed feed. The single full-screen block in the whole
/// product is "no mailbox connected" — everything else degrades quietly.
struct RootView: View {
    @State private var store = FeedStore()

    var body: some View {
        Group {
            if store.mailboxes.isEmpty {
                OnboardingFlow()
            } else {
                TabView {
                    Tab("Feed", systemImage: "house") {
                        FeedView()
                    }
                    Tab("Saved", systemImage: "bookmark") {
                        SavedView()
                    }
                    Tab("Search", systemImage: "magnifyingglass", role: .search) {
                        SearchView()
                    }
                }
                .tint(Ink.primary)
            }
        }
        .environment(store)
    }
}

#Preview {
    RootView()
}
