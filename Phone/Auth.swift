import Foundation

/// A signed-in Firebase account. Only the refresh token is kept (in the
/// Keychain); ID tokens live in memory.
struct Session: Codable, Equatable {
    var uid: String
    var email: String?
    var refreshToken: String
}

enum AuthError: LocalizedError {
    case signedOut
    /// A Firebase Auth error code, e.g. "EMAIL_EXISTS".
    case server(String)
    case network

    var errorDescription: String? {
        switch self {
        case .signedOut:
            return tr("Нужно войти заново")
        case .network:
            return tr("Нет связи, проверь интернет")
        case .server(let code):
            let code = code.components(separatedBy: " ").first ?? code
            switch code {
            case "TOO_MANY_ATTEMPTS_TRY_LATER": return tr("Слишком много попыток, попробуй чуть позже")
            case "USER_DISABLED": return tr("Этот аккаунт отключён")
            case "BAD_CALLBACK": return tr("Вход не завершился, попробуй ещё раз")
            default: return tr("Не получилось войти ({code})", ["code": code])
            }
        }
    }

    /// Errors after which the stored session is useless.
    var endsSession: Bool {
        switch self {
        case .signedOut: return true
        case .network: return false
        case .server(let code):
            return ["TOKEN_EXPIRED", "USER_DISABLED", "USER_NOT_FOUND", "INVALID_REFRESH_TOKEN", "INVALID_GRANT_TYPE"]
                .contains { code.hasPrefix($0) }
        }
    }
}

/// Firebase Auth over its REST API, as in the Mac app. Apple signs in right
/// here (AppleSignIn.swift); Google and email on the site's /signin/ page in
/// Safari, which hands the session back via lovearound://signin, sealed to a
/// one-time key of ours (SignInBox.swift).
@MainActor
final class Auth {
    private(set) var session: Session?
    private var idToken: String?
    private var expiresAt = Date.distantPast
    private var refreshing: Task<String, Error>?
    private var pendingState: String?
    private var pendingKey: SignInKey?
    /// A test run's ID token, given at launch: nothing is saved or refreshed,
    /// and it stops working within the hour (DEBUG builds only).
    private var borrowed = false

    private static let keychainAccount = "account"

    init() {
        #if DEBUG
        if let token = ProcessInfo.processInfo.environment["LOVEAROUND_TEST_ID_TOKEN"], !token.isEmpty {
            let claims = Self.claims(token)
            session = Session(uid: claims["user_id"] as? String ?? "", email: claims["email"] as? String, refreshToken: "")
            idToken = token
            expiresAt = (claims["exp"] as? Double).map { Date(timeIntervalSince1970: $0) } ?? Date().addingTimeInterval(1800)
            borrowed = true
            return
        }
        #endif
        if let text = Keychain.read(Self.keychainAccount) {
            session = try? JSONDecoder().decode(Session.self, from: Data(text.utf8))
        }
    }

    /// A valid ID token, refreshed when it is about to expire.
    func token(forceRefresh: Bool = false) async throws -> String {
        if borrowed {
            guard let idToken, expiresAt > Date() else { throw AuthError.signedOut }
            return idToken
        }
        if !forceRefresh, let idToken, expiresAt.timeIntervalSinceNow > 300 {
            return idToken
        }
        if let refreshing {
            return try await refreshing.value
        }
        let task = Task { try await self.refresh() }
        refreshing = task
        defer { refreshing = nil }
        return try await task.value
    }

    private func refresh() async throws -> String {
        guard let session else { throw AuthError.signedOut }
        var req = URLRequest(url: URL(string: "https://securetoken.googleapis.com/v1/token?key=\(Config.firebaseAPIKey)")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = [
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: session.refreshToken),
        ]
        req.httpBody = form.percentEncodedQuery?.data(using: .utf8)
        let json = try await Self.call(req)
        guard let id = json["id_token"] as? String, let refreshToken = json["refresh_token"] as? String else {
            throw AuthError.server("BAD_RESPONSE")
        }
        idToken = id
        expiresAt = Date().addingTimeInterval(Double(json["expires_in"] as? String ?? "") ?? 3600)
        if refreshToken != session.refreshToken {
            self.session?.refreshToken = refreshToken
            save()
        }
        return id
    }

    // MARK: Apple

    func adopt(apple user: AppleSignIn.FirebaseUser) throws {
        guard !user.uid.isEmpty, !user.refreshToken.isEmpty else { throw AuthError.server("BAD_RESPONSE") }
        adopt(Session(uid: user.uid, email: user.email, refreshToken: user.refreshToken))
        idToken = user.idToken
        expiresAt = Date().addingTimeInterval(3600)
    }

    // MARK: Google or email, on the site

    /// The page that signs in (Google, email, Apple too) and returns to
    /// lovearound://signin with the session sealed to our one-time key. Asked
    /// again before it answered, it is the same page, so whichever tab
    /// finishes signs in.
    func browserSignInURL() -> URL {
        if let state = pendingState, let key = pendingKey {
            return Self.signInURL(state: state, key: key)
        }
        let state = UUID().uuidString
        let key = SignInKey()
        pendingState = state
        pendingKey = key
        return Self.signInURL(state: state, key: key)
    }

    private static func signInURL(state: String, key: SignInKey) -> URL {
        URL(string: "\(Config.site)/signin?state=\(state)&key=\(key.publicKey)")!
    }

    /// lovearound://signin?state=…&epk=…&box=…, the box holding uid, email and
    /// the refresh token.
    func completeBrowser(_ url: URL) async throws {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let q = Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
        // The state proves the callback answers our own request, so a crafted
        // link cannot sign the app into someone else's account.
        guard let state = pendingState, q["state"] == state else { throw AuthError.server("BAD_CALLBACK") }
        guard let sealed = pendingKey?.open(epk: q["epk"] ?? "", box: q["box"] ?? "", state: state),
              !sealed.uid.isEmpty, !sealed.rt.isEmpty else { throw AuthError.server("BAD_CALLBACK") }
        pendingState = nil
        pendingKey = nil
        adopt(Session(uid: sealed.uid, email: sealed.email, refreshToken: sealed.rt))
        _ = try await token(forceRefresh: true)
    }

    // MARK: Session

    /// How this session signed in, from the ID token: "apple.com",
    /// "google.com" or "password"; nil before the first token.
    var provider: String? {
        guard let idToken else { return nil }
        return (Self.claims(idToken)["firebase"] as? [String: Any])?["sign_in_provider"] as? String
    }

    func signOut() {
        session = nil
        idToken = nil
        expiresAt = .distantPast
        if !borrowed {
            Keychain.write(Self.keychainAccount, nil)
        }
        borrowed = false
    }

    private func adopt(_ session: Session) {
        self.session = session
        idToken = nil
        expiresAt = .distantPast
        borrowed = false
        save()
    }

    private func save() {
        guard !borrowed, let session, let data = try? JSONEncoder().encode(session) else { return }
        Keychain.write(Self.keychainAccount, String(decoding: data, as: UTF8.self))
    }

    /// An ID token's payload, unverified: only for what the app shows (the
    /// email of a test run, how the account signs in).
    private static func claims(_ token: String) -> [String: Any] {
        let parts = token.split(separator: ".")
        guard parts.count == 3, let data = SignInKey.data(base64url: String(parts[1])) else { return [:] }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    private static func call(_ req: URLRequest) async throws -> [String: Any] {
        let data: Data
        let resp: URLResponse
        do {
            (data, resp) = try await URLSession.shared.data(for: req)
        } catch {
            throw AuthError.network
        }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let error = json["error"] as? [String: Any]
            throw AuthError.server(error?["message"] as? String ?? "HTTP_\(status)")
        }
        return json
    }
}
