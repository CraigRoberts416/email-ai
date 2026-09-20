import Foundation

struct DiscussionTurn: Codable, Identifiable {
    var id: UUID = UUID()
    let question: String
    var answer: String?
    var failed = false
    var scope: String?
}

struct DiscussionRecord: Codable {
    var mailboxID: String
    var turns: [DiscussionTurn] = []
    var draft = ""
}

@MainActor
enum DiscussionStore {
    static var directoryOverride: URL?
    private static var generations: [String: Int] = [:]
    static func generation(for accountID: String) -> Int { generations[accountID, default: 0] }
    private static var file: URL {
        (directoryOverride ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0])
            .appendingPathComponent("Discussions.json")
    }
    private static var records: [String: DiscussionRecord] {
        guard let data = try? Data(contentsOf: file) else { return [:] }
        return (try? JSONDecoder().decode([String: DiscussionRecord].self, from: data)) ?? [:]
    }
    static func load(_ key: String) -> DiscussionRecord? { records[key] }
    @discardableResult static func save(_ record: DiscussionRecord, key: String, generation: Int) -> Bool {
        guard generation == self.generation(for: record.mailboxID) else { return false }
        var all = records; all[key] = record
        return write(all)
    }
    static func remove(accountID: String) {
        generations[accountID, default: 0] += 1
        _ = write(records.filter { $0.value.mailboxID != accountID })
    }
    static func clear() { _ = write([:]) }
    private static func write(_ all: [String: DiscussionRecord]) -> Bool {
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(all).write(to: file, options: .atomic)
            #if os(iOS)
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: file.path)
            #endif
            var url = file
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            try url.setResourceValues(values)
            return true
        } catch { return false }
    }
}
