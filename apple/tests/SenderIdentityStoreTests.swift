import Foundation

// Only app/domain dependencies are substituted. Matching, persistence,
// refresh guards and failure behavior run through the production stores.
final class AuthService {
    struct Account { let id: String }
    var accounts: [Account]
    var photoAuthorizationVersion = 0
    var grants: Set<String> = [GooglePeoplePhotos.contactsScope, GooglePeoplePhotos.otherContactsScope]
    var tokenCalls = 0
    var isAuthenticated: Bool { !accounts.isEmpty }
    init(_ ids: [String]) { accounts = ids.map { Account(id: $0) } }
    func googlePhotoScopes(for id: String) -> Set<String> { accounts.contains { $0.id == id } ? grants : [] }
    func validAccessToken(for id: String) async throws -> String { tokenCalls += 1; return "test:\(id)" }
}
struct APIClient { let auth: AuthService; let accountID: String; var baseURL = URL(string: "https://test.invalid")! }
struct Sender { let address: String; let logoURL: URL? }
struct Message {
    let sender: Sender
    let receivedAt = Date()
    let mailboxID: String
    var heroImageURL: URL?
    var heroBackground: String?
    var senderDescription: String?
}

@main struct SenderIdentityStoreTests {
    @MainActor static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var requests: [URLRequest] = []
        var fail = false
        let transport: GooglePeoplePhotos.Transport = { request in
            requests.append(request)
            if fail { throw URLError(.notConnectedToInternet) }
            let payload: String
            if request.url!.host == "people.googleapis.com" {
                payload = request.url!.path.contains("otherContacts") ? #"{"otherContacts":[]}"#
                    : #"{"connections":[{"emailAddresses":[{"value":"hayden@example.com"}],"photos":[{"url":"https://lh3.googleusercontent.com/real"}]}]}"#
            } else {
                payload = ##"{"address":"hello@amazon.co.uk","avatarUri":"https://img.logo.dev/amazon.co.uk","heroImageUrl":"https://test.invalid/hero-image/amazon.co.uk","heroImageBgColor":"#123456","senderDescription":"Amazon"}"##
            }
            return (Data(payload.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let auth = AuthService(["one@example.com"])
        let identity = SenderIdentityStore(cacheDirectory: directory, transport: transport)
        identity.configure(auth: auth, isSample: false)
        identity.setGooglePhotosEnabled(true)
        let sender = Sender(address: "hello@amazon.co.uk", logoURL: nil)
        await identity.load(for: sender)
        precondition(identity.profile(for: sender.address)?.heroImageUrl?.path == "/hero-image/amazon.co.uk",
                     "A profile loads without any retained inbox message")
        precondition(identity.googlePhoto(for: "HAYDEN@example.com")?.url.path == "/real")
        let photoKey = identity.googlePhoto(for: "hayden@example.com")!.cacheKey
        precondition(photoKey.contains("one@example.com"), "Private images are account scoped")

        identity.remember(messages: [Message(sender: sender, mailboxID: "one@example.com")])
        precondition(identity.profile(for: sender.address)?.heroImageUrl != nil, "A partial card cannot erase known artwork")
        fail = true
        await identity.refreshGooglePhotos(force: true)
        precondition(identity.googlePhoto(for: "hayden@example.com") != nil, "Offline refresh keeps last good photo")
        precondition(identity.photoFailures["one@example.com"] != nil)

        let relaunched = SenderIdentityStore(cacheDirectory: directory, transport: transport)
        relaunched.configure(auth: auth, isSample: false)
        precondition(relaunched.profile(for: sender.address)?.heroImageUrl != nil, "Profile artwork survives relaunch")
        precondition(relaunched.googlePhoto(for: "hayden@example.com") != nil, "Personal photo metadata hydrates before refresh")
        let other = AuthService(["two@example.com"])
        relaunched.configure(auth: other, isSample: false)
        precondition(relaunched.googlePhoto(for: "hayden@example.com") == nil, "A second account cannot inherit private photos")
        precondition(relaunched.profile(for: sender.address) == nil)

        let count = requests.count
        relaunched.configure(auth: auth, isSample: true)
        await relaunched.load(for: sender)
        await relaunched.refreshGooglePhotos(force: true)
        precondition(requests.count == count, "Sample mode never calls identity or Google APIs")
        precondition(relaunched.googlePhoto(for: "hayden@example.com") == nil)
        precondition(relaunched.profile(for: sender.address) == nil)
        auth.grants = []
        identity.configure(auth: auth, isSample: false)
        precondition(identity.googlePhoto(for: "hayden@example.com") == nil, "Revoked scope hides cached personal photos")
        identity.clearCache()
        precondition(identity.profile(for: sender.address) == nil)

        // A shared lookup may outlive an avatar, but must stop when permission
        // is switched off or the app enters sample mode.
        var started = false
        var cancellationCalls = 0
        let switching = SenderIdentityStore(cacheDirectory: directory) { request in
            cancellationCalls += 1
            started = true
            try await Task.sleep(for: .seconds(10))
            return (Data(#"{"connections":[]}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let multiAuth = AuthService(["one@example.com", "two@example.com"])
        switching.configure(auth: multiAuth, isSample: false)
        let pending = Task { await switching.refreshGooglePhotos(force: true) }
        while !started { await Task.yield() }
        switching.configure(auth: multiAuth, isSample: true)
        await pending.value
        precondition(cancellationCalls == 1, "Switching to sample cancels the first request and never starts a second account")
        precondition(switching.googlePhoto(for: "hayden@example.com") == nil)
        print("Sender identity: independent profiles, partial metadata, offline photos, relaunch, account/sample isolation, grants and clearing passed")
    }
}
