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

    struct Recap: Codable, Equatable {
        let greeting: String?
        let summary: String?
        let totalInView: Int?
        let requireAttention: Int?
    }

    /// The server's card. Every AI field is optional because interpretation
    /// arrives after the message does — the UI reserves the slot and fills it.
    struct Card: Codable {
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
        /// The picture this particular email carried, proxied through our
        /// server. Distinct from the hero, which stands for the sender in
        /// general — this one is about *this* message.
        let imageUrl: String?
        /// `none` or `possible_scam`. Only ever set when the server could also
        /// say why — a flag it cannot explain is downgraded server-side.
        let riskLevel: String?
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

    /// Asks the model about one specific email. The body is fetched server-side
    /// rather than sent from here — the device has a snippet, and a question
    /// about an email deserves the whole email.
    func discuss(messageID: String, question: String) async throws -> String {
        let body = try JSONSerialization.data(withJSONObject: [
            "messageId": messageID, "question": question,
        ])
        let data = try await send(path: "/discuss", method: "POST", body: body)
        struct Answer: Decodable { let answer: String }
        return try JSONDecoder().decode(Answer.self, from: data).answer
    }

    /// A reply the model drafted. Offered to the composer, never inserted —
    /// a draft that types itself into the body is one careless tap from going
    /// out as though the user wrote it.
    func suggestReply(messageID: String) async throws -> String {
        let body = try JSONSerialization.data(withJSONObject: ["messageId": messageID])
        let data = try await send(path: "/suggest-reply", method: "POST", body: body)
        struct Draft: Decodable { let draft: String }
        return try JSONDecoder().decode(Draft.self, from: data).draft
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
        // The feed answered 304 and URLSession served a stale body from its
        // own cache. This data is the point of the app; it is never revalidated
        // against a local copy. Our own on-disk cache is the offline story.
        request.cachePolicy = .reloadIgnoringLocalCacheData
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
    /// Person or brand, which decides the avatar's shape and whether a
    /// generated hero image is allowed to stand in for a missing picture.
    ///
    /// It used to be `promo ? .brand : .person`, meaning the only brands in
    /// the product were the ones carrying a List-Unsubscribe header. So
    /// "Anthropic, PBC" was filed as a human being, got a circular avatar, and
    /// was refused the fallback image on the grounds that inventing a
    /// photograph of a person would be a lie — correct rule, wrong subject.
    static func senderKind(name: String?, address: String?, promo: Bool) -> Sender.Kind {
        let name = (name ?? "").trimmingCharacters(in: .whitespaces)
        let local = (address ?? "").split(separator: "@").first.map(String.init)?.lowercased() ?? ""

        if promo { return .brand }
        if name.isEmpty && local.isEmpty { return .unknown }

        // A mailbox nobody reads belongs to a company, whatever it signs
        // itself as. This is the strongest signal available and it is in the
        // address rather than the display name, which senders style freely.
        let automated = [
            "noreply", "no-reply", "donotreply", "do-not-reply", "notification",
            "notifications", "mailer", "mail", "support", "help", "info",
            "hello", "team", "news", "newsletter", "updates", "update",
            "receipts", "receipt", "billing", "invoice", "account", "accounts",
            "alerts", "alert", "service", "contact", "admin", "automated",
        ]
        if automated.contains(where: { local == $0 || local.hasPrefix($0 + "-") || local.hasPrefix($0 + ".") }) {
            return .brand
        }

        // Legal suffixes are decisive; nobody is called "PBC".
        let lowered = name.lowercased()
        let corporate = [" inc", " inc.", " llc", " ltd", " ltd.", " corp", " corp.",
                         " pbc", " co.", " gmbh", " plc", " s.a.", " b.v."]
        if corporate.contains(where: { lowered.hasSuffix($0) || lowered.contains($0 + ",") }) {
            return .brand
        }

        // A person's display name is a given name and a family name. One word
        // ("Vercel", "StockX") or four is a company; two or three is a person,
        // which also lets "Maria van der Berg" through.
        let words = name.split(separator: " ").filter { !$0.isEmpty }
        if name.isEmpty { return .brand }
        return (2...3).contains(words.count) ? .person : .brand
    }

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
                kind: Self.senderKind(name: fromName, address: fromEmail, promo: promo),
                logoURL: avatarUri.flatMap(URL.init(string:))
            ),
            subject: subject ?? "",
            snippet: snippet ?? "",
            receivedAt: Date(timeIntervalSince1970: (internalDate ?? 0) / 1000),
            quote: quote,
            summary: summary,
            actionLabel: action,
            actionURL: actionUrl.flatMap(URL.init(string:)),
            // Placeholders — `reinterpret` decides both from the fields above.
            kicker: .reading,
            shape: .text,
            heroImageURL: heroImageUrl.flatMap(URL.init(string:)),
            heroBackground: heroImageBgColor,
            imageURL: imageUrl.flatMap(URL.init(string:)),
            isRead: !(labelIds ?? []).contains("UNREAD"),
            isSaved: false,
            threadCount: 1,
            unsubscribeURL: unsubscribeUrl.flatMap(URL.init(string:)),
            requiresAttention: requiresAttention ?? false,
            isAtRisk: riskLevel == "possible_scam",
            isInterpreting: interpreting
        )
        message.reinterpret(failed: failed)

        // The email's own picture wins over the sender's generated one, for
        // everybody — a photograph of the apartment StreetEasy is showing you
        // says more than a photograph of what StreetEasy is like, and it is
        // the real thing rather than a stand-in. It is not restricted to bulk
        // senders: a person who sent you a picture sent you a picture.
        //
        // The hero stays as the fallback for designed mail with nothing
        // usable in it. People still never get a *generated* image; an
        // invented photograph attached to a human would be a lie.
        if !failed, let picture = message.imageURL {
            message.shape = .media([picture])
        } else if !failed, message.sender.kind == .brand, let hero = message.heroImageURL {
            // Roughly half of all mail carries no picture of its own — a plain
            // receipt has nothing to show — and a feed where every other post
            // is a block of text does not read as a feed. A brand always has
            // its generated hero to fall back on.
            //
            // Still never for a person: an invented photograph attached to a
            // human being is a lie, and the absence is the honest answer.
            message.shape = .media([hero])
        }
        return message
    }
}
