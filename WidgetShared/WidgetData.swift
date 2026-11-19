import Foundation
import WidgetKit

/// What the widgets draw, kept by the app in the app group: the people (for
/// the bubbles), my color, when a heart last came here (the ♥ glows for an
/// hour) and what a widget just sent. All of it stays on this device; the
/// time of a heart is never shown, only "recently", and nothing is counted.
enum WidgetData {
    static let group = "group.me.lovearound.ios"
    /// How long the ♥ glows after a heart.
    static let glowFor: TimeInterval = 3600
    /// How long a bubble shows its ♥ after a tap.
    static let sentFor: TimeInterval = 2
    /// «Кому-нибудь на свете» in `sent`.
    static let anyoneID = "anyone"

    struct Person: Codable, Hashable, Identifiable {
        let id: String
        let label: String
        let color: Int?
        let close: Bool

        var initial: String {
            label.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "♥"
        }
    }

    private static var defaults: UserDefaults? { UserDefaults(suiteName: group) }

    /// Close people first, each group in the owner's order; nil: signed out.
    static var people: [Person]? {
        guard let data = defaults?.data(forKey: "widgetPeople") else { return nil }
        return try? JSONDecoder().decode([Person].self, from: data)
    }

    static func save(people: [Person]?) {
        defaults?.set(people.flatMap { try? JSONEncoder().encode($0) }, forKey: "widgetPeople")
        reload()
    }

    /// The color the screen glows in for me (Settings → «Как светится»).
    static var myColor: Int {
        get { defaults?.object(forKey: "widgetMyColor") as? Int ?? 1 }
        set {
            guard newValue != myColor else { return }
            defaults?.set(newValue, forKey: "widgetMyColor")
            reload()
        }
    }

    /// A heart came here just now: the ♥ glows until an hour from now.
    static func heartCame(at date: Date = Date()) {
        defaults?.set(date, forKey: "widgetLastHeart")
        reload()
    }

    /// Until when the ♥ glows, if it does.
    static func glowsUntil(now: Date = Date()) -> Date? {
        guard let last = defaults?.object(forKey: "widgetLastHeart") as? Date else { return nil }
        let until = last.addingTimeInterval(glowFor)
        return until > now ? until : nil
    }

    /// A widget's bubble sent to `id`: it shows a ♥ for a moment.
    static func sent(_ id: String, at date: Date = Date()) {
        defaults?.set(["id": id, "at": date.timeIntervalSince1970], forKey: "widgetSent")
        reload()
    }

    /// The bubble showing its ♥ now, and until when.
    static func justSent(now: Date = Date()) -> (id: String, until: Date)? {
        guard let dict = defaults?.dictionary(forKey: "widgetSent"),
              let id = dict["id"] as? String, let at = dict["at"] as? Double else { return nil }
        let until = Date(timeIntervalSince1970: at).addingTimeInterval(sentFor)
        return until > now ? (id, until) : nil
    }

    /// Signed out: the widgets forget everyone.
    static func clear() {
        for key in ["widgetPeople", "widgetLastHeart", "widgetSent"] { defaults?.removeObject(forKey: key) }
        reload()
    }

    static func reload() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}
