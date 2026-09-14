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
        if status == errSecSuccess { return true }

        print("[keychain] write failed for \(key): OSStatus \(status)")

        #if DEBUG && targetEnvironment(simulator)
        // A simulator build is ad-hoc signed and carries no
        // `application-identifier`, so iOS refuses every keychain write with
        // errSecMissingEntitlement. That made the app impossible to exercise
        // against a real mailbox on a simulator — sign-in appeared to succeed
        // and then every request found no token.
        //
        // Never compiled into a device build and never into Release: this is
        // a development affordance, and a real credential does not belong in
        // a plist anywhere it could ship.
        fallbackSet(key, value)
        return true
        #else
        return false
        #endif
    }

    #if DEBUG && targetEnvironment(simulator)
    // UserDefaults rather than memory: an in-memory fallback is wiped by every
    // reinstall, which is exactly when a developer is trying to check that a
    // session survived. Simulator-only, Debug-only, never on a device.
    private static let fallbackPrefix = "debug.keychain."

    private static var fallback: [String: String] {
        get { [:] }
        set { _ = newValue }
    }

    private static func fallbackGet(_ key: String) -> String? {
        UserDefaults.standard.string(forKey: fallbackPrefix + key)
    }

    private static func fallbackSet(_ key: String, _ value: String?) {
        UserDefaults.standard.set(value, forKey: fallbackPrefix + key)
    }
    #endif

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
           let data = item as? Data {
            return String(decoding: data, as: UTF8.self)
        }
        #if DEBUG && targetEnvironment(simulator)
        return fallbackGet(key)
        #else
        return nil
        #endif
    }

    static func remove(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
        #if DEBUG && targetEnvironment(simulator)
        fallbackSet(key, nil)
        #endif
    }
}
