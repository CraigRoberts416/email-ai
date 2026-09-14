import SwiftUI

struct FeedView: View {
    @Environment(FeedStore.self) private var store
    @State private var scrollY: CGFloat = 0

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        Masthead(waiting: store.waitingCount, total: store.messages.count)

                        ForEach(store.messages(), id: \.0) { section, items in
                            Dateline(section)
                            ForEach(items) { message in
                                PostView(
                                    message: message,
                                    onOpen: { store.markRead(message) },
                                    onSave: { store.toggleSaved(message) },
                                    onArchive: { withAnimation(Move.layout) { store.archive(message) } }
                                )
                            }
                        }

                        CaughtUp(handled: store.messages.count)
                    }
                    // The tab bar floats over content on iOS 26, so the feed
                    // has to clear it itself or the last post sits underneath.
                    .safeAreaPadding(.bottom, Space.xxxl + Space.xl)
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        -proxy.frame(in: .scrollView).origin.y
                    } action: { scrollY = $0 }
                }
                .scrollIndicators(.hidden)
                .refreshable { try? await Task.sleep(for: .milliseconds(600)) }

                condition

                if !store.pending.isEmpty, scrollY > Move.Pill.showBelowScrollY {
                    NewPostsPill(senders: store.pending.map(\.sender), count: store.pending.count) {
                        withAnimation(Move.enter) { store.admitPending() }
                    }
                    .padding(.top, Space.sm)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .background(Ink.surface)
            .navigationBarHidden(true)
        }
    }

    /// Degraded states never take the screen. They sit above the feed and the
    /// feed keeps working underneath.
    @ViewBuilder private var condition: some View {
        switch store.condition {
        case .normal:
            EmptyView()
        case .statusStrip(let state, let freshness):
            StatusStrip(state: state, freshness: freshness)
        case .actionBar(let message, let verb):
            ActionBarView(message: message, verb: verb) {}
        case .fallback(let freshness):
            StatusStrip(state: "NOT INTERPRETING", freshness: freshness)
        }
    }
}

// MARK: - Masthead

struct Masthead: View {
    let waiting: Int
    let total: Int

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(greeting)
                .typeStyle(Style.display)
                .foregroundStyle(Ink.primary)

            Text("Two things are waiting on you. The rest is receipts and promos.")
                .typeStyle(Style.body)
                .foregroundStyle(Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Space.xs + 2) {
                Text("\(total) NEW").typeStyle(Style.kicker).foregroundStyle(Ink.secondary)
                Text("·").typeStyle(Style.meta).foregroundStyle(Ink.tertiary)
                Text("\(waiting) NEED YOU").typeStyle(Style.kicker).foregroundStyle(Ink.primary)
            }
            .padding(.top, Space.xs)
        }
        .padding(.horizontal, Metric.gutter)
        .padding(.top, Space.xxl)
        .padding(.bottom, Space.xl)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        switch hour {
        case ..<12: return "Good morning"
        case ..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }
}

// MARK: - Dateline
//
// 40pt above a band and nowhere else, so the spacing itself means "new day".

struct Dateline: View {
    let label: String
    init(_ label: String) { self.label = label }

    var body: some View {
        VStack(spacing: 0) {
            Rule()
            Text(label)
                .typeStyle(Style.kicker)
                .foregroundStyle(Ink.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Metric.gutter)
                .padding(.vertical, Space.sm)
                .background(Ink.surfaceTertiary)
            Rule()
        }
    }
}

// MARK: - Caught up
//
// A receipt, not a trophy. The feed is finite on purpose.

struct CaughtUp: View {
    let handled: Int

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Text("That\u{2019}s the lot.")
                .typeStyle(Style.display)
                .foregroundStyle(Ink.primary)
            Text("Nothing left is waiting on you.")
                .typeStyle(Style.body)
                .foregroundStyle(Ink.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Metric.gutter)
        .padding(.vertical, Space.xxxl + Space.xl)
    }
}
