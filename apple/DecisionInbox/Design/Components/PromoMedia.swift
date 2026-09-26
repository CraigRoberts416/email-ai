import SwiftUI

extension EnvironmentValues {
    @Entry var holdsFeedMediaLayout = false
}

/// A promotion's picture, at the proportions the sender actually sent.
///
/// Forcing every promo image into one ratio breaks them in two different ways,
/// and real mail produced both inside a minute:
///
///   • A **wide** banner squeezed into 4:5 loses its sides. One sender's card
///     read "TAHOE'S / …ntner / …nner / …tober 16" — the left half of every
///     line cropped away, because the image was wider than the box and `fill`
///     takes the middle.
///   • A **tall** full-email render centred in 4:5 lands on the legal footer,
///     with the offer itself above the frame.
///
/// So the box takes the image's own ratio. Nothing is ever cropped horizontally
/// — the width is always exact — and the only crop that can happen is vertical,
/// when an image is so tall that honouring it would make one post several
/// screens deep. That crop keeps the TOP, because marketing puts the message
/// first and the small print last.
struct PromoMedia: View {
    let url: URL
    @Environment(\.holdsFeedMediaLayout) private var holdsLayout

    /// The tallest a promo may be, as a multiple of the card's width. 1.25 is
    /// 4:5 — the portrait shape a phone-first marketing email is built to —
    /// and past it a single post stops being a post.
    private static let heightCap: CGFloat = 1.25

    @State private var loaded: UIImage?
    @State private var pending: UIImage?

    var body: some View {
        Color.clear
            .aspectRatio(aspect, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .top) {
                if let loaded {
                    Image(uiImage: loaded)
                        .resizable()
                        // Exact fit whenever the box matches the image, which
                        // is every case except a capped one.
                        .scaledToFill()
                        .accessibilityHidden(true)
                } else {
                    Ink.surfaceTertiary
                }
            }
            .clipped()
            .task(id: url) { await load() }
            .onChange(of: holdsLayout) { _, held in
                guard !held, let pending else { return }
                loaded = pending
                self.pending = nil
            }
            #if DEBUG
            .task(id: holdsLayout) {
                // An image response during a real pan, independent of network
                // speed. Only this reserved synthetic URL enters the fixture.
                guard url.scheme == "feed-fixture", holdsLayout, loaded == nil else { return }
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled else { return }
                let image = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 100)).image { context in
                    UIColor.systemBlue.setFill()
                    context.fill(CGRect(x: 0, y: 0, width: 400, height: 100))
                }
                receive(image)
            }
            #endif
            .animation(Move.crossfade, value: loaded == nil)
    }

    /// Width ÷ height of the box. The image's own ratio, unless that is taller
    /// than the cap.
    private var aspect: CGFloat {
        guard let loaded, loaded.size.width > 0, loaded.size.height > 0 else {
            // Nothing known yet, so hold the commonest shape rather than
            // collapsing and then shoving the feed down when the image lands.
            return Metric.mediaAspect
        }
        return max(loaded.size.width / loaded.size.height, 1 / Self.heightCap)
    }

    private func load() async {
        guard loaded == nil else { return }
        #if DEBUG
        if url.scheme == "feed-fixture" { return }
        #endif
        // `URLSession.shared` reads and writes `URLCache.shared`, so a post
        // scrolled past and back does not refetch. The reason this is not
        // `AsyncImage` is that AsyncImage hands back an `Image`, which has no
        // size — and the size is the entire point here.
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let image = UIImage(data: data)
        else { return }
        receive(image)
    }

    private func receive(_ image: UIImage) {
        // Keep the measured card bounds stable from touch-down through
        // deceleration. Publish the image's own proportions once the gesture
        // ends, so its arrival cannot invalidate unrelated scroll-past reads.
        if holdsLayout { pending = image }
        else { loaded = image }
    }
}
