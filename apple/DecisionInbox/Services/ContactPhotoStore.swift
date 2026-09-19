import Contacts
import Foundation
import Observation

/// Personal photos come from contacts the reader permits this phone to see.
/// Lookup and image bytes stay on the device; no address book is uploaded.
@MainActor
@Observable
final class ContactPhotoStore {
    static let shared = ContactPhotoStore()
    var authorizationVersion = 0
    var enabled = UserDefaults.standard.bool(forKey: "people.contactPhotos")
    private var photos: [String: Data] = [:]
    private var queried: Set<String> = []
    private var loading: Set<String> = []

    var permitted: Bool {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        return status == .authorized || status == .limited
    }

    func imageData(for address: String) -> Data? {
        guard enabled, permitted else { return nil }
        return photos[address.lowercased()]
    }

    @discardableResult
    func setEnabled(_ value: Bool) async -> Bool {
        if value, CNContactStore.authorizationStatus(for: .contacts) == .notDetermined {
            _ = try? await CNContactStore().requestAccess(for: .contacts)
        }
        enabled = value && permitted
        UserDefaults.standard.set(enabled, forKey: "people.contactPhotos")
        refreshAuthorization()
        return enabled
    }

    func refreshAuthorization() {
        photos.removeAll()
        queried.removeAll()
        authorizationVersion += 1
    }

    func loadPhoto(for address: String) async {
        let key = address.lowercased()
        guard enabled, permitted, !queried.contains(key), loading.insert(key).inserted else { return }
        let version = authorizationVersion
        // CNContactStore's synchronous query runs away from the UI thread.
        let data = await Task.detached(priority: .utility) {
            let predicate = CNContact.predicateForContacts(matchingEmailAddress: key)
            let contacts = try? CNContactStore().unifiedContacts(matching: predicate,
                keysToFetch: [CNContactThumbnailImageDataKey as CNKeyDescriptor])
            return contacts?.compactMap(\.thumbnailImageData).first
        }.value
        loading.remove(key)
        guard version == authorizationVersion, enabled, permitted else { return }
        queried.insert(key)
        if let data { photos[key] = data }
    }
}
