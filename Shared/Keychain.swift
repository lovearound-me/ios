import Foundation
import Security

/// Sign-in secrets, kept in the Keychain of this device only: they never
/// leave it except to the server (and to Firebase, for the iPhone's session).
/// They are in the app group's part of the Keychain, so the widgets, the
/// Control Center buttons and Siri can send a heart too.
enum Keychain {
    private static let service = "me.lovearound.session"
    private static let group: String? = "group.me.lovearound.ios"

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
        if let group {
            var shared = add
            shared[kSecAttrAccessGroup as String] = group
            if SecItemAdd(shared as CFDictionary, nil) == errSecSuccess { return }
            // A build signed without the app group (a simulator build in CI):
            // the app's own part of the Keychain, as before.
        }
        SecItemAdd(add as CFDictionary, nil)
    }

    /// An item from before the app group (1.0 and earlier) moves into it, so
    /// the widgets find it. Reading finds it in either place.
    static func share(_ account: String) {
        guard group != nil, let value = read(account) else { return }
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
        ]
        query[kSecAttrAccessGroup as String] = group
        var out: AnyObject?
        if SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess { return }
        write(account, value)
    }
}
