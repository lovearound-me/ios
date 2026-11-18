import Foundation

/// One of the person's own devices: a watch, a lamp, a board, each with its
/// own token.
struct Device: Codable, Identifiable, Equatable {
    let id: String
    var kind: String?
    let name: String
    let capabilities: [String]
    var last_seen_at: String?

    var receives: Bool { capabilities.contains("receive") }
    var sends: Bool { capabilities.contains("send") }
}

struct Me: Codable {
    let uid: String
    let invite_url: String
}

/// What a device showing a code asked for (POST /v1/pairing/find).
struct PairingCard: Codable, Equatable {
    let name: String
    let kind: String?
    let capabilities: [String]
}

enum APIError: LocalizedError {
    case status(Int, String)
    case network

    /// A 13th close person: «Рядом» holds 12.
    var tooManyClose: Bool {
        if case .status(409, "too many close") = self { return true }
        return false
    }

    var status: Int {
        if case .status(let code, _) = self { return code }
        return 0
    }

    var errorDescription: String? {
        if case .network = self { return tr("Нет связи, проверь интернет") }
        if case .status(400, "that is your own invite") = self { return tr("Это твоя собственная ссылка") }
        if case .status(400, "not an invite code") = self { return tr("Не похоже на ссылку-приглашение") }
        if case .status(400, "too many contacts") = self { return tr("В списке уже 200 человек") }
        if tooManyClose { return tr("Рядом уже 12 человек: сначала убери кого-нибудь.") }
        switch status {
        case 401: return tr("Сервер не принял вход, попробуй чуть позже")
        case 404: return tr("Не нашли")
        case 409: return tr("Уже есть в списке")
        case 429: return tr("Слишком много попыток, попробуй через час")
        default: return tr("Сервер не ответил, попробуй ещё раз")
        }
    }
}

/// needed-server's REST API (server repo, docs/schema.md), as the Mac app
/// calls it, with a Firebase ID token.
@MainActor
final class API {
    private let auth: Auth

    init(auth: Auth) {
        self.auth = auth
    }

    func me() async throws -> Me {
        try decode(Me.self, try await request("GET", "v1/me"))
    }

    func contacts() async throws -> [Contact] {
        struct List: Codable { let contacts: [Contact] }
        return try decode(List.self, try await request("GET", "v1/contacts")).contacts
    }

    /// Answers the same whether or not the code belongs to anyone.
    func addContact(code: String, label: String, close: Bool, color: Int) async throws -> Contact {
        try decode(Contact.self, try await request("POST", "v1/contacts", body: ["code": code, "label": label, "close": close, "color": color]))
    }

    func updateContact(_ id: String, label: String? = nil, position: Int? = nil, close: Bool? = nil, color: Int? = nil) async throws {
        var body: [String: Any] = [:]
        if let label { body["label"] = label }
        if let position { body["position"] = position }
        if let close { body["close"] = close }
        if let color { body["color"] = color }
        _ = try await request("PATCH", "v1/contacts/\(id)", body: body)
    }

    func deleteContact(_ id: String) async throws {
        _ = try await request("DELETE", "v1/contacts/\(id)")
    }

    func signal(_ contactID: String) async throws {
        _ = try await request("POST", "v1/events", body: ["type": "signal", "to": ["contact": contactID]])
    }

    /// 202 even with nobody online to take it; 429 if one already went this hour.
    func signalAnyone() async throws {
        _ = try await request("POST", "v1/events", body: ["type": "signal", "to": ["anyone": true]])
    }

    func devices() async throws -> [Device] {
        struct List: Codable { let devices: [Device] }
        return try decode(List.self, try await request("GET", "v1/devices")).devices
    }

    /// The token comes back only here, once.
    func addDevice(name: String, capabilities: [String]) async throws -> (Device, String) {
        struct Created: Codable { let device: Device; let token: String }
        let body: [String: Any] = ["name": name, "kind": "custom", "capabilities": capabilities]
        let created = try decode(Created.self, try await request("POST", "v1/devices", body: body))
        return (created.device, created.token)
    }

    func deleteDevice(_ id: String) async throws {
        _ = try await request("DELETE", "v1/devices/\(id)")
    }

    /// The card for six digits a device shows; 404 for a wrong or old code.
    func findPairing(_ code: String) async throws -> PairingCard {
        try decode(PairingCard.self, try await request("POST", "v1/pairing/find", body: ["code": code]))
    }

    /// The device joins this account; its token goes to the device, not here.
    func confirmPairing(_ code: String) async throws {
        _ = try await request("POST", "v1/pairing/confirm", body: ["code": code])
    }

    func deleteMe() async throws {
        _ = try await request("DELETE", "v1/me")
    }

    private func request(_ method: String, _ path: String, body: [String: Any]? = nil) async throws -> Data {
        for attempt in 0..<2 {
            var req = URLRequest(url: Config.apiBase.appendingPathComponent(path))
            req.httpMethod = method
            let token = try await auth.token(forceRefresh: attempt > 0)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue(Config.client, forHTTPHeaderField: "X-Client")
            if let body {
                req.httpBody = try JSONSerialization.data(withJSONObject: body)
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
            let data: Data
            let resp: URLResponse
            do {
                (data, resp) = try await URLSession.shared.data(for: req)
            } catch {
                throw APIError.network
            }
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            // Once more with a fresh token. Refused again, it stays a 401 and
            // the session is kept: Firebase has just renewed it, so the fault
            // is on the server's side, and signing out would not mend it.
            if status == 401 && attempt == 0 {
                continue
            }
            guard (200..<300).contains(status) else {
                let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                throw APIError.status(status, json?["error"] as? String ?? "")
            }
            return data
        }
        throw APIError.status(401, "unauthorized")
    }

    private func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        try JSONDecoder().decode(type, from: data)
    }
}
