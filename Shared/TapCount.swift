import Foundation

/// «Вибрация»: how many times a heart taps the wrist or the hand, 0 to 5;
/// three unless changed, «тук-тук-тук», like a heartbeat.
enum TapCount {
    static let range = 0...5
    static let standard = 3
    /// Between two taps, in seconds.
    static let gap = 0.4

    /// «тук-тук-тук», or «Без вибрации» for none.
    static func words(_ count: Int) -> String {
        count <= 0 ? tr("Без вибрации") : Array(repeating: tr("тук"), count: count).joined(separator: "-")
    }
}
