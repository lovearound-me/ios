import Foundation

/// A person in the address book, as the server gives it to a device.
struct Contact: Codable, Identifiable, Equatable {
    /// The server's id for this entry; the person's own id never leaves it.
    let id: String
    var label: String
    var position: Int
    /// A close person: a circle first. Optional: older servers leave it out.
    var close: Bool?
    /// The owner's color for them, an index into `Palette`.
    var color: Int?

    var isClose: Bool { close ?? false }
}

enum APIError: Error, Equatable {
    case status(Int, String)
    case network

    var status: Int {
        if case .status(let code, _) = self { return code }
        return 0
    }

    /// The device was removed in «Устройства» (or its account deleted): sign in again.
    var sessionGone: Bool { status == 401 || status == 403 }
}

/// needed-server REST for a device. Everything here goes with the device
/// token, except pairing (no token yet) and the two calls made with a
/// Firebase ID token right after «Войти через Apple».
struct API {
    let token: String

    func contacts() async throws -> [Contact] {
        struct List: Decodable { let contacts: [Contact] }
        let (status, data) = try await API.send("GET", "v1/contacts", bearer: token)
        try API.check(status, data)
        return try JSONDecoder().decode(List.self, from: data).contacts
    }

    func signal(_ contactID: String) async throws {
        let (status, data) = try await API.send("POST", "v1/events", bearer: token,
                                                body: ["type": "signal", "to": ["contact": contactID]])
        try API.check(status, data)
    }

    /// 202 even with nobody to take it; 429 if one already went this hour.
    func signalAnyone() async throws {
        let (status, data) = try await API.send("POST", "v1/events", bearer: token,
                                                body: ["type": "signal", "to": ["anyone": true]])
        try API.check(status, data)
    }

    // MARK: Pairing by code

    /// What this device asks for: it shows people and sends, and takes signals.
    static let deviceAsk: [String: Any] = [
        "name": "Apple Watch",
        "kind": "watch",
        "capabilities": ["receive", "send"],
    ]

    struct PairingCode: Decodable, Equatable {
        /// Six digits to show.
        let code: String
        /// Kept here: only it gets the token, the digits alone never do.
        let secret: String
        /// lovearound.me/login/devices#<code>, for the QR.
        let url: String
        let expires_in: Int
        let poll_every: Int
    }

    enum PairingState: Equatable {
        case waiting
        case paired(Session)
        /// Expired, used or never existed: ask for a new code.
        case gone
    }

    static func startPairing() async throws -> PairingCode {
        let (status, data) = try await send("POST", "v1/pairing", body: deviceAsk)
        try check(status, data)
        return try JSONDecoder().decode(PairingCode.self, from: data)
    }

    static func pollPairing(secret: String) async throws -> PairingState {
        struct Paired: Decodable { let token: String; let account: String? }
        let (status, data) = try await send("POST", "v1/pairing/token", body: ["secret": secret])
        switch status {
        case 202: return .waiting
        case 200:
            let paired = try JSONDecoder().decode(Paired.self, from: data)
            return .paired(Session(token: paired.token, email: paired.account))
        case 404, 410: return .gone
        default:
            try check(status, data)
            return .waiting
        }
    }

    // MARK: With a Firebase ID token (after «Войти через Apple»)

    /// Makes this device's own token, like «Устройства» → «Добавить» does.
    static func createDevice(firebaseToken: String, email: String?) async throws -> Session {
        struct Created: Decodable { let token: String }
        let (status, data) = try await send("POST", "v1/devices", bearer: firebaseToken, body: deviceAsk)
        try check(status, data)
        return Session(token: try JSONDecoder().decode(Created.self, from: data).token, email: email)
    }

    /// Deletes the whole account, as Settings → Account in the web app does.
    static func deleteAccount(firebaseToken: String) async throws {
        let (status, data) = try await send("DELETE", "v1/me", bearer: firebaseToken)
        try check(status, data)
    }

    // MARK: Plumbing

    static func send(_ method: String, _ path: String, bearer: String? = nil,
                     body: [String: Any]? = nil) async throws -> (Int, Data) {
        var req = URLRequest(url: Config.apiBase.appendingPathComponent(path))
        req.httpMethod = method
        req.timeoutInterval = 20
        if let bearer { req.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        req.setValue(Config.client, forHTTPHeaderField: "X-Client")
        if let body {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            return ((resp as? HTTPURLResponse)?.statusCode ?? 0, data)
        } catch {
            throw APIError.network
        }
    }

    static func check(_ status: Int, _ data: Data) throws {
        guard !(200..<300).contains(status) else { return }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        throw APIError.status(status, json?["error"] as? String ?? "")
    }
}
