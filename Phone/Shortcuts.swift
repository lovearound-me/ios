import AppIntents

/// Siri and Shortcuts: «Отправь сердечко Маме в Love Around». The names come
/// from the widgets' copy of the book (WidgetData), refreshed with it.
struct LoveAroundShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: SendHeartIntent(),
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
