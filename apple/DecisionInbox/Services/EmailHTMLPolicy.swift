import Foundation

/// The policy is injected before any sender-controlled markup. It is never loosened by sender content.
enum EmailHTMLPolicy {
    static func document(html: String, allowRemote: Bool) -> String {
        let remote = allowRemote ? " https: http:" : ""
        let policy = "default-src 'none'; script-src 'none'; style-src 'unsafe-inline'\(remote); img-src data: cid:\(remote); font-src data:\(remote); media-src 'none'; frame-src 'none'; object-src 'none'; connect-src 'none'; base-uri 'none'; form-action 'none'"

        // A viewport meta and a width clamp, because bulk senders still ship
        // 600px fixed-width tables that would otherwise force a sideways scroll.
        return """
        <!doctype html><html><head>
        <meta http-equiv="Content-Security-Policy" content="\(policy)">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
          :root { color-scheme: light; }
          /* No horizontal padding: the card that hosts this already owns the
             margin, and adding a second one cost the sender 32pt of the 358
             they had — enough to break a 320px table layout. */
          html, body { margin: 0; padding: 0; background: transparent;
            font: 16px/1.45 -apple-system, system-ui, sans-serif; color: #000;
            -webkit-text-size-adjust: 100%; word-break: break-word; }
          img, video, table, pre { max-width: 100% !important; height: auto; }
          table { width: 100% !important; }
          a { color: #000; }
        </style></head><body>\(html)</body></html>
        """
    }

}
