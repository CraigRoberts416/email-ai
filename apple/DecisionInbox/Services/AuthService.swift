import AuthenticationServices
import CryptoKit
import Foundation
import Observation

/// Google OAuth for a native iOS client, for as many mailboxes as you like.
///
/// Native clients get no secret, so the flow is authorization-code + PKCE
/// through `ASWebAuthenticationSession` — which runs in a system view the app
/// cannot read. The app never sees the password, only the code Google hands
/// back to our redirect scheme.
///
/// Multi-account is not a feature bolted on top: every token is namespaced by
/// the address it belongs to, and there is no "current account". The server
/// resolves a user from whichever token it is handed, so N mailboxes is N
/// independent sessions that this app unions — no server ever learns they are
/// the same person, which is the privacy-preserving shape as well as the
/// simplest one.
@Observable
final class AuthService: NSObject {
    static let clientID = "363042805824-u1l35m2a76bgvratjrjdfs9s645b33jd.apps.googleusercontent.com"

    struct Account: Identifiable, Hashable {
        /// The address. The mailbox is the account, so it needs no other id.
        let id: String
        /// Two to four characters, shown when a unified feed has to attribute
        /// a message without spending the one colour the product has.
        var tag: String
    }

    private static var redirectURI: String {
        let reversed = clientID.replacingOccurrences(of: ".apps.googleusercontent.com", with: "")
        return "com.googleusercontent.apps.\(reversed):/oauth2redirect"
    }

    private static let scopes = [
        "openid", "profile", "email", "https://mail.google.com/",
    ].joined(separator: " ")

    private enum Key {
        static let index = "google.accounts"
        static func accessToken(_ id: String) -> String { "google.\(id).accessToken" }
        static func refreshToken(_ id: String) -> String { "google.\(id).refreshToken" }
        static func expiresAt(_ id: String) -> String { "google.\(id).expiresAt" }
        static func tag(_ id: String) -> String { "google.\(id).tag" }
    }

    var accounts: [Account] = []
    var lastError: String?
    var isConnecting = false

    var isAuthenticated: Bool { !accounts.isEmpty }

    private var session: ASWebAuthenticationSession?

    override init() {
        super.init()
        accounts = Self.storedIDs().map {
            Account(id: $0, tag: Keychain.get(Key.tag($0)) ?? Self.defaultTag(for: $0))
        }
    }

    // MARK: Connecting a mailbox

    /// Runs the whole flow and returns the account it connected. Adding the
    /// second mailbox is the same call as adding the first.
    @MainActor
    @discardableResult
    func connect() async -> Account? {
        lastError = nil
        isConnecting = true
        defer { isConnecting = false }

        let verifier = Self.randomVerifier()
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            .init(name: "client_id", value: Self.clientID),
            .init(name: "redirect_uri", value: Self.redirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: Self.scopes),
            .init(name: "code_challenge", value: Self.challenge(for: verifier)),
            .init(name: "code_challenge_method", value: "S256"),
            // Without these Google returns no refresh token on repeat consent,
            // and the session silently dies an hour later.
            .init(name: "access_type", value: "offline"),
            .init(name: "prompt", value: "consent select_account"),
        ]

        guard let url = components.url else { return nil }
        let scheme = String(Self.redirectURI.split(separator: ":").first ?? "")

        do {
            let callback: URL = try await withCheckedThrowingContinuation { continuation in
                let session = ASWebAuthenticationSession(
                    url: url, callbackURLScheme: scheme
                ) { callbackURL, error in
                    if let callbackURL {
                        continuation.resume(returning: callbackURL)
                    } else {
                        continuation.resume(throwing: error ?? AuthError.cancelled)
                    }
                }
                session.presentationContextProvider = self
                // Not ephemeral: a second mailbox on the same device should be
                // able to reuse an existing Google session rather than retyping
                // a password the app must never see.
                session.prefersEphemeralWebBrowserSession = false
                self.session = session
                session.start()
            }

            guard let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "code" })?.value else {
                throw AuthError.noCode
            }

            let token = try await postForm([
                "client_id": Self.clientID,
                "grant_type": "authorization_code",
                "code": code,
                "redirect_uri": Self.redirectURI,
                "code_verifier": verifier,
            ])
            guard let refresh = token.refreshToken else { throw AuthError.noRefreshToken }

            // The address has to be resolved before anything is stored, because
            // it *is* the key everything else is filed under.
            let address = try await Self.email(for: token.accessToken)
            store(token, for: address, keepingRefresh: refresh)

            if let existing = accounts.firstIndex(where: { $0.id == address }) {
                // Reconnecting an expired mailbox, not adding a new one.
                return accounts[existing]
            }
            let account = Account(id: address, tag: uniqueTag(for: address))
            Keychain.set(account.tag, for: Key.tag(address))
            accounts.append(account)
            Self.storeIDs(accounts.map(\.id))
            return account
        } catch AuthError.cancelled {
            return nil  // The user backed out. Not an error worth surfacing.
        } catch let error as NSError
            where error.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
            return nil
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    func disconnect(_ id: String) {
        [Key.accessToken(id), Key.refreshToken(id), Key.expiresAt(id), Key.tag(id)]
            .forEach(Keychain.remove)
        accounts.removeAll { $0.id == id }
        Self.storeIDs(accounts.map(\.id))
    }

    func rename(_ id: String, tag: String) {
        guard let i = accounts.firstIndex(where: { $0.id == id }) else { return }
        let cleaned = String(tag.uppercased().prefix(4)).trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty else { return }
        accounts[i].tag = cleaned
        Keychain.set(cleaned, for: Key.tag(id))
    }

    // MARK: Tokens

    /// Returns a token good for at least another minute, refreshing if needed.
    func validAccessToken(for id: String) async throws -> String {
        let expiry = Keychain.get(Key.expiresAt(id)).flatMap(Double.init) ?? 0
        if let token = Keychain.get(Key.accessToken(id)),
           Date().timeIntervalSince1970 < expiry - 60 {
            return token
        }
        guard let refresh = Keychain.get(Key.refreshToken(id)) else {
            throw AuthError.signedOut
        }
        let token = try await postForm([
            "client_id": Self.clientID,
            "grant_type": "refresh_token",
            "refresh_token": refresh,
        ])
        store(token, for: id, keepingRefresh: refresh)
        return token.accessToken
    }

    func refreshToken(for id: String) -> String? { Keychain.get(Key.refreshToken(id)) }

    func expiresAt(for id: String) -> Double {
        Keychain.get(Key.expiresAt(id)).flatMap(Double.init) ?? 0
    }

    private func store(_ token: TokenResponse, for id: String, keepingRefresh existing: String?) {
        Keychain.set(token.accessToken, for: Key.accessToken(id))
        Keychain.set(
            String(Date().timeIntervalSince1970 + Double(token.expiresIn)),
            for: Key.expiresAt(id)
        )
        // Google omits the refresh token on refresh responses; never clobber it.
        if let refresh = token.refreshToken ?? existing {
            Keychain.set(refresh, for: Key.refreshToken(id))
        }
    }

    private func postForm(_ fields: [String: String]) async throws -> TokenResponse {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(
            fields.map { "\($0.key)=\($0.value.formEncoded)" }.joined(separator: "&").utf8
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            // A revoked grant surfaces here; the caller reconnects rather than looping.
            throw AuthError.tokenEndpoint(String(decoding: data, as: UTF8.self))
        }
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    private static func email(for accessToken: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://www.googleapis.com/oauth2/v3/userinfo")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: request)
        struct Info: Decodable { let email: String? }
        guard let email = try? JSONDecoder().decode(Info.self, from: data).email, !email.isEmpty else {
            throw AuthError.noEmail
        }
        return email
    }

    // MARK: Tags

    private static func defaultTag(for address: String) -> String {
        let local = address.prefix(while: { $0 != "@" })
        return String(local.prefix(2)).uppercased()
    }

    /// Collisions are resolved at creation rather than at render, so a tag
    /// never changes meaning once the user has learned it.
    private func uniqueTag(for address: String) -> String {
        let taken = Set(accounts.map(\.tag))
        let local = String(address.prefix(while: { $0 != "@" })).uppercased()
        let domain = String(address.drop(while: { $0 != "@" }).dropFirst().prefix(while: { $0 != "." })).uppercased()

        for candidate in [
            String(local.prefix(2)), String(local.prefix(3)), String(local.prefix(4)),
            String(domain.prefix(3)), String(domain.prefix(4)),
        ] where !candidate.isEmpty && !taken.contains(candidate) {
            return candidate
        }
        var n = 2
        while taken.contains("\(local.prefix(2))\(n)") { n += 1 }
        return "\(local.prefix(2))\(n)"
    }

    // MARK: Index

    private static func storedIDs() -> [String] {
        guard let raw = Keychain.get(Key.index), let data = raw.data(using: .utf8),
              let ids = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return ids
    }

    private static func storeIDs(_ ids: [String]) {
        guard let data = try? JSONEncoder().encode(ids) else { return }
        Keychain.set(String(decoding: data, as: UTF8.self), for: Key.index)
    }

    // MARK: PKCE

    private static func randomVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncoded
    }

    private static func challenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded
    }
}

// MARK: - Presentation

extension AuthService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}

// MARK: - Supporting types

enum AuthError: LocalizedError {
    case cancelled
    case noCode
    case noRefreshToken
    case noEmail
    case signedOut
    case tokenEndpoint(String)

    var errorDescription: String? {
        switch self {
        case .cancelled, .noCode:
            return "You didn\u{2019}t finish connecting. Nothing was shared and nothing was stored."
        case .noRefreshToken:
            return "Google didn\u{2019}t return a refresh token, so the session would expire in an hour. Try connecting again."
        case .noEmail:
            return "Google didn\u{2019}t say which address that was. Try connecting again."
        case .signedOut:
            return "That mailbox needs reconnecting."
        case .tokenEndpoint(let detail):
            return detail
        }
    }
}

struct TokenResponse: Decodable {
    let accessToken: String
    let expiresIn: Int
    let refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
    }
}

// `Data.base64URLEncoded` lives in GmailClient.swift — PKCE and Gmail's raw
// message field want the same encoding.

private extension String {
    var formEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? self
    }
}
