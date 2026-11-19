import Foundation

enum APIError: Error, Equatable {
    case status(Int, String)
    case network

    var status: Int {
        if case .status(let code, _) = self { return code }
        return 0
    }

    /// The device was removed in «Устройства» (or its account deleted): sign in again.
    var sessionGone: Bool { status == 401 }

    /// The token works, but this is switched off in the watch's card for now
    /// (sending, say): keep the token, it may be switched back on.
    var switchedOff: Bool { status == 403 }
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

    /// «Выйти»: the watch leaves the account's devices, its token stops
    /// working, and the server forgets where its notifications went.
    func removeSelf() async throws {
        let (status, data) = try await API.send("DELETE", "v1/devices/self", bearer: token)
        try API.check(status, data)
    }

    // MARK: This watch as a device

    /// What the watch's card on the phone shows: what it does, and the most
    /// it may do (what it asked for at pairing).
    struct Me: Decodable, Equatable {
        let capabilities: [String]
        let requested_capabilities: [String]?

        var receives: Bool { capabilities.contains("receive") }
    }

    func me() async throws -> Me {
        let (status, data) = try await API.send("GET", "v1/devices/self", bearer: token)
        try API.check(status, data)
        return try JSONDecoder().decode(Me.self, from: data)
    }

    /// «Получать сердечки» on the watch: the same switch as «Принимает» in
    /// its card on the phone. 400 if the watch never asked to receive.
    func setCapabilities(_ capabilities: [String]) async throws -> Me {
        let (status, data) = try await API.send("PATCH", "v1/devices/self", bearer: token,
                                                body: ["capabilities": capabilities])
        try API.check(status, data)
        return try JSONDecoder().decode(Me.self, from: data)
    }

    /// Hearts come to this watch as its own notifications.
    /// `silent`: «Вибрация» is none, so they come without a tap.
    func registerPush(_ pushToken: String, sandbox: Bool, silent: Bool) async throws {
        var body: [String: Any] = ["token": pushToken, "sandbox": sandbox]
        if silent { body["silent"] = true }
        let (status, data) = try await API.send("PUT", "v1/devices/self/push", bearer: token, body: body)
        try API.check(status, data)
    }

    // MARK: Pairing by code

    /// What this device asks for: it shows people and sends, and takes
    /// hearts as its own notifications.
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
