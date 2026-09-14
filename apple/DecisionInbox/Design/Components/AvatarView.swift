import SwiftUI

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

    private var corner: CGFloat {
        // Circles crop logos badly and read as people, so brands get a tile.
        sender.kind == .brand ? size * 0.25 : size / 2
    }

    var body: some View {
        ZStack {
            shape.fill(Ink.surfaceTertiary)

            if let url = sender.logoURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
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
        .overlay(shape.strokeBorder(Ink.border, lineWidth: 1))
        .opacity(dimmed ? 0.55 : 1)
        .accessibilityHidden(true)
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
    var max: Int = 3

    var body: some View {
        HStack(spacing: -(size * 0.4)) {
            ForEach(senders.prefix(max)) { sender in
                AvatarView(sender: sender, size: size)
                    .overlay(
                        RoundedRectangle(
                            cornerRadius: sender.kind == .brand ? size * 0.25 : size / 2,
                            style: .continuous
                        )
                        .strokeBorder(ringColor, lineWidth: 2)
                    )
            }
        }
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
