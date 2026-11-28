import Foundation

/// One of the person's own devices: a watch, a lamp, a board, each with its
/// own token.
struct Device: Codable, Identifiable, Equatable {
    let id: String
    var kind: String?
    var name: String
    var capabilities: [String]
    var last_seen_at: String?
    /// What a device paired by code asked for: the most it may do. None for
    /// a board made in an app, which may do anything and can get a new token.
    var requested_capabilities: [String]? = nil
    /// Whether it takes hearts from anyone in the world; none: as it asks.
    var accept_anyone: Bool? = nil
    var quiet_hours: QuietHours? = nil
    // Device protocol v1 (DeviceParts.swift). How it joined: app | code | bluetooth.
    var setup: String? = nil
    /// "phone": a Bluetooth-only toy this phone talks for; else the server does.
    var link: String? = nil
    var tz: String? = nil
    var book: DeviceBook? = nil
    /// A socket of it is open now; none for a toy the phone talks for.
    var online: Bool? = nil
    var about: DeviceAbout? = nil
    /// What the owner wants, as a revision, and the last one the device applied.
    var rev: String? = nil
    var values: PartValues? = nil
    var applied: String? = nil
    var battery: Int? = nil

    var receives: Bool { capabilities.contains("receive") }
    var sends: Bool { capabilities.contains("send") }
    var paired: Bool { requested_capabilities != nil }

    /// Whether `capability` may be switched on: anything for a board, only
    /// what it asked for for a paired device.
    func may(_ capability: String) -> Bool {
        requested_capabilities?.contains(capability) ?? true
    }
}

/// A daily window when a device gets no hearts at all, in the time zone of
/// the phone that set it. The server keeps it; nothing is held for later.
struct QuietHours: Codable, Equatable {
    var from: String
    var to: String
    var tz: String
}

extension QuietHours {
    /// Whether `date` falls in the window, in its own time zone, `from`
    /// inclusive: as the server's quiet.rs.
    func contains(_ date: Date) -> Bool {
        guard let from = Self.minutes(from), let to = Self.minutes(to), from != to else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: tz) ?? .current
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let now = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        return from < to ? (from <= now && now < to) : (now >= from || now < to)
    }

    private static func minutes(_ hhmm: String) -> Int? {
        let parts = hhmm.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, (0..<24).contains(parts[0]), (0..<60).contains(parts[1]) else { return nil }
        return parts[0] * 60 + parts[1]
    }
}

/// What changes on a device; nil fields stay as they are.
struct DeviceChange {
    var name: String?
    var capabilities: [String]?
    var acceptAnyone: Bool?
    /// `.some(nil)` turns quiet hours off.
    var quietHours: QuietHours??
    var book: DeviceBook?

    var body: [String: Any] {
        var body: [String: Any] = [:]
        if let book { body["book"] = book.body }
        if let name { body["name"] = name }
        if let capabilities { body["capabilities"] = capabilities }
        if let acceptAnyone { body["accept_anyone"] = acceptAnyone }
        if let quietHours {
            if let hours = quietHours {
                body["quiet_hours"] = ["from": hours.from, "to": hours.to, "tz": hours.tz]
            } else {
                body["quiet_hours"] = NSNull()
            }
        }
        return body
    }

    func applied(to device: Device) -> Device {
        var device = device
        if let name { device.name = name }
        if let capabilities { device.capabilities = capabilities }
        if let acceptAnyone { device.accept_anyone = acceptAnyone }
        if let quietHours { device.quiet_hours = quietHours }
        if let book { device.book = book }
        return device
    }
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

    /// The server's `code`, for programs: "offline", "too_many", "no_about".
    var code: String {
        if case .status(_, let text) = self { return text }
        return ""
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

    /// A board set up over Bluetooth, once it has joined Wi-Fi: its token
    /// goes to it over Bluetooth and is never shown.
    func addBluetoothBoard(name: String, capabilities: [String]) async throws -> (Device, String) {
        struct Created: Codable { let device: Device; let token: String }
        let body: [String: Any] = ["name": name, "setup": "bluetooth", "capabilities": capabilities,
                                   "tz": TimeZone.current.identifier]
        let created = try decode(Created.self, try await request("POST", "v1/devices", body: body))
        return (created.device, created.token)
    }

    /// A Bluetooth-only toy: no token, this phone talks to the server for it.
    func addToy(name: String, capabilities: [String]) async throws -> Device {
        struct Created: Codable { let device: Device }
        let body: [String: Any] = ["name": name, "setup": "bluetooth", "link": "phone", "capabilities": capabilities,
                                   "tz": TimeZone.current.identifier]
        return try decode(Created.self, try await request("POST", "v1/devices", body: body)).device
    }

    /// Merged into what was set before; `null` is back to the default. The
    /// device as it is after. At most 10 a minute per device (429 too_many).
    func setDeviceValues(_ id: String, _ values: PartValues) async throws -> Device {
        let body: [String: Any] = ["values": values.mapValues { $0.mapValues(\.any) }]
        return try decode(Device.self, try await request("PATCH", "v1/devices/\(id)/settings", body: body))
    }

    /// «Проверить»: a heart on that one device, as it is set now. 409
    /// "offline" without an open socket of it.
    func previewDevice(_ id: String) async throws {
        _ = try await request("POST", "v1/devices/\(id)/preview")
    }

    /// For a toy this phone talks for: what it is made of → its `settings`
    /// message, to write to it.
    func putToyAbout(_ id: String, about: [String: Any]) async throws -> [String: Any] {
        let data = try await request("PUT", "v1/devices/\(id)/about", body: about)
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    /// For the same toy: the revision it applied, its battery.
    func postToyState(_ id: String, rev: String?, battery: Int?) async throws {
        var body: [String: Any] = [:]
        if let rev { body["rev"] = rev }
        if let battery { body["battery"] = battery }
        guard !body.isEmpty else { return }
        _ = try await request("POST", "v1/devices/\(id)/state", body: body)
    }

    /// A toy's button: the target is a signal's `to`, pasted as it is.
    func signal(to target: Any) async throws {
        _ = try await request("POST", "v1/events", body: ["type": "signal", "to": target])
    }

    func deleteDevice(_ id: String) async throws {
        _ = try await request("DELETE", "v1/devices/\(id)")
    }

    /// The device as it is after the change.
    func updateDevice(_ id: String, _ change: DeviceChange) async throws -> Device {
        try decode(Device.self, try await request("PATCH", "v1/devices/\(id)", body: change.body))
    }

    /// A board's new token, shown only now; the old one stops working at once.
    func newDeviceToken(_ id: String) async throws -> String {
        struct Issued: Codable { let token: String }
        return try decode(Issued.self, try await request("POST", "v1/devices/\(id)/token")).token
    }

    /// The card for six digits a device shows; 404 for a wrong or old code.
    func findPairing(_ code: String) async throws -> PairingCard {
        try decode(PairingCard.self, try await request("POST", "v1/pairing/find", body: ["code": code]))
    }

    /// The device joins this account; its token goes to the device, not here.
    func confirmPairing(_ code: String) async throws {
        _ = try await request("POST", "v1/pairing/confirm", body: ["code": code])
    }

    /// Where this iPhone's notifications go, and when not (docs/schema.md,
    /// /v1/push). The token is Apple's address of the app on this iPhone.
    func putPush(token: String, sandbox: Bool, anyone: Bool, pausedUntil: Date?, quietHours: QuietHours?) async throws {
        var body: [String: Any] = ["token": token, "sandbox": sandbox, "anyone": anyone]
        body["paused_until"] = pausedUntil.map { ISO8601DateFormatter().string(from: $0) } ?? NSNull()
        body["quiet_hours"] = quietHours.map { ["from": $0.from, "to": $0.to, "tz": $0.tz] } ?? NSNull()
        _ = try await request("PUT", "v1/push", body: body)
    }

    /// This iPhone takes no more notifications for the account.
    func deletePush(token: String) async throws {
        _ = try await request("DELETE", "v1/push", body: ["token": token])
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
                // `error` is for people and may change; the texts matched in
                // APIError are the old ones, kept. `code` is for programs.
                let known = ["offline", "no_about", "phone_link", "server_link", "too_many", "bad_value", "no_send"]
                if let code = json?["code"] as? String, known.contains(code) {
                    throw APIError.status(status, code)
                }
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
