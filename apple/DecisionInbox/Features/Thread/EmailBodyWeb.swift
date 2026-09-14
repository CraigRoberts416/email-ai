import SwiftUI
import WebKit

/// Renders an email's own HTML, sized to its content so it scrolls with the
/// page rather than trapping a scroll view inside a scroll view.
///
/// Two things are off and both are deliberate:
///   JavaScript — an email has no business running code.
///   Remote loads — a tracking pixel is a read receipt the sender never asked
///   permission for, and this product reads your mail before you do. Blocking
///   them until you say otherwise is the only position that holds.
struct EmailBodyWeb: View {
    let html: String
    let loadRemoteContent: Bool

    @State private var height: CGFloat = 1

    var body: some View {
        WebBody(html: html, loadRemoteContent: loadRemoteContent, height: $height)
            .frame(height: height)
    }
}

private struct WebBody: UIViewRepresentable {
    let html: String
    let loadRemoteContent: Bool
    @Binding var height: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.suppressesIncrementalRendering = true

        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.scrollView.isScrollEnabled = false
        view.scrollView.bounces = false
        view.isOpaque = false
        view.backgroundColor = .clear

        // Measured by watching the scroll view rather than by asking the page,
        // because the page has no JavaScript to answer with.
        context.coordinator.observation = view.scrollView.observe(
            \.contentSize, options: [.new]
        ) { _, change in
            guard let size = change.newValue, size.height > 0 else { return }
            context.coordinator.report(size.height)
        }
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        context.coordinator.onHeight = { height = $0 }
        let document = Self.document(html: html, allowRemote: loadRemoteContent)
        guard context.coordinator.lastLoaded != document else { return }
        context.coordinator.lastLoaded = document
        view.loadHTMLString(document, baseURL: nil)
    }

    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        coordinator.observation?.invalidate()
    }

    // MARK: Document

    private static func document(html: String, allowRemote: Bool) -> String {
        var body = html
        if !allowRemote {
            // Renaming the attribute rather than deleting the element keeps the
            // sender's layout intact — the space stays, the beacon doesn't fire.
            body = body.replacingOccurrences(
                of: #"(?i)\s(src|background)\s*=\s*(["'])\s*https?://"#,
                with: " data-blocked-$1=$2https://",
                options: .regularExpression
            )
            body = body.replacingOccurrences(
                of: #"(?i)url\(\s*(["']?)\s*https?://"#,
                with: "url($1about:blank#",
                options: .regularExpression
            )
        }

        // A viewport meta and a width clamp, because bulk senders still ship
        // 600px fixed-width tables that would otherwise force a sideways scroll.
        return """
        <!doctype html><html><head>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
          :root { color-scheme: light; }
          html, body { margin: 0; padding: 0 16px; background: transparent;
            font: 16px/1.45 -apple-system, system-ui, sans-serif; color: #000;
            -webkit-text-size-adjust: 100%; word-break: break-word; }
          img, video, table, pre { max-width: 100% !important; height: auto; }
          table { width: 100% !important; }
          a { color: #000; }
        </style></head><body>\(body)</body></html>
        """
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastLoaded: String?
        var observation: NSKeyValueObservation?
        var onHeight: ((CGFloat) -> Void)?
        private var reported: CGFloat = 0

        /// Sub-pixel churn during layout would otherwise loop the view forever.
        func report(_ height: CGFloat) {
            guard abs(height - reported) > 1 else { return }
            reported = height
            Task { @MainActor in onHeight?(height) }
        }

        /// Links open in Safari, never in place.
        func webView(
            _ webView: WKWebView,
            decidePolicyFor action: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard action.navigationType == .linkActivated, let url = action.request.url else {
                decisionHandler(.allow)
                return
            }
            decisionHandler(.cancel)
            UIApplication.shared.open(url)
        }
    }
}
