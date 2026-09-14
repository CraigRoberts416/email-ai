import Foundation

/// Sending talks to Gmail directly.
///
/// The app already holds the `https://mail.google.com/` scope, so routing a
/// send through our own server would add a hop, a queue, and a place for
/// somebody's reply to get stuck — without adding anything. The server owns
/// interpretation; Gmail owns the mailbox.
struct GmailClient {
    let auth: AuthService
    /// Which mailbox the message is sent from.
    let accountID: String

    struct Draft {
        var to: [String]
        var cc: [String] = []
        var subject: String
        var body: String
        /// Set on a reply so Gmail files it in the existing conversation
        /// rather than starting a new one beside it.
        var threadID: String?
        var inReplyTo: String?
    }

    func send(_ draft: Draft) async throws {
        var headers = [
            "To: \(draft.to.joined(separator: ", "))",
            "Subject: \(Self.encodeHeader(draft.subject))",
            "MIME-Version: 1.0",
            "Content-Type: text/plain; charset=UTF-8",
        ]
        if !draft.cc.isEmpty { headers.insert("Cc: \(draft.cc.joined(separator: ", "))", at: 1) }
        if let inReplyTo = draft.inReplyTo {
            headers.append("In-Reply-To: \(inReplyTo)")
            headers.append("References: \(inReplyTo)")
        }

        let raw = (headers.joined(separator: "\r\n") + "\r\n\r\n" + draft.body)
        var payload: [String: Any] = ["raw": Data(raw.utf8).base64URLEncoded]
        if let threadID = draft.threadID { payload["threadId"] = threadID }

        var request = URLRequest(
            url: URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/send")!
        )
        request.httpMethod = "POST"
        request.setValue("Bearer \(try await auth.validAccessToken(for: accountID))", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw GmailError.send(String(decoding: data, as: UTF8.self))
        }
    }

    /// Removes INBOX, which is what archiving is. Marking read is a different
    /// act and was all the app was doing — so a message the user archived
    /// stayed in their inbox on every other client they own.
    func archive(messageID: String) async throws {
        var request = URLRequest(
            url: URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/\(messageID)/modify")!
        )
        request.httpMethod = "POST"
        request.setValue("Bearer \(try await auth.validAccessToken(for: accountID))", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: ["removeLabelIds": ["INBOX", "UNREAD"]]
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw GmailError.send(String(decoding: data, as: UTF8.self))
        }
    }

    /// RFC 2047 for anything outside ASCII, so an em dash in a subject line
    /// does not arrive as mojibake.
    private static func encodeHeader(_ value: String) -> String {
        guard value.contains(where: { !$0.isASCII }) else { return value }
        return "=?UTF-8?B?\(Data(value.utf8).base64EncodedString())?="
    }
}

enum GmailError: LocalizedError {
    case send(String)

    var errorDescription: String? {
        switch self {
        case .send(let detail):
            return detail.isEmpty ? "Gmail wouldn\u{2019}t accept that message." : detail
        }
    }
}

extension Data {
    var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
