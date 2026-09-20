import Foundation

struct MailDraftRecord: Codable, Identifiable {
    let id: String
    var mailboxID: String
    var draft: GmailClient.Draft
    var pendingAttachments: [Attachment] = []
    var originalLoaded: Bool = true
    var requiresSentCheck = false
    var composeIntent = "new"
    var sourceMessage: Message?
    var updatedAt: Date = .now
}

struct SendJob: Codable, Identifiable {
    enum Phase: String, Codable {
        case queued, sending, sent, failed, unknown, held
        var title: String {
            switch self {
            case .queued: "Ready to send"
            case .sending: "Sending"
            case .sent: "Sent"
            case .failed: "Couldn’t send"
            case .unknown: "Send not confirmed"
            case .held: "Draft kept"
            }
        }
    }
    let id: UUID
    var mailboxID: String
    var draftKey: String
    var draft: GmailClient.Draft
    var phase: Phase
    var createdAt: Date = .now
    var detail: String?
    var canUndo: Bool { phase == .queued }
    var canEdit: Bool { phase == .held || phase == .failed || phase == .unknown }
    var isRunning: Bool { phase == .queued || phase == .sending }
}

/// Drafts and send outcomes are user work, separate from the regenerable feed
/// cache. A recovered queued send is held; it never silently sends on restart.
@MainActor
enum MailDraftStore {
    static var directoryOverride: URL?
    private static var directory: URL {
        if let directoryOverride { return directoryOverride }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MailDrafts", isDirectory: true)
    }

    private static func read<T: Decodable>(_ type: T.Type, name: String) -> T? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(name)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    @discardableResult private static func write<T: Encodable>(_ value: T, name: String) -> Bool {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let destination = directory.appendingPathComponent(name)
            let data = try JSONEncoder().encode(value)
            try data.write(to: destination, options: .atomic)
            #if os(iOS)
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: destination.path)
            #endif
            var folder = directory
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try folder.setResourceValues(values)
            return true
        } catch { return false }
    }

    static func drafts(for accounts: Set<String>) -> [MailDraftRecord] {
        Array((read([String: MailDraftRecord].self, name: "drafts.json") ?? [:]).values)
            .filter { accounts.contains($0.mailboxID) && (!$0.draft.body.isEmpty || !$0.draft.attachments.isEmpty || !$0.pendingAttachments.isEmpty) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    static func draft(_ key: String) -> MailDraftRecord? {
        read([String: MailDraftRecord].self, name: "drafts.json")?[key]
    }

    @discardableResult static func save(_ record: MailDraftRecord) -> Bool {
        var records = read([String: MailDraftRecord].self, name: "drafts.json") ?? [:]
        records[record.id] = record
        return write(records, name: "drafts.json")
    }

    static func removeDraft(_ key: String) {
        var records = read([String: MailDraftRecord].self, name: "drafts.json") ?? [:]
        records.removeValue(forKey: key)
        write(records, name: "drafts.json")
    }

    static func recoveredJobs() -> [UUID: SendJob] {
        let stored = read([SendJob].self, name: "outbox.json") ?? []
        return Dictionary(stored.map { stored in
            var job = stored
            if job.phase == .queued { job.phase = .held; job.detail = "The app closed before sending. Your draft is ready to edit." }
            if job.phase == .sending { job.phase = .unknown; job.detail = "Check Sent mail before sending this draft again." }
            return (job.id, job)
        }, uniquingKeysWith: { _, latest in latest })
    }

    @discardableResult static func saveJobs(_ jobs: [UUID: SendJob]) -> Bool {
        write(Array(jobs.values).sorted { $0.createdAt < $1.createdAt }, name: "outbox.json")
    }

    static func remove(accountID: String) {
        let records = read([String: MailDraftRecord].self, name: "drafts.json") ?? [:]
        write(records.filter { $0.value.mailboxID != accountID }, name: "drafts.json")
        let jobs = read([SendJob].self, name: "outbox.json") ?? []
        write(jobs.filter { $0.mailboxID != accountID }, name: "outbox.json")
    }

    static func clear() {
        write([String: MailDraftRecord](), name: "drafts.json")
        write([SendJob](), name: "outbox.json")
    }
}
