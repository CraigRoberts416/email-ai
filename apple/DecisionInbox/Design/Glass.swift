import SwiftUI

// Liquid Glass, and the edges a scrolling feed has to resolve.
//
// The product is deliberately flat — no card fill, no radius, no shadow —
// which is a decision about *content*. It was never a decision about chrome.
// Where the system's own surfaces float over scrolling content (the status
// bar, the tab bar, a pill), something has to happen at the seam, and until
// now nothing did: posts ran under the clock, a CTA button hung in the
// notch, and the dateline had bare white above it. That reads as a bug,
// because it is one.
//
// Everything here is behind an availability check. The deployment target is
// iOS 18 and these are iOS 26 APIs; on 18 the app keeps its solid surfaces,
// which is a plainer result rather than a broken one.

extension View {
    /// Softens the top and bottom edges of a scroll view so content dissolves
    /// under the system's floating chrome instead of colliding with it.
    ///
    /// `.soft` and not `.hard`: a hard edge draws a line, and this feed's only
    /// line is the hairline between posts. A second, heavier one at the top
    /// would outrank it and the post separator would stop reading as structure.
    func feedEdges() -> some View {
        modifier(FeedEdges())
    }

    /// A floating control — a pill, a back button, an ask field — on Liquid
    /// Glass, falling back to the flat fill it used to have.
    ///
    /// `interactive` for anything that responds to touch, because the glass
    /// reacts to the press and a control that does not is the odd one out.
    func glassControl(
        interactive: Bool = true,
        fallback: Color = Ink.surface,
        in shape: some Shape = Capsule()
    ) -> some View {
        modifier(GlassControl(interactive: interactive, fallback: fallback, shape: shape))
    }
}

private struct FeedEdges: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .scrollEdgeEffectStyle(.soft, for: .top)
                .scrollEdgeEffectStyle(.soft, for: .bottom)
        } else {
            content
        }
    }
}

private struct GlassControl<S: Shape>: ViewModifier {
    let interactive: Bool
    let fallback: Color
    let shape: S

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(
                interactive ? .regular.interactive() : .regular,
                in: shape
            )
        } else {
            content.background(fallback, in: shape)
        }
    }
}
