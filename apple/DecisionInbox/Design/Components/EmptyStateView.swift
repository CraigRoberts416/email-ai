import SwiftUI

/// The native copy/actions distinguish absence from failure. Optional paper
/// poses reinforce that distinction without becoming the only status signal.
///
/// Selected destinations add a quiet paper illustration; text remains primary.
struct EmptyStateView: View {
    let headline: String
    let detail: String
    var actionLabel: String?
    var action: (() -> Void)?

    var illustration: PaperArt? = nil
    var illustrationPhase = 4

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            if let illustration {
                PaperIllustration(art: illustration, phase: illustrationPhase)
                    .frame(width: 180, height: typeSize.isAccessibilitySize ? 80 : 108)
            }
            Text(headline)
                .typeStyle(Style.display)
                .foregroundStyle(Ink.primary)
                .fixedSize(horizontal: false, vertical: true)
            Text(detail)
                .typeStyle(Style.monoSmall)
                .foregroundStyle(Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let actionLabel, let action {
                Button(action: action) {
                    Text(actionLabel)
                        .typeStyle(Style.sender)
                        .foregroundStyle(Ink.primary)
                        .padding(.horizontal, Space.lg)
                        .padding(.vertical, Space.md)
                        .frame(minHeight: Metric.tapTarget)
                        .overlay(Capsule().strokeBorder(Ink.primary, lineWidth: 1))
                }
                .buttonStyle(TapStyle())
                .padding(.top, Space.xs)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, Metric.gutter)
        // Scale is the illustration here, and the 140pt drop is what provides
        // it — but at accessibility sizes the copy itself is the scale, and the
        // same 140 pushes the headline off-screen entirely. That turns "nothing
        // here" into "nothing at all".
        .padding(.top, typeSize.isAccessibilitySize ? Space.xl : (illustration == nil ? 140 : 64))
    }
}
