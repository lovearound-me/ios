import SwiftUI
import WatchKit

/// «Вид»: how the people are laid out on the main screen. Stays on this watch.
enum WatchLayout: String, CaseIterable, Identifiable {
    /// Bubbles packed like the watch's own app screen, smaller at the edges.
    case hive
    /// Circles with the first letter, three in a row.
    case circles
    /// The same circles with the name under each.
    case named
    /// One person per line, the whole name.
    case list

    var id: String { rawValue }

    var name: String {
        switch self {
        case .hive: return tr("Соты")
        case .circles: return tr("Кружочки")
        case .named: return tr("Кружочки с именами")
        case .list: return tr("Список")
        }
    }

    private static let key = "layout"

    static var saved: WatchLayout {
        get { UserDefaults.standard.string(forKey: key).flatMap(WatchLayout.init(rawValue:)) ?? .hive }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }
}

/// The watch's «Вибрация» (TapCount): the taps a heart plays.
enum Taps {
    private static let key = "taps"

    /// Read by the notification's long look too, which runs without the model.
    static var count: Int {
        get { UserDefaults.standard.object(forKey: key) as? Int ?? TapCount.standard }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    /// `count` taps a heartbeat apart, the first after `delay` seconds.
    static func play(_ count: Int, after delay: Double = 0) {
        guard count > 0 else { return }
        for i in 0..<count {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay + Double(i) * TapCount.gap) {
                WKInterfaceDevice.current().play(.start)
            }
        }
    }
}

/// What a bubble, circle or line sends to: «Кому-нибудь на свете» or a person.
enum Target: Identifiable, Equatable {
    case anyone
    case person(Contact)

    var id: String {
        switch self {
        case .anyone: return AppModel.anyoneID
        case .person(let contact): return contact.id
        }
    }

    /// The whole name, as VoiceOver and the held finger say it.
    var label: String {
        switch self {
        case .anyone: return tr("Кому-нибудь на свете")
        case .person(let contact): return contact.label
        }
    }

    /// Under a circle, where there is room for a word or two.
    var short: String {
        switch self {
        case .anyone: return tr("Кому-нибудь")
        case .person(let contact): return contact.label
        }
    }

    var color: Color {
        switch self {
        case .anyone: return Palette.star
        case .person(let contact): return Palette.color(contact.color)
        }
    }

    var initial: String {
        switch self {
        case .anyone: return ""
        case .person(let contact):
            return String(contact.label.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
        }
    }
}
