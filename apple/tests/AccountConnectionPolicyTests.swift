import Foundation

@main struct AccountConnectionPolicyTests {
    static func main() {
        let base = AccountConnectionPolicy.scopes(includeGooglePhotos: false)
        precondition(base.contains("https://mail.google.com/"))
        precondition(!base.contains("contacts"), "Photos must not be requested implicitly")
        let photos = AccountConnectionPolicy.scopes(includeGooglePhotos: true)
        precondition(photos.contains("contacts.readonly") && photos.contains("contacts.other.readonly"))
        precondition(AccountConnectionPolicy.matches("Work@Example.invalid", expected: "work@example.invalid"))
        precondition(!AccountConnectionPolicy.matches("personal@example.invalid", expected: "work@example.invalid"))
        precondition(AccountConnectionPolicy.matches("new@example.invalid", expected: nil))
        precondition(AccountConnectionPolicy.normalizedTag(" h-o1me ") == "HO1M")
        let suggestions = AccountConnectionPolicy.tagSuggestions("HOME", address: "home@example.invalid", taken: ["HOME", "EXAM"])
        precondition(suggestions == ["HOM2"], "A four-character collision must produce a usable correction")
        precondition(suggestions.allSatisfy { AccountConnectionPolicy.normalizedTag($0) == $0 && (2...4).contains($0.count) })
        let suite = "account-policy-test-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        precondition(AccountConnectionPolicy.included("work", defaults: defaults))
        AccountConnectionPolicy.setIncluded(false, accountID: "work", defaults: defaults)
        let relaunched = UserDefaults(suiteName: suite)!
        precondition(!AccountConnectionPolicy.included("work", defaults: relaunched))
        precondition(AccountConnectionPolicy.included("personal", defaults: relaunched))
        AccountConnectionPolicy.setIncluded(false, accountID: "personal", defaults: relaunched)
        precondition(!AccountConnectionPolicy.included("work", defaults: relaunched) && !AccountConnectionPolicy.included("personal", defaults: relaunched))
        print("Account connection policy: 13 synthetic checks passed")
    }
}
