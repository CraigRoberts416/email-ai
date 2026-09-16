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
        /// One line about who this sender is, generated per domain. Nil when
        /// the model did not recognise them — a blank is a missing sentence,
        /// a guess would be a false claim about a real company.
        let senderDescription: String?
        /// The picture this particular email carried, proxied through our
        /// server. Distinct from the hero, which stands for the sender in
        /// general — this one is about *this* message.
        let imageUrl: String?
        /// Files the email carried. Metadata only — an image gets a signed
        /// thumbnail URL, a document gets none because there is nothing to
        /// show.
        let attachments: [AttachmentWire]?
        /// `none` or `possible_scam`. Only ever set when the server could also
        /// say why — a flag it cannot explain is downgraded server-side.
        let riskLevel: String?
    }

    struct AttachmentWire: Codable {
        let id: String
        let filename: String
        let mimeType: String?
        let byteCount: Int?
        let isImage: Bool?
        let pages: Int?
        let previewUrl: String?
        /// The original bytes, under the sender's own content type. The
        /// preview URL is a resized image and cannot stand in for a PDF.
        let fileUrl: String?
    }

    // MARK: Conversations

    // Codable, not just Decodable: these are cached to disk so the People
    // list renders from what was true a minute ago instead of an empty screen.
    struct ConversationWire: Codable {
        struct Participant: Codable {
            let name: String?
            let email: String
            /// Their organisation's mark, not a photograph of them. See the
            /// server note — a person at a company is recognisable by it, and
            /// nothing here reaches a third party with their address.
            let avatarUri: String?
        }
        let id: String
        let participants: [Participant]
        let preview: String?
        let lastAt: Double
        let lastFromMe: Bool?
        let unread: Bool?
        let messageCount: Int?
    }

    // Codable so a thread can be cached and render before the network answers.
    struct ConversationMessageWire: Codable {
        let messageId: String
        let subject: String?
        let fromName: String?
        let fromEmail: String?
        let avatarUri: String?
        let mine: Bool
        let body: String?
        let internalDate: Double
        let attachments: [AttachmentWire]?
    }

    func conversations() async throws -> [ConversationWire] {
        struct Wrapper: Decodable { let conversations: [ConversationWire] }
        let wrapper: Wrapper = try await get("/conversations")
        return wrapper.conversations
    }

    func conversationMessages(_ id: String) async throws -> [ConversationMessageWire] {
        struct Wrapper: Decodable { let messages: [ConversationMessageWire] }
        // NOT percent-encoded here. `URL.appending(path:)` escapes what it is
        // given, so a pre-encoded id arrived double-escaped: `%2E` became
        // `%252E`, the server decoded it once back to `%2E`, and the
        // participant set never matched anything. Every thread opened empty.
        let wrapper: Wrapper = try await get("/conversations/\(id)/messages")
        return wrapper.messages
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
            senderDescription: senderDescription,
            imageURL: imageUrl.flatMap(URL.init(string:)),
            attachments: (attachments ?? []).map { wire in
                Attachment(
                    id: wire.id,
                    filename: wire.filename,
                    byteCount: wire.byteCount ?? 0,
                    // A document shows its type rather than a drawn page: the
                    // page count is not in the metadata Gmail returns, and a
                    // number we did not count is not one to print.
                    preview: (wire.isImage == true)
                        ? (wire.previewUrl.flatMap(URL.init(string:)).map(Attachment.Preview.image)
                            ?? .document(pages: 0))
                        : .document(pages: wire.pages ?? 0),
                    fileURL: wire.fileUrl.flatMap(URL.init(string:)),
                    mimeType: wire.mimeType
                )
            },
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
        // SPEC: a picture on a feed card is ALWAYS from the email itself, and
        // never the generated hero. No exceptions, for any sender.
        //
        // The hero is a portrait of a sender in general. On a card it would be
        // making a claim about *this message* using an image that has nothing
        // to do with it — a painting of an aircraft above a receipt for a
        // seat-selection fee. It is decoration wearing the clothes of evidence,
        // and in a product whose entire premise is that the quote is verbatim
        // and the summary is grounded, that is the one thing the card cannot
        // be allowed to do.
        //
        // A card with no picture is the honest and common case: roughly half
        // of all mail carries no image worth showing. It gets text, and text
        // is not a failure state.
        //
        // The hero keeps its job on the thread screen, where it is plainly the
        // sender's banner and is not standing in for content.
        if !failed, let picture = message.imageURL {
            message.shape = .media([picture])
        }
        return message
    }
}
