import AppKit
import Foundation
import WebKit

@MainActor final class RecorderDelegate: NSObject, WKNavigationDelegate {
    var finished = false
    var failure: String?
    var externalNavigations: [URL] = []
    var navigationRequests: [URL] = []

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finished = true }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        failure = error.localizedDescription; finished = true
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        failure = error.localizedDescription; finished = true
    }

    // Inserted verbatim from the production delegate, except the external-open
    // boundary is recorded rather than opening any browser or mail client.
    __PRODUCTION_NAVIGATION__
}

@main struct EmailWebKitRuntime {
    @MainActor static func main() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        Task { @MainActor in
            do { try await run(); exit(0) }
            catch { print("FAIL: \(error)"); exit(1) }
        }
        NSApplication.shared.run()
    }

    struct Failure: Error, CustomStringConvertible {
        let description: String
    }
    static func require(_ condition: Bool, _ description: String) throws {
        if !condition { throw Failure(description: description) }
    }

    @MainActor static func run() async throws {
        let origin = CommandLine.arguments[1]
        // Extracted from production WebBody.makeUIView at test execution time.
        __PRODUCTION_CONFIGURATION__
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 800), configuration: configuration)
        let delegate = RecorderDelegate()
        webView.navigationDelegate = delegate
        // A hidden window gives WebKit a native rendering tree without opening
        // the app, touching the user's UI or using a signed-in browser profile.
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 800),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = webView
        window.orderOut(nil)

        let ruleIdentifier = "email-runtime-test-\(UUID())"
        let rules: WKContentRuleList = try await withCheckedThrowingContinuation { continuation in
            WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: ruleIdentifier, encodedContentRuleList: __PRODUCTION_RULE__
            ) { rules, error in
                if let rules { continuation.resume(returning: rules) }
                else { continuation.resume(throwing: error ?? Failure(description: "Rule compilation failed")) }
            }
        }

        var instrumented = false
        for (phase, allowed) in [("blocked", false), ("consented", true), ("blocked-again", false)] {
            webView.configuration.userContentController.removeAllContentRuleLists()
            if !allowed { webView.configuration.userContentController.add(rules) }
            delegate.finished = false; delegate.failure = nil
            let base = origin + "/" + phase
            let fixture = html(base: base)
            webView.loadHTMLString(EmailHTMLPolicy.document(html: fixture, allowRemote: allowed), baseURL: nil)
            let deadline = Date().addingTimeInterval(12)
            while !delegate.finished && Date() < deadline { try await Task.sleep(for: .milliseconds(30)) }
            try require(delegate.finished, "\(phase): document never finished")
            try require(delegate.failure == nil, "\(phase): navigation error \(delegate.failure ?? "")")
            // Let stylesheet imports, fonts, media and refresh navigation settle.
            try await Task.sleep(for: .seconds(1.5))

            if allowed {
                let inlineRan = try await webView.evaluateJavaScript("Boolean(window.inlineRan)")
                try require((inlineRan as? Bool) == false, "Sender inline JavaScript ran")
                let connected = try await webView.callAsyncJavaScript(
                    "try { await fetch(url); return true; } catch (error) { return false; }",
                    arguments: ["url": base + "/connect/from-instrumentation"], in: nil, contentWorld: .page)
                try require((connected as? Bool) == false, "CSP allowed a programmatic connection")
                _ = try await webView.evaluateJavaScript("document.getElementById('manual').click()")
                _ = try await webView.evaluateJavaScript("document.getElementById('mail').click()")
                _ = try await webView.evaluateJavaScript("document.getElementById('script-link').click()")
                _ = try await webView.evaluateJavaScript("document.getElementById('form').requestSubmit()")
                try await Task.sleep(for: .milliseconds(300))
                try require(delegate.externalNavigations.contains(URL(string: base + "/navigation/manual")!), "Deliberate HTTP link was not routed to external-open boundary")
                try require(delegate.externalNavigations.contains(URL(string: "mailto:synthetic@example.invalid")!), "Deliberate mailto was not routed to external-open boundary")
                try require(!delegate.externalNavigations.contains { $0.scheme == "javascript" }, "JavaScript URL reached external opener")
                instrumented = true
            }
            let (data, _) = try await URLSession.shared.data(from: URL(string: origin + "/events")!)
            let all = try JSONDecoder().decode([String].self, from: data)
            try require(all.allSatisfy { path in ["/blocked/", "/consented/", "/blocked-again/"].contains { path.hasPrefix($0) } }, "Unexpected recorder path: \(all)")
            let paths = all.filter { $0.hasPrefix("/" + phase + "/") }
            try require(delegate.navigationRequests.contains { $0.path == "/" + phase + "/navigation/automatic" }, "Automatic navigation fixture did not exercise the delegate")
            if allowed {
                for expected in ["/img/quoted.png", "/img/unquoted.png", "/img/css.png", "/css/external.css", "/css/import.css", "/font/fixture.woff2"] {
                    try require(paths.contains("/" + phase + expected), "Consented resource did not request: \(expected); got \(paths)")
                }
                let forbidden = paths.filter { !$0.hasPrefix("/" + phase + "/img/") && !$0.hasPrefix("/" + phase + "/css/") && !$0.hasPrefix("/" + phase + "/font/") }
                try require(forbidden.isEmpty, "Unapproved resource requested after consent: \(forbidden)")
            } else {
                try require(paths.isEmpty, "Remote resources escaped blocked policy: \(paths)")
            }
            print("PASS \(phase): \(paths.count) loopback resource requests\(allowed ? " (images/styles/fonts only)" : "")")
        }
        try require(instrumented, "Did not exercise JavaScript/navigation boundary")
        try require(!webView.configuration.websiteDataStore.isPersistent, "WebKit data store is persistent")
        print("PASS JavaScript disabled; connect/form/script URLs and automatic navigation blocked; deliberate HTTP/mailto routed externally without network/open side effects")
        print("PASS nonpersistent WebKit store; consent revoked on same view")
        webView.stopLoading()
        window.close()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            WKContentRuleListStore.default().removeContentRuleList(forIdentifier: ruleIdentifier) { _ in continuation.resume() }
        }
    }

    static func html(base: String) -> String {
        """
        <title>Synthetic email</title>
        <link rel="stylesheet" href="\(base)/css/external.css">
        <link rel="preload" as="script" href="\(base)/script/preload.js">
        <link rel="prefetch" href="\(base)/navigation/prefetch">
        <style>
        @import url('\(base)/css/import.css');
        @font-face { font-family: Fixture; src: url('\(base)/font/fixture.woff2') format('woff2'); }
        .font { font-family: Fixture, serif; }
        .background { background: url('\(base)/img/css.png'); width: 64px; height: 64px; }
        </style>
        <p class="font">Font boundary</p><div class="background"></div>
        <img src="\(base)/img/quoted.png"><img src=\(base)/img/unquoted.png>
        <img src="\(base)/img/fallback.png" srcset="\(base)/img/srcset-1.png 1x, \(base)/img/srcset-2.png 2x">
        <img src="\(base.replacingOccurrences(of: "http:", with: ""))/img/scheme-relative.png">
        <iframe src="\(base)/frame/child"></iframe>
        <object data="\(base)/object/plugin"></object>
        <video src="\(base)/media/video" poster="\(base)/img/poster.png" preload="auto"></video>
        <audio src="\(base)/media/audio" preload="auto"></audio>
        <script src="\(base)/script/external.js"></script>
        <script>window.inlineRan=true; fetch('\(base)/connect/inline'); new Image().src='\(base)/script/inline-ran';</script>
        <img src="data:invalid" onerror="fetch('\(base)/script/handler-ran')">
        <a id="manual" href="\(base)/navigation/manual">Open source</a>
        <a id="mail" href="mailto:synthetic@example.invalid">Write</a>
        <a id="script-link" href="javascript:fetch('\(base)/script/url-ran')">Unsafe script URL</a>
        <form id="form" method="post" action="\(base)/form/submit"><button>Submit</button></form>
        <meta http-equiv="refresh" content="1;url=\(base)/navigation/automatic">
        """
    }
}
