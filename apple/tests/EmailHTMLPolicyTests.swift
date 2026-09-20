import Foundation

@main struct EmailHTMLPolicyTests {
    static func main() {
        let hostile = #"<img src=https://example.invalid/pixel srcset='//example.invalid/2x 2x'><link rel=stylesheet href='https://example.invalid/css'><style>@import 'https://example.invalid/style';a{background:url(https://example.invalid/pixel)}</style><iframe src='https://example.invalid/frame'></iframe><script>alert(1)</script>"#
        let blocked = EmailHTMLPolicy.document(html: hostile, allowRemote: false)
        let consented = EmailHTMLPolicy.document(html: hostile, allowRemote: true)
        let blockedPolicy = blocked.components(separatedBy: "content=\"")[1].components(separatedBy: "\"")[0]
        precondition(!blockedPolicy.contains("https:"))
        precondition(!blockedPolicy.contains("http:"))
        precondition(blockedPolicy.contains("default-src 'none'"))
        precondition(blockedPolicy.contains("img-src data: cid:"))
        precondition(blocked.range(of: "Content-Security-Policy")!.lowerBound < blocked.range(of: hostile)!.lowerBound)
        for policy in [blocked, consented] {
            precondition(policy.contains("script-src 'none'"))
            precondition(policy.contains("frame-src 'none'"))
            precondition(policy.contains("form-action 'none'"))
            precondition(policy.contains("base-uri 'none'"))
        }
        precondition(consented.contains("img-src data: cid: https: http:"))
        print("PASS: email document deny-by-default policy, precedence and consent boundary. WebKit network recorder remains a separate runtime check.")
    }
}
