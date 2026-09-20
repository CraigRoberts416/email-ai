import Foundation

/// The live half of the feed. `/feed` gives the set; this gives everything
/// that happens to it afterwards — mail arriving, the model writing a summary
/// a token at a time, an unsubscribe agent working through a site.
///
/// Reconnects with backoff and stays quiet about it. A dropped stream is not
/// something the user should be told about: the feed they can already see is
/// still true, it just stops growing.
actor SSEClient {
    enum Event {
        case messageAdded(APIClient.Card)
        case messageRead(String, wasUnread: Bool?)
        case processing(String)
        /// A token of a field being written. Field is `quote`, `summary`, `action`.
        case chunk(messageID: String, field: String, text: String)
        case fieldComplete(messageID: String, field: String, value: String?)
        case messageReady(String)
        case unsubscribeStatus(UnsubscribeStatus)
    }

    /// The enum is fixed, the sentence is free.
    ///
    /// `step` drives the tray's shape, its counter and its progress segments,
    /// so it has to be deterministic — the model is never allowed to invent
    /// one. `message` is written fresh from what was actually found on the
    /// page, so the words stay alive across runs.
    typealias UnsubscribeStatus = UnsubscribeRun

    private let baseURL: URL
    private let auth: AuthService
    private let accountID: String
    private var task: Task<Void, Never>?

    init(baseURL: URL, auth: AuthService, accountID: String) {
        self.baseURL = baseURL
        self.auth = auth
        self.accountID = accountID
    }

    func connect(_ handle: @escaping @Sendable (Event) async -> Void) {
        task?.cancel()
        task = Task { [baseURL, auth, accountID] in
            var backoff: Duration = .seconds(1)
            while !Task.isCancelled {
                do {
                    let token = try await auth.validAccessToken(for: accountID)
                    var request = URLRequest(url: baseURL.appending(path: "/feed/events"))
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    // The stream is meant to stay open; the default 60s timeout
                    // would tear it down mid-idle and look like a server fault.
                    request.timeoutInterval = .infinity

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                        throw APIError.transport
                    }
                    backoff = .seconds(1)

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }  // `: keepalive` and blanks
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        guard let event = Self.decode(Data(payload.utf8)) else { continue }
                        await handle(event)
                    }
                } catch is CancellationError {
                    return
                } catch {
                    // Silent. Reconnect and let the feed speak for itself.
                }
                guard !Task.isCancelled else { return }
                try? await Task.sleep(for: backoff)
                backoff = min(backoff * 2, .seconds(30))
            }
        }
    }

    func disconnect() {
        task?.cancel()
        task = nil
    }

    // MARK: Decoding

    private struct Envelope: Decodable {
        let type: String
        let messageId: String?
        let wasUnread: Bool?
        let field: String?
        let chunk: String?
        let value: String?

        enum CodingKeys: String, CodingKey { case type, messageId, field, chunk, value, wasUnread }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            type = try c.decode(String.self, forKey: .type)
            messageId = try c.decodeIfPresent(String.self, forKey: .messageId)
            wasUnread = try c.decodeIfPresent(Bool.self, forKey: .wasUnread)
            field = try c.decodeIfPresent(String.self, forKey: .field)
            chunk = try c.decodeIfPresent(String.self, forKey: .chunk)

            // `value` is whatever the field happens to be. requiresAttention
            // arrives as a JSON boolean, and decoding it as String? threw for
            // the whole event — so the one field that drives NEEDS YOU was
            // silently dropped on every message, live.
            if let text = try? c.decodeIfPresent(String.self, forKey: .value) {
                value = text
            } else if let flag = try? c.decodeIfPresent(Bool.self, forKey: .value) {
                value = flag ? "true" : "false"
            } else if let number = try? c.decodeIfPresent(Double.self, forKey: .value) {
                value = String(number)
            } else {
                value = nil
            }
        }
    }

    private static func decode(_ data: Data) -> Event? {
        let decoder = JSONDecoder()
        guard let envelope = try? decoder.decode(Envelope.self, from: data) else { return nil }

        switch envelope.type {
        case "message-added":
            // The added-event carries the same field names as a /feed card,
            // so the one mapping in APIClient covers both paths.
            return (try? decoder.decode(APIClient.Card.self, from: data)).map(Event.messageAdded)
        case "message-read":
            return envelope.messageId.map { Event.messageRead($0, wasUnread: envelope.wasUnread) }
        case "processing":
            return envelope.messageId.map(Event.processing)
        case "chunk":
            guard let id = envelope.messageId, let field = envelope.field,
                  let chunk = envelope.chunk else { return nil }
            return .chunk(messageID: id, field: field, text: chunk)
        case "field-complete":
            guard let id = envelope.messageId, let field = envelope.field else { return nil }
            return .fieldComplete(messageID: id, field: field, value: envelope.value)
        case "message-ready":
            return envelope.messageId.map(Event.messageReady)
        case "unsubscribe-status":
            return (try? decoder.decode(UnsubscribeStatus.self, from: data))
                .map(Event.unsubscribeStatus)
        default:
            return nil
        }
    }
}
