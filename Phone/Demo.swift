import Foundation

/// Screens for screenshots and UI tests: `--demo <name>` fills the app with
/// made-up people and never touches the network. scripts/screenshots.sh
/// walks them all.
struct Demo {
    let name: String

    static let names = ["signin", "home", "sent", "anyone", "empty", "signal", "paused",
                        "book", "contact", "add", "toys", "board", "pair", "settings"]

    static func fromArguments() -> Demo? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "--demo"), i + 1 < args.count else { return nil }
        return Demo(name: args[i + 1])
    }

    /// A sheet's screen, shown on its own.
    enum Page {
        case contact, add, board, pair
    }

    var page: Page? {
        switch name {
        case "contact": return .contact
        case "add": return .add
        case "board": return .board
        case "pair": return .pair
        default: return nil
        }
    }

    static let contacts: [Contact] = [
        Contact(id: "1", label: "Мама", position: 0, close: true, color: 1, invite_url: "https://lovearound.me/i/K7MXR-2QHP9"),
        Contact(id: "2", label: "Аня", position: 1, close: true, color: 2, invite_url: "https://lovearound.me/i/B3NWT-8FJD4"),
        Contact(id: "3", label: "Оля", position: 2, close: true, color: 3),
        Contact(id: "4", label: "Лёша", position: 3, close: true, color: 5),
        Contact(id: "5", label: "Петя", position: 4, close: true, color: 4),
        Contact(id: "6", label: "Бабушка", position: 5, close: true, color: 0),
        Contact(id: "7", label: "Ваня", position: 6, close: false, color: 10),
        Contact(id: "8", label: "Дима", position: 7, close: false, color: 6),
        Contact(id: "9", label: "Света", position: 8, close: false, color: 8),
    ]

    static let devices: [Device] = [
        Device(id: "d1", kind: "watch", name: "Apple Watch", capabilities: ["receive", "send"],
               last_seen_at: ISO8601DateFormatter().string(from: Date().addingTimeInterval(-300))),
        Device(id: "d2", kind: "lamp", name: "Котик на полке", capabilities: ["receive"],
               last_seen_at: ISO8601DateFormatter().string(from: Date().addingTimeInterval(-7200))),
        Device(id: "d3", kind: "custom", name: "Кнопка на столе", capabilities: ["send"], last_seen_at: nil),
    ]

    @MainActor
    func apply(to model: AppModel) {
        let people = Demo.contacts
        switch name {
        case "signin":
            model.demoSet(signedIn: false, contacts: [])
        case "sent":
            model.demoSet(signedIn: true, contacts: people, justSent: "2",
                          toast: tr("{name} — улетело ♥", ["name": "Аня"]))
        case "anyone":
            model.demoSet(signedIn: true, contacts: people, justSent: AppModel.anyoneID,
                          toast: tr("Кому-нибудь на свете — улетело ✨"), anyoneSentAt: Date().addingTimeInterval(-60))
        case "empty":
            model.demoSet(signedIn: true, contacts: [])
        case "paused":
            model.demoSet(signedIn: true, contacts: people, tab: .settings, pausedUntil: .distantFuture)
        case "signal":
            model.demoSet(signedIn: true, contacts: people)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 400_000_000)
                model.showSignal()
            }
        case "book", "contact", "add":
            model.demoSet(signedIn: true, contacts: people, tab: .book)
        case "toys", "board", "pair":
            model.demoSet(signedIn: true, contacts: people, devices: Demo.devices, tab: .toys)
        case "settings":
            model.demoSet(signedIn: true, contacts: people, tab: .settings)
        default:
            model.demoSet(signedIn: true, contacts: people)
        }
    }
}
