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
    @State private var lane: Lane = .messages
    @State private var open: Message?

    enum Lane: String, CaseIterable, Identifiable {
        case messages, media, docs
        var id: String { rawValue }
        var label: String { rawValue.uppercased() }
    }

    private var all: [Message] { store.messages(from: sender.address) }
    private var threads: [Message] { all.filter { $0.threadCount > 1 } }
    private var replies: [Message] { all.filter { $0.kicker == .waitingOnThem } }

    /// Every picture this sender has sent: the email's own image, plus any
    /// image they attached. Never the generated hero — it is not a photograph
    /// of anything that happened, and a grid is a claim that these are.
    private var media: [URL] {
        all.flatMap { message -> [URL] in
            var found: [URL] = []
            if let picture = message.imageURL { found.append(picture) }
            for attachment in message.attachments {
                if case .image(let url) = attachment.preview { found.append(url) }
            }
            return found
        }
    }

    /// Everything they attached that is not a picture.
    private var docs: [(message: Message, file: Attachment)] {
        all.flatMap { message in
            message.attachments
                .filter { if case .document = $0.preview { return true } else { return false } }
                .map { (message, $0) }
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

                switch lane {
                case .media:   mediaGrid
                case .docs:    docsList
                case .messages: messageList
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
                    // Glass over the banner, for the same reason as the
                    // thread: the image underneath is different for every
                    // sender, so a fixed disc is wrong for a bright one and
                    // heavy on a dark one.
                    .glassControl(fallback: banner == nil ? .clear : Ink.scrim, in: Circle())
            }
            .buttonStyle(.plain)
            .padding(.leading, Space.md)
            // 8, not 68.
            //
            // `ignoresSafeArea` applies to the scroll view; this overlay is
            // attached outside it and still gets the inset, so a padding
            // measured from the screen top was being added to 59pt of status
            // bar and landing the control at 127 — straight onto the avatar.
            // The inset is already the clearance; this is the gap after it.
            .padding(.top, Space.sm)
            .accessibilityLabel("Back")
        }
        .navigationDestination(item: $open) { ThreadView(message: $0) }
    }

    // MARK: Header
    //
    // Built to `SenderProfile`. The Twitter shape, in this product's system:
    // banner, chrome floating on it, avatar crossing the seam, identity
    // descending loudest to quietest, counts, two actions.

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The banner, or the sender's own ground if no image has been
            // generated yet. Never a placeholder pattern — an empty band of
            // their colour is honest and still recognisably theirs.
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
            // 180, and the depth was never the problem — the chrome position
            // was. The back control and the avatar both sit on the 16pt
            // gutter, so they stack on one vertical line: the banner has to
            // clear the status bar, the control, a real gap, and the part of
            // the avatar above the seam. Deepening it without moving the
            // control just moved the collision down.
            .frame(height: 180)
            .frame(maxWidth: .infinity)
            .clipped()

            VStack(alignment: .leading, spacing: Space.xs) {
                // Crosses the seam, ringed in the page ground — the one shape
                // on this screen belonging to both bands.
                AvatarView(sender: sender, size: 84)
                    .overlay(Circle().strokeBorder(Ink.surface, lineWidth: 4))
                    .padding(.top, -34)
                    .padding(.bottom, Space.md)

                Text(sender.displayName)
                    .typeStyle(Style.quote)
                    .foregroundStyle(Ink.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(sender.address)
                    .typeStyle(Style.monoCaption)
                    .foregroundStyle(Ink.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                // Where a profile would carry a bio. This sender did not write
                // one, so it is ours — and it is counted from their actual mail
                // rather than written by a model, which makes it checkable.
                // Mono, so it is never mistaken for their words.
                Text(characterisation)
                    .typeStyle(Style.gloss)
                    .foregroundStyle(Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Space.sm)

                metaRow
                    .padding(.top, Space.sm)

                stats
                    .padding(.top, Space.md)

                actions
                    .padding(.top, Space.lg)
            }
            .padding(.horizontal, Metric.gutter)
            .padding(.bottom, Space.lg)
        }
    }

    /// One line about what this sender sends, derived from what they actually
    /// sent. Every number here is counted, so nothing can be wrong in the way
    /// a generated sentence can.
    private var characterisation: String {
        guard !all.isEmpty else { return "NOTHING FROM THEM YET." }
        let recent = Array(all.prefix(10))
        let asked = recent.count { $0.kicker == .needsYou }
        let promos = all.count { $0.isPromotion }

        var kind = "Mostly correspondence."
        if promos > all.count / 2 { kind = "Mostly broadcast." }
        else if all.allSatisfy({ $0.kicker == .receipt }) { kind = "Receipts." }

        let attention = asked == 0
            ? "None of the last \(recent.count) asked anything of you."
            : "\(asked) of the last \(recent.count) needed you."
        return "\(kind) \(attention)"
    }

    /// What Twitter fills with a location and a join date.
    private var metaRow: some View {
        HStack(spacing: Space.lg) {
            if let first = all.last {
                Label {
                    Text(first.receivedAt.formatted(.dateTime.month(.abbreviated).year()).uppercased())
                        .typeStyle(Style.monoMicro)
                } icon: {
                    Image(systemName: "calendar").font(.system(size: 11))
                }
                .foregroundStyle(Ink.tertiary)
            }
            if let domain = sender.address.split(separator: "@").last {
                Label {
                    Text(String(domain))
                        .typeStyle(Style.monoMicro)
                        .lineLimit(1)
                } icon: {
                    Image(systemName: "link").font(.system(size: 11))
                }
                .foregroundStyle(Ink.tertiary)
            }
        }
    }

    /// Where Twitter has Message and Follow. Following a sender is not a thing
    /// a mailbox can offer — their mail arrives whether you want it or not —
    /// so the second slot is the one action that actually changes that.
    private var actions: some View {
        HStack(spacing: Space.md) {
            Button { open = all.first } label: {
                Text("Compose")
                    .typeStyle(Style.body)
                    .foregroundStyle(Ink.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .overlay(Capsule().strokeBorder(Ink.border, lineWidth: 1))
            }
            .buttonStyle(TapStyle())

            if let promo = all.first(where: { $0.isPromotion }) {
                Button { store.unsubscribe(from: promo) } label: {
                    Text("Unsubscribe")
                        .typeStyle(Style.body)
                        .foregroundStyle(Ink.surface)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Ink.primary, in: Capsule())
                }
                .buttonStyle(TapStyle())
            }
        }
    }

    // MARK: Lanes

    /// Their mail, in the feed's own card.
    @ViewBuilder private var messageList: some View {
        if all.isEmpty {
            EmptyStateView(headline: "Nothing from them.", detail: "NO MAIL FROM THIS SENDER YET.")
                .frame(height: 240)
        } else {
            ForEach(all) { message in
                PostView(
                    message: message,
                    onOpen: { open = message },
                    onReply: { open = message },
                    onDiscuss: { open = message },
                    onForward: { open = message },
                    onSave: { store.toggleSaved(message) },
                    onArchive: { store.archive(message) },
                    onUnsubscribe: { store.unsubscribe(from: message) },
                    onReact: { store.react(message, $0) }
                )
            }
        }
    }

    /// Every picture they have sent, three across.
    ///
    /// Built to `ProfileMediaGrid`. One-pixel gutters, edge to edge — the one
    /// place the product drops its 16pt gutter entirely. At this size a
    /// picture stops being evidence attached to a message and becomes
    /// something you scan on shape and colour alone; a margin round each cell
    /// would turn it back into a list of small pictures.
    @ViewBuilder private var mediaGrid: some View {
        if media.isEmpty {
            EmptyStateView(headline: "No pictures.", detail: "NOTHING THIS SENDER WROTE CARRIED ONE.")
                .frame(height: 240)
        } else {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 3),
                spacing: 1
            ) {
                ForEach(Array(media.enumerated()), id: \.offset) { _, url in
                    // Square whatever the source ratio. Uniform crop is what
                    // makes a grid readable as a grid; honouring each image
                    // would produce a ragged wall.
                    Color.clear
                        .aspectRatio(1, contentMode: .fit)
                        .overlay {
                            AsyncImage(url: url, transaction: Transaction(animation: Move.crossfade)) { phase in
                                if case .success(let image) = phase {
                                    image.resizable().scaledToFill()
                                } else {
                                    Ink.surfaceTertiary
                                }
                            }
                        }
                        .clipped()
                }
            }
            .padding(.top, 1)
        }
    }

    /// Everything they attached that is not a picture.
    ///
    /// Built to `ProfileDocsList`. A list rather than a grid: a document has
    /// no thumbnail worth scanning, so a grid of them is a wall of identical
    /// grey squares. The useful axes are name, type and date, and all three
    /// are text.
    @ViewBuilder private var docsList: some View {
        if docs.isEmpty {
            EmptyStateView(headline: "No files.", detail: "THIS SENDER HAS NOT ATTACHED ANYTHING.")
                .frame(height: 240)
        } else {
            ForEach(Array(docs.enumerated()), id: \.offset) { _, entry in
                Button { open = entry.message } label: {
                    HStack(spacing: Space.md) {
                        // The extension, set as type. A generic document glyph
                        // says "file", which the reader already knows; the
                        // extension says which file.
                        Text(entry.file.filename.split(separator: ".").last.map { String($0).uppercased() } ?? "FILE")
                            .typeStyle(Style.monoMicro)
                            .foregroundStyle(Ink.secondary)
                            .frame(width: 44, height: 44)
                            .background(Ink.surfaceTertiary, in: RoundedRectangle(cornerRadius: Corner.sm, style: .continuous))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.file.filename)
                                .typeStyle(Style.monoCaption)
                                .foregroundStyle(Ink.primary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text("\(entry.file.sizeLabel.uppercased()) \u{00B7} \(entry.message.receivedAt.feedStamp)")
                                .typeStyle(Style.monoMicro)
                                .foregroundStyle(Ink.tertiary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 13))
                            .foregroundStyle(Ink.tertiary)
                    }
                    .padding(.horizontal, Metric.gutter)
                    .padding(.vertical, Space.md)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(entry.file.filename), \(entry.file.sizeLabel)")

                Rule()
            }
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


}
