import Foundation
import Observation

/// Sender identity outlives a post's presence in the inbox. Contact matching
/// happens on this device; the sync server only supplies domain-based art.
@MainActor @Observable
final class SenderIdentityStore {
    static let shared = SenderIdentityStore()

    struct Profile: Codable {
        let address: String
        var avatarUri: URL?
        var heroImageUrl: URL?
        var heroImageBgColor: String?
        var senderDescription: String?

        mutating func merge(_ newer: Profile) {
            avatarUri = newer.avatarUri ?? avatarUri
            heroImageUrl = newer.heroImageUrl ?? heroImageUrl
            heroImageBgColor = newer.heroImageBgColor ?? heroImageBgColor
            senderDescription = newer.senderDescription ?? senderDescription
        }
    }
    struct PhotoReference { let url: URL; let cacheKey: String }
    private struct Photos: Codable { let byEmail: [String: URL]; let fetchedAt: Date; let scopes: Set<String> }

    private var auth: AuthService?
    private var isSample = true
    @ObservationIgnored private var profiles: [String: Profile] = [:]
    @ObservationIgnored private var photos: [String: Photos] = [:]
    @ObservationIgnored private var checkedProfiles: Set<String> = []
    @ObservationIgnored private var checkedAccounts: Set<String> = []
    private var revision = 0
    private var loading: Set<String> = []
    private var attempts: [String: Date] = [:]
    private var generation = 0
    @ObservationIgnored private var photoTasks: [String: Task<[String: URL], Error>] = [:]
    private(set) var photoFailures: [String: String] = [:]
    private(set) var googlePhotosEnabled = UserDefaults.standard.object(forKey: "people.googlePhotos") as? Bool ?? true
    var allowsPersonalPhotos: Bool { !isSample && auth?.isAuthenticated == true }
    @ObservationIgnored private let cacheDirectory: URL?
    @ObservationIgnored private let transport: GooglePeoplePhotos.Transport

    init(cacheDirectory: URL? = nil,
         transport: @escaping GooglePeoplePhotos.Transport = { try await URLSession.shared.data(for: $0) }) {
        self.cacheDirectory = cacheDirectory
        self.transport = transport
    }
    private var disk: IdentityDiskCache { IdentityDiskCache(directory: cacheDirectory) }

    var authorizationVersion: String {
        "\(generation):\(auth?.photoAuthorizationVersion ?? 0):\(googlePhotosEnabled):\(auth?.accounts.map(\.id).joined(separator: ",") ?? "")"
    }

    func configure(auth: AuthService, isSample: Bool) {
        if self.auth !== auth || self.isSample != isSample {
            cancelPhotoWork()
            generation += 1
            profiles.removeAll(); photos.removeAll(); checkedProfiles.removeAll(); checkedAccounts.removeAll()
            loading.removeAll(); attempts.removeAll(); photoFailures.removeAll()
            revision += 1
        }
        self.auth = auth
        self.isSample = isSample
        guard !isSample else { return }
        // Hydrate permitted Google photo metadata before AvatarView's first frame.
        for account in auth.accounts where !auth.googlePhotoScopes(for: account.id).isEmpty {
            hydratePhotos(for: account.id)
        }
    }

    func setGooglePhotosEnabled(_ enabled: Bool) {
        cancelPhotoWork()
        googlePhotosEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "people.googlePhotos")
        generation += 1
        loading.removeAll(); attempts.removeAll()
        if !enabled { photos.removeAll(); checkedAccounts.removeAll(); photoFailures.removeAll() }
    }

    func hasGooglePhotoAccess(for account: String) -> Bool {
        !isSample && !(auth?.googlePhotoScopes(for: account).isEmpty ?? true)
    }

    func hasAllGooglePhotoAccess(for account: String) -> Bool {
        guard !isSample, let scopes = auth?.googlePhotoScopes(for: account) else { return false }
        return scopes.contains(GooglePeoplePhotos.contactsScope) && scopes.contains(GooglePeoplePhotos.otherContactsScope)
    }

    func imageKey(for address: String, role: String) -> String {
        let scope = isSample ? "sample" : (auth?.accounts.map(\.id).sorted().joined(separator: "|") ?? "signed-out")
        return "\(scope):\(GooglePeoplePhotos.normalized(address)):\(role)"
    }

    func remember(messages: [Message]) {
        // Iterate oldest first so newer, nonempty metadata wins.
        for message in messages.sorted(by: { $0.receivedAt < $1.receivedAt }) {
            let address = GooglePeoplePhotos.normalized(message.sender.address)
            let key = profileKey(account: message.mailboxID, address: address)
            guard isSample || auth?.accounts.contains(where: { $0.id == message.mailboxID }) == true else { continue }
            hydrateProfile(key)
            let fresh = Profile(address: address, avatarUri: message.sender.logoURL,
                                heroImageUrl: message.heroImageURL, heroImageBgColor: message.heroBackground,
                                senderDescription: message.senderDescription)
            var merged = profiles[key] ?? fresh
            merged.merge(fresh)
            profiles[key] = merged
            if !isSample { disk.save(merged, key: key) }
        }
        if !messages.isEmpty { revision += 1 }
    }

    func profile(for address: String) -> Profile? {
        _ = revision
        let address = GooglePeoplePhotos.normalized(address)
        if isSample { return profiles.values.first { $0.address == address } }
        var result: Profile?
        for account in auth?.accounts ?? [] {
            let key = profileKey(account: account.id, address: address)
            hydrateProfile(key)
            if var profile = profiles[key] {
                if let result { profile.merge(result) }
                result = profile
            }
        }
        return result
    }

    func googlePhoto(for address: String) -> PhotoReference? {
        _ = revision
        guard !isSample, googlePhotosEnabled, let auth else { return nil }
        let email = GooglePeoplePhotos.normalized(address)
        for account in auth.accounts where !auth.googlePhotoScopes(for: account.id).isEmpty {
            hydratePhotos(for: account.id)
            if let snapshot = photos[account.id], snapshot.scopes == auth.googlePhotoScopes(for: account.id),
               Date().timeIntervalSince(snapshot.fetchedAt) < IdentityDiskCache.lifetime,
               let url = snapshot.byEmail[email] {
                return PhotoReference(url: url, cacheKey: "google:\(account.id):\(email)")
            }
        }
        return nil
    }

    func load(for sender: Sender) async {
        guard !isSample, let auth, let account = auth.accounts.first else { return }
        // Contact refresh is shared across every avatar, with one request per
        // page per account. Don't hold a logo behind the contact request.
        async let contacts: Void = refreshGooglePhotos()
        let address = GooglePeoplePhotos.normalized(sender.address)
        let key = profileKey(account: account.id, address: address)
        if Date().timeIntervalSince(attempts[key] ?? .distantPast) > 3600, loading.insert(key).inserted {
            attempts[key] = .now
            let version = generation
            var succeeded = false
            do {
                let client = APIClient(auth: auth, accountID: account.id)
                var components = URLComponents(url: client.baseURL.appending(path: "sender-identity"), resolvingAgainstBaseURL: false)!
                components.queryItems = [.init(name: "address", value: address)]
                var request = URLRequest(url: components.url!)
                request.setValue("Bearer \(try await auth.validAccessToken(for: account.id))", forHTTPHeaderField: "Authorization")
                request.timeoutInterval = 20
                let (data, response) = try await transport(request)
                if let http = response as? HTTPURLResponse, http.statusCode == 200,
                   version == generation, !isSample, auth.accounts.contains(where: { $0.id == account.id }) {
                    let fresh = try JSONDecoder().decode(Profile.self, from: data)
                    if fresh.address == address {
                        var merged = profiles[key] ?? fresh
                        merged.merge(fresh)
                        profiles[key] = merged
                        disk.save(merged, key: key)
                        revision += 1
                        succeeded = true
                    }
                }
            } catch { /* Keep known sender art during a failed refresh. */ }
            if version == generation {
                loading.remove(key)
                if !succeeded { attempts[key] = Date().addingTimeInterval(-3540) }
            }
        }
        await contacts
    }

    func refreshGooglePhotos(force: Bool = false) async {
        guard !isSample, googlePhotosEnabled, let auth else { return }
        let refreshGeneration = generation
        for account in auth.accounts {
            guard refreshGeneration == generation, !isSample, googlePhotosEnabled, self.auth === auth else { return }
            guard auth.accounts.contains(where: { $0.id == account.id }) else { continue }
            let scopes = auth.googlePhotoScopes(for: account.id)
            guard !scopes.isEmpty else { continue }
            hydratePhotos(for: account.id)
            if !force, let current = photos[account.id], current.scopes == scopes,
               Date().timeIntervalSince(current.fetchedAt) < 86_400 { continue }
            let key = "google:" + account.id
            guard (force || Date().timeIntervalSince(attempts[key] ?? .distantPast) > 60), loading.insert(key).inserted else { continue }
            attempts[key] = .now
            let version = generation
            do {
                // Shared work belongs to the identity store. Scrolling its
                // initiating avatar offscreen must not cancel everybody's lookup.
                let transport = self.transport
                let worker = Task {
                    try Task.checkCancellation()
                    let token = try await auth.validAccessToken(for: account.id)
                    return try await GooglePeoplePhotos.fetch(token: token, scopes: scopes, transport: transport)
                }
                photoTasks[account.id] = worker
                let map = try await worker.value
                guard version == generation, googlePhotosEnabled, !isSample,
                      auth.accounts.contains(where: { $0.id == account.id }), auth.googlePhotoScopes(for: account.id) == scopes else {
                    if version == generation { loading.remove(key) }
                    continue
                }
                let snapshot = Photos(byEmail: map, fetchedAt: .now, scopes: scopes)
                photos[account.id] = snapshot
                disk.save(snapshot, key: "googlePhotos:" + account.id)
                revision += 1
                photoFailures.removeValue(forKey: account.id)
            } catch {
                if version == generation { photoFailures[account.id] = error.localizedDescription }
            }
            if version == generation {
                loading.remove(key)
                photoTasks.removeValue(forKey: account.id)
            }
        }
    }

    func clearCache() {
        cancelPhotoWork()
        generation += 1
        profiles.removeAll(); photos.removeAll(); checkedProfiles.removeAll(); checkedAccounts.removeAll()
        loading.removeAll(); attempts.removeAll(); photoFailures.removeAll()
        revision += 1
        disk.clear()
    }

    private func cancelPhotoWork() {
        for task in photoTasks.values { task.cancel() }
        photoTasks.removeAll()
    }

    private func profileKey(account: String, address: String) -> String {
        "profile:\(isSample ? "sample" : account.lowercased()):\(address)"
    }
    private func hydrateProfile(_ key: String) {
        guard checkedProfiles.insert(key).inserted, !isSample else { return }
        if let saved = disk.load(Profile.self, key: key) { profiles[key] = saved }
    }
    private func hydratePhotos(for account: String) {
        guard googlePhotosEnabled, checkedAccounts.insert(account).inserted, !isSample else { return }
        if let saved = disk.load(Photos.self, key: "googlePhotos:" + account) { photos[account] = saved }
    }
}
