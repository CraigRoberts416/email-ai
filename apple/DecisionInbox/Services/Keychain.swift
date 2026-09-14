import Foundation
import Security

/// Token storage. The Keychain rather than UserDefaults because these are
/// credentials to somebody's entire mailbox — and `afterFirstUnlock` so the
/// background fetch can still sync before the user has unlocked the phone.
enum Keychain {
    private static let service = "com.craigroberts.decisioninbox"

    /// Returns whether the write actually landed.
    ///
    /// Worth checking rather than assuming: a build without code signing has
    /// no `application-identifier` entitlement, and iOS then refuses every
    /// keychain write with errSecMissingEntitlement (-34018). Ignoring the
    /// status made that look like a successful sign-in followed by an
    /// inexplicable "that mailbox needs reconnecting" — the failure surfaced
    /// three layers away from its cause.
    @discardableResult
    static func set(_ value: String, for key: String) -> Bool {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)

        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(insert as CFDictionary, nil)
        if status != errSecSuccess {
            print("[keychain] write failed for \(key): OSStatus \(status)")
        }
        return status == errSecSuccess
    }

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    static func remove(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
