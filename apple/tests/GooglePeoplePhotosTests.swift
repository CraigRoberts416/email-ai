import Foundation

@main struct GooglePeoplePhotosTests {
    static func main() async throws {
        let personJSON = #"{"emailAddresses":[{"value":" Hayden@Example.com "},{"value":"second@example.com"}],"photos":[{"url":"https://lh3.googleusercontent.com/default","default":true},{"url":"https://evil.googleusercontent.com.attacker.test/photo","metadata":{"primary":true}},{"url":"https://lh3.googleusercontent.com/real","metadata":{"primary":true}}]}"#
        let person = try JSONDecoder().decode(GooglePeoplePhotos.Person.self, from: Data(personJSON.utf8))
        let map = GooglePeoplePhotos.photoMap([person])
        precondition(map["hayden@example.com"]?.path == "/real", "Exact normalized email matches a real Google photo")
        precondition(map["second@example.com"]?.path == "/real")
        precondition(map["other@example.com"] == nil, "Names and nearby addresses cannot match")
        let defaultOnly = try JSONDecoder().decode(GooglePeoplePhotos.Person.self, from: Data(#"{"emailAddresses":[{"value":"x@example.com"}],"photos":[{"url":"https://lh3.googleusercontent.com/default","default":true}]}"#.utf8))
        precondition(GooglePeoplePhotos.photoMap([defaultOnly]).isEmpty, "Google's placeholder is not a personal photo")

        var calls: [URLRequest] = []
        let result = try await GooglePeoplePhotos.fetch(token: "test-only", scopes: [GooglePeoplePhotos.contactsScope, GooglePeoplePhotos.otherContactsScope]) { request in
            calls.append(request)
            let other = request.url!.path.contains("otherContacts")
            let pageTwo = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!.contains { $0.name == "pageToken" }
            let payload: String
            if other {
                payload = #"{"otherContacts":[{"emailAddresses":[{"value":"other@example.com"},{"value":"hayden@example.com"}],"photos":[{"url":"https://lh3.googleusercontent.com/other"}]}]}"#
            } else if pageTwo { payload = #"{"connections":[]}"# }
            else { payload = "{\"connections\":[\(personJSON)],\"nextPageToken\":\"page-2\"}" }
            return (Data(payload.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        precondition(calls.count == 3, "Every saved and Other Contacts page must be read")
        precondition(result["hayden@example.com"]?.path == "/real", "Saved contact photo wins over automatic contacts")
        precondition(result["other@example.com"]?.path == "/other")
        for request in calls {
            precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-only")
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            precondition(query.contains { $0.value == "emailAddresses,photos" })
            precondition(query.filter { $0.name == "sources" }.count == 2)
        }
        var noConsentCalls = 0
        let empty = try await GooglePeoplePhotos.fetch(token: "unused", scopes: []) { _ in
            noConsentCalls += 1
            throw URLError(.badURL)
        }
        precondition(empty.isEmpty && noConsentCalls == 0, "No permission means no People API call")
        do {
            _ = try await GooglePeoplePhotos.fetch(token: "test", scopes: [GooglePeoplePhotos.contactsScope]) { request in
                (Data(), HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: nil, headerFields: nil)!)
            }
            preconditionFailure("A failed fetch must not become a successful empty address book")
        } catch let error as GooglePeoplePhotos.APIError { precondition(error.status == 403) }
        print("Google People photos: exact identity, photo sources, pagination, scopes, and failure checks passed")
    }
}
