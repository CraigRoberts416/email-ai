import CryptoKit
import Foundation

// Compile this executable with Services/FeedCache.swift. Only the wire types
// are substituted; disk encoding, expiry, namespacing, and removal use the
// production implementation and an isolated temporary directory.
enum APIClient {
    struct Card: Codable {}
    struct Recap: Codable {}
    struct ConversationWire: Codable {}
    struct ConversationMessageWire: Codable {}
    struct Body: Codable, Equatable {
        let plainText: String
        let htmlRaw: String
    }
}

@main struct FeedCacheTests {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "decision-inbox-cache-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let created = Date(timeIntervalSince1970: 1_800_000_000)
        let cache = AccountMailCache(directory: directory, now: created)
        let body = APIClient.Body(plainText: "Hello café 👋", htmlRaw: "<p>Hello &amp; welcome</p>")
        cache.save(body, account: "one@example.com", kind: .body, key: "Message-A")
        precondition(cache.load(APIClient.Body.self, account: "ONE@example.com", kind: .body,
                                key: "Message-A") == body, "Round trip must preserve both body formats")
        precondition(cache.load(APIClient.Body.self, account: "two@example.com", kind: .body,
                                key: "Message-A") == nil, "Account IDs must isolate identical message IDs")
        precondition(cache.load(APIClient.Body.self, account: "one@example.com", kind: .body,
                                key: "message-a") == nil, "Provider message IDs retain exact case")
        precondition(cache.load(APIClient.Body.self, account: "one@example.com", kind: .thread,
                                key: "Message-A") == nil, "Body and thread keys use separate namespaces")
        let beforeExpiry = AccountMailCache(directory: directory, now: created.addingTimeInterval(7 * 86_400 - 1))
        precondition(beforeExpiry.load(APIClient.Body.self, account: "one@example.com", kind: .body,
                                       key: "Message-A") == body, "Body stays readable through its lifetime")
        let expired = AccountMailCache(directory: directory, now: created.addingTimeInterval(7 * 86_400))
        precondition(expired.load(APIClient.Body.self, account: "one@example.com", kind: .body,
                                  key: "Message-A") == nil, "Seven-day boundary expires the body")
        let expiredFiles = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        precondition(expiredFiles.isEmpty,
                     "Expired content must be removed from disk")

        cache.save(body, account: "one@example.com", kind: .body, key: "corrupt")
        let corruptFile = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)[0]
        try Data("not JSON".utf8).write(to: corruptFile)
        precondition(cache.load(APIClient.Body.self, account: "one@example.com", kind: .body,
                                key: "corrupt") == nil, "Corruption becomes a cache miss")
        precondition(!FileManager.default.fileExists(atPath: corruptFile.path), "Remove corrupt content")

        cache.save(body, account: "one@example.com", kind: .body, key: "first")
        cache.save(["message one"], account: "one@example.com", kind: .thread, key: "person")
        cache.save(body, account: "two@example.com", kind: .body, key: "first")
        cache.save(["message two"], account: "two@example.com", kind: .thread, key: "person")
        let accountHash = SHA256.hash(data: Data("one@example.com".utf8)).prefix(16)
            .map { String(format: "%02x", $0) }.joined()
        let feedFile = directory.appending(path: "\(accountHash).json")
        try Data("old feed".utf8).write(to: feedFile)
        let legacyThread = directory.appending(path: "thread-01234567890123456789012345678901.json")
        try Data("legacy mail".utf8).write(to: legacyThread)
        cache.clear(account: "ONE@example.com")
        precondition(cache.load(APIClient.Body.self, account: "one@example.com", kind: .body,
                                key: "first") == nil, "Disconnect removes opened bodies")
        precondition(cache.load([String].self, account: "one@example.com", kind: .thread,
                                key: "person") == nil, "Disconnect removes conversation messages")
        precondition(!FileManager.default.fileExists(atPath: feedFile.path), "Disconnect removes feed")
        precondition(!FileManager.default.fileExists(atPath: legacyThread.path), "Disconnect removes anonymous legacy threads")
        precondition(cache.load(APIClient.Body.self, account: "two@example.com", kind: .body,
                                key: "first") == body, "Other accounts keep their opened bodies")
        precondition(cache.load([String].self, account: "two@example.com", kind: .thread,
                                key: "person") == ["message two"], "Other accounts keep their conversation messages")
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        precondition(names.allSatisfy { !$0.contains("example.com") && !$0.contains("first") },
                     "Filenames must not expose account addresses or message IDs")
        print("16 mail-cache behavior checks passed")
    }
}
