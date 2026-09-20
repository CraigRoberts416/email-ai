import SwiftUI

/// The weather behind the masthead.
///
/// Three soft washes that drift under the greeting, saying what the mailbox is
/// doing before any of the words do. It is the only decorative thing in the
/// product, and it earns the slot by carrying state: you can tell at arm's
/// length whether the app is still working, whether something is waiting, or
/// whether you are done, without reading a number.
///
/// Monochrome, like everything else. An earlier pass warmed the cleared state
/// toward green because "done" wanted to feel like something, and that is
/// exactly the move the system exists to prevent — the moment hue carries
/// meaning here, every grey elsewhere becomes a colour that failed to load.
/// The states separate by *intensity and tempo* instead, which are the same
/// tools the rest of the design uses.
///
/// The motion is driven by repeating animations on three offsets rather than a
/// `TimelineView`, so it runs on the render server instead of rebuilding the
/// top of a scrolling feed every frame.
struct MastheadAtmosphere: View {
    enum Weather: Equatable {
        /// Still reading the mailbox. Motion is meant to be obvious here —
        /// this is the one state where something is genuinely happening.
        case reading
        /// Mail is waiting on you.
        case needsYou
        /// Nothing waiting.
        case clear

        var intensity: Double {
            switch self {
            case .reading: 1.0
            case .needsYou: 0.70
            case .clear: 0.40
            }
        }

        /// Multiplier on every period. Working is visibly quicker; a cleared
        /// inbox barely moves.
        var tempo: Double {
            switch self {
            case .reading: 1.0
            case .needsYou: 2.2
            case .clear: 3.4
            }
        }
    }

    let weather: Weather

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.motionIsActive) private var motionIsActive
    @State private var drifting = false
    @State private var visible = true
    private var animating: Bool { !reduceMotion && motionIsActive && visible && scenePhase == .active }

    /// Position, size and travel for each wash, as fractions of the masthead
    /// box so this scales with Dynamic Type rather than drifting off it.
    ///
    /// The periods are coprime — 11, 13 and 17 — so the three never come back
    /// into phase inside any session. A composition that visibly repeats is
    /// worse than one that does not move.
    private static let washes: [(x: CGFloat, y: CGFloat, size: CGFloat,
                                 dx: CGFloat, dy: CGFloat, alpha: Double, period: Double)] = [
        (0.16, 0.30, 1.25,  0.16, -0.10, 0.115, 11),
        (0.82, 0.14, 1.00, -0.18,  0.13, 0.085, 13),
        (0.54, 0.80, 1.45,  0.10,  0.14, 0.060, 17),
    ]

    var body: some View {
        GeometryReader { geo in
            let side = max(geo.size.width, 1)
            ZStack {
                ForEach(Array(Self.washes.enumerated()), id: \.offset) { index, wash in
                    let diameter = side * wash.size
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Ink.primary.opacity(wash.alpha * weather.intensity),
                                    Ink.primary.opacity(0),
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: diameter / 2
                            )
                        )
                        .frame(width: diameter, height: diameter)
                        .position(
                            x: side * wash.x + (drifting ? side * wash.dx : 0),
                            y: geo.size.height * wash.y + (drifting ? geo.size.height * wash.dy : 0)
                        )
                        .animation(spec(period: wash.period), value: drifting)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        // Faded out, never cut.
        //
        // This was `.clipped()`, and a clip is exactly wrong here: a wash is
        // still at half strength where the frame ends, so cutting it drew the
        // frame — a hard grey rectangle with two visible straight edges sitting
        // behind the greeting. A soft thing needs a soft boundary. The left and
        // right edges are the screen's own and can stay hard; the top and
        // bottom are invented, so they dissolve.
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0), location: 0),
                    .init(color: .black, location: 0.14),
                    .init(color: .black, location: 0.58),
                    .init(color: .black.opacity(0), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        // Intensity and tempo both change with state, so the transition
        // between them has to be slow enough not to read as a flicker when a
        // sync finishes.
        .animation(reduceMotion ? Move.crossfade : .easeInOut(duration: 0.8), value: weather)
        .onAppear { visible = true }
        .onDisappear { visible = false }
        .onScrollVisibilityChange(threshold: 0.01) { visible = $0 }
        .onChange(of: animating, initial: true) { _, active in
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = !active
            withTransaction(transaction) { drifting = active }
        }
    }

    /// Nil under Reduce Motion, which leaves the washes at their resting
    /// positions — still a composition, just a still one.
    private func spec(period: Double) -> Animation? {
        guard animating else { return nil }
        return .easeInOut(duration: period * weather.tempo).repeatForever(autoreverses: true)
    }
}
