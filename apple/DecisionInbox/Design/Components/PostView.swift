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
    /// Reported at the start and end of a horizontal swipe so the feed can
    /// suppress the new-posts pill: a new object entering the frame under an
    /// active gesture competes with the dominant event.
    var onSwiping: (Bool) -> Void = { _ in }

    /// Which outcome the current drag has crossed into. Nil means the gesture
    /// is under the threshold and releasing would cancel.
    private enum Armed: Equatable { case save, archive }

    @State private var pressed = false
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
        // A custom DragGesture rather than `List.swipeActions`: `List` imposes
        // row insets, separators and a container fill, and the post's defining
        // decision is that it is decontained. The platform component's cost
        // here is a design regression.
        //
        // `.gesture`, NOT `.simultaneousGesture`. A simultaneous drag claims
        // the touch stream alongside the scroll view, which stops the scroll
        // from cancelling the reading surface's button — so every vertical
        // scroll also fired it and opened a thread. Arbitrated, the scroll
        // wins vertically and this never starts.
        .gesture(swipe)
        // Attached AFTER the drag gesture on purpose. A long press that then
        // moves cancels the menu's recogniser, so a slow swipe still works.
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
                defer { axis = nil; onSwiping(false) }
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
    @ViewBuilder private var overflowMenu: some View {
        if message.density != .compact {
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
            .padding(.top, Metric.postPaddingY + Metric.avatar / 2 - Metric.tapTarget / 2)
            .offset(x: dx)
        }
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

    @ViewBuilder private var content: some View {
        if case .compact = message.density {
            compactRow
        } else {
            standard
        }
    }

    private var standard: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            // Only the reading surface is the button. The action row keeps its
            // own buttons — a control inside a button's label never receives a
            // tap — and the pressed fill is lifted to the whole row so the
            // ground still changes as one object.
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: Space.lg) {
                    header

                    Group {
                        switch message.shape {
                        case .html(let url):       htmlBody(url)
                        case .media(let urls):     mediaBody(urls)
                        case .carousel(let items): carouselBody(items)
                        case .quoted(let quoted):  quotedBody(quoted)
                        case .degraded:            degradedBody
                        case .text:                textBody
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(PostPressStyle(pressed: $pressed))
            .accessibilityHidden(true)

            ActionRow(
                message: message,
                onReply: onReply, onDiscuss: onDiscuss, onForward: onForward,
                onSave: onSave, onArchive: onArchive, onUnsubscribe: onUnsubscribe
            )
            .padding(.horizontal, Metric.gutter)
            // Every internal gap is 16; the action row alone sits 24 off the
            // block above it, which is what keeps it reading as a footer
            // rather than as another line of content.
            .padding(.top, Space.sm)
        }
        .padding(.vertical, Metric.postPaddingY)
    }

    // MARK: Header — one identity line, Twitter-style

    private var header: some View {
        HStack(alignment: stackedHeader ? .top : .center, spacing: Space.md) {
            AvatarView(
                sender: message.sender,
                size: message.density == .compact ? Metric.avatarCompact : Metric.avatar,
                dimmed: message.density == .compact
            )

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
        Text("\u{201C}\(quote)\u{201D}")
            .typeStyle(Style.display)
            .foregroundStyle(ink)
            .lineLimit(3)
            .transaction { $0.animation = nil }
    }

    private var textBody: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            KickerLabel(message.kicker)

            if message.isInterpreting && message.quote == nil {
                CaretLine(label: "Reading this one\u{2026}")
            } else if let quote = message.quote {
                quoteText(quote, ink: message.isRead ? metaInk : Ink.primary)
            }

            if let summary = message.summary {
                SummaryBlock(text: summary, density: message.density, emphasised: message.kicker == .possibleScam)
            }

            if let label = message.actionLabel {
                CTAButton(label: label) {
                    if let url = message.actionURL { UIApplication.shared.open(url) }
                }
                .padding(.top, Space.xs)
            }
        }
        .padding(.horizontal, Metric.gutter)
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

    private func mediaBody(_ urls: [URL]) -> some View {
        VStack(alignment: .leading, spacing: Space.md) {
            VStack(alignment: .leading, spacing: Space.sm) {
                KickerLabel(message.kicker)
                if let quote = message.quote {
                    quoteText(quote, ink: Ink.primary)
                }
            }
            .padding(.horizontal, Metric.gutter)

            // The one place the gutter breaks.
            AsyncImage(url: urls[0], transaction: Transaction(animation: Move.crossfade)) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    // A missing image is not a broken card. The post drops back
                    // to text rather than showing a placeholder that means
                    // nothing to the reader.
                    Color.clear.frame(height: 0)
                default:
                    // Its own extracted ground, so nothing flashes white.
                    heroGround
                }
            }
            .aspectRatio(Metric.mediaAspect, contentMode: .fill)
            .frame(maxWidth: .infinity)
            .clipped()

            if let summary = message.summary {
                SummaryBlock(text: summary, density: message.density, emphasised: false)
                    .padding(.horizontal, Metric.gutter)
            }
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
                    SummaryBlock(text: summary, density: message.density, emphasised: false)
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
                    SummaryBlock(text: summary, density: message.density, emphasised: false)
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

    /// A broadcast that asks nothing: one row, a mono sender, one clause, and
    /// the two things you might do with it. No timestamp, no thread count, no
    /// overflow — a receipt does not earn an identity line.
    private var compactRow: some View {
        VStack(spacing: 0) {
            HStack(spacing: Space.md) {
                // Same split as a standard post: the reading surface is the
                // button, the filing glyphs stay their own controls, and the
                // pressed fill is reported up to the whole row.
                Button(action: onOpen) {
                    HStack(spacing: Space.md) {
                        AvatarView(
                            sender: message.sender,
                            size: Metric.avatarCompact,
                            dimmed: true
                        )

                        VStack(alignment: .leading, spacing: Space.xxs) {
                            Text(message.sender.displayName.uppercased())
                                .typeStyle(Style.compactSender)
                                .foregroundStyle(metaInk)
                                .lineLimit(1)
                            Text(message.summary ?? message.subject)
                                .typeStyle(Style.body)
                                .foregroundStyle(Ink.primary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: Space.sm)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(PostPressStyle(pressed: $pressed))
                .accessibilityHidden(true)

                // The one place the filing glyphs step down: a compact row is
                // already the quietest thing in the feed and should not carry
                // two black icons.
                compactAction(message.isSaved ? "bookmark.fill" : "bookmark", "Save", filed(onSave))
                compactAction("archivebox", "Archive", filed(onArchive))
            }
            .padding(.horizontal, Metric.gutter)
            .padding(.vertical, Space.md)
        }
    }

    private func compactAction(
        _ symbol: String, _ label: String, _ action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: Metric.iconFile))
                .foregroundStyle(metaInk)
                .frame(width: Metric.tapTarget, height: Metric.tapTarget)
                .contentShape(.rect)
        }
        .buttonStyle(TapStyle())
        .accessibilityLabel(label)
        // The bookmark filling is the entire visible consequence of a save, so
        // the glyph swap is the event. Reduce Motion gets a plain swap.
        .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace.offUp))
        .animation(Move.resolved(Move.crisp, reduceMotion), value: message.isSaved)
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
// Mono is the machine's voice. A filled panel at lead density; a margin rule
// everywhere else, because fill plus radius plus even padding reads as a code
// block rather than editorial gloss.

struct SummaryBlock: View {
    let text: String
    let density: Density
    let emphasised: Bool

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        if density == .lead {
            Text(text)
                .typeStyle(Style.ai)
                .foregroundStyle(Ink.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Space.md)
                .background(Ink.surfaceTertiary, in: RoundedRectangle(cornerRadius: Corner.md, style: .continuous))
        } else {
            Text(text)
                .typeStyle(Style.ai)
                .foregroundStyle(Ink.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, Space.md)
                .overlay(alignment: .leading) {
                    Rectangle()
                        // Structural, so it moves with every other structural
                        // line under Increase Contrast rather than leaving the
                        // feed's dividers to strengthen alone.
                        .fill(emphasised ? Ink.primary : Ink.rule(contrast == .increased))
                        .frame(width: emphasised ? 2 : 1)
                }
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
