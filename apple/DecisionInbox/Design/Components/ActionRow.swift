import SwiftUI

/// Left-cluster acts on the message, right-cluster files it. Counts sit beside
/// their glyph in mono rather than inside a pill — a bare count reads as
/// information, a pill reads as a badge demanding attention.
struct ActionRow: View {
    let message: Message
    var onReply: () -> Void = {}
    var onDiscuss: () -> Void = {}
    var onForward: () -> Void = {}
    var onSave: () -> Void = {}
    var onArchive: () -> Void = {}
    var onUnsubscribe: () -> Void = {}

    var body: some View {
        HStack(spacing: Space.xl) {
            if message.isPromotion {
                // Nobody replies to a newsletter, so unsubscribe takes the slot.
                Button(action: onUnsubscribe) {
                    HStack(spacing: Space.xs) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13))
                        Text("Unsubscribe")
                            .typeStyle(Style.bodySmall)
                    }
                    .foregroundStyle(Ink.primary)
                    .padding(.horizontal, Space.md)
                    .padding(.vertical, 6)
                    .overlay(Capsule().strokeBorder(Ink.primary, lineWidth: 1))
                }
                .buttonStyle(.plain)

                iconButton("sparkles", count: nil, label: "Discuss", action: onDiscuss)
            } else {
                iconButton("face.smiling", count: nil, label: "React", action: {})
                iconButton("arrowshape.turn.up.left", count: nil, label: "Reply", action: onReply)
                iconButton("arrowshape.turn.up.right", count: nil, label: "Forward", action: onForward)
                iconButton("sparkles", count: nil, label: "Discuss", action: onDiscuss)
            }

            Spacer(minLength: 0)

            iconButton(message.isSaved ? "bookmark.fill" : "bookmark",
                       count: nil, label: "Save", action: onSave)
            iconButton("archivebox", count: nil, label: "Archive", action: onArchive)
        }
    }

    private func iconButton(
        _ systemName: String,
        count: Int?,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Space.xs) {
                Image(systemName: systemName)
                    .font(.system(size: Metric.iconAction))
                if let count {
                    Text("\(count)")
                        .typeStyle(Style.meta)
                        .foregroundStyle(Ink.secondary)
                }
            }
            .foregroundStyle(Ink.secondary)
            .frame(minWidth: Metric.tapTarget * 0.6, minHeight: Metric.tapTarget, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - Quoted card
//
// A forward has always been a quote-tweet; this just draws it that way.

struct QuotedCard: View {
    let quoted: QuotedMessage

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
                .strokeBorder(Ink.border, lineWidth: 1)
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

    @State private var page = 0

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: Space.sm) {
                    ForEach(attachments) { attachment in
                        AttachmentTile(attachment: attachment)
                    }
                    OpenThreadTile(action: onOpenThread)
                }
                .padding(.horizontal, Metric.gutter)
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)

            HStack(spacing: Space.xs + 2) {
                ForEach(0..<(attachments.count + 1), id: \.self) { index in
                    Circle()
                        .fill(index == page ? Ink.primary : Ink.border)
                        .frame(width: 5, height: 5)
                }
                Spacer(minLength: 0)
                Text("\(page + 1)/\(attachments.count + 1)")
                    .typeStyle(Style.chip)
                    .foregroundStyle(Ink.secondary)
            }
            .padding(.horizontal, Metric.gutter)
        }
    }
}

struct AttachmentTile: View {
    let attachment: Attachment

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
            .frame(maxHeight: .infinity)
            .clipped()

            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.filename)
                    .typeStyle(Style.bodySmall)
                    .foregroundStyle(Ink.primary)
                    .lineLimit(1)
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
        .frame(width: Metric.carouselTile, height: Metric.carouselTileHeight)
        .background(Ink.surfaceTertiary)
        .clipShape(RoundedRectangle(cornerRadius: Corner.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Corner.md, style: .continuous)
                .strokeBorder(Ink.border, lineWidth: 1)
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
