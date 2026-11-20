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

/// Siri and Shortcuts: «Love Around, сердечко Маме». The names come from the
/// widgets' copy of the book (WidgetData), refreshed with it.
///
/// Most phrases start with the app's name: a phrase starting with «Send…»
/// went to Messages on a real iPhone ("Send a heart with Love Around" became
/// an SMS reading "heart with Love Around"). Without a person, Siri asks
/// «Кому?» inside our intent.
struct LoveAroundShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: SendHeartToPersonIntent(),
                    phrases: [
                        "\(.applicationName) send a heart to \(\.$person)",
                        "\(.applicationName) heart \(\.$person)",
                        "\(.applicationName) send a heart",
                        "\(.applicationName) heart",
                        "Heart \(\.$person) with \(.applicationName)",
                        "Heart \(\.$person) in \(.applicationName)",
                        "Think of \(\.$person) with \(.applicationName)",
                        "Send a heart to \(\.$person) with \(.applicationName)",
                    ],
                    shortTitle: "Send a heart",
                    systemImageName: "heart.fill")
        AppShortcut(intent: SendAnyoneIntent(),
                    phrases: [
                        "\(.applicationName) someone in the world",
                        "\(.applicationName) send a heart to someone in the world",
                        "Heart someone in the world with \(.applicationName)",
                        "Send a heart to someone in the world with \(.applicationName)",
                    ],
                    shortTitle: "Someone in the world",
                    systemImageName: "sparkles")
    }
}
