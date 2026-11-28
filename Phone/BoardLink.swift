import ESPProvision
import Foundation

/// A Wi-Fi network as the board itself sees it.
struct WifiNetwork: Identifiable, Equatable {
    var ssid: String
    /// dBm, as the board measured it.
    var rssi: Int
    var secured: Bool

    var id: String { ssid }

    /// 1–4, for the bars.
    var bars: Int {
        rssi >= -55 ? 4 : rssi >= -67 ? 3 : rssi >= -78 ? 2 : 1
    }
}

/// Why a setup over Bluetooth stopped, in words for the person.
enum SetupError: LocalizedError {
    case notFound
    case connection
    case about
    case wrongPassword
    case networkNotFound
    case wifi
    case token
    case neverOnline
    case pairing

    var errorDescription: String? {
        switch self {
        case .notFound: return tr("Устройство пропало. Проверь, что оно ещё мигает, и поднеси телефон ближе.")
        case .connection: return tr("Связь по Bluetooth оборвалась. Поднеси телефон ближе и попробуй ещё раз.")
        case .about: return tr("Устройство не рассказало о себе. Похоже, у него старая прошивка.")
        case .wrongPassword: return tr("Пароль не подошёл. Проверь его и попробуй ещё раз.")
        case .networkNotFound: return tr("Устройство не нашло эту сеть. Проверь название: нужна сеть 2,4 ГГц.")
        case .wifi: return tr("Устройство не смогло подключиться к Wi-Fi. Попробуй ещё раз.")
        case .token: return tr("Не получилось передать устройству его ключ. В аккаунте ничего не осталось, попробуй ещё раз.")
        case .neverOnline: return tr("Устройство подключилось к Wi-Fi, но не вышло на связь с сервером. В аккаунте ничего не осталось, попробуй ещё раз.")
        case .pairing: return tr("Не получилось связаться с игрушкой. Проверь, что она в режиме настройки, и согласись на запрос iOS о сопряжении.")
        }
    }
}

/// A board in setup mode, over Bluetooth: Espressif's Wi-Fi provisioning
/// with two endpoints of ours. The order is the server's docs' ("Setup over
/// Bluetooth"): about → confirm → Wi-Fi → the token.
@MainActor
protocol BoardLink: AnyObject {
    func connect() async throws
    /// The board's `about`, from its `lovearound-about` endpoint.
    func about() async throws -> [String: Any]
    /// The networks the board sees: 2.4 GHz only, such boards catch no other.
    func networks() async throws -> [WifiNetwork]
    /// Sends the name and password and waits until the board says it joined.
    func join(ssid: String, password: String) async throws
    /// The device token, to its `lovearound-token` endpoint. Throws `.token`
    /// when the board said no, `.connection` when its answer never came.
    func send(token: String) async throws
    func close()
}

/// What a board in setup mode asks of the phone before it talks (Security
/// 2, SRP). Until boards have codes of their own, every board has this same
/// public pair: it keeps the link encrypted, it does not tell boards apart.
/// Later the password is the board's code, typed or scanned: these two
/// strings are the one place to change then.
enum BoardKey {
    static let username = "lovearound"
    static let password = "lovearound"
}

/// The real one: ESPProvision (github.com/espressif/esp-idf-provisioning-ios),
/// BLE transport, Security 2 with `BoardKey`. The phone and the board agree
/// on a key over the air, so the Wi-Fi password and the token travel
/// encrypted.
@MainActor
final class ESPBoardLink: BoardLink {
    static let namePrefix = "LoveAround-"

    private let name: String
    private var device: ESPDevice?

    init(name: String) {
        self.name = name
    }

    func connect() async throws {
        let found: ESPDevice = try await withCheckedThrowingContinuation { done in
            var answered = false
            ESPProvisionManager.shared.searchESPDevices(devicePrefix: name, transport: .ble, security: .secure2) { devices, _ in
                guard !answered else { return }
                answered = true
                if let device = devices?.first(where: { $0.name == self.name }) ?? devices?.first {
                    done.resume(returning: device)
                } else {
                    done.resume(throwing: SetupError.notFound)
                }
            }
        }
        // Both set here, so the library never asks a delegate for them. It
        // takes the scheme from what the board says of itself, and these
        // serve a Security 1 board as well.
        found.username = BoardKey.username
        found.proofOfPossession = BoardKey.password
        device = found
        try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, Error>) in
            var answered = false
            found.connect(delegate: nil) { status in
                guard !answered else { return }
                answered = true
                if case .connected = status {
                    done.resume()
                } else {
                    done.resume(throwing: SetupError.connection)
                }
            }
        }
    }

    func about() async throws -> [String: Any] {
        let data = try await send(path: "lovearound-about", Data("{}".utf8), failing: .about)
        guard var about = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], about["parts"] != nil else {
            throw SetupError.about
        }
        about["type"] = nil
        return about
    }

    func networks() async throws -> [WifiNetwork] {
        guard let device else { throw SetupError.connection }
        let seen: [ESPWifiNetwork] = await withCheckedContinuation { done in
            device.scanWifiList { list, _ in done.resume(returning: list ?? []) }
        }
        // One row per name, the strongest of its access points.
        var best: [String: WifiNetwork] = [:]
        for network in seen where !network.ssid.isEmpty {
            let row = WifiNetwork(ssid: network.ssid, rssi: Int(network.rssi), secured: network.auth != .open)
            if let old = best[row.ssid], old.rssi >= row.rssi { continue }
            best[row.ssid] = row
        }
        return best.values.sorted { $0.rssi != $1.rssi ? $0.rssi > $1.rssi : $0.ssid < $1.ssid }
    }

    func join(ssid: String, password: String) async throws {
        guard let device else { throw SetupError.connection }
        do {
            try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, Error>) in
                var answered = false
                device.provision(ssid: ssid, passPhrase: password) { status in
                    guard !answered else { return }
                    switch status {
                    case .configApplied:
                        // The board is trying; `success` or `failure` follows.
                        break
                    case .success:
                        answered = true
                        done.resume()
                    case .failure(let error):
                        answered = true
                        switch error {
                        case .wifiStatusAuthenticationError: done.resume(throwing: SetupError.wrongPassword)
                        case .wifiStatusNetworkNotFound: done.resume(throwing: SetupError.networkNotFound)
                        case .sessionError, .configurationError: done.resume(throwing: SetupError.connection)
                        default: done.resume(throwing: SetupError.wifi)
                        }
                    }
                }
            }
        } catch {
            // So the board takes another try in the same session.
            await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
                device.resetWifiStatus { _, _ in done.resume() }
            }
            throw error
        }
    }

    func send(token: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["token": token])
        // A lost answer is not a "no": the board stops Bluetooth as soon as
        // it has the token, so the caller waits for it to come online.
        let answer = try await send(path: "lovearound-token", body, failing: .connection)
        // `{"ok":true}`, or `{"ok":false}` when the board could not keep it.
        if let said = (try? JSONSerialization.jsonObject(with: answer)) as? [String: Any], said["ok"] as? Bool == false {
            throw SetupError.token
        }
    }

    func close() {
        device?.disconnect()
        device = nil
    }

    private func send(path: String, _ body: Data, failing: SetupError) async throws -> Data {
        guard let device else { throw SetupError.connection }
        return try await withCheckedThrowingContinuation { done in
            device.sendData(path: path, data: body) { data, error in
                if let data, error == nil {
                    done.resume(returning: data)
                } else {
                    done.resume(throwing: failing)
                }
            }
        }
    }
}

/// A made-up board for `--demo`: a tester without hardware walks the same
/// screens. «12345678» is the password that fits.
@MainActor
final class DemoBoardLink: BoardLink {
    static let name = "LoveAround-7C3A"
    static let password = "12345678"
    static let about: [String: Any] = [
        "proto": 1, "model": "heart-ring", "firmware": "2.1.0", "wants": ["receive", "send"],
        "parts": [
            ["id": "ring", "kind": "light", "leds": 24,
             "settings": ["on", "color", "brightness", "effect", "speed", "duration", "idle"],
             "effects": ["glow", "heartbeat", "wave", "sparkle", "rainbow"]],
            ["id": "beep", "kind": "sound", "settings": ["on", "volume", "melody"],
             "melodies": ["short", "two_notes", "heartbeat"]],
            ["id": "btn", "kind": "button", "settings": ["press", "long_press", "double_press", "confirm"]],
        ],
    ]

    func connect() async throws {
        try? await Task.sleep(nanoseconds: 700_000_000)
    }

    func about() async throws -> [String: Any] {
        Self.about
    }

    func networks() async throws -> [WifiNetwork] {
        try? await Task.sleep(nanoseconds: 500_000_000)
        return [WifiNetwork(ssid: "Casa-Lisboa", rssi: -48, secured: true),
                WifiNetwork(ssid: "Casa-Lisboa-Guest", rssi: -61, secured: false),
                WifiNetwork(ssid: "MEO-4F2A", rssi: -74, secured: true)]
    }

    func join(ssid: String, password: String) async throws {
        try? await Task.sleep(nanoseconds: 900_000_000)
        if ssid != "Casa-Lisboa-Guest" && password != Self.password { throw SetupError.wrongPassword }
    }

    func send(token: String) async throws {
        try? await Task.sleep(nanoseconds: 400_000_000)
    }

    func close() {}
}
