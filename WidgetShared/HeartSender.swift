import Foundation

/// Sends a heart from outside the app's own screens: a widget's bubble, a
/// Control Center button, the Action button, Siri. Signs in with what the
/// app keeps in the shared Keychain: the iPhone's Firebase refresh token
/// (traded for an ID token here, each time).
enum HeartSender {
    enum Failure: LocalizedError {
        case signedOut, network, anyoneThisHour, refused

        var errorDescription: String? {
            switch self {
            case .signedOut: return tr("Войди в Love Around на этом iPhone")
            case .network: return tr("Не улетело, проверь интернет")
            case .anyoneThisHour: return tr("Кому-нибудь на свете уже улетело в этот час.")
            case .refused: return tr("Не получилось. Попробуй ещё раз.")
            }
        }
    }

    static func send(to contactID: String) async throws {
        try await post(["type": "signal", "to": ["contact": contactID]])
    }

    /// Once an hour: the server answers 429 to a second one.
    static func sendAnyone() async throws {
        try await post(["type": "signal", "to": ["anyone": true]])
    }

    private static let keychainAccount = "account"

    private static func post(_ body: [String: Any]) async throws {
        let token = try await idToken()
        var req = URLRequest(url: Config.apiBase.appendingPathComponent("v1/events"))
        req.httpMethod = "POST"
        req.timeoutInterval = 20
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue(Config.client, forHTTPHeaderField: "X-Client")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let status: Int
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        } catch {
            throw Failure.network
        }
        switch status {
        case 200..<300: return
        case 401: throw Failure.signedOut
        case 429 where (body["to"] as? [String: Any])?["anyone"] != nil: throw Failure.anyoneThisHour
        default: throw Failure.refused
        }
    }

    /// The app's session (Phone/Auth.swift keeps it as JSON with a
    /// `refreshToken`), traded at Firebase for an ID token. A new refresh
    /// token, if Firebase gives one, goes back into the Keychain.
    private static func idToken() async throws -> String {
        guard let text = Keychain.read(keychainAccount),
              var session = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any],
              let refresh = session["refreshToken"] as? String, !refresh.isEmpty else { throw Failure.signedOut }
        var req = URLRequest(url: URL(string: "https://securetoken.googleapis.com/v1/token?key=\(Config.firebaseAPIKey)")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 20
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = [
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: refresh),
        ]
        req.httpBody = form.percentEncodedQuery?.data(using: .utf8)
        let data: Data
        let resp: URLResponse
        do {
            (data, resp) = try await URLSession.shared.data(for: req)
        } catch {
            throw Failure.network
        }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (resp as? HTTPURLResponse)?.statusCode == 200, let id = json["id_token"] as? String else {
            throw Failure.signedOut
        }
        if let newRefresh = json["refresh_token"] as? String, newRefresh != refresh {
            session["refreshToken"] = newRefresh
            if let data = try? JSONSerialization.data(withJSONObject: session) {
                Keychain.write(keychainAccount, String(decoding: data, as: UTF8.self))
            }
        }
        return id
    }
}
