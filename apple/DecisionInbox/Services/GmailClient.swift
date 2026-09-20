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

    struct Draft: Codable, Equatable, Sendable {
        var to: [String]
        var cc: [String] = []
        var subject: String
        var body: String
        /// Set on a reply so Gmail files it in the existing conversation
        /// rather than starting a new one beside it.
        var threadID: String?
        var inReplyTo: String?
        var attachments: [FileAttachment] = []
    }

    struct FileAttachment: Codable, Equatable, Sendable {
        var filename: String
        var mimeType: String
        var data: Data
    }

    func unreadCount() async throws -> Int {
        var request = URLRequest(url: URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/labels/UNREAD")!)
        request.setValue("Bearer \(try await auth.validAccessToken(for: accountID))", forHTTPHeaderField: "Authorization")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw APIError.transport }
        struct Label: Decodable { let messagesUnread: Int }
        let count = try JSONDecoder().decode(Label.self, from: data).messagesUnread
        guard count >= 0 else { throw APIError.transport }
        return count
    }

    func send(_ draft: Draft) async throws {
        let raw = try Self.mimeMessage(draft)
        var payload: [String: Any] = ["raw": Data(raw.utf8).base64URLEncoded]
        if let threadID = draft.threadID { payload["threadId"] = threadID }

        var request = URLRequest(
            url: URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/send")!
        )
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("Bearer \(try await auth.validAccessToken(for: accountID))", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        // A provider/server failure does not establish that submission failed.
        guard http.statusCode < 500 else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else {
            struct Failure: Decodable { struct Detail: Decodable { let message: String }; let error: Detail }
            let reason = (try? JSONDecoder().decode(Failure.self, from: data).error.message) ?? "Gmail declined this email (\(http.statusCode))."
            throw GmailError.send(reason)
        }
    }

    static func mimeMessage(_ draft: Draft, boundary: String = "mail-\(UUID().uuidString)") throws -> String {
        let addresses = draft.to + draft.cc
        guard !draft.to.isEmpty, addresses.allSatisfy({ address in
            address.rangeOfCharacter(from: .newlines) == nil && address.contains("@")
        }) else { throw GmailError.send("Check the recipient addresses.") }
        guard draft.attachments.reduce(0, { $0 + $1.data.count }) <= 25_000_000 else {
            throw GmailError.send("The combined attachments exceed 25 MB. Remove a file or send a link.")
        }
        var headers = [
            "To: \(draft.to.joined(separator: ", "))",
            "Subject: \(Self.encodeHeader(draft.subject.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ")))",
            "MIME-Version: 1.0",
        ]
        if !draft.cc.isEmpty { headers.insert("Cc: \(draft.cc.joined(separator: ", "))", at: 1) }
        // A Gmail resource ID is not an RFC Message-ID. Only carry a real
        // header value; threadID is independently used for Gmail grouping.
        if let inReplyTo = draft.inReplyTo, inReplyTo.hasPrefix("<"), inReplyTo.hasSuffix(">"),
           inReplyTo.rangeOfCharacter(from: .newlines) == nil {
            headers.append("In-Reply-To: \(inReplyTo)")
            headers.append("References: \(inReplyTo)")
        }

        let textPart = "Content-Type: text/plain; charset=UTF-8\r\nContent-Transfer-Encoding: base64\r\n\r\n" + Data(draft.body.utf8).base64EncodedString(options: [.lineLength76Characters, .endLineWithCarriageReturn, .endLineWithLineFeed])
        if draft.attachments.isEmpty {
            return headers.joined(separator: "\r\n") + "\r\n" + textPart
        }
        headers.append("Content-Type: multipart/mixed; boundary=\"\(boundary)\"")
        var parts = [textPart]
        for attachment in draft.attachments {
            let filename = attachment.filename.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "attachment"
            let type = attachment.mimeType.range(of: #"^[a-zA-Z0-9.+-]+/[a-zA-Z0-9.+-]+$"#, options: .regularExpression) != nil
                ? attachment.mimeType : "application/octet-stream"
            parts.append("Content-Type: \(type)\r\nContent-Disposition: attachment; filename*=UTF-8''\(filename)\r\nContent-Transfer-Encoding: base64\r\n\r\n" + attachment.data.base64EncodedString(options: [.lineLength76Characters, .endLineWithCarriageReturn, .endLineWithLineFeed]))
        }
        return headers.joined(separator: "\r\n") + "\r\n\r\n--\(boundary)\r\n" + parts.joined(separator: "\r\n--\(boundary)\r\n") + "\r\n--\(boundary)--\r\n"
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
