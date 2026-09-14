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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    /// Raising every target to a real 44pt makes the row 5 × 44 wide before any
    /// gaps. With `Space.xl` between them that is 316pt against 361pt of usable
    /// width — tight, and gone the moment the type grows. The gaps give ground
    /// before the targets do.
    private var spacing: CGFloat { typeSize >= .xxxLarge ? Space.md : Space.xl }
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

    private var row: some View {
        HStack(spacing: spacing) {
            if message.isPromotion {
                // Nobody replies to a newsletter, so unsubscribe takes the slot.
                Button(action: filed(onUnsubscribe)) {
                    HStack(spacing: Space.xs) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13))
                        Text("Unsubscribe")
                            .typeStyle(Style.bodySmall)
                            .lineLimit(1)
                    }
                    .foregroundStyle(Ink.primary)
                    .padding(.horizontal, Space.md)
                    .padding(.vertical, 6)
                    .overlay(Capsule().strokeBorder(Ink.primary, lineWidth: 1))
                }
                .buttonStyle(TapStyle())

                actOn("sparkles", label: "Discuss", action: onDiscuss)
            } else {
                // "React" used to sit here calling an empty closure on every
                // non-promotional post. A visible control that does nothing is
                // worse than an absent one, and reactions need a product
                // decision before they need a motion one — so it is removed
                // rather than faked. Restoring it is a one-line change.
                actOn("arrowshape.turn.up.left", label: "Reply", action: onReply)
                actOn("arrowshape.turn.up.right", label: "Forward", action: onForward)
                actOn("sparkles", label: "Discuss", action: onDiscuss)
            }

            Spacer(minLength: 0)

            file(message.isSaved ? "bookmark.fill" : "bookmark", label: "Save", action: onSave)
            file("archivebox", label: "Archive", action: onArchive)
        }
    }

    private var collapsedMenu: some View {
        Menu {
            if message.isPromotion {
                Button("Unsubscribe", systemImage: "xmark", action: filed(onUnsubscribe))
            } else {
                Button("Reply", systemImage: "arrowshape.turn.up.left", action: onReply)
                Button("Forward", systemImage: "arrowshape.turn.up.right", action: onForward)
            }
            Button("Discuss", systemImage: "sparkles", action: onDiscuss)
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

    /// Acting on the message.
    private func actOn(
        _ systemName: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        icon(systemName, size: Metric.iconAction, tint: Ink.secondary, label: label, action: action)
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
                .frame(minWidth: Metric.tapTarget, minHeight: Metric.tapTarget, alignment: .leading)
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

struct AttachmentCarousel: View {
    let attachments: [Attachment]
    var onOpenThread: () -> Void = {}

    /// The dots used to read 1/N forever: `page` was declared and never
    /// written, and `.viewAligned` had no position binding. An indicator
    /// stating something false is worse than no indicator.
    @State private var scrolledID: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    private var page: Int { scrolledID ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: Space.sm) {
                    ForEach(Array(attachments.enumerated()), id: \.offset) { index, attachment in
                        AttachmentTile(attachment: attachment).id(index)
                    }
                    OpenThreadTile(action: onOpenThread).id(attachments.count)
                }
                .padding(.horizontal, Metric.gutter)
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $scrolledID)

            HStack(spacing: Space.xs + 2) {
                ForEach(0..<(attachments.count + 1), id: \.self) { index in
                    Circle()
                        .fill(index == page ? Ink.primary : Ink.rule(contrast == .increased))
                        .frame(width: 5, height: 5)
                }
                Spacer(minLength: 0)
                Text("\(page + 1)/\(attachments.count + 1)")
                    .typeStyle(Style.chip)
                    .foregroundStyle(Ink.secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, Metric.gutter)
            // No haptic on a page change. A flicked carousel is continuous and
            // frequent, and the dots already carry it — a detented picker would
            // earn `Haptics.detent()`; this does not.
            .animation(Move.resolved(Move.crisp, reduceMotion), value: page)
        }
    }
}

struct AttachmentTile: View {
    let attachment: Attachment

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch attachment.preview {
                case .image(let url):
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Rectangle().fill(Ink.surfaceTertiary)
                    }
                case .document(let pages):
                    DocumentFirstPage(pages: pages)
                }
            }
            .frame(width: Metric.carouselTile)
            // A floor rather than a fixed share: the footer sizes itself at
            // accessibility sizes and the preview takes whatever is left,
            // instead of the filename clipping against a hard 375pt tile.
            .frame(minHeight: Metric.carouselTileHeight * 0.5)
            .frame(maxHeight: .infinity)
            .clipped()

            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.filename)
                    .typeStyle(Style.bodySmall)
                    .foregroundStyle(Ink.primary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                Text(attachment.sizeLabel.uppercased())
                    .typeStyle(Style.chip)
                    .foregroundStyle(Ink.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Space.md + 2)
            .padding(.vertical, Space.md)
            .background(Ink.surface)
            .overlay(alignment: .top) { Rule() }
        }
        .frame(width: Metric.carouselTile)
        .frame(minHeight: Metric.carouselTileHeight)
        .background(Ink.surfaceTertiary)
        .clipShape(RoundedRectangle(cornerRadius: Corner.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Corner.md, style: .continuous)
                // Structural.
                .strokeBorder(Ink.rule(contrast == .increased), lineWidth: 1)
        )
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
