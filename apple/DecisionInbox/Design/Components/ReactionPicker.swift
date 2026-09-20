import SwiftUI

/// The six answers you can give an email without writing one.
///
/// Each carries a word, and the word is the point. A face on its own is
/// ambiguous — nobody agrees what 😔 means — and these are answers to mail,
/// not feelings about a photo. The label is what makes the set usable by
/// somebody who did not choose it.
struct Reaction: Identifiable, Equatable {
    let emoji: String
    let label: String

    var id: String { emoji }

    static let all: [Reaction] = [
        Reaction(emoji: "\u{1F44D}", label: "Noted"),
        Reaction(emoji: "\u{2705}",  label: "Handled"),
        Reaction(emoji: "\u{1F440}", label: "Reading"),
        Reaction(emoji: "\u{1F389}", label: "Good news"),
        Reaction(emoji: "\u{1F614}", label: "Not great"),
        Reaction(emoji: "\u{2757}",  label: "Urgent"),
    ]

    static func label(for emoji: String) -> String? {
        all.first { $0.emoji == emoji }?.label
    }
}

/// The long-press reaction picker.
///
/// It rises from the button that was pressed rather than from the middle of
/// the card, so it reads as something that button did.
///
/// The whole row bends toward the finger instead of one glyph popping out of a
/// static line: a single item scaling reads as a hover state that got stuck,
/// where a row that deforms reads as a surface responding. The falloff is a
/// gaussian, so neighbours lift a little and the row has no seams in it.
struct ReactionPicker: View {
    let reactions: [Reaction]
    /// Index under the finger, or nil while the finger is off the row.
    let focus: Int?
    var selected: String? = nil
    var showsLabels = false
    var onSelect: (String) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Geometry is public because `ActionRow` has to map a drag's x position
    /// onto these items, and it cannot ask the layout where they landed
    /// mid-gesture.
    static let item: CGFloat = Metric.tapTarget
    static let gap: CGFloat = 6
    static let padH: CGFloat = 10
    static let padV: CGFloat = 8
    /// How far the lift reaches, in points. Wide enough that two neighbours
    /// move with the focused one.
    static let falloff: CGFloat = 56

    static func width(_ count: Int) -> CGFloat {
        padH * 2 + CGFloat(count) * item + CGFloat(max(count - 1, 0)) * gap
    }

    /// Centre of item `index`, in the picker's own coordinate space.
    static func centre(of index: Int) -> CGFloat {
        padH + CGFloat(index) * (item + gap) + item / 2
    }

    /// Which item a point belongs to, and how strongly — 1 at dead centre,
    /// falling off with distance. Returns nil below the threshold where a
    /// choice would be a guess.
    static func focus(at x: CGFloat, count: Int) -> Int? {
        guard count > 0, x >= 0, x <= width(count) else { return nil }
        var best: (index: Int, weight: CGFloat)?
        for index in 0..<count {
            let weight = pull(x, centre(of: index))
            if weight > (best?.weight ?? 0) { best = (index, weight) }
        }
        guard let best, best.weight > 0.34 else { return nil }
        return best.index
    }

    static func pull(_ x: CGFloat, _ centre: CGFloat) -> CGFloat {
        let d = (x - centre) / falloff
        return exp(-d * d)
    }

    var body: some View {
        Group {
            if showsLabels {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: Space.sm)], spacing: Space.sm) {
                    ForEach(Array(reactions.enumerated()), id: \.element.id) { index, reaction in
                        choice(reaction, index: index)
                    }
                }
            } else {
                HStack(spacing: Self.gap) {
                    ForEach(Array(reactions.enumerated()), id: \.element.id) { index, reaction in
                        choice(reaction, index: index)
                    }
                }
                .padding(.horizontal, Self.padH)
                .padding(.vertical, Self.padV)
                .glassControl()
                .overlay(alignment: .topLeading) { caption }
            }
        }
        .animation(reduceMotion ? nil : Move.crisp, value: focus)
    }

    private func choice(_ reaction: Reaction, index: Int) -> some View {
        Button { onSelect(reaction.emoji) } label: {
            VStack(spacing: Space.xs) {
                Text(reaction.emoji)
                    .font(.system(size: 26))
                    .frame(width: Self.item, height: Self.item)
                    .scaleEffect(showsLabels ? 1 : scale(index), anchor: .bottom)
                    .offset(y: showsLabels ? 0 : lift(index))
                if showsLabels {
                    Text(reaction.label)
                        .typeStyle(Style.bodySmall)
                        .foregroundStyle(Ink.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: showsLabels ? .infinity : nil, minHeight: Metric.tapTarget)
            .padding(.vertical, showsLabels ? Space.sm : 0)
            .background(selected == reaction.emoji && showsLabels ? Ink.surfaceTertiary : .clear,
                        in: RoundedRectangle(cornerRadius: Corner.md))
            .contentShape(.rect)
        }
        .buttonStyle(TapStyle())
        .accessibilityLabel(reaction.label)
        .accessibilityAddTraits(selected == reaction.emoji ? .isSelected : [])
    }

    /// The word for whatever is under the finger.
    @ViewBuilder private var caption: some View {
        if let focus, reactions.indices.contains(focus) {
            Text(reactions[focus].label.uppercased())
                .typeStyle(Style.monoMicro)
                .foregroundStyle(Ink.onInverse)
                .padding(.horizontal, Space.sm + 2)
                .padding(.vertical, 5)
                .background(Ink.inverse, in: Capsule())
                .fixedSize()
                // Centred on the focused glyph, then lifted clear of the row.
                .alignmentGuide(.leading) { $0.width / 2 - Self.centre(of: focus) }
                .alignmentGuide(.top) { _ in Self.padV + 34 }
                .transition(.opacity)
        }
    }

    private func weight(_ index: Int) -> CGFloat {
        guard let focus, !reduceMotion else { return 0 }
        return Self.pull(Self.centre(of: focus), Self.centre(of: index))
    }

    private func scale(_ index: Int) -> CGFloat { 1 + 0.22 * weight(index) }
    private func lift(_ index: Int) -> CGFloat { -8 * weight(index) }
}
