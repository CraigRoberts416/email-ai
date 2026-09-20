import SwiftUI

/// A post in the feed.
///
/// Deliberately decontained: no card fill, no radius, no border. Posts run
/// full width and are separated by an edge-to-edge hairline. That single
/// decision is what turns a catalogue of tiles into a feed — containers made
/// a contract and a receipt look equally important.
///
/// Media breaks the 16pt gutter and runs 0 → full width. It is the only thing
/// that does, and that break is what makes it read as a post rather than an
/// image inside a card.
struct PostView: View {
    /// Opens whatever the sender attached. One per card rather than one per
    /// feed, because the sheet has to be presented from the row the file is in.
    @State private var opener = AttachmentOpener()

    let message: Message
    /// Which mailbox this arrived in. Nil with a single mailbox — a tag on
    /// every row when there is only one thing it can mean is pure noise.
    var tag: String?
    var onOpen: () -> Void = {}
    var onReply: () -> Void = {}
    var onDiscuss: () -> Void = {}
    var onForward: () -> Void = {}
    var onSave: () -> Void = {}
    var onArchive: () -> Void = {}
    var onUnsubscribe: () -> Void = {}
    /// Tapping the avatar or the name opens the sender, not the message.
    var onProfile: () -> Void = {}
    /// Nil clears the reaction.
    var onReact: (String?) -> Void = { _ in }
    /// Suspends feed read tracking and new-post entrances during a reaction interaction.
    var onSwiping: (Bool) -> Void = { _ in }

    @GestureState(resetTransaction: Transaction(animation: Move.pressOut)) private var pressed = false
    @State private var linkFailed = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.openURL) private var openURL

    /// Which file is being fetched, if any — the tile dims while it is.
    private var openingID: Attachment.ID? {
        if case .loading(let id) = opener.state { return id }
        return nil
    }

    private var increasedContrast: Bool { contrast == .increased }
    /// `Ink.tertiary` measures 3.0:1 — below AA — and carries the `·`
    /// separators and the timestamp. Under Increase Contrast the meta has to
    /// strengthen with everything else or the post's grammar comes apart.
    private var metaInk: Color { Ink.secondary }
    /// At accessibility sizes the header stacks: a `lineLimit(1)` name beside
    /// a non-compressing `· time · count` truncates the identity anchor to
    /// nothing while the timestamp survives.
    private var stackedHeader: Bool { typeSize >= .accessibility1 }

    var body: some View {
        VStack(spacing: 0) {
            content
            // A lead is set apart by space, not a line. Isolation is the
            // strongest emphasis device there is, and here it is free.
            // One separator, every time. A lead used to be set apart by
            // space instead of a line, which meant the feed's only structural
            // grammar switched off for the posts that mattered most.
            Rule()
        }
        .background(pressed ? Ink.surfaceTertiary : Ink.surface)
        .contentShape(.rect)
        // The whole card opens the thread, and it is a TapGesture rather than
        // a Button for exactly one reason: a scroll cancels it. The inner
        // controls — avatar, CTA, action row — are real Buttons and still take
        // their own taps first, so this only catches the reading surface.
        .onTapGesture { onOpen() }
        // A non-recognizing hold observes touch-down; travel cancels it.
        // Unlike a row DragGesture it never claims the scroll view's pan.
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 60, maximumDistance: 8)
                .updating($pressed) { down, state, transaction in
                    transaction.animation = Move.pressIn
                    state = down
                }
        )
        // NO row-level DragGesture here, in either form. This was measured, not
        // reasoned about: with the same synthetic drag over the same feed, the
        // scroll offset reached 4681pt without it and exactly 0 with it —
        // arbitrated (`.gesture`) AND simultaneous. SwiftUI will not let a
        // drag on a row coexist with the scroll view's pan; `guard axis ==
        // .horizontal` stops this handler from acting but never returns the
        // touch, and there is no API to fail a gesture after the fact. Posts
        // cover the whole feed, so the feed did not scroll at all.
        //
        // Visible Save/Archive buttons, the menu and accessibility actions
        // own filing. Native swipeActions would require a List migration;
        // no dormant custom swipe implementation is kept to re-enable.
        //
        // No haptic from us: `.contextMenu` fires the system's own lift cue and
        // ours would double it.
        .contextMenu { menuItems }
        .overlay(alignment: .topTrailing) { overflowMenu }
        // Presented from the row, because that is where the file is.
        .sheet(item: $opener.previewing) { QuickLookView(url: $0.url).ignoresSafeArea() }
        .alert("Couldn’t open this link", isPresented: $linkFailed) {
            Button("Open original email", action: onOpen)
            Button("Cancel", role: .cancel) { }
        } message: { Text("The original email is still available.") }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("Opens the thread")
        .accessibilityAddTraits(.isButton)
        // Combining children makes the post one readable element and drops
        // every button inside it, so the actions have to be re-offered by
        // hand, including reactions, links and attachments.
        .accessibilityActions {
            Button("Open", action: onOpen)
            if message.isPromotion {
                Button("Unsubscribe", action: requested(onUnsubscribe))
            }
            Button("Reply", action: onReply)
            Button("Forward", action: onForward)
            Button("Discuss", action: onDiscuss)
            ForEach(Reaction.all) { reaction in
                Button("Mark \(reaction.label)") { onReact(reaction.emoji) }
            }
            if message.reaction != nil { Button("Remove reaction") { onReact(nil) } }
            if let label = message.actionLabel, !label.isEmpty {
                Button(primaryActionTitle, action: performPrimaryAction)
            }
            ForEach(message.attachments) { attachment in
                Button("Open \(attachment.filename)") {
                    Task { await opener.open(attachment, authorization: nil) }
                }
            }
            Button("Open \(message.sender.displayName)", action: onProfile)
            Button(message.isSaved ? "Remove from saved" : "Save", action: filed(onSave))
            Button("Archive", action: filed(onArchive))
        }
    }

    // MARK: Menu
    //
    // One menu, two entry points, identical content: the long press and the
    // ellipsis. "Mark unread" and "Mute this sender" are deliberately absent —
    // neither is backed by anything in the store, and a visible control that
    // does nothing is worse than an absent one.

    @ViewBuilder private var menuItems: some View {
        Button(message.isSaved ? "Unsave" : "Save",
               systemImage: message.isSaved ? "bookmark.fill" : "bookmark",
               action: filed(onSave))
        if !message.isPromotion {
            Button("Reply", systemImage: "arrowshape.turn.up.left", action: onReply)
            Button("Forward", systemImage: "arrowshape.turn.up.right", action: onForward)
        }
        Button("Discuss", systemImage: "sparkles", action: onDiscuss)
        Button("Copy quote", systemImage: "doc.on.doc") {
            UIPasteboard.general.string = message.quote ?? message.snippet
        }
        Divider()
        if message.isPromotion {
            Button("Unsubscribe", systemImage: "xmark",
                   role: .destructive, action: requested(onUnsubscribe))
        }
        Button("Archive", systemImage: "archivebox",
               role: .destructive, action: filed(onArchive))
    }

    /// The `ellipsis` was a plain `Image` — it advertised an action that did
    /// not exist. It is overlaid rather than placed inline because the tappable
    /// body of the post is a `Button`, and a control inside a button's label
    /// never gets its own taps.
    private var overflowMenu: some View {
        Menu { menuItems } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15))
                .foregroundStyle(Ink.secondary)
                .frame(width: Metric.tapTarget, height: Metric.tapTarget)
                .contentShape(.rect)
        }
        .accessibilityLabel("More actions")
        // Centred on the header's first line and on the gutter, from the
        // tokens rather than by eye.
        .padding(.trailing, Metric.gutter)
        .padding(.top, Space.xl + Metric.avatar / 2 - Metric.tapTarget / 2)
    }

    /// Wraps a filing action so it carries its own commit cue. Save and
    /// archive mean "that state now holds" the instant the finger lifts, so
    /// they share one cue — punctuation on a loud visual event, not the news.
    ///
    /// Unsubscribe used to route through here and must not: it is a network
    /// operation that opens a tray and can fail minutes later, so a commit cue
    /// at tap asserts a state that has not been reached. `requested()` marks
    /// the intent instead, and `needsYou()` reports the failure if it comes.
    ///
    /// The swipe path deliberately does NOT route through this either: the
    /// threshold cue already reported that decision.
    private func filed(_ action: @escaping () -> Void) -> () -> Void {
        { Haptics.commit(); action() }        // H3 / H4
    }

    /// An asynchronous request leaving the device. No cue — the tray appearing
    /// is the acknowledgement, and the outcome speaks for itself later.
    private func requested(_ action: @escaping () -> Void) -> () -> Void {
        action
    }

    // MARK: Content

    /// One card. There is no second layout.
    ///
    /// The feed used to have three: a lead, a standard, and a 44pt compact row
    /// for anything broadcast. The compact row could not hold a picture, an
    /// action row, or a summary, so most of a real mailbox — which is mostly
    /// broadcast — rendered as a list of subject lines sitting inside a feed
    /// of posts, and the two never read as the same product.
    ///
    /// The design skills allow variation across a repeated unit but not this
    /// kind: "Do not make every row visually independent if they are clearly
    /// part of one list. Repeated components should feel almost musical."
    /// Variation now comes from what a message actually has — a picture, a
    /// thing to click — not from a template chosen for it in advance.
    @ViewBuilder private var content: some View {
        if isPromoPost { promo } else { standard }
    }

    /// A promotion that came with its own picture.
    ///
    /// Marketing mail is the one genre where a brand paid somebody to design
    /// the thing, and the standard card throws all of that away: it crops the
    /// image into a band, puts our pull quote above it and our summary below,
    /// and what survives is our reading of an advert rather than the advert.
    ///
    /// Promotions without a picture are NOT this. There is nothing to lead
    /// with, so they stay on the standard card — the same rule the rest of the
    /// product uses, that the shape follows what the message actually is.
    /// The words under a promotion's picture, and there are always words.
    ///
    /// The model's pulled line when it has written one. Otherwise the subject,
    /// which is the sender's own text and is always present — the same trust
    /// anchor the quote is, just not chosen by us. Nothing here is invented:
    /// if the model has not read the mail yet, the card shows what the sender
    /// themselves put at the top of it rather than a guess or a blank.
    private var promoCaption: String {
        if let quote = message.quote, !quote.isEmpty { return quote }
        let subject = message.subject.trimmingCharacters(in: .whitespacesAndNewlines)
        if !subject.isEmpty { return subject }
        // No subject either — a real, if rare, piece of bulk mail. The snippet
        // is the last verbatim thing available.
        return message.snippet.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isPromoPost: Bool {
        guard message.isPromotion else { return false }
        if case .media(let urls) = message.shape { return !urls.isEmpty }
        return false
    }

    /// The card, in one piece and in one order.
    ///
    /// Every seam has exactly one owner of vertical space — `spacing: 0` plus
    /// a single `.padding(.top:)` per element — because a VStack spacing plus
    /// per-element padding produces the compound margin the skills warn about,
    /// where two individually correct values make an incorrect relationship.
    ///
    /// The gaps are a three-level ladder rather than one repeated value, which
    /// is what does the grouping now that the post has no fill, no radius and
    /// no border to do it. Equal gaps everywhere erase structure:
    ///
    ///   kicker -> quote      4   tightest in the card. The kicker labels the
    ///                            quote, so it has to bind downward; at the
    ///                            same gap as the one above it, it read as
    ///                            part of the sender's metadata instead.
    ///   quote -> picture    12   associative
    ///   picture -> summary  12   associative
    ///   header -> kicker    20   separating
    ///   summary -> CTA      20   separating
    ///   CTA -> actions      20   separating
    ///   card padding        20   with the hairline, the component boundary
    private var standard: some View {
        // NOT a Button. A Button's label spanning the whole card holds the
        // touch long enough that the scroll view never claims it, so the feed
        // only scrolled from the masthead and from the 3-dot overflow — the
        // two places that were not inside this control. The tap is attached at
        // the post's root instead, where a plain TapGesture is cancelled by a
        // scroll the moment the finger moves.
        VStack(alignment: .leading, spacing: 0) {
            header
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityHidden(true)

            KickerLabel(message.kicker)
                .padding(.horizontal, Metric.gutter)
                .padding(.top, Space.xl)
                .accessibilityHidden(true)

            // The one thing on this card the model did not write.
            Group {
                if message.kicker == .original {
                    VStack(alignment: .leading, spacing: Space.sm) {
                        Text(message.subject).typeStyle(Style.quote).foregroundStyle(Ink.primary).lineLimit(3)
                        Text(message.snippet).typeStyle(Style.bodySmall).foregroundStyle(Ink.secondary).lineLimit(3)
                    }
                } else if message.isInterpreting && message.quote == nil {
                    CaretLine(label: "Reading this one\u{2026}")
                } else if let quote = message.quote {
                    quoteText(quote, ink: message.isRead ? metaInk : Ink.primary)
                } else if case .degraded = message.shape {
                    degradedLine
                }
            }
            .padding(.horizontal, Metric.gutter)
            .padding(.top, Space.xs)
            .accessibilityHidden(true)

            // Full bleed, deliberately, and never any other value. The photo
            // and the hairline are the only two things that own the screen
            // edge; the text owns the gutter. A third inset between them would
            // be the near-alignment that reads as a mistake rather than a
            // choice.
            if case .media(let urls) = message.shape, let picture = urls.first {
                pictureBand(picture)
                    .padding(.top, Space.md)
                    .accessibilityHidden(true)
            }

            if let summary = message.summary {
                SummaryBlock(text: summary, emphasised: message.kicker == .possibleScam)
                    .padding(.horizontal, Metric.gutter)
                    .padding(.top, Space.md)
                    .accessibilityHidden(true)
            }

            // Breaks the gutter like the picture does, because it is the same
            // kind of thing: content the sender supplied, not a label we wrote.
            if !message.attachments.isEmpty {
                AttachmentCarousel(
                    attachments: message.attachments,
                    onOpenThread: onOpen,
                    onOpen: { file in
                        Task { await opener.open(file, authorization: nil) }
                    },
                    opening: openingID
                )
                .padding(.top, Space.lg)
            }

            // Shown whenever there is something to click, rather than only on
            // a density that no longer exists.
            if let label = message.actionLabel, !label.isEmpty {
                CTAButton(label: primaryActionTitle, isLink: primaryActionURL != nil,
                          action: performPrimaryAction)
                .padding(.horizontal, Metric.gutter)
                .padding(.top, Space.xl)
            }

            // The footer is in the spec, and taking it out was my call rather
            // than the design's. The argument for removing it — that swipe,
            // the context menu and the rotor already covered these six — lost
            // its first leg when the swipe had to go so the feed could scroll.
            // A long press is a discovery problem and the rotor is not a route
            // most people have, so this is the only visible way to act on a
            // post without opening it.
            ActionRow(
                message: message,
                onReply: onReply,
                onDiscuss: onDiscuss,
                onForward: onForward,
                onSave: onSave,
                onArchive: onArchive,
                onUnsubscribe: onUnsubscribe,
                onReact: onReact,
                onInteractionChanged: onSwiping
            )
            .padding(.horizontal, Metric.gutter)
            .padding(.top, Space.xl)
        }
        .padding(.vertical, Space.xl)
    }

    // MARK: Promotion — Instagram's order, with our last line

    /// Picture first and edge to edge, the action attached to the bottom of
    /// it, then the words. Instagram's anatomy, because Instagram solved this
    /// exact problem: a designed image that wants to lead, and a caption that
    /// has to say something without competing with it.
    ///
    /// One departure from Instagram, and it is deliberate: the action row goes
    /// *last*, below the caption, where Instagram puts the caption last. The
    /// row is this product's one constant — the control you reach for should
    /// never be in a different place twice — and consistency across the feed
    /// outranks fidelity to another app's layout.
    private var promo: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityHidden(true)

            if case .media(let urls) = message.shape, let picture = urls.first {
                PromoMedia(url: picture)
                    .padding(.top, Space.lg)
                    .accessibilityHidden(true)
            }

            if let label = message.actionLabel, !label.isEmpty {
                CTAStrip(label: primaryActionTitle, isLink: primaryActionURL != nil,
                         action: performPrimaryAction)
            }

            // The sender's own line, as a caption. Their name leads it the way
            // a handle leads an Instagram caption — it is the same sentence,
            // and splitting it into two blocks would invent a hierarchy the
            // words do not have.
            //
            // ALWAYS present. This block used to be `if let quote`, and on a
            // promotion the model had not read yet that left a photograph, six
            // icons and not one word about what had arrived — a card that
            // cannot be understood at all. A picture is the message only when
            // there is also a sentence saying whose it is and what it wants.
            // Every other card in the product guarantees a line; this one now
            // does too.
            //
            // Concatenated rather than two views in an HStack, so the sender's
            // name and their sentence wrap as one paragraph — the name is the
            // first words of the caption, not a label beside it. `.typeStyle`
            // returns a View and cannot be joined, so the two runs take the
            // style's parts directly.
            (Text(message.sender.displayName)
                .font(Style.sender.font)
                .tracking(Style.sender.tracking)
                + Text("  ")
                + Text(promoCaption)
                .font(Style.bodySmall.font)
                .tracking(Style.bodySmall.tracking))
                .lineSpacing(Style.bodySmall.lineSpacing)
                .foregroundStyle(message.isRead ? metaInk : Ink.primary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Metric.gutter)
                .padding(.top, Space.lg)
                .accessibilityHidden(true)

            // Still the machine's voice, still mono, just no longer boxed —
            // a ruled panel under an advert reads as a second advert.
            //
            // When there is no read yet, this says so rather than going blank.
            // Nothing is ever invented to fill it.
            Group {
                if let summary = message.summary, !summary.isEmpty {
                    Text(summary)
                        .typeStyle(Style.monoCaption)
                        .foregroundStyle(Ink.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if message.isInterpreting {
                    CaretLine(label: "Reading this one\u{2026}")
                }
            }
            .padding(.horizontal, Metric.gutter)
            .padding(.top, Space.sm)
            .accessibilityHidden(true)

            ActionRow(
                message: message,
                onReply: onReply,
                onDiscuss: onDiscuss,
                onForward: onForward,
                onSave: onSave,
                onArchive: onArchive,
                onUnsubscribe: onUnsubscribe,
                onReact: onReact,
                onInteractionChanged: onSwiping
            )
            .padding(.horizontal, Metric.gutter)
            .padding(.top, Space.xl)
        }
        .padding(.vertical, Space.xl)
    }

    // MARK: Header — identity on the left, controls on the right

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(alignment: .top, spacing: Space.md) {
                AvatarView(sender: message.sender, size: Metric.avatar)
                    .frame(minWidth: Metric.tapTarget, minHeight: Metric.tapTarget)
                    .contentShape(.rect)
                    .highPriorityGesture(TapGesture().onEnded { onProfile() })
                    .accessibilityLabel("\(message.sender.displayName), open sender")
                VStack(alignment: .leading, spacing: Space.xxs) {
                    senderName
                    meta
                    if let tag { tagChip(tag) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if message.isPromotion && !stackedHeader { unsubscribeButton }
                Color.clear.frame(width: Metric.tapTarget, height: Metric.tapTarget)
            }
            if message.isPromotion && stackedHeader { unsubscribeButton }
        }
        .padding(.horizontal, Metric.gutter)
    }

    private var unsubscribeButton: some View {
        Button(action: requested(onUnsubscribe)) {
            Text("Unsubscribe")
                .typeStyle(Style.chip)
                .foregroundStyle(Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Space.md)
                .padding(.vertical, Space.sm)
                .overlay(Capsule().strokeBorder(Ink.border, lineWidth: 1))
                .frame(minHeight: Metric.tapTarget)
                .contentShape(.rect)
        }
        .buttonStyle(TapStyle())
        .accessibilityLabel("Unsubscribe from \(message.sender.displayName)")
    }

    private var primaryActionURL: URL? {
        guard let url = message.actionURL,
              ["http", "https", "mailto", "tel"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url
    }

    private var primaryActionTitle: String {
        primaryActionURL == nil ? "Open original email" : (message.actionLabel ?? "Open link")
    }

    private func performPrimaryAction() {
        guard let url = primaryActionURL else { onOpen(); return }
        openURL(url) { accepted in if !accepted { linkFailed = true } }
    }

    /// Read changes the weight and nothing else. The name stays black — it is
    /// the quote that greys out, because what you have already read is the
    /// words, not who sent them.
    private var senderName: some View {
        Text(message.sender.displayName)
            .typeStyle(message.isRead ? Style.senderRead : Style.sender)
            .foregroundStyle(Ink.primary)
            .lineLimit(stackedHeader ? nil : 2)
            .fixedSize(horizontal: false, vertical: true)
            .truncationMode(.tail)
    }

    /// One mono line under the name.
    ///
    /// The thread count is spelled out rather than left as a bare numeral.
    /// "12m · 4" needs the reader to already know what the 4 counts; now that
    /// the line has a whole row to itself there is no reason to make them
    /// guess, and a count with no noun is the thing this product keeps
    /// promising not to print.
    private var meta: some View {
        Text(metaText)
            .typeStyle(Style.meta)
            .foregroundStyle(metaInk)
            .lineLimit(stackedHeader ? nil : 2)
            .fixedSize(horizontal: false, vertical: true)
            .monospacedDigit()
    }

    private var metaText: String {
        let stamp = message.receivedAt.feedStamp
        guard message.threadCount > 1 else { return stamp }
        return "\(stamp) · \(message.threadCount) emails in thread"
    }

    private func tagChip(_ tag: String) -> some View {
        Text(tag)
            .typeStyle(Style.chip)
            .foregroundStyle(Ink.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .overlay(
                RoundedRectangle(cornerRadius: Corner.chip, style: .continuous)
                    // Structural, so it strengthens with every other
                    // structural line under Increase Contrast.
                    .strokeBorder(Ink.rule(increasedContrast), lineWidth: 1)
            )
    }

    // MARK: Bodies

    /// The verbatim line, and the one thing on a post the model did not write.
    ///
    /// `chunk` events append characters into `message.quote`, and a `Text`
    /// whose string grows inside an observable mutation will animate if any
    /// enclosing animation is active — sliding as lines reflow. Growth is
    /// typing, not a transition, so the text opts out. The *container's*
    /// height change still animates with `Move.layout`, which is what keeps
    /// neighbouring posts from jumping: one dominant event, one supporting one.
    private func quoteText(_ quote: String, ink: Color) -> some View {
        // The opening quote mark hangs into the margin so the reading edge
        // lands on the "A" of "Amount", not on the punctuation before it.
        // Optically-aligned text against a mathematically-aligned kicker is
        // the near-miss that reads as a bug in a card this precise.
        //
        // Expressed as a fraction of the current size rather than a constant,
        // so it survives Dynamic Type: a magic -6 derived from 26pt is wrong
        // at every other size. DM Sans's left side bearing on the curly quote
        // is a shade over a quarter of its em.
        //
        // The glyphs are ours; everything between them is the sender's and
        // passes through untouched — no smart-quote substitution, no
        // normalisation. A verbatim pull is only worth having if it is
        // verbatim.
        Text("\u{201C}\(quote)\u{201D}")
            .typeStyle(Style.quote)
            .foregroundStyle(ink)
            .lineLimit(3)
            .padding(.leading, -Style.quote.hangingIndent)
            .transaction { $0.animation = nil }
    }

    /// Interpretation failed. Says so rather than inventing a line.
    private var degradedLine: some View {
        Text("Couldn\u{2019}t read this one.")
            .typeStyle(Style.quote)
            .foregroundStyle(metaInk)
            .lineLimit(2)
    }

    /// The email's own photograph, or the sender's generated stand-in.
    ///
    /// The container's height is set by an empty shape and the image fills it
    /// from behind: `.aspectRatio(_, contentMode: .fill)` on an AsyncImage may
    /// return something larger than the space offered, which is how a tall
    /// picture once grew until it took the whole screen.
    ///
    /// The box is reserved before the bytes arrive, so the action row below it
    /// never jumps when a picture lands mid-scroll.
    private func pictureBand(_ url: URL) -> some View {
        Color.clear
            .aspectRatio(Metric.mediaAspectWide, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay {
                CachedRemoteImage(url: url, cacheKey: url == message.heroImageURL
                    ? SenderIdentityStore.shared.imageKey(for: message.sender.address, role: "hero")
                    : "mail:\(message.mailboxID):\(message.id):picture") {
                    heroGround
                }
            }
            .clipped()
    }


    /// Marketing mail is already designed, so the AI steps back and we render
    /// their own first 1:1 section rather than reinterpreting it.
    private func htmlBody(_ url: URL) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            KickerLabel(message.kicker).padding(.horizontal, Metric.gutter)

            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Rectangle().fill(Ink.surfaceTertiary)
            }
            .aspectRatio(Metric.htmlAspect, contentMode: .fill)
            .frame(maxWidth: .infinity)
            .clipped()

            Text("SENDER\u{2019}S OWN LAYOUT  ·  NOT INTERPRETED")
                .typeStyle(Style.chip)
                .foregroundStyle(Ink.secondary)
                .padding(.horizontal, Metric.gutter)
        }
    }


    /// The colour the generator extracted from the image itself, so the space
    /// it will occupy already belongs to that sender before the bytes arrive.
    private var heroGround: some View {
        Rectangle().fill(
            message.heroBackground
                .flatMap { UInt32($0.dropFirst(($0.hasPrefix("#") ? 1 : 0)), radix: 16) }
                .map { Color(hex: $0) } ?? Ink.surfaceTertiary
        )
    }

    private func carouselBody(_ items: [Attachment]) -> some View {
        VStack(alignment: .leading, spacing: Space.md) {
            VStack(alignment: .leading, spacing: Space.sm) {
                KickerLabel(message.kicker)
                if let quote = message.quote {
                    quoteText(quote, ink: Ink.primary)
                }
                if let summary = message.summary {
                    SummaryBlock(text: summary, emphasised: false)
                }
            }
            .padding(.horizontal, Metric.gutter)

            AttachmentCarousel(
                attachments: items,
                onOpenThread: onOpen,
                onOpen: { file in
                    Task { await opener.open(file, authorization: nil) }
                },
                opening: openingID
            )
        }
    }

    private func quotedBody(_ quoted: QuotedMessage) -> some View {
        VStack(alignment: .leading, spacing: Space.md) {
            VStack(alignment: .leading, spacing: Space.sm) {
                KickerLabel(message.kicker)
                if let quote = message.quote {
                    quoteText(quote, ink: Ink.primary)
                }
                if let summary = message.summary {
                    SummaryBlock(text: summary, emphasised: false)
                }
            }
            QuotedCard(quoted: quoted, onProfile: onProfile)
        }
        .padding(.horizontal, Metric.gutter)
    }

    /// Interpretation failed. The quote slot is suppressed, never filled with
    /// a guess — and tapping still opens the real message.
    private var degradedBody: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            KickerLabel(.notRead)
            Text(message.subject)
                .typeStyle(Style.body)
                .foregroundStyle(Ink.primary)
                .lineLimit(2)
            Text(message.snippet)
                .typeStyle(Style.bodySmall)
                .foregroundStyle(Ink.secondary)
                .lineLimit(2)
        }
        .padding(.horizontal, Metric.gutter)
    }



    /// Spoken in the order it is read, and — crucially — with the quote
    /// announced as a quotation. The verbatim line is the one thing on a post
    /// the AI did not write, and a VoiceOver user has to be able to tell.
    private var accessibilityLabel: String {
        var parts = ["\(message.sender.displayName), \(message.kicker.rawValue.lowercased())"]
        if message.kicker == .original { parts += [message.subject, message.snippet] }
        // In a unified feed, which account a message landed in is information,
        // not decoration.
        if let tag { parts.append("in \(tag)") }
        if let quote = message.quote {
            parts.append("They wrote, quote, \(quote), end quote")
        }
        if let summary = message.summary {
            parts.append("Our summary: \(summary)")
        }
        if message.threadCount > 1 {
            parts.append("\(message.threadCount) in thread")
        }
        parts.append(message.receivedAt.spokenStamp)
        return parts.joined(separator: ". ")
    }

    /// The caret is `accessibilityHidden`, so the post has to carry the status
    /// itself — otherwise a VoiceOver user is told nothing at all about a card
    /// that is visibly still being written.
    private var accessibilityValue: String {
        if message.isInterpreting && message.quote == nil { return "Still being read" }
        return message.isRead ? "Read" : "Unread"
    }
}

// MARK: - Kicker
//
// The intent, stated rather than hued. This is what stands in for an accent
// colour: scan the left gutter alone and you can read the feed.

struct KickerLabel: View {
    let kicker: Kicker
    init(_ kicker: Kicker) { self.kicker = kicker }

    var body: some View {
        // Every kicker is black, NOT READ included. The state is carried by
        // the word, which is why there are eleven of them — greying the
        // awkward ones would hide exactly the posts worth noticing.
        Text(kicker.rawValue)
            .typeStyle(Style.kicker)
            .foregroundStyle(Ink.primary)
    }
}

// MARK: - Summary
//
// Mono is the machine's voice, and it is always a margin rule — a filled panel
// would be a card, a fill and a radius, inside a feed whose defining decision
// is that posts have neither.
//
// It is shown on every post now. It used to appear only at lead density or on
// a suspected scam, which meant the model's reasoning — the entire premise of
// the product — was hidden on most of the feed.

struct SummaryBlock: View {
    let text: String
    let emphasised: Bool

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        // One treatment, always a margin rule. The filled panel was a card —
        // a fill and a radius — sitting inside a feed whose defining decision
        // is that posts have neither, placed on the one post where that
        // contradiction was most visible.
        //
        // 13pt, not 16. DM Mono's fixed 0.6em advance means 16pt mono occupies
        // the width of 20pt sans, so the machine was set larger than the human
        // on every post. Smaller here is both quieter and more informative.
        Text(text)
            .typeStyle(Style.gloss)
            .foregroundStyle(emphasised ? Ink.primary : Ink.secondary)
            // Uncapped. Two lines put an ellipsis through the one sentence
            // the product exists to write — "Kyoku rebuilt their shake—30g
            // protein, 5g creatine, gentler fiber, plus a new reco…" is the
            // summary failing at exactly the job it was for.
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, Space.md)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(emphasised ? Ink.primary : Ink.rule(contrast == .increased))
                    .frame(width: emphasised ? 2 : 1)
            }
    }
}

// MARK: - CTA
//
// A hairline pill in the border grey, with a chevron.
//
// It was a full-black 1pt outline at sender weight, which made it the loudest
// mark on the card — sitting one line above an action row that already offers
// reply, forward and discuss. Two competing invitations, one of them shouting,
// and the quieter one was the row people actually need.
//
// The worry that a grey outline reads as disabled is real but does not apply
// here: a disabled control greys its *label*, and this label stays at full
// ink. The border is doing containment, not state. It now matches the weight
// of the unsubscribe chip it shares a card with, which is the right comparison
// — both are things the sender is offering rather than things the app asks of
// you.

struct CTAButton: View {
    let label: String
    var isLink = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.xs + 2) {
                Text(label)
                    .typeStyle(Style.bodySmall)
                    .foregroundStyle(Ink.primary)
                // Says it leaves for somewhere else, which the words alone do
                // not — half these labels are verbs that could equally mean
                // something happens in place.
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Ink.secondary)
            }
            .padding(.horizontal, Space.md + 2)
            .padding(.vertical, 9)
            .frame(minHeight: Metric.tapTarget)
            .overlay(
                Capsule().strokeBorder(Ink.border, lineWidth: 1)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(TapStyle())
        .accessibilityLabel(label)
        .accessibilityAddTraits(isLink ? .isLink : .isButton)
    }
}

// MARK: - CTA strip
//
// The promotion's action, attached to the bottom of its picture.
//
// A pill floating in the gutter under an edge-to-edge image reads as belonging
// to the card; a strip that touches the image reads as belonging to the *ad*,
// which is the truth — these words are the sender's, not ours. It is the one
// full-bleed control in the product, and it is full-bleed for the same reason
// the picture above it is: both are things the sender supplied.
//
// Only ever under media. Without a picture there is nothing to attach to, and
// a grey bar hanging in white is just a button that lost its shape — those
// promotions keep the ordinary `CTAButton`.

struct CTAStrip: View {
    let label: String
    var isLink = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.md) {
                Text(label)
                    .typeStyle(Style.sender)
                    .foregroundStyle(Ink.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Ink.secondary)
            }
            .padding(.horizontal, Metric.gutter)
            .padding(.vertical, Space.md + 2)
            .frame(minHeight: Metric.tapTarget)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Ink.surfaceTertiary)
            .contentShape(.rect)
        }
        .buttonStyle(TapStyle())
        .accessibilityLabel(label)
        .accessibilityAddTraits(isLink ? .isLink : .isButton)
    }
}

// The streaming caret used to be declared here, and again in the unsubscribe
// tray, and again in Discuss — three near-identical implementations of one
// signal, all with the same craft defect (a 530ms ramp on a 530ms hold, which
// never rests and reads as a pulse). It now lives once, in `Caret.swift`.

// MARK: - Date

extension Date {
    /// What VoiceOver says. "2h" is announced as "two h".
    var spokenStamp: String {
        let seconds = Date.now.timeIntervalSince(self)
        if seconds < 60 { return "just now" }
        if seconds < 3600 {
            let m = Int(seconds / 60)
            return m == 1 ? "1 minute ago" : "\(m) minutes ago"
        }
        if seconds < 86_400 {
            let h = Int(seconds / 3600)
            return h == 1 ? "1 hour ago" : "\(h) hours ago"
        }
        let d = Int(seconds / 86_400)
        return d == 1 ? "yesterday" : "\(d) days ago"
    }

    /// Relative and short. Absolute timestamps are for the thread, not the feed.
    var feedStamp: String {
        let seconds = Date.now.timeIntervalSince(self)
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        if seconds < 86_400 { return "\(Int(seconds / 3600))h" }
        if seconds < 7 * 86_400 { return "\(Int(seconds / 86_400))d" }
        return formatted(.dateTime.month(.abbreviated).day())
    }

    /// The time of day, for a turn in a conversation.
    ///
    /// A thread is read in clock time, not elapsed time. "4:32 PM" places a
    /// message against the rest of your day; "2 hours ago" only places it
    /// against the moment you happened to open the app, and stops being true
    /// while you are looking at it.
    var clockStamp: String {
        formatted(.dateTime.hour().minute())
    }

    /// The label that divides one day from the next in a thread.
    var threadDayStamp: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(self) { return "Today" }
        if calendar.isDateInYesterday(self) { return "Yesterday" }
        if Date.now.timeIntervalSince(self) < 7 * 86_400 {
            return formatted(.dateTime.weekday(.wide))
        }
        return formatted(.dateTime.month(.abbreviated).day())
    }
}

#Preview {
    ScrollView {
        LazyVStack(spacing: 0) {
            ForEach(Sample.messages) { PostView(message: $0) }
        }
    }
}
