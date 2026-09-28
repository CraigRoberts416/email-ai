import Foundation
import Observation

struct BacklogJob: Codable {
    let id: String
    var phase: String
    let before: String
    var total: Int
    var completed: Int
    var version: Int
    var readIDs: [String]
}

/// The server stores the frozen identities and each committed batch. This
/// journal stores only the account/job references and the user's approval.
/// Relaunch never authorizes or resumes writes by itself.
@MainActor @Observable final class BacklogCleanup {
    struct Entry: Codable, Identifiable {
        let id: String
        let address: String
        var job: BacklogJob?
    }
    struct Journal: Codable {
        var entries: [Entry]
        var before: Date?
        var snapshotBefore: Date?
        var approved = false
    }
    typealias Request = (String, BacklogJob?, Date?, String?) async throws -> BacklogJob
    private(set) var journal: Journal?
    private(set) var busy = false
    private(set) var pauseRequested = false
    private(set) var failure: String?
    @ObservationIgnored private let request: Request
    @ObservationIgnored private let persist: (Journal?) -> Void
    @ObservationIgnored var onProgress: ((String, [String]) -> Void)?
    @ObservationIgnored var onSettled: (() async -> Void)?

    var entries: [Entry] { journal?.entries ?? [] }
    var total: Int { entries.compactMap(\.job).reduce(0) { $0 + $1.total } }
    var completed: Int { entries.compactMap(\.job).reduce(0) { $0 + $1.completed } }
    var ready: Bool { !entries.isEmpty && entries.allSatisfy { $0.job?.phase == "ready" } }
    var done: Bool { !entries.isEmpty && entries.allSatisfy { $0.job?.phase == "complete" } }
    var approved: Bool { journal?.approved == true }
    var hasWork: Bool { journal != nil }

    init(restored: Journal? = nil, request: @escaping Request, persist: @escaping (Journal?) -> Void) {
        journal = restored; self.request = request; self.persist = persist
    }

    convenience init(auth: AuthService, sample: Bool) {
        let key = "feed.backlogCleanup.v1"
        let restored = sample ? nil : UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(Journal.self, from: $0) }
        self.init(restored: restored, request: { account, job, before, action in
            if sample {
                #if DEBUG
                try await Task.sleep(for: .milliseconds(ProcessInfo.processInfo.arguments.contains("-sampleBacklogSlow") ? 600 : 200))
                var item = job ?? BacklogJob(id: UUID().uuidString, phase: "scanning", before: ISO8601DateFormatter().string(from: before ?? .now), total: 0, completed: 0, version: 0, readIDs: [])
                switch action {
                case "scan": item.total = 1_200; item.phase = "ready"
                case "start": item.phase = "applying"
                case "apply":
                    item.completed = min(item.total, item.completed + 500)
                    if item.completed == item.total { item.phase = "complete" }
                default: break
                }
                item.version += 1
                return item
                #else
                throw APIError.sampleUnavailable
                #endif
            }
            return try await APIClient(auth: auth, accountID: account).backlogJob(id: job?.id, before: before, action: action, version: job?.version ?? 0)
        }, persist: { journal in
            guard !sample else { return }
            if let journal, let data = try? JSONEncoder().encode(journal) { UserDefaults.standard.set(data, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        })
    }

    func preview(mailboxes: [Mailbox], before: Date?) async {
        guard !busy, !mailboxes.isEmpty else { return }
        journal = Journal(entries: mailboxes.map { Entry(id: $0.id, address: $0.address) }, before: before)
        persist(journal)
        await resume()
    }

    func approve() async {
        guard ready, !busy else { return }
        journal?.approved = true
        persist(journal)
        await resume()
    }

    func pause() { if busy { pauseRequested = true } }
    func reset() { guard !busy else { return }; journal = nil; failure = nil; persist(nil) }

    func resume() async {
        guard !busy, journal != nil, !done else { return }
        busy = true; pauseRequested = false; failure = nil
        defer { busy = false; pauseRequested = false }
        do {
            for index in entries.indices {
                guard !pauseRequested else { break }
                let entry = entries[index]
                // Recover a committed request whose HTTP response was lost.
                let fresh = try await request(entry.id, entry.job, journal?.before ?? journal?.snapshotBefore, nil)
                record(fresh, at: index)
                while !pauseRequested {
                    guard let job = entries[index].job else { break }
                    if job.phase == "complete" || (job.phase == "ready" && !approved) { break }
                    let action: String
                    switch job.phase {
                    case "scanning": action = "scan"
                    case "ready": action = "start"
                    case "applying": guard approved else { throw APIError.transport }; action = "apply"
                    default: throw APIError.transport
                    }
                    let next = try await request(entry.id, job, journal?.before ?? journal?.snapshotBefore, action)
                    record(next, at: index)
                }
            }
        } catch {
            if case APIError.server(409) = error { failure = "This preview expired. Start a new preview before marking anything else read." }
            else if case APIError.unauthorized = error { failure = "Reconnect the mailbox in Settings, then resume. Your progress is saved." }
            else { failure = "Cleanup paused. Couldn’t confirm the last step. Resume to check it and continue; confirmed batches won’t be repeated." }
        }
        if approved { await onSettled?() }
    }

    private func record(_ job: BacklogJob, at index: Int) {
        if journal?.snapshotBefore == nil {
            let parser = ISO8601DateFormatter()
            parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            journal?.snapshotBefore = parser.date(from: job.before) ?? ISO8601DateFormatter().date(from: job.before)
        }
        journal?.entries[index].job = job
        persist(journal)
        if approved, !job.readIDs.isEmpty { onProgress?(entries[index].id, job.readIDs) }
    }
}
