import SwiftUI
import UIKit

/// Sender identity. In a monochrome feed this is the only chroma, so shape
/// carries the sender class and the logo carries the identity.
///
/// The 1pt inset ring is what makes twenty unrelated brand grounds read as
/// one system.
struct AvatarView: View {
    let sender: Sender
    var size: CGFloat = Metric.avatar
    /// Read mail keeps its colour — read is a weight change elsewhere, never
    /// a faded avatar, because opacity is not a contrast channel.
    var dimmed: Bool = false

    @Environment(\.colorSchemeContrast) private var contrast
    @State private var contactPhotos = ContactPhotoStore.shared

    /// One circular identity shape for people and companies. The source
    /// determines the image: an authorized contact photo, a supplied avatar,
    /// then the sender's initial. Never invent a portrait from an address.
    private var corner: CGFloat { size / 2 }

    private var contactImage: UIImage? {
        contactPhotos.imageData(for: sender.address).flatMap(UIImage.init(data:))
    }

    var body: some View {
        ZStack {
            shape.fill(Ink.surfaceTertiary)

            if let contactImage {
                Image(uiImage: contactImage)
                    .resizable()
                    .scaledToFill()
            } else if let url = sender.logoURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        // Photo and square logo sources share the same crop.
                        image.resizable().scaledToFill()
                    default:
                        monogram
                    }
                }
            } else {
                monogram
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        // Structural — this ring is what makes twenty unrelated brand grounds
        // read as one system, so it strengthens with every other structural
        // line under Increase Contrast.
        .overlay(shape.strokeBorder(Ink.rule(contrast == .increased), lineWidth: 1))
        .opacity(dimmed ? 0.55 : 1)
        // Avatars stay at their token size and do not scale with Dynamic Type.
        // An avatar is an image, not text.
        .accessibilityHidden(true)
        .task(id: sender.address.lowercased() + ":\(contactPhotos.authorizationVersion)") {
            await contactPhotos.loadPhoto(for: sender.address)
        }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: corner, style: .continuous)
    }

    private var monogram: some View {
        Text(sender.monogram)
            .typeStyle(Style.meta)
            .foregroundStyle(Ink.secondary)
    }
}

/// Overlapping identity stack. Used by the new-posts pill, the agent tray and
/// the collapsed thread spine — anywhere several senders are one object.
struct AvatarStack: View {
    let senders: [Sender]
    var size: CGFloat = Metric.avatarPill
    var ringColor: Color = Ink.surface
    /// Was a hardcoded 3 beside a `Move.Pill.maxAvatars` token that nothing
    /// read. One number, one home.
    var max: Int = Move.Pill.maxAvatars
    /// Avatars enter one after another only where the set is small, ordered
    /// and user-summoned — the new-posts pill. Three items with a clear order
    /// is exactly the case where a stagger is legitimate; a stagger over an
    /// unbounded batch is the waterfall tax.
    var staggered = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        HStack(spacing: -(size * 0.4)) {
            ForEach(Array(senders.prefix(max).enumerated()), id: \.element.id) { index, sender in
                AvatarView(sender: sender, size: size)
                    // Matches the avatar it separates, which is now a circle
                    // for every sender class — a rounded-tile ring around a
                    // circular avatar would show as a sliver of ground at each
                    // corner where the two shapes disagree.
                    .overlay(Circle().strokeBorder(ringColor, lineWidth: 2))
                    .opacity(staggered && !shown ? 0 : 1)
                    .animation(
                        // Reduce Motion: the whole set lands together.
                        reduceMotion
                            ? Move.crossfade
                            : Move.reveal.delay(Double(index) * Move.Pill.avatarStagger),
                        value: shown
                    )
            }
        }
        .onAppear { shown = true }
        .accessibilityHidden(true)
    }
}

#Preview {
    HStack(spacing: Space.lg) {
        AvatarView(sender: Sample.priya)
        AvatarView(sender: Sample.delta)
        AvatarView(sender: Sender(name: "", address: "billing@x.io", kind: .unknown, logoURL: nil))
        AvatarStack(senders: [Sample.priya, Sample.delta, Sample.marcus])
    }
    .padding()
}
