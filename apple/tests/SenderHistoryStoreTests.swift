import Foundation

final class AuthService {
    struct Account { let id: String }
    var accounts: [Account]
    init(_ ids: [String]) { accounts = ids.map { Account(id: $0) } }
    func validAccessToken(for id: String) async throws -> String { id }
    func refreshToken(for id: String) -> String? { "test" }
    func expiresAt(for id: String) -> Double { 1_800_000_000 }
}
enum AuthError: Error { case signedOut }
@MainActor final class SenderIdentityStore {
    static let shared = SenderIdentityStore()
    func remember(messages: [Message]) {}
}
final class HistoryProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> [String: Any])!
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let body = try JSONSerialization.data(withJSONObject: Self.handler(request))
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
@main struct HistoryTests {
    static var checks = 0
    static func check(_ test: @autoclosure () -> Bool, _ reason: String) { precondition(test(), reason); checks += 1 }
    static func card(_ id: String, _ date: Int = 100) -> [String: Any] {
        ["messageId": id, "internalDate": date, "fromEmail": "orders@amazon.com", "fromName": "Amazon", "subject": "Real subject", "snippet": "Real preview", "labelIds": [], "aiStatus": "pending", "sourceInspected": true]
    }
    static func page(_ cards: [[String: Any]], total: Int?, cursor: String? = nil, complete: Bool = true, state: String = "complete", pending: Int = 0) -> [String: Any] {
        ["cards": cards, "nextCursor": cursor as Any? ?? NSNull(), "totalCount": total as Any? ?? NSNull(), "countComplete": complete,
         "syncState": state, "scope": "domain", "scopeKey": "amazon.com", "sourcePendingCount": pending]
    }
    @MainActor static func main() async throws {
        URLProtocol.registerClass(HistoryProtocol.self)
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir); URLProtocol.unregisterClass(HistoryProtocol.self) }
        let cache = IdentityDiskCache(directory: dir)
        let auth = AuthService(["one", "two"])
        let sender = Sender(name: "Amazon", address: "orders@amazon.com", kind: .brand)
        var calls = 0
        HistoryProtocol.handler = { request in
            calls += 1
            let account = request.value(forHTTPHeaderField: "Authorization")!
            let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            precondition(items.first { $0.name == "kind" }?.value == "brand")
            if account == "Bearer two" { return page([card("same", 50)], total: 1) }
            if items.contains(where: { $0.name == "cursor" }) { return page([card("same"), card("older", 10)], total: 2) }
            return page([card("same")], total: 2, cursor: "older-page")
        }
        let history = SenderHistoryStore(auth: auth, sender: sender, sample: false, seed: [], cache: cache)
        check(history.totalCount == nil, "Unknown is not zero")
        await history.start()
        check(history.totalCount == 3, "Independent connected-account totals aggregate")
        check(history.messages.count == 2 && history.hasMore, "Count includes unloaded history")
        check(!history.isExhausted, "First page cannot imply end")
        check(history.messages.allSatisfy { $0.isRead }, "Read emails belong in profile history")
        check(history.messages.allSatisfy { $0.kicker == .original && !$0.isInterpreting && $0.quote == nil }, "Uninterpreted history shows source without fake summary or spinner")
        await history.loadMore()
        check(history.messages.count == 3 && history.isExhausted, "Duplicate pages merge and complete history reaches verified end")
        check(history.sourcesComplete, "Inspected complete source supports media/document absence")
        check(history.messages.map(\.id) == ["same", "same", "older"], "Newest first across mailboxes with account-scoped identity")
        let cached = SenderHistoryStore(auth: auth, sender: sender, sample: false, seed: [], cache: cache)
        check(cached.messages.count == 3, "History cached independently of feed")
        check(cached.totalCount == nil, "Cached subset never claims full total before verification")
        HistoryProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        await cached.start()
        check(cached.messages.count == 3 && cached.failure != nil && !cached.isExhausted, "Failure preserves cached history and blocks false end")
        HistoryProtocol.handler = { _ in page([], total: 0) }
        await cached.start()
        check(cached.totalCount == 0 && cached.messages.isEmpty && cached.isExhausted, "Provider-confirmed empty history clears stale cache")
        let sample = SenderHistoryStore(auth: auth, sender: sender, sample: true, seed: [], cache: cache)
        let before = calls
        await sample.start(); await sample.loadMore()
        check(calls == before && sample.totalCount == 0, "Sample history has no network side effects")

        let single = AuthService(["one"])
        let hydrated = SenderHistoryStore(auth: single, sender: sender, sample: false, seed: [], cache: cache, pollingInterval: .zero)
        var sourcePass = 0
        HistoryProtocol.handler = { _ in
            sourcePass += 1
            var source = card("source")
            source["sourceInspected"] = sourcePass > 1
            if sourcePass > 1 { source["originalText"] = "The original email body." }
            return page([source], total: 1, pending: sourcePass > 1 ? 0 : 1)
        }
        await hydrated.start()
        check(sourcePass == 2 && hydrated.sourcesComplete, "Pending source polls the same page to inspection completion")
        check(hydrated.messages.first?.snippet == "The original email body.", "Original body replaces short cached preview without AI")
        sourcePass = 0
        HistoryProtocol.handler = { _ in
            sourcePass += 1
            var source = card("source"); source["sourceInspected"] = false
            return page([source], total: 1, pending: 1)
        }
        await hydrated.start()
        check(sourcePass == 10 && hydrated.failure != nil && !hydrated.sourcesComplete, "Unreachable source ends bounded polling with retry, never a false empty gallery")
        check(hydrated.messages.count == 1 && hydrated.totalCount == 1, "Source failure retains content and an independently verified count")
        HistoryProtocol.handler = { _ in page([card("source")], total: 1) }
        await hydrated.start()
        check(hydrated.failure == nil && hydrated.sourcesComplete, "Retry recovers failed source inspection")

        var syncPass = 0
        HistoryProtocol.handler = { _ in
            syncPass += 1
            return syncPass == 1 ? page([card("new")], total: nil, complete: false, state: "syncing")
                : page([card("new"), card("old", 1)], total: 2)
        }
        await hydrated.start()
        check(syncPass == 2 && hydrated.totalCount == 2 && hydrated.isExhausted, "Incomplete enumeration polls until full membership is known")

        syncPass = 0
        HistoryProtocol.handler = { _ in
            syncPass += 1
            if syncPass == 1 { return page([], total: nil, complete: false, state: "syncing") }
            throw URLError(.timedOut)
        }
        await hydrated.start()
        check(hydrated.messages.map(\.id) == ["new", "old"], "Empty pending enumeration preserves visible cached history")
        let pendingCache = SenderHistoryStore(auth: single, sender: sender, sample: false, seed: [], cache: cache)
        check(pendingCache.messages.map(\.id) == ["new", "old"], "Empty pending enumeration never erases the disk cache")
        syncPass = 0
        HistoryProtocol.handler = { _ in
            syncPass += 1
            return syncPass == 1 ? page([], total: nil, complete: false, state: "syncing")
                : page([card("replacement")], total: 1)
        }
        await hydrated.start()
        check(hydrated.messages.map(\.id) == ["replacement"] && hydrated.totalCount == 1,
              "First usable head replaces stale cache after empty enumeration responses")

        HistoryProtocol.handler = { request in
            if request.value(forHTTPHeaderField: "Authorization") == "Bearer two" { throw URLError(.timedOut) }
            return page([card("source")], total: 1)
        }
        await history.start()
        check(history.totalCount == nil && history.failure != nil && !history.isExhausted, "One failed account cannot produce a supposedly complete combined total")
        check(!history.messages.isEmpty, "Partial account failure keeps available history visible")
        print("\(checks) sender history checks passed")
    }
}
