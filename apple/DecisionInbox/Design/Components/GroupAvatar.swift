import SwiftUI

/// The participants of a conversation, in the footprint one avatar takes.
///
/// Built to `GroupAvatar`. Faces overlap left to right inside the same 52pt
/// box a single person occupies, so a list stays on one grid whoever is in a
/// conversation.
///
/// The ring is load-bearing, not decoration: without a gap of the page's own
/// ground between them, overlapping circles read as one lumpy shape rather
/// than as several people. It is also part of the arithmetic — an earlier
/// version stacked the faces as a triangle and let the outermost ring sit 2pt
/// past the frame, which is exactly where a row's clipping bites and the pile
/// was cut off.
struct GroupAvatar: View {
    let participants: [Sender]
    var size: CGFloat = 52

    private var ring: CGFloat { size * (2.0 / 52.0) }
    private var inner: CGFloat { size - ring * 2 }

    /// Two faces get more room each; three or more share it. Beyond three the
    /// last slot becomes a count — a fourth face at this size is unreadable
    /// grey, and how many people are in this is the thing the reader wants.
    private var shown: Int { min(participants.count, 3) }
    private var overflow: Int { max(0, participants.count - 2) }

    private var faceSize: CGFloat {
        participants.count <= 2 ? inner * (34.0 / 48.0) : inner * (30.0 / 48.0)
    }

    private var step: CGFloat {
        participants.count <= 2 ? inner - faceSize : (inner - faceSize) / 2
    }

    var body: some View {
        if participants.count <= 1 {
            AvatarView(sender: participants.first ?? .unknown, size: size)
        } else {
            ZStack(alignment: .topLeading) {
                ForEach(Array(slots.enumerated()), id: \.offset) { index, slot in
                    face(slot)
                        .offset(x: ring + step * CGFloat(index), y: (size - faceSize) / 2)
                }
            }
            .frame(width: size, height: size)
            // It fits now, so clipping costs nothing and guarantees the pile
            // can never bleed into the text beside it.
            .clipped()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                participants.count == 2
                    ? "\(participants[0].displayName) and \(participants[1].displayName)"
                    : "\(participants.count) people"
            )
        }
    }

    private enum Slot: Hashable {
        case person(Sender)
        case count(Int)
    }

    private var slots: [Slot] {
        if participants.count <= 3 {
            return participants.prefix(shown).map(Slot.person)
        }
        return participants.prefix(2).map(Slot.person) + [.count(overflow)]
    }

    @ViewBuilder private func face(_ slot: Slot) -> some View {
        switch slot {
        case .person(let sender):
            AvatarView(sender: sender, size: faceSize)
                .overlay(Circle().strokeBorder(Ink.surface, lineWidth: ring))
        case .count(let n):
            // Filled, because it is a label rather than a person — and the one
            // dark shape in the pile reads as "and more" without a legend.
            Circle()
                .fill(Ink.primary)
                .frame(width: faceSize, height: faceSize)
                .overlay {
                    Text("+\(n)")
                        .typeStyle(Style.monoMicro)
                        .foregroundStyle(Ink.surface)
                        .monospacedDigit()
                }
                .overlay(Circle().strokeBorder(Ink.surface, lineWidth: ring))
        }
    }
}

extension Sender {
    static let unknown = Sender(name: "", address: "", kind: .unknown, logoURL: nil)
}
