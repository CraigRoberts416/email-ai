#!/usr/bin/env python3
"""Hidden macOS WebKit integration test using production policy/configuration.

Uses only a temporary executable, a nonpersistent WebKit store, synthetic HTML,
and an HTTP recorder bound to 127.0.0.1. No app, account, credentials, or browser
profile is opened. The external-open API is replaced with an in-memory sink.
"""
import base64
import http.server
import json
from pathlib import Path
import re
import subprocess
import tempfile
import threading

ROOT = Path(__file__).resolve().parents[2]
PRODUCTION = ROOT / "apple/DecisionInbox/Features/Thread/EmailBodyWeb.swift"
source = PRODUCTION.read_text()
configuration = source.split("        let configuration = WKWebViewConfiguration()", 1)[1].split("        let view = WKWebView", 1)[0]
configuration = "let configuration = WKWebViewConfiguration()" + configuration
rule = re.search(r'encodedContentRuleList:\s*(#".*?"#)', source).group(1)
start = source.index("        func webView(")
brace = source.index("{", start)
depth = 1
end = brace + 1
while depth:
    depth += (source[end] == "{") - (source[end] == "}")
    end += 1
navigation = source[start:end].replace("UIApplication.shared.open(url)", "externalNavigations.append(url)")
navigation = navigation.replace("        ) {", "        ) {\n            if let requested = action.request.url { navigationRequests.append(requested) }", 1)
assert "UIApplication" not in navigation
template = (ROOT / "apple/tests/EmailWebKitRuntime.template.swift").read_text()
harness = template.replace("__PRODUCTION_CONFIGURATION__", configuration).replace("__PRODUCTION_RULE__", rule).replace("__PRODUCTION_NAVIGATION__", navigation)

events = []
lock = threading.Lock()
pixel = base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a1X8AAAAASUVORK5CYII=")

class Recorder(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_GET(self):
        if self.path == "/events":
            with lock:
                body = json.dumps(events).encode()
            kind = "application/json"
        else:
            with lock:
                events.append(self.path)
            if "/img/" in self.path:
                body, kind = pixel, "image/png"
            elif "/css/" in self.path:
                body, kind = b"p { padding: 1px; }", "text/css"
            elif "/font/" in self.path:
                # The boundary being tested is whether the font request occurs,
                # not font decoding. Invalid font bytes still exercise fetching.
                body, kind = b"synthetic-font", "font/woff2"
            else:
                body, kind = b"synthetic disallowed resource", "text/plain"
        self.send_response(200)
        self.send_header("Content-Type", kind)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        self.do_GET()

server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Recorder)
thread = threading.Thread(target=server.serve_forever, daemon=True)
thread.start()
try:
    with tempfile.TemporaryDirectory(prefix="email-webkit-runtime-") as temporary:
        temporary = Path(temporary)
        swift = temporary / "EmailWebKitRuntime.swift"
        swift.write_text(harness)
        binary = temporary / "email-webkit-runtime"
        subprocess.run(["swiftc", "-swift-version", "5", "-parse-as-library", str(ROOT / "apple/DecisionInbox/Services/EmailHTMLPolicy.swift"), str(swift), "-o", str(binary)], check=True, timeout=60)
        result = subprocess.run([str(binary), f"http://127.0.0.1:{server.server_port}"], text=True, capture_output=True, timeout=55)
        print(result.stdout, end="")
        if result.returncode:
            print(result.stderr)
            print("Recorded requests:", json.dumps(events))
        raise SystemExit(result.returncode)
finally:
    server.shutdown()
    server.server_close()
