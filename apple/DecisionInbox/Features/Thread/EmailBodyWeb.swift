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
        configuration.websiteDataStore = .nonPersistent()

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
        let document = EmailHTMLPolicy.document(html: html, allowRemote: loadRemoteContent)
        guard context.coordinator.lastLoaded != document else { return }
        context.coordinator.lastLoaded = document
        if loadRemoteContent {
            view.configuration.userContentController.removeAllContentRuleLists()
            view.loadHTMLString(document, baseURL: nil)
        } else {
            // Compile before loading any sender HTML. CSP also blocks remote
            // resources; the WebKit rule covers speculative network requests.
            WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: "email-block-remote-v1",
                encodedContentRuleList: #"[{"trigger":{"url-filter":"^https?://"},"action":{"type":"block"}}]"#
            ) { rules, _ in
                guard context.coordinator.lastLoaded == document else { return }
                guard let rules else {
                    view.loadHTMLString(EmailHTMLPolicy.document(html: "<p>This email’s layout could not be opened with remote content blocked. You can choose Load to open it.</p>", allowRemote: false), baseURL: nil)
                    return
                }
                view.configuration.userContentController.add(rules)
                view.loadHTMLString(document, baseURL: nil)
            }
        }
    }

    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        coordinator.lastLoaded = nil
        view.stopLoading()
        coordinator.observation?.invalidate()
    }

    // MARK: Document


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
            if action.navigationType == .linkActivated, let url = action.request.url,
               ["http", "https", "mailto", "tel"].contains(url.scheme?.lowercased() ?? "") {
                decisionHandler(.cancel)
                UIApplication.shared.open(url)
                return
            }
            // Only the locally supplied document may navigate this view.
            decisionHandler(action.request.url?.scheme == "about" ? .allow : .cancel)
        }
    }
}
