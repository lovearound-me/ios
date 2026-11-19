import Foundation

/// Screens for screenshots and UI tests: `--demo <name>` fills the app with
/// made-up people and never touches the network. scripts/screenshots.sh
/// walks them all.
struct Demo {
    let name: String

    static let names = ["signin", "home", "sent", "anyone", "empty", "signal", "paused", "offHere",
                        "book", "contact", "add", "choose", "toys", "board", "pair", "device", "deviceWho",
                        "deviceDoes", "deviceBoard", "settings", "settingsAccount", "settingsWho", "notifyLook"]

    static func fromArguments() -> Demo? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "--demo"), i + 1 < args.count else { return nil }
        return Demo(name: args[i + 1])
    }

    /// A sheet's screen, shown on its own.
    enum Page {
        case contact, add, choose, board, pair
    }

    var page: Page? {
        switch name {
        case "contact": return .contact
        case "add": return .add
        case "choose": return .choose
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
               last_seen_at: ISO8601DateFormatter().string(from: Date().addingTimeInterval(-300)),
               requested_capabilities: ["receive", "send"]),
        Device(id: "d2", kind: "lamp", name: "Котик на полке", capabilities: ["receive"],
               last_seen_at: ISO8601DateFormatter().string(from: Date().addingTimeInterval(-7200)),
               requested_capabilities: ["receive"], accept_anyone: true,
               quiet_hours: QuietHours(from: "23:00", to: "08:00", tz: TimeZone.current.identifier)),
        Device(id: "d3", kind: "custom", name: "Кнопка на столе", capabilities: ["send"], last_seen_at: nil),
    ]

    @MainActor
    func apply(to model: AppModel) {
        let people = Demo.contacts
        switch name {
        case "signin":
            model.demoSet(signedIn: false, contacts: [])
        case "sent":
            // The glow starts a moment late, so the screenshot at 3 s catches
            // the emoji halfway up.
            model.demoSet(signedIn: true, contacts: people)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_600_000_000)
                model.send(people[1])
            }
        case "anyone":
            model.demoSet(signedIn: true, contacts: people)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_600_000_000)
                model.sendToAnyone()
            }
        case "empty":
            model.demoSet(signedIn: true, contacts: [])
        case "paused":
            model.demoSet(signedIn: true, contacts: people, pausedUntil: .distantFuture)
        case "offHere":
            model.demoSet(signedIn: true, contacts: people, receiveHere: false)
        case "signal":
            model.demoSet(signedIn: true, contacts: people)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 400_000_000)
                model.showSignal()
            }
        case "book", "contact", "add", "choose":
            model.demoSet(signedIn: true, contacts: people, tab: .book)
        case "toys", "board", "pair":
            model.demoSet(signedIn: true, contacts: people, devices: Demo.devices, tab: .toys)
        case "device", "deviceWho", "deviceDoes":
            model.demoSet(signedIn: true, contacts: people, devices: Demo.devices, tab: .toys)
            model.toysPath = ["d2"] + (name == "deviceWho" ? [DeviceCard.who("d2")] : name == "deviceDoes" ? [DeviceCard.does("d2")] : [])
        case "deviceBoard":
            model.demoSet(signedIn: true, contacts: people, devices: Demo.devices, tab: .toys)
            model.toysPath = ["d3"]
        case "settings", "settingsAccount", "settingsWho", "notifyLook":
            let quiet = name == "settingsWho" ? QuietHours(from: "23:00", to: "08:00", tz: TimeZone.current.identifier) : nil
            model.demoSet(signedIn: true, contacts: people, tab: .settings, quietHours: quiet)
            model.notifyLook = .many
            model.notifyWords = false
            model.settingsPath = name == "settingsWho" ? [.who] : name == "notifyLook" ? [.look]
                : name == "settingsAccount" ? [.account] : []
        default:
            model.demoSet(signedIn: true, contacts: people)
        }
    }
}
