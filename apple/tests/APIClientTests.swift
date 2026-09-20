import Foundation

/// Intercepts URLSession's real requests, including URL construction, query
/// encoding, headers, methods, status handling, and response decoding. Only
/// authentication is substituted; no credentials or live network are used.
final class AuthService {
    func validAccessToken(for id: String) async throws -> String { "test-token-" + id }
    func refreshToken(for id: String) -> String? { "test-refresh" }
    func expiresAt(for id: String) -> Double { 1_800_000_000 }
}
enum AuthError: Error { case signedOut }

final class ClientURLProtocol: URLProtocol {
    static var respond: ((URLRequest) throws -> (Int, Data))!
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, body) = try Self.respond(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                           headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

@main struct APIClientTests {
    struct Failed: Error, CustomStringConvertible { let description: String }
    static var checks = 0
    static func check(_ condition: @autoclosure () -> Bool, _ reason: String) throws {
        guard condition() else { throw Failed(description: reason) }
        checks += 1
    }
    static func data(_ value: Any) throws -> Data { try JSONSerialization.data(withJSONObject: value) }

    /// Express's query parser decodes + as a space, unlike URLComponents.
    /// Test the wire representation as the server actually receives it.
    static func serverQuery(_ url: URL) -> [String: String] {
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQuery ?? ""
        func decode(_ string: Substring) -> String {
            String(string).replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? ""
        }
        return Dictionary(uniqueKeysWithValues: query.split(separator: "&").map { field in
            let pair = field.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            return (decode(pair[0]), pair.count == 2 ? decode(pair[1]) : "")
        })
    }

    static func main() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ClientURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let zone = TimeZone(identifier: "Etc/GMT+5")!
        let client = APIClient(baseURL: URL(string: "https://api-client.test.invalid")!, auth: AuthService(),
                               accountID: "mailbox-one", session: session, timeZone: zone)
        let sectionDate = ISO8601DateFormatter().date(from: "2026-09-19T14:00:00Z")!
        let known = ["Message_A", "Message-B"]
        let cursorJSON: [String: Any] = ["v": 1, "account": "user-id", "snapshot": "2026-09-19T14:00:00.000Z",
            "sectionDate": "2026-09-19T14:00:00.000Z", "timeZone": zone.identifier,
            "before": [1_789_825_000_000, "Message_A"]]
        let cursor = try data(cursorJSON).base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")

        // Mirrors server/feedStorage.js page()+withCompleteness() wire keys.
        // Badge total includes mail excluded from feed sections (spam/trash).
        var metadata: [String: Any] = [
            "sections": ["today": 4, "yesterday": 30, "earlier": 400], "unreadCount": 450,
            "feedUnreadCount": 434, "allSyncedUnreadCount": 450, "syncedUnreadCount": 434,
            "countsComplete": true, "syncState": "complete", "syncCompletedAt": "2026-09-19T14:00:00.000Z",
            "countsAsOf": "2026-09-19T14:00:00.000Z", "sectionDate": "2026-09-19T14:00:00.000Z",
            "timeZone": zone.identifier, "knownReadMessageIds": ["Message-B"], "knownStateComplete": true,
        ]
        var feed = metadata
        feed["nextCursor"] = cursor
        feed["cards"] = [["messageId": "Message_A", "labelIds": ["UNREAD"], "fromEmail": "sender@example.com",
                          "internalDate": 1_789_825_000_000, "aiStatus": "done"],
                         ["messageId": 99]] as [[String: Any]]
        let feedBody = try data(feed)
        ClientURLProtocol.respond = { request in
            try check(request.url?.host == "api-client.test.invalid", "Tests cannot contact a live server")
            try check(request.url?.path == "/feed", "Query must not be percent-encoded into the route")
            try check(request.httpMethod == "GET", "Feed uses GET")
            try check(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token-mailbox-one", "Use this mailbox's token")
            try check(request.cachePolicy == .reloadIgnoringLocalCacheData, "Network feed bypasses stale HTTP cache")
            let query = serverQuery(request.url!)
            try check(query["timeZone"] == zone.identifier, "IANA timezone + must survive Express form decoding")
            try check(query["sectionDate"] == "2026-09-19T14:00:00Z", "Session date reaches the server intact")
            try check(query["knownMessageIds"] == known.joined(separator: ","), "Known-ID reconciliation survives query encoding")
            try check(query["cursor"] == cursor, "Opaque server cursor must round trip unchanged")
            try check(query.count == 4 && request.url?.fragment == nil, "No extra query fields or fragment")
            return (200, feedBody)
        }
        let page = try await client.feed(cursor: cursor, sectionDate: sectionDate, knownMessageIDs: known)
        try check(page.cards.map(\.messageId) == ["Message_A"] && page.droppedCards == 1, "Malformed card cannot discard a good page")
        try check(page.sections == FeedSectionCounts(today: 4, yesterday: 30, earlier: 400), "Decode exact server section keys")
        try check(page.unreadCount == 450 && page.countsComplete, "Badge and feed counts remain distinct")
        try check(page.knownReadMessageIds == ["Message-B"] && page.knownStateComplete, "Decode read reconciliation fields")
        try check(page.nextCursor == cursor, "Decode opaque next cursor")
        try check(!page.cards[0].asMessage(mailboxID: "mailbox-one").isRead, "UNREAD survives production card mapping")

        let countsBody = try data(metadata)
        ClientURLProtocol.respond = { request in
            try check(request.url?.path == "/feed/counts", "Counts route must not contain encoded question mark")
            let query = serverQuery(request.url!)
            try check(query["knownMessageIds"] == known.joined(separator: ","), "Counts carries reconciliation IDs")
            try check(query["timeZone"] == zone.identifier && query["sectionDate"] == "2026-09-19T14:00:00Z", "Counts shares feed boundaries")
            try check(query["cursor"] == nil, "Counts is not restricted to a page cursor")
            return (200, countsBody)
        }
        let counts = try await client.feedCounts(sectionDate: sectionDate, knownMessageIDs: known)
        try check(counts.sections.total == 434 && counts.unreadCount == 450 && counts.countsComplete, "Full counts decode without cards or cursor")
        try check(counts.knownReadMessageIds == ["Message-B"] && counts.knownStateComplete == true, "Counts reconciliation decodes")

        ClientURLProtocol.respond = { request in
            let query = serverQuery(request.url!)
            try check(query["cursor"] == nil && query["knownMessageIds"] == nil, "First page omits absent optional query fields")
            return (200, try data(["cards": [], "nextCursor": NSNull()]))
        }
        let legacy = try await client.feed(sectionDate: sectionDate)
        try check(legacy.unreadCount == nil && legacy.sections == nil && !legacy.countsComplete,
                  "Missing server counts are unknown, never confirmed zero")

        metadata["unreadCount"] = -1
        ClientURLProtocol.respond = { _ in (200, try data(metadata)) }
        let invalidCounts = try await client.feedCounts(sectionDate: sectionDate)
        try check(invalidCounts.unreadCount == nil && !invalidCounts.countsComplete && invalidCounts.knownStateComplete == false,
                  "Invalid provider count cannot certify completion")
        metadata["unreadCount"] = 0
        metadata["sections"] = ["today": -1, "yesterday": 0, "earlier": 0]
        ClientURLProtocol.respond = { _ in (200, try data(metadata)) }
        let invalidSections = try await client.feedCounts(sectionDate: sectionDate)
        try check(!invalidSections.countsComplete, "Negative section counts are not complete")

        let allMailCursor = 1_789_800_123_456
        ClientURLProtocol.respond = { request in
            try check(request.url?.path == "/all-mail", "Old posts use actual all-mail route")
            try check(serverQuery(request.url!)["cursor"] == String(allMailCursor), "Old-post timestamp cursor reaches server")
            return (200, try data(["cards": [["messageId": "older", "labelIds": []]], "nextCursor": allMailCursor - 50]))
        }
        let old = try await client.allMail(cursor: allMailCursor)
        try check(old.cards.first?.messageId == "older" && old.nextCursor == allMailCursor - 50, "Old-post cursor retains integer precision")

        let conversationID = "first.last+newsletter@example.com|second%2E/ç?#@example.net"
        ClientURLProtocol.respond = { request in
            let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
            let segments = components.percentEncodedPath.split(separator: "/")
            try check(segments.count == 3 && segments[0] == "conversations" && segments[2] == "messages", "Participant set is exactly one path segment")
            try check(String(segments[1]).removingPercentEncoding == conversationID, "Express's single path decode restores exact ID")
            try check(serverQuery(request.url!)["limit"] == "50" && components.fragment == nil, "ID punctuation cannot become pagination query or fragment")
            return (200, try data(["messages": [["messageId": "reply", "mine": false, "internalDate": 1_789_825_000_000]]]))
        }
        let messages = try await client.conversationMessages(conversationID)
        try check(messages.first?.messageId == "reply", "Conversation response decodes after transport")

        let peopleCursor = "opaque+page/with=punctuation"
        ClientURLProtocol.respond = { request in
            try check(request.url?.path == "/conversations", "People uses actual route")
            try check(serverQuery(request.url!)["cursor"] == peopleCursor, "People cursor round trips through form decoding")
            try check(serverQuery(request.url!)["limit"] == "50", "People response page is bounded")
            return (200, try data(["conversations": [], "nextCursor": "next", "totalConversations": 230,
                "unreadConversations": 47, "historyComplete": false, "historySyncState": "syncing"]))
        }
        let people = try await client.conversationsPage(cursor: peopleCursor)
        try check(people.totalConversations == 230 && people.unreadConversations == 47 && people.nextCursor == "next", "People totals cover more than the returned page")
        try check(people.historyComplete == false && people.historySyncState == "syncing", "Incomplete archive cannot certify exact totals")
        ClientURLProtocol.respond = { request in
            try check(serverQuery(request.url!)["cursor"] == peopleCursor, "Thread cursor round trips")
            let path = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.percentEncodedPath
            try check(String(path.split(separator: "/")[1]).removingPercentEncoding == conversationID,
                      "Thread ID remains one decoded component alongside cursor")
            return (200, try data(["messages": [], "nextCursor": NSNull(), "totalMessages": 1106,
                                  "historyComplete": true, "historySyncState": "complete", "sourcesPending": true]))
        }
        let threadPage = try await client.conversationMessagesPage(conversationID, cursor: peopleCursor)
        try check(threadPage.totalMessages == 1106 && threadPage.nextCursor == nil && threadPage.historyComplete == true,
                  "Thread count and pagination end decode independently of loaded bodies")
        try check(threadPage.sourcesPending == true,
                  "A complete historical inventory can still require body and inline-file refresh")

        ClientURLProtocol.respond = { request in
            try check(request.httpMethod == "PATCH" && request.url?.path == "/messages/Message_A/read", "Mark read keeps mutation method and route")
            return (200, try data(["wasUnread": true]))
        }
        let wasUnread = try await client.markRead("Message_A")
        try check(wasUnread == true, "Provider prior read state decodes")
        ClientURLProtocol.respond = { _ in (401, try data(["error": "unauthorized"])) }
        do { _ = try await client.allMail(); throw Failed(description: "401 must fail") }
        catch APIError.unauthorized { checks += 1 }
        ClientURLProtocol.respond = { _ in (500, try data(["error": "server unavailable"])) }
        do { _ = try await client.allMail(); throw Failed(description: "500 must fail") }
        catch APIError.server(500) { checks += 1 }
        ClientURLProtocol.respond = { request in
            try check(request.httpMethod == "DELETE" && request.url?.path == "/auth/account", "Disconnect uses account lifecycle route")
            try check(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token-mailbox-one", "Disconnect authenticates the selected mailbox")
            return (200, try data(["disconnected": true, "storedMailDeleted": false]))
        }
        try await client.disconnectAccount()
        ClientURLProtocol.respond = { _ in (200, try data(["disconnected": false])) }
        do { try await client.disconnectAccount(); throw Failed(description: "An unconfirmed response cannot remove local credentials") }
        catch APIError.transport { checks += 1 }
        ClientURLProtocol.respond = { _ in (503, try data(["error": "retry"])) }
        do { try await client.disconnectAccount(); throw Failed(description: "Failed disconnect must remain retryable") }
        catch APIError.server(503) { checks += 1 }
        print("\(checks) production API transport/decoding checks passed; no live network used")
    }
}
