import Foundation

/// How a heart's notification reads (Settings → «Уведомление»): emoji, and
/// words after them if «Со словами» is on. The server
/// sends a bare «♥» and never says who; the iPhone's notification extension
/// (NotificationService) writes the text from this, new emoji each time.
/// Watches and bands show the same text as the iPhone.
enum NotifyLook: String, CaseIterable, Identifiable {
    case many, three, one, plain

    var id: String { rawValue }

    /// Shared by the app and its notification extension.
    static let appGroup = "group.me.lovearound.ios"
    private static let key = "notifyLook"
    private static let wordsKey = "notifyWords"
    private static let tapsKey = "taps"

    static var current: NotifyLook {
        get { UserDefaults(suiteName: appGroup)?.string(forKey: key).flatMap(NotifyLook.init(rawValue:)) ?? .many }
        set { UserDefaults(suiteName: appGroup)?.set(newValue.rawValue, forKey: key) }
    }

    /// «Со словами»: «Кто-то думает о тебе» after the emoji.
    static var withWords: Bool {
        get { UserDefaults(suiteName: appGroup)?.bool(forKey: wordsKey) ?? false }
        set { UserDefaults(suiteName: appGroup)?.set(newValue, forKey: wordsKey) }
    }

    /// «Вибрация»: taps when a heart comes while the app is open, 0 to 5
    /// (three unless changed). At 0 the notification comes without a sound,
    /// so iOS doesn't vibrate either.
    static var taps: Int {
        get { UserDefaults(suiteName: appGroup)?.object(forKey: tapsKey) as? Int ?? 3 }
        set { UserDefaults(suiteName: appGroup)?.set(newValue, forKey: tapsKey) }
    }

    static var words: String { tr("Кто-то думает о тебе") }

    var name: String {
        switch self {
        case .many: return tr("Волна сердечек")
        case .three: return tr("Три сердечка")
        case .one: return tr("Одно сердечко")
        case .plain: return tr("Простое ♥")
        }
    }

    /// For the list in Settings: one fixed example each.
    var example: String {
        switch self {
        case .many: return "✨💗💖💞💖💗✨"
        case .three: return "💕💖💕"
        case .one: return "💗"
        case .plain: return "♥"
        }
    }

    var note: String? {
        self == .plain ? tr("Для браслетов, которые не рисуют эмодзи") : nil
    }

    /// The notification's text: the wave; three hearts; one heart; «♥» from
    /// the plain font every band has. Then the words, if asked.
    func text(words: Bool) -> String {
        let emoji: String
        switch self {
        case .many: emoji = Emoji.wave()
        case .three: emoji = Emoji.three()
        case .one: emoji = Emoji.hearts.randomElement() ?? "💗"
        case .plain: emoji = "♥"
        }
        return words ? emoji + " " + Self.words : emoji
    }
}
