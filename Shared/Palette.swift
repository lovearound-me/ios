import SwiftUI

/// The twelve warm colors of every lovearound app, in the same order: a
/// contact's `color` is an index here. Colors may repeat between contacts:
/// they are labels, a signal never says who sent it.
enum Palette {
    struct Entry {
        let name: String
        let color: UInt32
    }

    static let all: [Entry] = [
        Entry(name: tr("Коралловый"), color: 0xF07A62),
        Entry(name: tr("Розовый"), color: 0xE86A9A),
        Entry(name: tr("Голубой"), color: 0x4E9BD8),
        Entry(name: tr("Шалфей"), color: 0x6FAE7C),
        Entry(name: tr("Лавандовый"), color: 0x9B83DD),
        Entry(name: tr("Медовый"), color: 0xE5A93B),
        Entry(name: tr("Бирюзовый"), color: 0x3FB3A8),
        // Appended, not merged in: indices are what the server stores.
        Entry(name: tr("Вишнёвый"), color: 0xC94A5E),
        Entry(name: tr("Карамельный"), color: 0xC98B5E),
        Entry(name: tr("Оливковый"), color: 0x9DA24A),
        Entry(name: tr("Индиго"), color: 0x6474D6),
        Entry(name: tr("Грифельный"), color: 0x7E8C99),
    ]

    static func color(_ index: Int?) -> Color {
        Color(hex: all[((index ?? 0) % all.count + all.count) % all.count].color)
    }

    /// «Кому-нибудь на свете»: a star, not a person's color.
    static let star = Color(hex: 0xE8B54F)
    /// Links and accents on black.
    static let link = Color(hex: 0xF28C9B)
    /// Quiet text on black.
    static let muted = Color(hex: 0xC7B0A2)
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}
