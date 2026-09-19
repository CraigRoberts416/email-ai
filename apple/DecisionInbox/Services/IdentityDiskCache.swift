import CryptoKit
import Foundation

/// Small, private snapshots. Keys include the account; filenames contain no
/// address. Successful content survives network failures for at most seven days.
struct IdentityDiskCache {
    let directory: URL
    var now: Date = .now
    static let lifetime: TimeInterval = 7 * 86_400

    init(directory: URL? = nil, now: Date = .now) {
        self.directory = directory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appending(path: "DecisionInboxIdentity", directoryHint: .isDirectory)
        self.now = now
    }

    private struct Entry<T: Codable>: Codable { let savedAt: Date; let value: T }
    private func file(_ key: String) -> URL {
        let hash = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appending(path: hash + ".json")
    }

    func load<T: Codable>(_ type: T.Type, key: String) -> T? {
        let url = file(key)
        guard let data = try? Data(contentsOf: url),
              let entry = try? JSONDecoder().decode(Entry<T>.self, from: data),
              now.timeIntervalSince(entry.savedAt) < Self.lifetime,
              now.timeIntervalSince(entry.savedAt) >= 0 else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return entry.value
    }

    func save<T: Codable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(Entry(savedAt: now, value: value)) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        #if os(iOS)
        try? data.write(to: file(key), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try? data.write(to: file(key), options: .atomic)
        #endif
    }

    func clear() { try? FileManager.default.removeItem(at: directory) }
}
