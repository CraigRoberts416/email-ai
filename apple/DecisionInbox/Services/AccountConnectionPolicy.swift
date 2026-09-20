import Foundation

/// Pure account rules shared by the UI, auth boundary and synthetic tests.
enum AccountConnectionPolicy {
    static func scopes(includeGooglePhotos: Bool) -> String {
        var result = ["openid", "profile", "email", "https://mail.google.com/"]
        if includeGooglePhotos {
            result += ["https://www.googleapis.com/auth/contacts.readonly",
                       "https://www.googleapis.com/auth/contacts.other.readonly"]
        }
        return result.joined(separator: " ")
    }

    static func matches(_ address: String, expected: String?) -> Bool {
        expected.map { address.caseInsensitiveCompare($0) == .orderedSame } ?? true
    }

    static func normalizedTag(_ tag: String) -> String {
        String(tag.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(4))
    }

    static func tagSuggestions(_ tag: String, address: String, taken: Set<String>) -> [String] {
        let normalized = normalizedTag(tag)
        let parts = address.split(separator: "@", maxSplits: 1).map(String.init)
        let candidates = [String(normalized.prefix(3)) + "2"] + parts.map(normalizedTag)
        var seen: Set<String> = []
        return candidates.filter {
            (2...4).contains($0.count) && !taken.contains($0) && $0 != normalized && seen.insert($0).inserted
        }
    }

    static func included(_ accountID: String, defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: "feed.included.\(accountID)") as? Bool ?? true
    }

    static func setIncluded(_ value: Bool, accountID: String, defaults: UserDefaults = .standard) {
        defaults.set(value, forKey: "feed.included.\(accountID)")
    }
}
