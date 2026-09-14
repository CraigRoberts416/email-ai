import SwiftUI

struct SearchView: View {
    @Environment(FeedStore.self) private var store
    @State private var query = ""

    private var results: [Message] {
        guard !query.isEmpty else { return [] }
        let q = query.lowercased()
        return store.messages.filter {
            $0.sender.displayName.lowercased().contains(q)
                || $0.subject.lowercased().contains(q)
                || ($0.quote ?? "").lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if query.isEmpty {
                    EmptyStateView(
                        headline: "Search your mail.",
                        detail: "SENDERS, SUBJECTS, AND EVERY LINE THE AI PULLED OUT."
                    )
                } else if results.isEmpty {
                    // Not an error — the query ran and returned nothing.
                    EmptyStateView(
                        headline: "Nothing for \u{201C}\(query)\u{201D}.",
                        detail: "SEARCHED EVERY INTERPRETED EMAIL FROM THE LAST 30 DAYS."
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(results) { PostView(message: $0) }
                        }
                    }
                }
            }
            .background(Ink.surface)
            .navigationTitle("Search")
            .searchable(text: $query, prompt: "Find an email")
        }
    }
}
