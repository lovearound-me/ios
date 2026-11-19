import Foundation

/// Screens for screenshots: `--demo <name>` fills the app with made-up people
/// and never touches the network. scripts/screenshots.sh walks them all.
struct Demo {
    let name: String

    static let names = ["signin", "exists", "code", "expired", "computer", "connected",
                        "circles", "sent", "anyone", "empty", "signal", "notification", "settings", "glow", "delete"]

    /// A made-up name: the Russian one in Russian, the English one elsewhere.
    static func said(_ russian: String, _ english: String) -> String {
        Strings.lang == "ru" ? russian : english
    }

    static func fromArguments() -> Demo? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "--demo"), i + 1 < args.count else { return nil }
        return Demo(name: args[i + 1])
    }

    /// A screen reached by navigation, shown on its own.
    enum Page {
        case computer, settings, glow, notification, delete
    }

    var page: Page? {
        switch name {
        case "computer": return .computer
        case "settings": return .settings
        case "glow": return .glow
        case "notification": return .notification
        case "delete": return .delete
        default: return nil
        }
    }

    static let session = Session(token: "demo", email: "anna@example.com")

    static let code = API.PairingCode(code: "482913", secret: "",
                                      url: "https://lovearound.me/login/devices#482913",
                                      expires_in: 600, poll_every: 3)

    static let contacts: [Contact] = [
        Contact(id: "1", label: Demo.said("Мама", "Mom"), position: 0, close: true, color: 1),
        Contact(id: "2", label: Demo.said("Аня", "Anna"), position: 1, close: true, color: 2),
        Contact(id: "3", label: Demo.said("Оля", "Olivia"), position: 2, close: true, color: 3),
        Contact(id: "4", label: Demo.said("Лёша", "Alex"), position: 3, close: true, color: 5),
        Contact(id: "5", label: Demo.said("Петя", "Peter"), position: 4, close: true, color: 4),
        Contact(id: "6", label: Demo.said("Ваня", "John"), position: 5, close: false, color: 10),
        Contact(id: "7", label: Demo.said("Дима", "Dan"), position: 6, close: false, color: 6),
        Contact(id: "8", label: Demo.said("Света", "Lucy"), position: 7, close: false, color: 8),
    ]

    @MainActor
    func apply(to model: AppModel) {
        let people = Demo.contacts
        switch name {
        case "signin":
            model.demoSet(session: nil, contacts: [], screen: .signIn)
        case "exists":
            model.demoSet(session: nil, contacts: [], screen: .emailExists)
        case "code", "computer":
            model.demoSet(session: nil, contacts: [], pairing: Demo.code, screen: .code)
        case "expired":
            model.demoSet(session: nil, contacts: [], pairing: Demo.code, expired: true, screen: .code)
        case "connected":
            model.demoSet(session: Demo.session, contacts: people, screen: .connected)
        case "sent":
            model.demoSet(session: Demo.session, contacts: people, justSent: "2",
                          caption: tr("{name} — улетело ♥", ["name": Demo.said("Аня", "Anna")]), screen: .main)
        case "anyone":
            model.demoSet(session: Demo.session, contacts: people, justSent: AppModel.anyoneID,
                          caption: tr("Кому-нибудь на свете — улетело ✨"), screen: .main)
        case "empty":
            model.demoSet(session: Demo.session, contacts: [], screen: .main)
        case "signal":
            model.demoSet(session: Demo.session, contacts: people, screen: .main)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 400_000_000)
                model.showSignal()
            }
        default:
            model.demoSet(session: Demo.session, contacts: people, screen: .main)
        }
    }
}
