import SwiftUI

/// Everything one sender has ever said to you.
///
/// Built the way a social profile is built, because that is the shape the
/// question already has: who is this, how much of my attention do they take,
/// and what is outstanding between us. An email client normally answers that
/// with a search results page, which answers none of it.
///
/// The banner is the sender's own generated image. It is the one place in the
/// product where a picture is the point rather than decoration — a mailbox is
/// mostly brands, and a brand is faster to recognise than to read.
struct SenderProfileView: View {
    let sender: Sender

    @Environment(FeedStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var lane: Lane = .threads
    @State private var open: Message?

    enum Lane: String, CaseIterable, Identifiable {
        case threads, replies, messages
        var id: String { rawValue }
        var label: String { rawValue.uppercased() }
    }

    private var all: [Message] { store.messages(from: sender.address) }
    private var threads: [Message] { all.filter { $0.threadCount > 1 } }
    private var replies: [Message] { all.filter { $0.kicker == .waitingOnThem } }

    private var lanes: [Message] {
        switch lane {
        case .threads: return threads.isEmpty ? all : threads
        case .replies: return replies
        case .messages: return all
        }
    }

    private var banner: URL? { all.compactMap(\.heroImageURL).first }
    private var ground: Color { .sheet(fromHex: all.compactMap(\.heroBackground).first) }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                header
                lanePicker
                Rule()

                if lanes.isEmpty {
                    EmptyStateView(
                        headline: emptyHeadline,
                        detail: "NOTHING IN THIS LANE YET."
                    )
                    .frame(height: 240)
                } else {
                    ForEach(lanes) { message in
                        PostView(
                            message: message,
                            onOpen: { open = message },
                            onReply: { open = message },
                            onDiscuss: { open = message },
                            onForward: { open = message },
                            onSave: { store.toggleSaved(message) },
                            onArchive: { store.archive(message) },
                            onUnsubscribe: { store.unsubscribe(from: message) }
                        )
                    }
                }
            }
            .safeAreaPadding(.bottom, Space.xxxl + Space.xl)
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top)
        .background(Ink.surface)
        .toolbar(.hidden, for: .navigationBar)
        // Same reason as the thread: this is a full-bleed screen carrying its
        // own back button over a banner, so the system's bars are its to hide.
        .toolbar(.hidden, for: .tabBar)
        .overlay(alignment: .topLeading) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(banner == nil ? Ink.primary : Ink.onSheet)
                    .frame(width: 40, height: 40)
                    .background(banner == nil ? Color.clear : Ink.scrim, in: Circle())
            }
            .buttonStyle(.plain)
            .padding(.leading, Space.md)
            .padding(.top, Space.xxl + Space.lg)
            .accessibilityLabel("Back")
        }
        .navigationDestination(item: $open) { ThreadView(message: $0) }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The banner, or the sender's ground if there is no image yet.
            // Never a placeholder pattern — an empty band of their own colour
            // is honest and still recognisably theirs.
            Group {
                if let banner {
                    AsyncImage(url: banner, transaction: Transaction(animation: Move.crossfade)) { phase in
                        if case .success(let image) = phase {
                            image.resizable().scaledToFill()
                        } else {
                            ground
                        }
                    }
                } else {
                    ground
                }
            }
            .frame(height: 168)
            .frame(maxWidth: .infinity)
            .clipped()

            VStack(alignment: .leading, spacing: Space.md) {
                // Overlaps the banner by half, ringed in the page ground —
                // the one shape on the screen that belongs to both bands.
                AvatarView(sender: sender, size: 72)
                    .overlay(Circle().strokeBorder(Ink.surface, lineWidth: 4))
                    .padding(.top, -48)

                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(sender.displayName)
                        .typeStyle(Style.display)
                        .foregroundStyle(Ink.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(sender.address)
                        .typeStyle(Style.monoCaption)
                        .foregroundStyle(Ink.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                stats

                if let unsubscribe = all.first(where: { $0.isPromotion }) {
                    Button { store.unsubscribe(from: unsubscribe) } label: {
                        HStack(spacing: Space.sm) {
                            Image(systemName: "xmark").font(.system(size: 13))
                            Text("Unsubscribe from \(sender.displayName)")
                                .typeStyle(Style.bodyMedium)
                        }
                        .foregroundStyle(Ink.primary)
                        .padding(.horizontal, Space.lg)
                        .padding(.vertical, 9)
                        .overlay(Capsule().strokeBorder(Ink.primary, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, Space.xs)
                }
            }
            .padding(.horizontal, Metric.gutter)
            .padding(.bottom, Space.xl)
        }
    }

    /// Counts, not engagement. How much of your attention this sender takes is
    /// a fact worth knowing; a follower count would be a fiction.
    private var stats: some View {
        HStack(spacing: Space.md) {
            stat(all.count, all.count == 1 ? "MESSAGE" : "MESSAGES")
            Text("·").typeStyle(Style.separator).foregroundStyle(Ink.tertiary)
            stat(threads.count, threads.count == 1 ? "THREAD" : "THREADS")
            if !replies.isEmpty {
                Text("·").typeStyle(Style.separator).foregroundStyle(Ink.tertiary)
                stat(replies.count, "AWAITING")
            }
        }
    }

    private func stat(_ count: Int, _ label: String) -> some View {
        HStack(spacing: Space.xs) {
            Text("\(count)")
                .typeStyle(Style.meta)
                .foregroundStyle(Ink.primary)
                .monospacedDigit()
            Text(label)
                .typeStyle(Style.meta)
                .foregroundStyle(Ink.tertiary)
        }
    }

    // MARK: Lanes

    /// Underline, not a pill. A filled segment would be the only soft
    /// container in the product, and the rule already does the job.
    private var lanePicker: some View {
        HStack(spacing: Space.xl) {
            ForEach(Lane.allCases) { option in
                Button {
                    withAnimation(Move.crisp) { lane = option }
                } label: {
                    VStack(spacing: Space.sm) {
                        Text(option.label)
                            .typeStyle(Style.kicker)
                            .foregroundStyle(lane == option ? Ink.primary : Ink.tertiary)
                        Rectangle()
                            .fill(lane == option ? Ink.primary : .clear)
                            .frame(height: 2)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(lane == option ? [.isSelected, .isButton] : .isButton)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Metric.gutter)
        .padding(.top, Space.sm)
    }

    private var emptyHeadline: String {
        switch lane {
        case .threads: return "No back-and-forth yet."
        case .replies: return "Nothing waiting on them."
        case .messages: return "Nothing from them."
        }
    }
}
