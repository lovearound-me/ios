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
            case "INVALID_PASSWORD", "INVALID_LOGIN_CREDENTIALS":
                return tr("Неверный пароль. Если раньше вход был через Google или Apple, нажми «Отмена» и войди так же")
            case "WEAK_PASSWORD": return tr("Пароль слишком простой")
            case "INVALID_EMAIL", "MISSING_EMAIL": return tr("Проверь адрес почты")
            case "MISSING_PASSWORD": return tr("Введи пароль")
            case "EMAIL_EXISTS": return tr("С этой почтой уже есть аккаунт. Войди так же, как в прошлый раз.")
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

/// Firebase Auth over its REST API, as in the Mac app, all of it right in
/// the app: Apple (AppleSignIn.swift), Google (Google's own sign-in gives the
/// ID token, GoogleAccount.swift), and email with a password.
@MainActor
final class Auth {
    private(set) var session: Session?
    private var idToken: String?
    private var expiresAt = Date.distantPast
    private var refreshing: Task<String, Error>?
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
            Keychain.share(Self.keychainAccount)
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

    // MARK: Google and email

    /// Google's ID token, from Google's own sign-in, for a Firebase session.
    /// One account per email: an email whose account was made another way is
    /// refused (EMAIL_EXISTS), and the person signs in that way.
    func signIn(google googleIDToken: String) async throws {
        let json = try await Self.identity("accounts:signInWithIdp", [
            "postBody": "id_token=\(googleIDToken)&providerId=google.com",
            "requestUri": "http://localhost",
            "returnIdpCredential": true,
            "returnSecureToken": true,
        ])
        if json["needConfirmation"] as? Bool == true { throw AuthError.server("EMAIL_EXISTS") }
        try adopt(json)
    }

    /// Email and password, as on the site: signs in, or makes the account if
    /// the email has none. With email enumeration protection a wrong password
    /// and a missing account look the same, so making it tells them apart.
    func signIn(email: String, password: String) async throws {
        let body: [String: Any] = ["email": email, "password": password, "returnSecureToken": true]
        do {
            try adopt(try await Self.identity("accounts:signInWithPassword", body))
        } catch AuthError.server(let code) where ["INVALID_LOGIN_CREDENTIALS", "EMAIL_NOT_FOUND", "INVALID_PASSWORD"].contains(where: code.hasPrefix) {
            do {
                try adopt(try await Self.identity("accounts:signUp", body))
            } catch AuthError.server(let made) where made.hasPrefix("EMAIL_EXISTS") {
                // The account is there, so it was the password.
                throw AuthError.server("INVALID_PASSWORD")
            }
        }
    }

    /// «Забыли пароль?»: Firebase mails a link for a new one.
    func sendPasswordReset(email: String) async throws {
        _ = try await Self.identity("accounts:sendOobCode", ["requestType": "PASSWORD_RESET", "email": email])
    }

    private func adopt(_ json: [String: Any]) throws {
        guard let uid = json["localId"] as? String, !uid.isEmpty,
              let refreshToken = json["refreshToken"] as? String, !refreshToken.isEmpty,
              let id = json["idToken"] as? String else { throw AuthError.server("BAD_RESPONSE") }
        adopt(Session(uid: uid, email: json["email"] as? String, refreshToken: refreshToken))
        idToken = id
        expiresAt = Date().addingTimeInterval(Double(json["expiresIn"] as? String ?? "") ?? 3600)
    }

    private static func identity(_ method: String, _ body: [String: Any]) async throws -> [String: Any] {
        var req = URLRequest(url: URL(string: "https://identitytoolkit.googleapis.com/v1/\(method)?key=\(Config.firebaseAPIKey)")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 20
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await call(req)
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
        var text = String(parts.count == 3 ? parts[1] : "")
            .replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        text += String(repeating: "=", count: (4 - text.count % 4) % 4)
        guard parts.count == 3, let data = Data(base64Encoded: text) else { return [:] }
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
