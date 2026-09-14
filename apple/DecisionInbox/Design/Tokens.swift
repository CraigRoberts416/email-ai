import SwiftUI

// Decision Inbox design system.
//
// Monochrome by commitment: the only colour in the product comes from sender
// avatars and the generated hero images. State is carried by weight, fill,
// rule and shape — never by hue.
//
// Two families, and the split is load-bearing:
//   DM Sans — what a human wrote, or what the user will do
//   DM Mono — what the machine wrote or counted
//
// Values mirror the Figma variables in Email-App-Component-Library.

// MARK: - Colour

enum Ink {
    /// Body copy, quotes, kickers, active icons. 21:1 on white.
    static let primary = Color(hex: 0x000000)

    /// Secondary copy. Darkened from the original #8F8F8F, which measured
    /// 3.23:1 on white and failed WCAG AA under 24px. This measures 4.54:1.
    static let secondary = Color(hex: 0x767676)

    /// Repeated, non-essential meta only — still below AA, so never load-bearing.
    static let tertiary = Color(hex: 0x8F8F8F)

    /// Unread post ground.
    static let surface = Color(hex: 0xFFFFFF)

    /// Read ground, dateline bands, pressed fill, hero summary panel.
    static let surfaceTertiary = Color(hex: 0xF8F8F8)

    /// Post dividers, margin rules, skeletons. Decorative only — 1.16:1.
    static let border = Color(hex: 0xEEEEEE)

    /// Increase Contrast swaps every border to this, or the feed loses its grammar.
    static let borderHighContrast = Color(hex: 0xC7C7C7)

    /// Inverted surfaces: the agent tray, toasts, the attachment lightbox.
    static let inverse = Color(hex: 0x000000)
    static let onInverse = Color(hex: 0xFFFFFF)

    /// The thread sheet, and the only place the product inverts wholesale.
    /// A thread is the sender's own words rather than our reading of them, so
    /// it arrives on its own ground — and the white message cards inside it
    /// are then unmistakably theirs, not ours.
    static let sheet = Color(hex: 0x081034)
    static let onSheet = Color(hex: 0xFFFFFF)
    /// 5.9:1 on the sheet — meta only, never a sentence that carries meaning.
    static let onSheetSecondary = Color(hex: 0x8F8F8F)

    /// Secondary copy on an inverted surface. 4.8–5.7:1 against near-black.
    static let onInverseSecondary = Color.white.opacity(0.62)

    static let scrim = Color.black.opacity(0.40)
    static let scrimHeavy = Color.black.opacity(0.55)

    /// Resolves the divider colour against the accessibility setting. A
    /// decontained feed has no other structural grammar, so this matters.
    static func rule(_ increaseContrast: Bool) -> Color {
        increaseContrast ? borderHighContrast : border
    }
}

// MARK: - Spacing
//
// Nothing inside a post is ever >= 24. Between posts is always 24 / rule / 24.
// A post reads as one unit only when its largest internal gap is smaller than
// its external one.

enum Space {
    static let xs: CGFloat = 4    // glued — icon to its count
    static let sm: CGFloat = 8    // same unit — kicker to quote
    static let md: CGFloat = 12   // related — compact row padding
    static let lg: CGFloat = 16   // distinct blocks, and the screen gutter
    static let xl: CGFloat = 24   // post padding, and the gap either side of a divider
    static let xxl: CGFloat = 32
    static let xxxl: CGFloat = 40 // above a dateline and nowhere else
}

enum Corner {
    static let chip: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let round: CGFloat = 999
}

// MARK: - Type
//
// Line heights come from the Figma percentages. SwiftUI has no direct
// line-height API, so each style carries the leading adjustment needed to hit
// the designed value at its own size.

enum Face {
    static let sans = "DMSans-Regular"
    static let sansMedium = "DMSans-Medium"
    static let mono = "DMMono-Regular"
    static let monoMedium = "DMMono-Medium"
}

struct TypeStyle {
    let font: Font
    let tracking: CGFloat
    let lineSpacing: CGFloat
}

enum Style {
    /// Pulled quote, greeting, screen titles. Never a UI label, never >3 lines.
    static let display = TypeStyle(
        font: .custom(Face.sans, size: 28, relativeTo: .title),
        tracking: -0.84, lineSpacing: 0
    )

    /// Recap, composer body, list rows, CTA labels. Never an AI summary.
    static let body = TypeStyle(
        font: .custom(Face.sans, size: 16, relativeTo: .body),
        tracking: -0.32, lineSpacing: 3
    )

    static let bodySmall = TypeStyle(
        font: .custom(Face.sans, size: 14, relativeTo: .subheadline),
        tracking: -0.28, lineSpacing: 3
    )

    /// Sender name — the one weight step on a card, and the identity anchor.
    static let sender = TypeStyle(
        font: .custom(Face.sansMedium, size: 16, relativeTo: .body),
        tracking: -0.32, lineSpacing: 0
    )

    /// Read drops the sender to regular. Read is a weight change, never opacity.
    static let senderRead = TypeStyle(
        font: .custom(Face.sans, size: 16, relativeTo: .body),
        tracking: -0.32, lineSpacing: 0
    )

    /// AI summaries. The machine speaking. Never for words a human wrote.
    /// Mono is never negative-tracked — the even advance is the signal.
    static let ai = TypeStyle(
        font: .custom(Face.mono, size: 16, relativeTo: .body),
        tracking: 0, lineSpacing: 3
    )

    /// Intent kickers, dateline bands, stamps. This is what replaces an accent colour.
    static let kicker = TypeStyle(
        font: .custom(Face.monoMedium, size: 12, relativeTo: .caption),
        tracking: 0.6, lineSpacing: 0
    )

    /// Timestamps, thread counts, tags.
    static let meta = TypeStyle(
        font: .custom(Face.monoMedium, size: 12, relativeTo: .caption),
        tracking: 0, lineSpacing: 0
    )

    /// Run-log lines, evidence, small stamps.
    static let monoSmall = TypeStyle(
        font: .custom(Face.mono, size: 12, relativeTo: .caption),
        tracking: 0, lineSpacing: 2
    )

    /// Account tags and the smallest stamps.
    static let chip = TypeStyle(
        font: .custom(Face.monoMedium, size: 10, relativeTo: .caption2),
        tracking: 0.4, lineSpacing: 0
    )

    /// Composer field labels — TO, SUBJECT. Tracked wider than a kicker
    /// because they are furniture to be skipped, not information to be read.
    static let fieldLabel = TypeStyle(
        font: .custom(Face.monoMedium, size: 11, relativeTo: .caption),
        tracking: 0.44, lineSpacing: 0
    )

    /// A sentence the model drafted for you to edit. Mono for the same reason
    /// a summary is mono — the machine wrote it — and looser leading because
    /// this is the one machine-written thing you are meant to read closely
    /// before putting your name on it.
    static let draft = TypeStyle(
        font: .custom(Face.mono, size: 15, relativeTo: .body),
        tracking: 0, lineSpacing: 4
    )

    /// Quoted mail and attachment names. One step below body.
    static let quoted = TypeStyle(
        font: .custom(Face.sans, size: 15, relativeTo: .subheadline),
        tracking: -0.3, lineSpacing: 3
    )

    /// File sizes and the smallest mono meta.
    static let fileMeta = TypeStyle(
        font: .custom(Face.mono, size: 10, relativeTo: .caption2),
        tracking: 0.2, lineSpacing: 3
    )

    /// The label on a filled button. The product has very few.
    static let button = TypeStyle(
        font: .custom(Face.sansMedium, size: 15, relativeTo: .body),
        tracking: -0.3, lineSpacing: 0
    )
}

extension View {
    /// Applies a type style as one unit so callers never set font, tracking
    /// and leading separately and drift apart.
    func typeStyle(_ style: TypeStyle) -> some View {
        self.font(style.font)
            .tracking(style.tracking)
            .lineSpacing(style.lineSpacing)
    }
}

// MARK: - Layout

enum Metric {
    static let gutter: CGFloat = Space.lg
    static let postPaddingY: CGFloat = Space.xl
    static let avatar: CGFloat = 40
    static let avatarCompact: CGFloat = 24
    static let avatarPill: CGFloat = 22
    static let avatarRow: CGFloat = 28
    static let iconAction: CGFloat = 17
    static let tapTarget: CGFloat = 44
    static let unreadBar: CGFloat = 2
    static let hairline: CGFloat = 1

    /// Instagram's proven card shape. Media crops to this unless it is landscape.
    static let mediaAspect: CGFloat = 4.0 / 5.0
    static let mediaAspectWide: CGFloat = 16.0 / 9.0
    static let htmlAspect: CGFloat = 1.0
    static let carouselTile: CGFloat = 300
    static let carouselTileHeight: CGFloat = 375
}

// MARK: - Motion
//
// Near-critically damped everywhere a user reads. The only hint of overshoot
// is on card commit, where it lands as punctuation.

enum Move {
    static let enter = Animation.spring(response: 0.34, dampingFraction: 0.78)
    static let crisp = Animation.spring(response: 0.30, dampingFraction: 0.86)
    static let sheet = Animation.spring(response: 0.28, dampingFraction: 0.90)
    static let layout = Animation.spring(response: 0.38, dampingFraction: 0.82)

    static let pressIn = Animation.easeOut(duration: 0.09)
    static let pressOut = Animation.easeOut(duration: 0.12)
    static let crossfade = Animation.easeInOut(duration: 0.16)
    static let reveal = Animation.easeOut(duration: 0.24)

    static let stagger: Double = 0.04

    /// Hold a skeleton this long once shown, or it flashes.
    static let skeletonMinHold: Double = 0.4
    /// Show nothing at all below this.
    static let loadingDelay: Double = 0.15
    static let undoWindow: Double = 5
    static let sendUndoWindow: Double = 8

    enum Swipe {
        static let threshold: CGFloat = 96
        static let rubberBand: CGFloat = 0.45
        static let rubberBandAt: CGFloat = 160
    }

    enum Pill {
        /// The pill only appears once the user is genuinely away from the top.
        static let showBelowScrollY: CGFloat = 260
        static let avatarStagger: Double = 0.034
        static let maxAvatars = 3
    }
}

// MARK: - Helpers

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }

    /// A ground taken from a sender's generated image.
    ///
    /// The hue is theirs — that is the whole point of the thread carrying the
    /// sender's colour. The legibility is not: the server averages the image
    /// and darkens it 40%, which lands a bright image on mid-grey where white
    /// text measures under 3:1. So the colour is darkened only as far as white
    /// body text needs, and no further.
    static func sheet(fromHex hex: String?, fallback: Color = Ink.sheet) -> Color {
        guard let hex,
              let value = UInt32(hex.hasPrefix("#") ? String(hex.dropFirst()) : hex, radix: 16),
              hex.count >= 6
        else { return fallback }

        var rgb = [
            Double((value >> 16) & 0xFF) / 255,
            Double((value >> 8) & 0xFF) / 255,
            Double(value & 0xFF) / 255,
        ]

        // WCAG AA for body text against white: luminance must sit at or below
        // 1.05 / 4.5 − 0.05.
        let ceiling = 1.05 / 4.5 - 0.05
        var guard_ = 0
        while luminance(rgb) > ceiling, guard_ < 40 {
            rgb = rgb.map { $0 * 0.92 }
            guard_ += 1
        }
        return Color(.sRGB, red: rgb[0], green: rgb[1], blue: rgb[2], opacity: 1)
    }

    private static func luminance(_ rgb: [Double]) -> Double {
        let linear = rgb.map { channel -> Double in
            channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
    }
}

/// Edge-to-edge hairline. Full bleed is deliberate — inset to the gutter it
/// reads as a settings list; edge to edge it reads as newsprint.
struct Rule: View {
    @Environment(\.colorSchemeContrast) private var contrast
    var body: some View {
        Rectangle()
            .fill(Ink.rule(contrast == .increased))
            .frame(height: Metric.hairline)
    }
}
