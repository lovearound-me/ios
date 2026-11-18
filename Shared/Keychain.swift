import Foundation
import Security

/// The device token and the account's email, kept in the Keychain of this
/// device only: they never leave it except to the server.
enum Keychain {
    private static let service = "me.lovearound.session"

    static func read(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// nil deletes.
    static func write(_ account: String, _ value: String?) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        guard let value else { return }
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }
}

/// Who this device is signed in as: a device token (`dev_…`) made for it,
/// which «Устройства» → «Убрать» in the web app cuts off on its own.
struct Session: Equatable {
    var token: String
    /// The account's email, to show where the watch is signed in.
    var email: String?

    static func load() -> Session? {
        guard let token = Keychain.read("token") else { return nil }
        return Session(token: token, email: Keychain.read("email"))
    }

    func save() {
        Keychain.write("token", token)
        Keychain.write("email", email)
    }

    static func clear() {
        Keychain.write("token", nil)
        Keychain.write("email", nil)
    }
}
