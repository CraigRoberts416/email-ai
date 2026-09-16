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
    @State private var lane: Lane = .emails
    @State private var open: Message?

    /// `emails`, not `messages`. This is a mail client — the thing on screen
    /// is an email, and calling it a message borrows a word from chat apps
    /// where it means something slightly different.
    enum Lane: String, CaseIterable, Identifiable {
        case emails, media, docs
        var id: String { rawValue }
        var label: String { rawValue.uppercased() }

        /// Carries the tab on its own when the tab is closed, so each has to
        /// be unambiguous without its label.
        var symbol: String {
            switch self {
            case .emails:   return "tray.full"
            case .media:    return "photo.on.rectangle"
            case .docs:     return "paperclip"
            }
        }
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
                case .emails:  emailList
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
                    .foregroundStyle(banner == nil ? Ink.primary : GlassInk.onScrim)
                    .frame(width: 40, height: 40)
                    // Glass over the banner, for the same reason as the
                    // thread: the image underneath is different for every
                    // sender, so a fixed disc is wrong for a bright one and
                    // heavy on a dark one.
                    .glassControl(fallback: banner == nil ? .clear : Ink.scrim, in: Circle())
                    // The glass is a background layer and contributes no hit
                    // shape of its own, so without this only the 15pt chevron
                    // glyph was tappable — a target you have to aim at, inside
                    // a control that looks 40pt wide. The flat scrim it
                    // replaced was a real shape and had been doing this job.
                    .contentShape(.circle)
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
        // A sheet everywhere, so a thread opened from here is the same
        // object as one opened from the feed.
        .sheet(item: $open) {
            ThreadView(message: $0)
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
                .presentationBackground(.clear)
        }
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

                // Where a profile carries a bio: who this sender is.
                //
                // Not a summary of their mail. The counts directly below
                // already report volume and what has been asked of you, and
                // saying that again in prose spends the one line that could
                // tell you something you did not already know.
                //
                // Absent rather than invented when the model does not
                // recognise the sender: a blank is a missing sentence, a guess
                // is a false claim about a real company on the one screen whose
                // whole job is identification.
                if let description = senderDescription {
                    Text(description)
                        .typeStyle(Style.gloss)
                        .foregroundStyle(Ink.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, Space.sm)
                }

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

    private var senderDescription: String? {
        all.compactMap(\.senderDescription).first
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
    @ViewBuilder private var emailList: some View {
        if all.isEmpty {
            EmptyStateView(headline: "Nothing from them.", detail: "NO EMAIL FROM THIS SENDER YET.")
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
            stat(all.count, all.count == 1 ? "EMAIL" : "EMAILS")
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
    /// Full width, icon alone when closed, icon and name when open.
    ///
    /// Three labels across 390pt forces either truncation or 10pt type, and
    /// neither is worth paying when the icon already says which is which. The
    /// name appears on the tab you are actually in, where there is room for it
    /// — which is also the only tab whose name you need.
    private var lanePicker: some View {
        HStack(spacing: 0) {
            ForEach(Lane.allCases) { option in
                Button {
                    withAnimation(Move.crisp) { lane = option }
                } label: {
                    VStack(spacing: Space.sm + 2) {
                        HStack(spacing: Space.xs + 2) {
                            Image(systemName: option.symbol)
                                .font(.system(size: 17))
                            if lane == option {
                                Text(option.label)
                                    .typeStyle(Style.kicker)
                            }
                        }
                        .foregroundStyle(lane == option ? Ink.primary : Ink.tertiary)
                        .frame(height: 22)

                        // Spans the tab, not the label: at full width an
                        // underline that hugs a word leaves the rest of the
                        // column looking unclaimed.
                        Rectangle()
                            .fill(lane == option ? Ink.primary : .clear)
                            .frame(height: 2)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.label.capitalized)
                .accessibilityAddTraits(lane == option ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(.top, Space.xl)
    }
}
