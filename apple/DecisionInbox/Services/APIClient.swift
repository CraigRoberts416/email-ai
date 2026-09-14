import Foundation

/// Talks to the existing Node server. The payload shapes mirror `/feed` and
/// `/all-mail` exactly, so swapping the sample data for this is a decode
/// rather than a refactor.
struct APIClient {
    var baseURL = URL(string: "https://email-ai-server.onrender.com")!
    let auth: AuthService
    /// The mailbox this client speaks for. Every request carries that
    /// mailbox's own token, which is how the server tells the sessions apart.
    let accountID: String

    // MARK: Wire types

    struct FeedResponse: Decodable {
        let cards: [Card]
        let recap: Recap?

        /// Decodes cards individually. A single unexpected field in one card
        /// used to throw for the whole response, which emptied the feed and
        /// reported nothing — the same fault as a hero image taking down
        /// /feed. One bad card should cost one post.
        private struct Lossy: Decodable {
            let card: Card?
            init(from decoder: Decoder) throws {
                do { card = try Card(from: decoder) } catch {
                    print("[feed] card dropped: \(error)")
                    card = nil
                }
            }
        }

        enum CodingKeys: String, CodingKey { case cards, recap }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let lossy = try container.decode([Lossy].self, forKey: .cards)
            cards = lossy.compactMap(\.card)
            recap = try? container.decodeIfPresent(Recap.self, forKey: .recap)
            if lossy.count != cards.count {
                print("[feed] kept \(cards.count) of \(lossy.count) cards")
            }
        }
    }

    struct AllMailResponse: Decodable {
        let cards: [Card]
        let nextCursor: Int?
    }

    struct Recap: Decodable, Equatable {
        let greeting: String?
        let summary: String?
        let totalInView: Int?
        let requireAttention: Int?
    }

    /// The server's card. Every AI field is optional because interpretation
    /// arrives after the message does — the UI reserves the slot and fills it.
    struct Card: Decodable {
        let messageId: String
        let threadId: String?
        let labelIds: [String]?
        let subject: String?
        let fromName: String?
        let fromEmail: String?
        let snippet: String?
        let internalDate: Double?
        let aiStatus: String?
        let quote: String?
        let summary: String?
        let action: String?
        let actionUrl: String?
        let requiresAttention: Bool?
        let unsubscribeUrl: String?
        let avatarUri: String?
        let avatarFallbackText: String?
        let heroImageUrl: String?
        let heroImageBgColor: String?
    }

    // MARK: Requests

    func feed() async throws -> FeedResponse {
        try await get("/feed")
    }

    func allMail(cursor: Int? = nil) async throws -> AllMailResponse {
        try await get(cursor.map { "/all-mail?cursor=\($0)" } ?? "/all-mail")
    }

    func markRead(_ messageID: String) async throws {
        _ = try await send(path: "/messages/\(messageID)/read", method: "PATCH", body: nil)
    }

    struct Body: Decodable {
        let plainText: String
        let htmlRaw: String
    }

    func body(of messageID: String) async throws -> Body {
        try await get("/messages/\(messageID)/body")
    }

    /// The masthead. Written fresh each session rather than assembled from a
    /// template — the whole point is that it reads like someone who has seen
    /// this particular inbox, not a counter with a sentence around it.
    func sessionRecap(cards: [Card], timeOfDay: String) async throws -> Recap {
        let payload: [[String: Any]] = cards.map { card in
            [
                "fromName": card.fromName ?? "",
                "fromEmail": card.fromEmail ?? "",
                "subject": card.subject ?? "",
                "summary": card.summary ?? card.snippet ?? "",
                "action": card.action ?? "",
                "requiresAttention": card.requiresAttention ?? false,
            ]
        }
        let body = try JSONSerialization.data(withJSONObject: [
            "cards": payload, "timeOfDay": timeOfDay,
        ])
        let data = try await send(path: "/session-recap", method: "POST", body: body)
        struct Wrapper: Decodable { let recap: Recap }
        return try JSONDecoder().decode(Wrapper.self, from: data).recap
    }

    /// Button labels and tab names, also generated. Cached server-side per user,
    /// so asking on launch costs one request and the words stay stable after.
    func uiCopy() async throws -> UICopy {
        try await get("/ui-copy")
    }

    struct UICopy: Decodable {
        let connectGmail: String?
        let mailFeed: String?
        let allMail: String?
        let loadingMore: String?
        let loadMore: String?
        let unsubscribeStart: String?
        let inView: String?
        let needAttention: String?
    }

    /// Kicks off the headless-browser agent. Progress arrives over SSE, not here.
    func unsubscribe(messageID: String, url: String, senderName: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: [
            "messageId": messageID, "unsubscribeUrl": url, "senderName": senderName,
        ])
        _ = try await send(path: "/unsubscribe", method: "POST", body: body)
    }

    /// Hands the server a refresh token so it can sync in the background and
    /// keep the Gmail watch alive while the app is closed.
    func register() async throws {
        guard let refresh = auth.refreshToken(for: accountID) else { throw AuthError.signedOut }
        let body = try JSONSerialization.data(withJSONObject: [
            "refreshToken": refresh,
            "expiresAt": auth.expiresAt(for: accountID) * 1000,
        ])
        _ = try await send(path: "/auth/register", method: "POST", body: body)
    }

    // MARK: Plumbing

    private func get<T: Decodable>(_ path: String) async throws -> T {
        let data = try await send(path: path, method: "GET", body: nil)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func send(path: String, method: String, body: Data?) async throws -> Data {
        let token = try await auth.validAccessToken(for: accountID)
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.transport }
        guard (200..<300).contains(http.statusCode) else {
            throw http.statusCode == 401 ? APIError.unauthorized : APIError.server(http.statusCode)
        }
        return data
    }
}

enum APIError: LocalizedError {
    case transport
    case unauthorized
    case server(Int)

    var errorDescription: String? {
        switch self {
        case .transport: return "Could not reach the server."
        case .unauthorized: return "That mailbox needs reconnecting."
        case .server(let code): return "The server returned \(code)."
        }
    }
}

// MARK: - Mapping
//
// Everything the design needs that the server does not yet send is derived
// here, in one place, so the views never guess.

extension APIClient.Card {
    func asMessage(mailboxID: String) -> Message {
        let failed = aiStatus == "error"
        let interpreting = !failed && aiStatus != "done"
        let promo = unsubscribeUrl?.isEmpty == false

        var message = Message(
            id: messageId,
            threadID: threadId,
            mailboxID: mailboxID,
            sender: Sender(
                name: fromName ?? "",
                address: fromEmail ?? "",
                kind: promo ? .brand : ((fromName?.isEmpty ?? true) ? .unknown : .person),
                logoURL: avatarUri.flatMap(URL.init(string:))
            ),
            subject: subject ?? "",
            snippet: snippet ?? "",
            receivedAt: Date(timeIntervalSince1970: (internalDate ?? 0) / 1000),
            quote: quote,
            summary: summary,
            actionLabel: action,
            actionURL: actionUrl.flatMap(URL.init(string:)),
            // Placeholders — `reinterpret` decides all three from the fields above.
            kicker: .reading,
            density: .standard,
            shape: .text,
            heroImageURL: heroImageUrl.flatMap(URL.init(string:)),
            heroBackground: heroImageBgColor,
            isRead: !(labelIds ?? []).contains("UNREAD"),
            isSaved: false,
            threadCount: 1,
            unsubscribeURL: unsubscribeUrl.flatMap(URL.init(string:)),
            requiresAttention: requiresAttention ?? false,
            isInterpreting: interpreting
        )
        message.reinterpret(failed: failed)

        // A bulk sender with a generated hero gets the image shape: their mail
        // is already designed, and a picture of the brand reads faster than a
        // second line of grey text. People never get one — a generated image
        // of a person would be a lie.
        if !failed, promo, let hero = message.heroImageURL {
            message.shape = .media([hero])
        }
        return message
    }
}
