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
    /// Reported at the start and end of a horizontal swipe so the feed can
    /// suppress the new-posts pill: a new object entering the frame under an
    /// active gesture competes with the dominant event.
    var onSwiping: (Bool) -> Void = { _ in }

    /// Which outcome the current drag has crossed into. Nil means the gesture
    /// is under the threshold and releasing would cancel.
    private enum Armed: Equatable { case save, archive }

    @State private var pressed = false
    /// The finger travelled during this touch, so its release is not a tap.
    /// The scroll view would normally cancel the button for us; running the
    /// swipe simultaneously is what takes that away, so it is restored here.
    @State private var dragged = false
    @State private var dx: CGFloat = 0
    @State private var armed: Armed?
    /// Latched on the first sample past 10pt and never revisited, so a swipe
    /// and a scroll can never fight over the same gesture.
    @State private var axis: Axis?
    @State private var committing: Armed?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.dynamicTypeSize) private var typeSize

    private var increasedContrast: Bool { contrast == .increased }
    /// `Ink.tertiary` measures 3.0:1 — below AA — and carries the `·`
    /// separators and the timestamp. Under Increase Contrast the meta has to
    /// strengthen with everything else or the post's grammar comes apart.
    private var metaInk: Color { increasedContrast ? Ink.secondary : Ink.tertiary }
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
        .offset(x: dx)
        // The action sits *behind* the post, in the gutter the post vacates —
        // as a background rather than a ZStack sibling so it takes the row's
        // own height instead of proposing to fill the viewport. Monochrome,
        // per the system's rule that state is carried by fill and shape and
        // never by hue: there is no red here.
        .background { swipeTrack }
        // The post slides out of its own row rather than over its neighbours'.
        .clipped()
        .contentShape(.rect)
        // The whole card opens the thread, and it is a TapGesture rather than
        // a Button for exactly one reason: a scroll cancels it. The inner
        // controls — avatar, CTA, action row — are real Buttons and still take
        // their own taps first, so this only catches the reading surface.
        .onTapGesture { onOpen() }
        // NO row-level DragGesture here, in either form. This was measured, not
        // reasoned about: with the same synthetic drag over the same feed, the
        // scroll offset reached 4681pt without it and exactly 0 with it —
        // arbitrated (`.gesture`) AND simultaneous. SwiftUI will not let a
        // drag on a row coexist with the scroll view's pan; `guard axis ==
        // .horizontal` stops this handler from acting but never returns the
        // touch, and there is no API to fail a gesture after the fact. Posts
        // cover the whole feed, so the feed did not scroll at all.
        //
        // Swipe-to-file is worth having, but not at the cost of scrolling a
        // feed. The route back is `List` + `.swipeActions`, where UIKit does
        // the arbitration properly — a real change, not a modifier. Until
        // then the action row carries these, which is where the spec had them.
        //
        // No haptic from us: `.contextMenu` fires the system's own lift cue and
        // ours would double it.
        .contextMenu { menuItems }
        .overlay(alignment: .topTrailing) { overflowMenu }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("Opens the thread")
        .accessibilityAddTraits(.isButton)
        // Combining children makes the post one readable element and drops
        // every button inside it, so the actions have to be re-offered by
        // hand. This is also the non-gesture route to anything a swipe does —
        // a drag-only path to archive would be a blocker.
        .accessibilityActions {
            Button("Open", action: onOpen)
            if message.isPromotion {
                Button("Unsubscribe", action: filed(onUnsubscribe))
            } else {
                Button("Reply", action: onReply)
                Button("Forward", action: onForward)
            }
            Button("Discuss", action: onDiscuss)
            Button("Open \(message.sender.displayName)", action: onProfile)
            Button(message.isSaved ? "Remove from saved" : "Save", action: filed(onSave))
            Button("Archive", action: filed(onArchive))
        }
    }

    // MARK: Swipe
    //
    // Trailing (right → left) archives: the dominant inward thumb direction,
    // and the platform-wide convention for "get rid of it". Leading saves:
    // additive, keeps the post, and inverts the destructive direction.

    private var swipe: some Gesture {
        DragGesture(minimumDistance: Move.Swipe.axisLatch, coordinateSpace: .local)
            .onChanged { value in
                // Any travel at all, on either axis. A vertical drag is a
                // scroll and must not also count as a tap on release.
                dragged = true
                if axis == nil {
                    axis = abs(value.translation.width)
                        > abs(value.translation.height) * Move.Swipe.axisRatio
                        ? .horizontal : .vertical
                    if axis == .horizontal {
                        // Prepared on the gesture's first sample, never on view
                        // appear — a prepared generator holds the Taptic Engine
                        // warm, and forty posts doing it on appear would hold it
                        // warm for the session.
                        Haptics.prepare()
                        onSwiping(true)
                    }
                }
                guard axis == .horizontal else { return }

                dx = resist(value.translation.width)
                let next: Armed? = abs(dx) < Move.Swipe.threshold
                    ? nil
                    : (dx < 0 ? .archive : .save)
                if next != armed {
                    armed = next
                    // H1 — the threshold is under the finger and therefore
                    // invisible, so touch is the only honest channel for it.
                    // Fires on disarm too, or a user who pulls back short gets
                    // no confirmation they escaped the commit.
                    Haptics.threshold()
                }
            }
            .onEnded { value in
                defer {
                    axis = nil
                    onSwiping(false)
                    // Cleared a turn later, never here: the button's action
                    // fires on this same touch-up, and it has to still see
                    // that the finger travelled.
                    Task { @MainActor in dragged = false }
                }
                guard axis == .horizontal else { return }

                // Velocity can commit early: a flick is a decision even when
                // the finger never reached the line.
                let flick = value.predictedEndTranslation.width - value.translation.width
                if let armed {
                    commit(armed, reported: true)
                } else if abs(flick) > Move.Swipe.flickDistance {
                    // The threshold was never crossed, so H1 never fired. One
                    // decision still owes exactly one cue, and this is the only
                    // place it can be paid.
                    commit(flick < 0 ? .archive : .save, reported: false)
                } else {
                    cancel()
                }
            }
    }

    /// Past `rubberBandAt` the sheet keeps moving but gives back less than the
    /// finger puts in, so the gesture has a floor without ever stopping dead.
    private func resist(_ raw: CGFloat) -> CGFloat {
        let cap = Move.Swipe.rubberBandAt
        guard abs(raw) > cap else { return raw }
        let over = abs(raw) - cap
        return (cap + over * Move.Swipe.rubberBand) * (raw < 0 ? -1 : 1)
    }

    /// - Parameter reported: whether H1 already fired for this decision. When
    ///   it did, nothing fires here — the threshold cue reported the decision
    ///   and the post leaving reports the outcome, so one gesture yields one
    ///   haptic.
    private func commit(_ direction: Armed, reported: Bool) {
        committing = direction
        armed = nil
        if !reported { Haptics.commit() }

        switch direction {
        case .archive:
            // The post is leaving. It travels off the edge it was swiped
            // toward and the row's height collapses in the SAME transaction —
            // the row leaves and the gap closes as one event, not two.
            withAnimation(Move.resolved(Move.commit, reduceMotion)) {
                // Reduce Motion: no lateral travel. The row crossfades out and
                // the height collapses. The outcome is identical; the journey
                // is what was making people ill.
                dx = reduceMotion ? 0 : -UIScreen.main.bounds.width
                onArchive()
            } completion: {
                // Only reached if this row is still mounted — the store
                // refused the archive, or this list keeps the post. Better a
                // snap back than an invisible row parked off-screen.
                dx = 0
                committing = nil
            }

        case .save:
            // Save keeps the post, so the sheet springs back. Flying it
            // off-screen would assert a removal that does not happen; the
            // bookmark filling is the outcome.
            onSave()
            withAnimation(Move.resolved(Move.commit, reduceMotion)) { dx = 0 }
            committing = nil
        }
    }

    private func cancel() {
        // Critically damped — a cancel that wobbles reads as a failed commit.
        // And silent: cancellation never fires a commit-class cue, and H1
        // already fired on the disarm crossing if the user retreated past it.
        withAnimation(Move.resolved(Move.settle, reduceMotion)) {
            dx = 0
            armed = nil
        }
    }

    /// The action revealed behind the post. The fill inversion *is* the armed
    /// signal, and it lands on the same frame as the threshold haptic.
    @ViewBuilder private var swipeTrack: some View {
        if dx != 0 || committing != nil {
            let archiving = committing.map { $0 == .archive } ?? (dx < 0)
            let isArmed = armed != nil || committing != nil
            let progress = min(1, abs(dx) / Move.Swipe.threshold)

            ZStack(alignment: archiving ? .trailing : .leading) {
                (isArmed ? Ink.primary : Ink.surfaceTertiary)

                HStack(spacing: Space.sm) {
                    Image(systemName: archiving ? "archivebox" : "bookmark")
                        .font(.system(size: Metric.iconAction))
                        // 0.86 → 1.0 interpolated on progress. Tracking, not
                        // animation: this follows the finger 1 : 1.
                        .scaleEffect(0.86 + 0.14 * progress)
                    if isArmed {
                        Text(archiving ? "ARCHIVE" : "SAVE").typeStyle(Style.kicker)
                    }
                }
                .foregroundStyle(isArmed ? Ink.onInverse : Ink.primary)
                .padding(.horizontal, Metric.gutter + Space.sm)
            }
            // The swipe's outcomes are re-offered in the Actions rotor and the
            // context menu; the track itself is furniture.
            .accessibilityHidden(true)
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
                   role: .destructive, action: filed(onUnsubscribe))
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
        .padding(.trailing, Metric.gutter - (Metric.tapTarget - 15) / 2)
        .padding(.top, Space.xl + Metric.avatar / 2 - Metric.tapTarget / 2)
    }

    /// Wraps a filing action so it carries its own commit cue. Save, archive
    /// and unsubscribe all mean "that state now holds", so they share one cue —
    /// punctuation on a loud visual event, not the news itself.
    ///
    /// The swipe path deliberately does NOT route through this: the threshold
    /// cue already reported that decision.
    private func filed(_ action: @escaping () -> Void) -> () -> Void {
        { Haptics.commit(); action() }        // H3 / H4
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
    private var content: some View { standard }

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
                if message.isInterpreting && message.quote == nil {
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
                AttachmentCarousel(attachments: message.attachments, onOpenThread: onOpen)
                    .padding(.top, Space.lg)
            }

            // Shown whenever there is something to click, rather than only on
            // a density that no longer exists.
            if let label = message.actionLabel, !label.isEmpty {
                CTAButton(label: label) {
                    if let url = message.actionURL { UIApplication.shared.open(url) }
                }
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
                onReact: onReact
            )
            .padding(.horizontal, Metric.gutter)
            .padding(.top, Space.xl)
        }
        .padding(.vertical, Space.xl)
    }

    // MARK: Header — one identity line, Twitter-style

    private var header: some View {
        HStack(alignment: stackedHeader ? .top : .center, spacing: Space.md) {
            Button(action: onProfile) {
                AvatarView(sender: message.sender, size: Metric.avatar)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(message.sender.displayName), open sender")

            // At accessibility sizes the identity line stacks: laid out
            // horizontally, a `lineLimit(1)` name beside a non-compressing
            // `· time · count` truncates the name to nothing while the
            // timestamp survives. The identity anchor must not lose to a
            // timestamp.
            if stackedHeader {
                VStack(alignment: .leading, spacing: Space.xxs) {
                    senderName
                    HStack(spacing: Space.xs + 2) { meta }
                    if let tag { tagChip(tag) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: Space.xs + 2) {
                    senderName.frame(maxWidth: .infinity, alignment: .leading)
                    meta
                }
                if let tag { tagChip(tag) }
            }

            // The slot the overflow menu is overlaid into. The control itself
            // sits outside the button so it can take its own taps.
            Color.clear.frame(width: 15, height: 15)
        }
        .padding(.horizontal, Metric.gutter)
    }

    /// Read changes the weight and nothing else. The name stays black — it is
    /// the quote that greys out, because what you have already read is the
    /// words, not who sent them.
    private var senderName: some View {
        Text(message.sender.displayName)
            .typeStyle(message.isRead ? Style.senderRead : Style.sender)
            .foregroundStyle(Ink.primary)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    @ViewBuilder private var meta: some View {
        Text("·").typeStyle(Style.separator).foregroundStyle(metaInk)
        Text(message.receivedAt.feedStamp)
            .typeStyle(Style.meta).foregroundStyle(metaInk)

        if message.threadCount > 1 {
            Text("·").typeStyle(Style.separator).foregroundStyle(metaInk)
            Text("\(message.threadCount)")
                .typeStyle(Style.meta).foregroundStyle(metaInk)
        }
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
                AsyncImage(url: url, transaction: Transaction(animation: Move.crossfade)) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        heroGround
                    }
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

            AttachmentCarousel(attachments: items, onOpenThread: onOpen)
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
            QuotedCard(quoted: quoted)
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
            .lineLimit(emphasised ? nil : 2)
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
// A black hairline, never grey — a grey outline reads as disabled.

struct CTAButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .typeStyle(Style.sender)
                .foregroundStyle(Ink.primary)
                .padding(.horizontal, Space.lg)
                .padding(.vertical, 9)
                .overlay(
                    Capsule().strokeBorder(Ink.primary, lineWidth: 1)
                )
        }
        .buttonStyle(TapStyle())
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
}

#Preview {
    ScrollView {
        LazyVStack(spacing: 0) {
            ForEach(Sample.messages) { PostView(message: $0) }
        }
    }
}
