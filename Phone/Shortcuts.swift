import AppIntents

/// Siri's «Отправь сердечко Маме»: the person as an entity, so Siri can
/// match the name and ask «Кому?». Runs in the app's process.
struct SendHeartToPersonIntent: AppIntent {
    static var title: LocalizedStringResource = "Send a heart"
    static var description = IntentDescription("Someone in your book learns that someone is thinking of them. Never who.")
    static var openAppWhenRun = false

    @Parameter(title: "Person")
    var person: PersonEntity

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await HeartSender.send(to: person.id)
        WidgetData.sent(person.id)
        return .result(dialog: IntentDialog(stringLiteral: tr("{name} — улетело ♥", ["name": person.name])))
    }
}

/// Siri and Shortcuts: «Отправь сердечко Маме в Love Around». The names come
/// from the widgets' copy of the book (WidgetData), refreshed with it.
struct LoveAroundShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: SendHeartToPersonIntent(),
                    phrases: [
                        "Send a heart to \(\.$person) with \(.applicationName)",
                        "Send a heart with \(.applicationName)",
                    ],
                    shortTitle: "Send a heart",
                    systemImageName: "heart.fill")
        AppShortcut(intent: SendAnyoneIntent(),
                    phrases: ["Send a heart to someone in the world with \(.applicationName)"],
                    shortTitle: "Someone in the world",
                    systemImageName: "sparkles")
    }
}
