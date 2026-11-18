import AuthenticationServices
import CryptoKit
import Foundation
import Security

/// «Войти через Apple» without the Firebase SDK: Apple's identity token is
/// traded for a Firebase ID token over Identity Toolkit REST, used for one or
/// two calls, then dropped. The device keeps only its own device token.
enum AppleSignIn {
    struct FirebaseUser {
        let idToken: String
        let email: String?
    }

    enum Failure: Error {
        /// The email already has an account made another way (Google, email):
        /// Firebase won't join them here, the code sign-in does.
        case emailExists
        case failed
    }

    /// A fresh random string; Apple gets its SHA-256, Firebase the string
    /// itself, so a stolen identity token can't be replayed.
    static func newNonce() -> String {
        let chars = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return String(bytes.map { chars[Int($0) % chars.count] })
    }

    static func sha256(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func identityToken(_ authorization: ASAuthorization) -> String? {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let data = credential.identityToken else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func firebase(identityToken: String, rawNonce: String) async throws -> FirebaseUser {
        var url = URLComponents(string: "https://identitytoolkit.googleapis.com/v1/accounts:signInWithIdp")!
        url.queryItems = [URLQueryItem(name: "key", value: Config.firebaseAPIKey)]
        var req = URLRequest(url: url.url!)
        req.httpMethod = "POST"
        req.timeoutInterval = 20
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "postBody": "id_token=\(identityToken)&providerId=apple.com&nonce=\(rawNonce)",
            "requestUri": "http://localhost",
            "returnIdpCredential": true,
            "returnSecureToken": true,
        ])
        let data: Data
        let status: Int
        do {
            let (body, resp) = try await URLSession.shared.data(for: req)
            data = body
            status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        } catch {
            throw APIError.network
        }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if status != 200 {
            let message = (json["error"] as? [String: Any])?["message"] as? String ?? ""
            throw message.contains("EMAIL_EXISTS") ? Failure.emailExists : Failure.failed
        }
        if json["needConfirmation"] as? Bool == true {
            throw Failure.emailExists
        }
        guard let idToken = json["idToken"] as? String else { throw Failure.failed }
        return FirebaseUser(idToken: idToken, email: json["email"] as? String)
    }
}
