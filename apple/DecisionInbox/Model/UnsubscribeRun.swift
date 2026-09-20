import Foundation

/// Work, evidence and visibility are separate. This record survives closing
/// its presentation and is scoped to the mailbox that owns the message.
struct UnsubscribeRun: Codable, Sendable, Identifiable {
    var messageId: String
    var senderName: String?
    var status: String
    var message: String?
    var index: Int?
    var total: Int?
    var fieldIndex: Int?
    var fieldTotal: Int?
    var mailboxID: String? = nil
    var runId: String? = nil
    var attemptId: String? = nil
    var updatedAt: Double? = nil
    var outcome: String? = nil
    var evidence: String? = nil
    var sourceURL: String? = nil
    var handoffURL: String? = nil
    var history: [Event]? = nil
    var openedByUserAt: Date? = nil
    var userReportedComplete: Bool? = nil

    struct Event: Codable, Sendable, Identifiable {
        var status: String
        var message: String?
        var at: Double
        var id: String { "\(at):\(status)" }
    }

    var id: String { (mailboxID ?? "") + ":" + messageId }
    var step: UnsubscribeStep { UnsubscribeStep(status) }
    var isTerminal: Bool { step.isTerminal }
    var needsAttention: Bool { [.needsYou, .failed, .noLink, .stillSending, .unknown].contains(step) }
    var isConfirmed: Bool { step == .done && outcome == "sender_confirmed" }
    var date: Date { Date(timeIntervalSince1970: (updatedAt ?? 0) / 1000) }
    var actionURL: URL? {
        guard let value = handoffURL ?? sourceURL, let url = URL(string: value),
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil else { return nil }
        return url
    }
    var title: String {
        if userReportedComplete == true { return "Marked complete by you" }
        if outcome == "outcome_unknown" { return "Outcome unconfirmed" }
        if step == .done {
            switch outcome {
            case "request_sent": return "Request sent"
            case "sender_confirmed": return "Sender confirmed"
            default: return "Attempt finished"
            }
        }
        return step.label
    }
    var summary: String {
        if userReportedComplete == true { return "You marked this complete. The app has not verified the sender’s result." }
        if outcome == "outcome_unknown" { return "The last attempt could not be confirmed. Check the sender’s page before trying again." }
        if step == .done && outcome == "request_sent" { return "The request was sent. The sender has not confirmed removal." }
        if step == .done && outcome != "sender_confirmed" { return "This older receipt does not include confirmation evidence." }
        return message ?? step.fallback(sender: senderName)
    }
}

enum UnsubscribeStep: String, Codable, Sendable {
    case queued, navigating, analyzing, filling, clicking, verifying, done, failed
    case noLink = "no_link"
    case needsYou = "needs_you"
    case stillSending = "still_sending"
    case unknown

    init(_ raw: String) { self = Self(rawValue: raw) ?? (raw == "error" ? .failed : .unknown) }
    var isTerminal: Bool {
        switch self {
        case .done, .noLink, .needsYou, .failed, .stillSending, .unknown: return true
        default: return false
        }
    }
    var label: String {
        switch self {
        case .queued: return "Queued"
        case .navigating: return "Opening sender page"
        case .analyzing: return "Reading sender page"
        case .filling: return "Filling the form"
        case .clicking: return "Submitting"
        case .verifying: return "Checking the result"
        case .done: return "Attempt finished"
        case .noLink: return "No link found"
        case .needsYou: return "Needs you"
        case .failed: return "Couldn’t finish"
        case .stillSending: return "Mail received again"
        case .unknown: return "Status unavailable"
        }
    }
    func fallback(sender: String?) -> String {
        switch self {
        case .done: return "The attempt finished. Check its receipt for confirmation."
        case .needsYou: return "The sender’s page needs a person to continue."
        case .noLink: return "No usable unsubscribe control was found."
        case .failed: return "The attempt could not be completed."
        case .stillSending: return "New mail was reported after this attempt."
        case .unknown: return "Open the task to review its last known result."
        default: return label
        }
    }
}
