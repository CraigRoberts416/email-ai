import SwiftUI

/// Left-cluster acts on the message, right-cluster files it. Acting is black;
/// filing is `Ink.secondary` at the same 17pt. The size stays level because
/// the file draws them level, but a row of six identical glyphs states that
/// answering someone and putting them away are the same act, and they are
/// not. Colour carries that step; size does not. Counts sit beside their glyph in mono rather than inside a pill:
/// a bare count reads as information, a pill reads as a badge demanding
/// attention.
///
/// Every glyph here is a real 44 × 44 target and every one of them does
/// something. Both were untrue before: the targets were 26.4pt wide at every
/// type size, and "React" was wired to an empty closure.
struct ActionRow: View {
    let message: Message
    var onReply: () -> Void = {}
    var onDiscuss: () -> Void = {}
    var onForward: () -> Void = {}
    var onSave: () -> Void = {}
    var onArchive: () -> Void = {}
    var onUnsubscribe: () -> Void = {}
    /// Nil clears it.
    var onReact: (String?) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    @State private var picking = false
    /// Which reaction is under the finger mid-drag.
    @State private var focus: Int?

    /// Zero, because the targets already carry the spacing.
    ///
    /// Each glyph sits in its own 44pt box, so butting the boxes together
    /// still puts 44pt between glyph centres — comfortably more than the
    /// smallest distance a finger can distinguish, and exactly the pitch the
    /// design was drawn at. Adding 16 on top of that pushed the centres to 60
    /// and spread four related icons across 224pt, which stopped reading as a
    /// group and started reading as a toolbar.
    ///
    /// The targets themselves do NOT shrink. The drawn row got tighter; the
    /// touchable row did not, which is the whole point of separating the two.
    private var spacing: CGFloat { 0 }
    /// At accessibility sizes no arrangement of five 44pt glyphs fits, so the
    /// row collapses to one labelled menu rather than clipping, or wrapping
    /// into something that no longer reads as a footer.
    private var collapsed: Bool { typeSize >= .accessibility1 }

    var body: some View {
        if collapsed {
            collapsedMenu
        } else {
            row
        }
    }

    /// Four on a ground, two outside it.
    ///
    /// Six evenly spaced glyphs read as six equal options, and they are not:
    /// four of them act on the conversation and two file it away. Spacing
    /// alone was not enough to say so — a wider gap in a row of identical
    /// marks reads as a layout accident. A soft ground under the acting four
    /// makes the grouping structural, and the filing two then need no
    /// container of their own because being *outside* one is the statement.
    ///
    /// This is the one place the product reintroduces a container it removed
    /// on purpose elsewhere. It earns it by carrying a distinction the feed
    /// cannot otherwise make.
    private var row: some View {
        HStack(spacing: 0) {
            // The same four actions on every post, promotion or not.
            //
            // Unsubscribe used to take this row's first slots on promotional
            // mail, which made a marketing post structurally different from
            // every other one — the opposite of one card — and put a
            // list-management control in the row that acts on the
            // conversation. It lives in the header now, next to the sender it
            // actually concerns.
            HStack(spacing: spacing) {
                react
                // `arrow.turn.up.left/right`, read from the glyphs in the file
                // rather than picked by eye — arrowshape is the filled-body
                // arrow and this row is drawn in the thin one.
                actOn("arrow.turn.up.left", label: "Reply", action: onReply)
                actOn("arrow.turn.up.right", label: "Forward", action: onForward)
                discuss
            }
            .padding(.horizontal, Space.sm + 2)
            .background(Ink.surfaceTertiary, in: Capsule())
            // The picker is drawn from the acting group so it can be aligned
            // to the react target's own leading edge, and lifted above the row
            // rather than over it.
            .overlay(alignment: .bottomLeading) { picker }

            Spacer(minLength: Space.md)

            file(message.isSaved ? "bookmark.fill" : "bookmark", label: "Save", action: onSave)
            file("archivebox", label: "Archive", action: onArchive)
        }
    }

    /// At accessibility sizes no arrangement of six 44pt targets fits, so the
    /// row collapses to one labelled menu rather than clipping or wrapping
    /// into something that no longer reads as a footer.
    private var collapsedMenu: some View {
        Menu {
            Button("Reply", systemImage: "arrowshape.turn.up.left", action: onReply)
            Button("Forward", systemImage: "arrowshape.turn.up.right", action: onForward)
            Button("Discuss", systemImage: "sparkles", action: onDiscuss)
            Menu("React") {
                ForEach(Reaction.all) { reaction in
                    Button("\(reaction.emoji)  \(reaction.label)") { onReact(reaction.emoji) }
                }
                if message.reaction != nil {
                    Button("Remove reaction", role: .destructive) { onReact(nil) }
                }
            }
            Button(message.isSaved ? "Unsave" : "Save",
                   systemImage: message.isSaved ? "bookmark.fill" : "bookmark", action: filed(onSave))
            Button("Archive", systemImage: "archivebox", action: filed(onArchive))
        } label: {
            HStack(spacing: Space.xs) {
                Text("Actions").typeStyle(Style.bodySmall)
                Image(systemName: "chevron.down").font(.system(size: 11))
            }
            .foregroundStyle(Ink.primary)
            .frame(minHeight: Metric.tapTarget, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
    }

    /// Discuss, carrying the thread's message count.
    ///
    /// The spec's AI Button is a glyph plus a text layer named "Message
    /// Count", so the number is the size of the thread you would be asking
    /// about. It is shown only when there is more than one message: a "1"
    /// beside every single-message post is noise, and a 0 would be a count of
    /// something that does not exist.
    @ViewBuilder private var discuss: some View {
        Button(action: onDiscuss) {
            HStack(spacing: Space.xxs) {
                Image(systemName: "sparkles")
                    .font(.system(size: Metric.iconAction))
                if message.threadCount > 1 {
                    Text("\(message.threadCount)")
                        .typeStyle(Style.monoMicro)
                        .monospacedDigit()
                }
            }
            // Acting, so black — it sits on the ground with the other three.
            .foregroundStyle(Ink.primary)
            .frame(minWidth: Metric.tapTarget, minHeight: Metric.tapTarget)
            .contentShape(.rect)
        }
        .buttonStyle(TapStyle())
        .accessibilityLabel(
            message.threadCount > 1
                ? "Discuss, \(message.threadCount) emails in thread"
                : "Discuss"
        )
    }

    /// React.
    ///
    /// It marks the message here and sends nothing. A reaction that quietly
    /// emailed a thumbs-up to the sender would be the app speaking in the
    /// user's name from a single tap on a scrolling feed, and nothing else in
    /// this product does that — Send has a composer and an undo window in
    /// front of it. If reactions should reach the other person, that wants the
    /// same treatment rather than this control.
    ///
    /// Once set, the chosen emoji replaces the glyph: the state is the mark
    /// itself, which is the cheapest possible indicator and cannot disagree
    /// with the thing it reports.
    @ViewBuilder private var react: some View {
        Group {
            if let reaction = message.reaction {
                Text(reaction).font(.system(size: Metric.iconAction))
            } else {
                Image(systemName: "face.smiling")
                    .font(.system(size: Metric.iconAction))
                    .foregroundStyle(Ink.primary)
            }
        }
        .frame(width: Metric.tapTarget, height: Metric.tapTarget)
        .contentShape(.rect)
        .gesture(pickGesture)
        // Tap is a separate, simpler contract than the press-and-drag: open
        // the row, or clear a reaction that is already set. Attached after the
        // drag gesture so the drag wins when both could apply.
        .simultaneousGesture(
            TapGesture().onEnded {
                if picking {
                    close()
                } else if message.reaction != nil {
                    Haptics.commit()
                    onReact(nil)
                } else {
                    open()
                }
            }
        )
        .accessibilityLabel(reactionLabel)
        // VoiceOver cannot drag a dock, so the whole set is offered as named
        // actions instead. This is the only route for it, so it lists every
        // reaction rather than a representative few.
        .accessibilityActions {
            ForEach(Reaction.all) { reaction in
                Button(reaction.label) { onReact(reaction.emoji) }
            }
            if message.reaction != nil {
                Button("Remove reaction") { onReact(nil) }
            }
        }
    }

    private var reactionLabel: String {
        guard let reaction = message.reaction else { return "React" }
        let named = Reaction.label(for: reaction) ?? reaction
        return "Reacted \(named). Tap to clear, press and hold to change"
    }

    @ViewBuilder private var picker: some View {
        if picking {
            ReactionPicker(reactions: Reaction.all, focus: focus)
                // Clear of the row, and hung from the acting group's leading
                // edge so it rises out of the react target rather than from
                // the centre of the card.
                .offset(y: -(Metric.tapTarget + Space.md))
                .transition(
                    .scale(scale: 0.86, anchor: .bottomLeading)
                        .combined(with: .opacity)
                )
                .zIndex(1)
        }
    }

    /// Press, then drag across without lifting — one continuous gesture, which
    /// is what makes it feel like a dock rather than a menu.
    private var pickGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.18)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                guard case .second(true, let drag) = value else { return }
                if !picking { open() }
                guard let drag else { return }
                let next = hit(drag.location)
                if next != focus {
                    // One tick per item crossed. This is the only feedback
                    // that the thing under your finger changed, since your
                    // finger is covering it.
                    if next != nil { Haptics.detent() }
                    focus = next
                }
            }
            .onEnded { value in
                guard case .second(true, let drag) = value else { return }
                // Lifting off the row leaves the picker up so it can be
                // tapped — a press that opened something should not close it
                // again just because the finger did not travel.
                guard let drag, let index = hit(drag.location) else { return }
                Haptics.commit()
                onReact(Reaction.all[index].emoji)
                close()
            }
    }

    /// Which reaction a point in the react target's space is over, if any.
    ///
    /// Vertical distance matters as much as horizontal. Picking by x alone
    /// means dragging your thumb down the card and letting go still commits a
    /// reaction, when dragging away from a picker is how every control of this
    /// kind is cancelled. The band is generous — the finger is expected to
    /// wander while crossing a row it cannot see under itself — but it ends.
    private func hit(_ point: CGPoint) -> Int? {
        guard Self.liveBand.contains(point.y) else { return nil }
        // The picker hangs from the acting group's leading edge and the react
        // target sits one ground-padding in from it, so the two coordinate
        // spaces differ by exactly that padding.
        return ReactionPicker.focus(at: point.x + Space.sm + 2, count: Reaction.all.count)
    }

    /// In the react target's own coordinate space, where 0 is its top edge.
    /// The picker sits above it, so the band reaches well into negative y and
    /// only a little below the target itself.
    private static let liveBand: ClosedRange<CGFloat> = -150...60

    private func open() {
        Haptics.announce()
        withAnimation(reduceMotion ? nil : Move.crisp) {
            picking = true
            focus = nil
        }
    }

    private func close() {
        withAnimation(reduceMotion ? nil : Move.exit) {
            picking = false
            focus = nil
        }
    }

    /// Acting on the message.
    private func actOn(
        _ systemName: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        icon(systemName, size: Metric.iconAction, tint: Ink.primary, label: label, action: action)
    }

    /// Filing it away.
    private func file(
        _ systemName: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        icon(systemName, size: Metric.iconAction, tint: Ink.secondary, label: label, action: action)
    }

    private func icon(
        _ systemName: String,
        size: CGFloat,
        tint: Color,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: filing(label) ? filed(action) : action) {
            Image(systemName: systemName)
                .font(.system(size: size))
                .foregroundStyle(tint)
                // Was `tapTarget * 0.6` — 26.4pt, under the 44pt minimum at
                // every type size rather than only the large ones.
                //
                // Centred, not leading. With the boxes butted together the
                // glyph's position inside its own box *is* the rhythm of the
                // row, and leading-aligned glyphs next to the centred ones in
                // `react` and `discuss` put two different pitches in one group.
                .frame(minWidth: Metric.tapTarget, minHeight: Metric.tapTarget)
                .contentShape(.rect)
        }
        .buttonStyle(TapStyle())
        .accessibilityLabel(label)
        // The glyph filling is the entire visible consequence of a save.
        .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace.offUp))
        .animation(Move.resolved(Move.crisp, reduceMotion), value: message.isSaved)
    }

    private func filing(_ label: String) -> Bool {
        label == "Save" || label == "Archive" || label == "Unsubscribe"
    }

    /// H3 / H4 — save, archive and unsubscribe all mean "that state now
    /// holds", so they share one cue. Save in particular is the one state
    /// change in the product with no visual consequence beyond a 17pt glyph
    /// filling: no navigation, no removal, no receipt. Touch is carrying real
    /// information there.
    ///
    /// Reply, Forward and Discuss open something instead, and the screen
    /// changing is their feedback — a cue on every navigation is the canonical
    /// over-buzz.
    private func filed(_ action: @escaping () -> Void) -> () -> Void {
        { Haptics.commit(); action() }
    }
}

// MARK: - Quoted card
//
// A forward has always been a quote-tweet; this just draws it that way.

struct QuotedCard: View {
    let quoted: QuotedMessage

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(spacing: Space.sm) {
                AvatarView(sender: quoted.sender, size: 20)
                Text(quoted.sender.displayName)
                    .typeStyle(Style.bodySmall)
                    .foregroundStyle(Ink.primary)
                Spacer(minLength: 0)
                Text(quoted.receivedAt.feedStamp)
                    .typeStyle(Style.meta)
                    .foregroundStyle(Ink.secondary)
            }

            Text(quoted.body)
                .typeStyle(Style.bodySmall)
                .foregroundStyle(Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let attachment = quoted.attachment {
                HStack(spacing: Space.sm) {
                    Image(systemName: "doc")
                        .font(.system(size: 13))
                        .foregroundStyle(Ink.secondary)
                    Text(attachment.filename)
                        .typeStyle(Style.bodySmall)
                        .foregroundStyle(Ink.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(attachment.sizeLabel)
                        .typeStyle(Style.chip)
                        .foregroundStyle(Ink.secondary)
                }
                .padding(.horizontal, Space.md)
                .padding(.vertical, Space.sm)
                .background(Ink.surfaceTertiary, in: RoundedRectangle(cornerRadius: Corner.sm, style: .continuous))
            }
        }
        .padding(Space.md + 2)
        .overlay(
            RoundedRectangle(cornerRadius: Corner.md, style: .continuous)
                // Structural.
                .strokeBorder(Ink.rule(contrast == .increased), lineWidth: 1)
        )
    }
}

// MARK: - Attachment carousel
//
// Paged horizontally with the next tile peeking, so it reads as swipeable
// without a hint. Documents render a real first page — a PDF thumbnail tells
// you whether it is the contract or the invoice; a file icon tells you nothing.
//
// The last tile is always "open the real thread", which preserves the original
// spec's carousel order: intent → attachments → open full email.

/// The attachments on one email, as a row you scroll.
///
/// Built to `EmailAttachments` in the component library.
///
/// The dots and the "1/4" counter are gone. They were stating a page number
/// for a row that does not page — the tiles are different widths and scroll
/// freely — and an indicator that reports something false is worse than no
/// indicator at all. What replaces them is the row itself: it starts on the
/// text gutter and runs off the right edge, so a tile cut by the screen is
/// the affordance. That is also one fewer piece of state to keep true.
struct AttachmentCarousel: View {
    let attachments: [Attachment]
    var onOpenThread: () -> Void = {}
    /// Tapping a file opens the file. It used to fall through to the card's
    /// own tap target, so a PDF opened the email instead — and the email did
    /// not show the PDF either.
    var onOpen: (Attachment) -> Void = { _ in }
    var opening: Attachment.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            // Counted, and it says what it counted. A bare number between
            // other controls has no referent.
            Text(attachments.count == 1 ? "1 ATTACHMENT" : "\(attachments.count) ATTACHMENTS")
                .typeStyle(Style.kicker)
                .foregroundStyle(Ink.secondary)
                .monospacedDigit()
                .padding(.horizontal, Metric.gutter)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: Space.md) {
                    ForEach(attachments) { attachment in
                        Button { onOpen(attachment) } label: {
                            AttachmentTile(attachment: attachment)
                                .opacity(opening == attachment.id ? 0.55 : 1)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Metric.gutter)
                .scrollTargetLayout()
            }
            // Rests with a tile on the gutter rather than wherever the flick
            // ended, so the column the eye reads down stays in one place.
            .scrollTargetBehavior(.viewAligned)
            .scrollClipDisabled()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            attachments.count == 1
                ? "1 attachment"
                : "\(attachments.count) attachments"
        )
    }
}


/// One attachment, to `AttachmentTile` in the library.
///
/// A file is one of the very few things in this product that earns a
/// container. The rule for a card is that posts are decontained; the rule for
/// an object you can open, save and send on its own is the opposite, and an
/// attachment is exactly that — it can move, be selected, be compared, and it
/// carries its own actions.
struct AttachmentTile: View {
    let attachment: Attachment

    private let edge: CGFloat = 132

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            // Square, always. The source images are every shape an email can
            // contain, and honouring each one turns a row into a ragged mess;
            // one ratio is what makes the set read as a set.
            Color.clear
                .frame(width: edge, height: edge)
                .overlay {
                    switch attachment.preview {
                    case .image(let url):
                        AsyncImage(url: url, transaction: Transaction(animation: Move.crossfade)) { phase in
                            if case .success(let image) = phase {
                                image.resizable().scaledToFill()
                            } else {
                                Ink.surfaceTertiary
                            }
                        }
                    case .document(let pages):
                        documentFace(pages: pages)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Corner.md, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.filename)
                    .typeStyle(Style.monoCaption)
                    .foregroundStyle(Ink.primary)
                    .lineLimit(1)
                    // The extension is the half that identifies the file, so
                    // the middle gives way rather than the end.
                    .truncationMode(.middle)
                Text(attachment.sizeLabel.uppercased())
                    .typeStyle(Style.monoMicro)
                    .foregroundStyle(Ink.tertiary)
            }
            .frame(width: edge, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(attachment.filename), \(attachment.sizeLabel)")
    }

    /// No thumbnail exists for a document, so the tile states what it is
    /// rather than drawing a fake page. The extension and the page count are
    /// both counted facts, which is why they are mono.
    private func documentFace(pages: Int) -> some View {
        VStack(spacing: Space.xs) {
            Text(attachment.filename.split(separator: ".").last.map { String($0).uppercased() } ?? "FILE")
                .typeStyle(Style.documentType)
                .foregroundStyle(Ink.primary)
            if pages > 0 {
                Text(pages == 1 ? "1 PAGE" : "\(pages) PAGES")
                    .typeStyle(Style.monoMicro)
                    .foregroundStyle(Ink.secondary)
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Ink.surfaceTertiary)
    }
}


/// A suggestion of the document's first page rather than a file-type badge.
private struct DocumentFirstPage: View {
    let pages: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array([0.5, 1, 1, 0.82, 1, 0.9, 0.4, 1, 0.95, 1, 0.66].enumerated()), id: \.offset) { index, width in
                Rectangle()
                    .fill(index == 0 ? Ink.primary : Ink.border)
                    .frame(width: 248 * width, height: index == 0 ? 10 : 6)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 26)
        .padding(.top, 30)
        .background(Ink.surface)
    }
}

private struct OpenThreadTile: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: Space.sm) {
                Image(systemName: "arrow.forward")
                    .font(.system(size: 22))
                Text("OPEN THE REAL THREAD")
                    .typeStyle(Style.kicker)
            }
            .foregroundStyle(Ink.primary)
            .frame(width: Metric.carouselTile, height: Metric.carouselTileHeight)
            .overlay(
                RoundedRectangle(cornerRadius: Corner.md, style: .continuous)
                    .strokeBorder(Ink.primary, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            )
        }
        .buttonStyle(.plain)
    }
}
