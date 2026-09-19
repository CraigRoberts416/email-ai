import Foundation

@main struct IdentityDiskCacheTests {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let cache = IdentityDiskCache(directory: directory, now: start)
        cache.save(["hero": "https://example.com/image"], key: "profile:account-one:sender")
        precondition(cache.load([String: String].self, key: "profile:account-one:sender")?["hero"] != nil)
        precondition(cache.load([String: String].self, key: "profile:account-two:sender") == nil)
        precondition(cache.load([String: String].self, key: "profile:sample:sender") == nil)
        let relaunched = IdentityDiskCache(directory: directory, now: start.addingTimeInterval(100))
        precondition(relaunched.load([String: String].self, key: "profile:account-one:sender")?["hero"] != nil,
                     "Identity can reload without retaining a feed message")
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        precondition(files.allSatisfy { !$0.contains("account") && !$0.contains("sender") })
        let expired = IdentityDiskCache(directory: directory, now: start.addingTimeInterval(7 * 86_400))
        precondition(expired.load([String: String].self, key: "profile:account-one:sender") == nil)
        let remaining = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        precondition(remaining.isEmpty)
        cache.save("image", key: "image:one")
        cache.clear()
        precondition(cache.load(String.self, key: "image:one") == nil)
        print("Identity cache: account/sample isolation, relaunch, hashed filenames, expiry, and clear checks passed")
    }
}
