import Foundation

/// The app's text, keyed by the Russian, as in the Mac app: i18n/<lang>.json
/// maps the Russian to the language's own. A missing line falls back to
/// English, then to the Russian itself.
///
///     tr("Кто-то думает о тебе")
///     tr("{name} — улетело ♥", ["name": "Аня"])
enum Strings {
    /// The site's languages, in its order.
    static let languages = ["en", "es", "pt", "de", "fr", "it", "pl", "tr", "uk", "ru", "id", "ko", "zh"]

    static let lang: String = {
        for preferred in Locale.preferredLanguages {
            let code = String(preferred.prefix(2))
            if languages.contains(code) { return code }
        }
        return "en"
    }()

    private static let table = load(lang)
    private static let english = lang == "en" || lang == "ru" ? [:] : load("en")

    private static func load(_ lang: String) -> [String: String] {
        guard lang != "ru",
              let url = Bundle.main.url(forResource: lang, withExtension: "json", subdirectory: "i18n"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return json.compactMapValues { $0 as? String }
    }

    static func get(_ key: String) -> String {
        table[key] ?? english[key] ?? key
    }
}

func tr(_ key: String, _ values: [String: String] = [:]) -> String {
    var text = Strings.get(key)
    for (name, value) in values {
        text = text.replacingOccurrences(of: "{\(name)}", with: value)
    }
    return text
}
