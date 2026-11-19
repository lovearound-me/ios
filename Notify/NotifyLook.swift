import Foundation

/// How a heart's notification reads (Settings → «Уведомление»). The server
/// sends a bare «♥» and never says who; the iPhone's notification extension
/// (NotificationService) writes the text from this, new emoji each time.
/// Watches and bands show the same text as the iPhone.
enum NotifyLook: String, CaseIterable, Identifiable {
    case many, three, one, plain, words

    var id: String { rawValue }

    /// Shared by the app and its notification extension.
    static let appGroup = "group.me.lovearound.ios"
    private static let key = "notifyLook"

    static var current: NotifyLook {
        get { UserDefaults(suiteName: appGroup)?.string(forKey: key).flatMap(NotifyLook.init(rawValue:)) ?? .many }
        set { UserDefaults(suiteName: appGroup)?.set(newValue.rawValue, forKey: key) }
    }

    var name: String {
        switch self {
        case .many: return tr("Много эмодзи")
        case .three: return tr("Три эмодзи")
        case .one: return tr("Одно сердечко")
        case .plain: return tr("Простое ♥")
        case .words: return tr("Словами")
        }
    }

    /// For the list in Settings: one fixed example each.
    var example: String {
        switch self {
        case .many: return "💗🫶😺🌷🧡🤗🐻✨💕☕️🥰🌼"
        case .three: return "🧡🫶😺"
        case .one: return "💗"
        case .plain: return "♥"
        case .words: return tr("Кто-то думает о тебе")
        }
    }

    var note: String? {
        self == .plain ? tr("Для браслетов, которые не рисуют эмодзи") : nil
    }

    /// The notification's text: twelve emoji, as many as float up in the
    /// app; three; one heart; «♥» from the plain font every band has; words.
    func text() -> String {
        switch self {
        case .many: return Emoji.warm.shuffled().prefix(12).joined()
        case .three: return Emoji.warm.shuffled().prefix(3).joined()
        case .one: return Emoji.hearts.randomElement() ?? "💗"
        case .plain: return "♥"
        case .words: return tr("Кто-то думает о тебе")
        }
    }
}
