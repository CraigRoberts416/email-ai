import SwiftUI

struct SavedView: View {
    @Environment(FeedStore.self) private var store

    var body: some View {
        NavigationStack {
            Group {
                if store.saved.isEmpty {
                    EmptyStateView(
                        headline: "Nothing kept yet.",
                        detail: "TAP THE BOOKMARK ON ANY CARD AND IT LANDS HERE."
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(store.saved) { PostView(message: $0) }
                        }
                    }
                }
            }
            .background(Ink.surface)
            .navigationTitle("Saved")
        }
    }
}
