import Foundation

// Service doubles only. The executable compiles the production FeedStore,
// APIClient (including decoding/mapping), FeedSession, and pagination lifecycle.
// Every URL is intercepted; a missing fixture is a test failure, never a request
// to a real mailbox. Preferences, disk caches, badges, and Gmail are in memory.
@MainActor final class UserDefaults {
    static let standard = UserDefaults()
    private var values: [String: Any] = [:]
    func object(forKey key: String) -> Any? { values[key] }
    func stringArray(forKey key: String) -> [String]? { values[key] as? [String] }
    func set(_ value: Any?, forKey key: String) { values[key] = value }
}

enum AuthError: Error { case signedOut }
final class AuthService {
    struct Account { let id: String; var tag = "TEST" }
    var accounts: [Account]
    init(accounts: [String] = []) { self.accounts = accounts.map { Account(id: $0) } }
    func validAccessToken(for id: String) async throws -> String { id }
    func refreshToken(for id: String) -> String? { "fixture-refresh" }
    func expiresAt(for id: String) -> Double { Date().timeIntervalSince1970 + 3600 }
    func connect() async -> Account? { nil }
    func disconnect(_ id: String) { accounts.removeAll { $0.id == id } }
    func rename(_ id: String, tag: String) {
        if let index = accounts.firstIndex(where: { $0.id == id }) { accounts[index].tag = tag }
    }
}

@MainActor struct GmailClient {
    struct Draft { var to: [String] = [] }
    let auth: AuthService
    let accountID: String
    func unreadCount() async throws -> Int { HarnessTransport.accounts[accountID]?.badge ?? 0 }
    func archive(messageID: String) async throws {
        HarnessTransport.accounts[accountID]?.archives.append(messageID)
    }
    func send(_ draft: Draft) async throws {}
}

@MainActor final class UNUserNotificationCenter {
    static let instance = UNUserNotificationCenter()
    static func current() -> UNUserNotificationCenter { instance }
    private(set) var badge = 0
    func setBadgeCount(_ count: Int) async throws { badge = count }
}
enum Haptics { static func commit() {}; static func needsYou() {} }
enum Move { static let undoWindow = 0.02; static let sendUndoWindow = 0.02 }

@MainActor final class SenderIdentityStore {
    static let shared = SenderIdentityStore()
    func configure(auth: AuthService, isSample: Bool) {}
    func remember(messages: [Message]) {}
    func clearCache() {}
}
@MainActor final class RemoteImageStore {
    static let shared = RemoteImageStore()
    func clearCache() {}
}
@MainActor enum FeedCache {
    struct Cached { let cards: [APIClient.Card]; let recap: APIClient.Recap? }
    static var feeds: [String: Cached] = [:]
    static func load(for account: String) -> Cached? { feeds[account] }
    static func save(_ cards: [APIClient.Card], recap: APIClient.Recap?, for account: String) {
        feeds[account] = Cached(cards: cards, recap: recap)
    }
    static func clear(for account: String) { feeds[account] = nil }
    static func clearAll() { feeds.removeAll() }
    static func loadConversations(for account: String) -> [APIClient.ConversationWire]? { nil }
    static func saveConversations(_ value: [APIClient.ConversationWire], for account: String) {}
    static func loadMessages(account: String, conversation: String) -> [APIClient.ConversationMessageWire]? { nil }
    static func saveMessages(_ value: [APIClient.ConversationMessageWire], account: String, conversation: String) {}
    static func saveBody(_ value: APIClient.Body, account: String, message: String) {}
}

@MainActor final class SSEClient {
    enum Event {
        case messageAdded(APIClient.Card)
        case messageRead(String, wasUnread: Bool?)
        case processing(String)
        case chunk(messageID: String, field: String, text: String)
        case fieldComplete(messageID: String, field: String, value: String?)
        case messageReady(String)
        case unsubscribeStatus(UnsubscribeStatus)
    }
    struct UnsubscribeStatus {
        let messageId: String
        let senderName: String?
        let status: String
        let message: String?
        let index: Int?
        let total: Int?
        let fieldIndex: Int?
        let fieldTotal: Int?
        enum Step { case done, working }
        var step: Step { .working }
    }
    let accountID: String
    init(baseURL: URL, auth: AuthService, accountID: String) { self.accountID = accountID }
    func connect(_ handler: @escaping @Sendable (Event) async -> Void) async {
        HarnessTransport.accounts[accountID]?.onEvent = handler
    }
    func disconnect() async { HarnessTransport.accounts[accountID]?.onEvent = nil }
}

struct HarnessReply {
    var status = 200
    var json: [String: Any]
}

@MainActor final class HarnessAccount {
    var badge = 0
    var archives: [String] = []
    var requests: [URLRequest] = []
    var onEvent: (@Sendable (SSEClient.Event) async -> Void)?
    var feed: (String?, [String]) async throws -> HarnessReply = { _, _ in
        throw HarnessFailure(message: "Unexpected feed request")
    }
    var counts: ([String]) async throws -> HarnessReply = { _ in
        throw HarnessFailure(message: "Unexpected counts request")
    }
    var conversations: (String?) async throws -> HarnessReply = { _ in
        throw HarnessFailure(message: "Unexpected People request")
    }

    var read: (String) async throws -> HarnessReply = { _ in
        HarnessReply(json: ["success": true, "wasUnread": true, "readChanged": true])
    }
    var messageCard: (String) async throws -> HarnessReply = { _ in
        throw HarnessFailure(message: "Unexpected notification card request")
    }
    func emit(_ event: SSEClient.Event) async {
        guard let onEvent else { preconditionFailure("SSE must be connected before emission") }
        await onEvent(event)
    }
}

struct HarnessFailure: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

@MainActor enum HarnessTransport {
    static var accounts: [String: HarnessAccount] = [:]
    static var unexpected: [String] = []

    static func reply(to request: URLRequest) async throws -> HarnessReply {
        let accountID = String((request.value(forHTTPHeaderField: "Authorization") ?? "").dropFirst(7))
        guard let account = accounts[accountID], let url = request.url else {
            unexpected.append("Request outside fixture")
            throw HarnessFailure(message: "No fixture for request")
        }
        account.requests.append(request)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func query(_ name: String) -> String? { items.first { $0.name == name }?.value }
        let known = query("knownMessageIds")?.split(separator: ",").map(String.init) ?? []
        switch url.path {
        case "/feed": return try await account.feed(query("cursor"), known)
        case "/feed/counts": return try await account.counts(known)
        case "/conversations": return try await account.conversations(query("cursor"))
        case "/auth/register", "/auth/push-token": return HarnessReply(json: ["success": true])
        case "/session-recap": return HarnessReply(json: ["recap": [:]])
        default:
            if url.path.hasPrefix("/messages/"), url.path.hasSuffix("/card") {
                return try await account.messageCard(String(url.path.dropFirst(10).dropLast(5)))
            }
            if url.path.hasPrefix("/messages/"), url.path.hasSuffix("/read") {
                return try await account.read(String(url.path.dropFirst(10).dropLast(5)))
            }
            unexpected.append(url.path)
            throw HarnessFailure(message: "Unstubbed route: \(url.path)")
        }
    }
}

final class HarnessURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Task { @MainActor in
            do {
                let reply = try await HarnessTransport.reply(to: request)
                let data = try JSONSerialization.data(withJSONObject: reply.json)
                let response = HTTPURLResponse(url: request.url!, statusCode: reply.status,
                                               httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }
    }
    override func stopLoading() {}
}

@MainActor final class HarnessGate {
    private var waiter: CheckedContinuation<HarnessReply, Never>?
    var waiting: Bool { waiter != nil }
    func wait() async -> HarnessReply {
        await withCheckedContinuation { waiter = $0 }
    }
    func finish(_ reply: HarnessReply) {
        guard let waiter else { preconditionFailure("Gate was not waiting") }
        self.waiter = nil
        waiter.resume(returning: reply)
    }
}
