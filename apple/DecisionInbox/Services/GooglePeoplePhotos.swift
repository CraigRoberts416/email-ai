import Foundation

/// Supported People API only. We request email addresses and photos, never
/// names or phone numbers, and join to a sender by exact normalized address.
struct GooglePeoplePhotos {
    static let contactsScope = "https://www.googleapis.com/auth/contacts.readonly"
    static let otherContactsScope = "https://www.googleapis.com/auth/contacts.other.readonly"
    typealias Transport = (URLRequest) async throws -> (Data, URLResponse)

    struct Page: Decodable {
        let connections: [Person]?
        let otherContacts: [Person]?
        let nextPageToken: String?
    }
    struct Person: Decodable {
        struct Email: Decodable { let value: String? }
        struct Photo: Decodable {
            struct Metadata: Decodable { let primary: Bool? }
            let url: String?
            let `default`: Bool?
            let metadata: Metadata?
        }
        let emailAddresses: [Email]?
        let photos: [Photo]?
    }
    struct APIError: LocalizedError {
        let status: Int
        var errorDescription: String? {
            switch status {
            case 401: return "Reconnect this Google account to load contact photos."
            case 403: return "Google contact photos are unavailable. Check that photo access was allowed and the Google People API is enabled for this app."
            default: return "Google contact photos could not refresh. Your saved photos are still available."
            }
        }
    }

    static func normalized(_ address: String) -> String {
        address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func realPhotoURL(_ person: Person) -> URL? {
        let photos = (person.photos ?? []).filter { $0.default != true }
            .sorted { ($0.metadata?.primary == true ? 0 : 1) < ($1.metadata?.primary == true ? 0 : 1) }
        return photos.compactMap { photo -> URL? in
            guard let value = photo.url, let url = URL(string: value), url.scheme == "https",
                  let host = url.host?.lowercased(),
                  host == "googleusercontent.com" || host.hasSuffix(".googleusercontent.com")
                    || host == "ggpht.com" || host.hasSuffix(".ggpht.com") else { return nil }
            return url
        }.first
    }

    static func photoMap(_ people: [Person]) -> [String: URL] {
        var result: [String: URL] = [:]
        for person in people {
            guard let photo = realPhotoURL(person) else { continue }
            for email in person.emailAddresses ?? [] {
                guard let value = email.value else { continue }
                let key = normalized(value)
                guard key.split(separator: "@").count == 2, !key.contains(" ") else { continue }
                if result[key] == nil { result[key] = photo }
            }
        }
        return result
    }

    static func fetch(token: String, scopes: Set<String>,
                      transport: Transport = { try await URLSession.shared.data(for: $0) }) async throws -> [String: URL] {
        var result: [String: URL] = [:]
        // Saved contacts take precedence over the automatic Other contacts list.
        for other in [false, true] where scopes.contains(other ? otherContactsScope : contactsScope) {
            var next: String?
            var visited: Set<String> = []
            repeat {
                try Task.checkCancellation()
                var components = URLComponents(string: other
                    ? "https://people.googleapis.com/v1/otherContacts"
                    : "https://people.googleapis.com/v1/people/me/connections")!
                components.queryItems = [
                    .init(name: other ? "readMask" : "personFields", value: "emailAddresses,photos"),
                    .init(name: "pageSize", value: "1000"),
                    .init(name: "sources", value: "READ_SOURCE_TYPE_CONTACT"),
                    .init(name: "sources", value: "READ_SOURCE_TYPE_PROFILE"),
                ]
                if let next { components.queryItems?.append(.init(name: "pageToken", value: next)) }
                var request = URLRequest(url: components.url!)
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.timeoutInterval = 30
                let (data, response) = try await transport(request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    throw APIError(status: (response as? HTTPURLResponse)?.statusCode ?? 0)
                }
                let page = try JSONDecoder().decode(Page.self, from: data)
                for (email, url) in photoMap(other ? (page.otherContacts ?? []) : (page.connections ?? []))
                    where result[email] == nil { result[email] = url }
                next = page.nextPageToken.flatMap { $0.isEmpty ? nil : $0 }
                if let next, !visited.insert(next).inserted { throw APIError(status: 0) }
            } while next != nil
        }
        return result
    }
}
