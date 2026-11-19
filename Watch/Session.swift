import Foundation

/// Who this device is signed in as: a device token (`dev_…`) made for it,
/// which «Устройства» → «Убрать» in the web app cuts off on its own.
struct Session: Equatable {
    var token: String
    /// The account's email, to show where the watch is signed in.
    var email: String?

    static func load() -> Session? {
        guard let token = Keychain.read("token") else { return nil }
        // From before the app group: where the watch's widgets find it.
        Keychain.share("token")
        Keychain.share("email")
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
