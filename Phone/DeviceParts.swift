import SwiftUI

// Device protocol v1 (server repo, docs/schema.md, "What a device is made
// of"): a device says what it is made of, its parts; each kind of part has
// standard settings, and the card draws a row per part. Unknown kinds and
// settings are skipped, so a newer firmware works with an older app.

/// Any JSON: a setting's value is a number, a string, a switch, or an object
/// (a button's target, a night light).
enum JSONValue: Codable, Equatable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() {
            self = .null
        } else if let it = try? value.decode(Bool.self) {
            self = .bool(it)
        } else if let it = try? value.decode(Int.self) {
            self = .int(it)
        } else if let it = try? value.decode(Double.self) {
            self = .double(it)
        } else if let it = try? value.decode(String.self) {
            self = .string(it)
        } else if let it = try? value.decode([JSONValue].self) {
            self = .array(it)
        } else {
            self = .object(try value.decode([String: JSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .null: try value.encodeNil()
        case .bool(let it): try value.encode(it)
        case .int(let it): try value.encode(it)
        case .double(let it): try value.encode(it)
        case .string(let it): try value.encode(it)
        case .array(let it): try value.encode(it)
        case .object(let it): try value.encode(it)
        }
    }

    /// From JSONSerialization's reading.
    init(any: Any) {
        switch any {
        case let it as NSNumber:
            if CFGetTypeID(it) == CFBooleanGetTypeID() {
                self = .bool(it.boolValue)
            } else if let whole = Int(exactly: it) {
                self = .int(whole)
            } else {
                self = .double(it.doubleValue)
            }
        case let it as String: self = .string(it)
        case let it as [Any]: self = .array(it.map(JSONValue.init(any:)))
        case let it as [String: Any]: self = .object(it.mapValues(JSONValue.init(any:)))
        default: self = .null
        }
    }

    /// For JSONSerialization.
    var any: Any {
        switch self {
        case .null: return NSNull()
        case .bool(let it): return it
        case .int(let it): return it
        case .double(let it): return it
        case .string(let it): return it
        case .array(let it): return it.map(\.any)
        case .object(let it): return it.mapValues(\.any)
        }
    }

    var bool: Bool? {
        if case .bool(let it) = self { return it }
        return nil
    }

    var int: Int? {
        switch self {
        case .int(let it): return it
        case .double(let it): return Int(it.rounded())
        default: return nil
        }
    }

    var string: String? {
        if case .string(let it) = self { return it }
        return nil
    }

    subscript(key: String) -> JSONValue? {
        if case .object(let it) = self { return it[key] }
        return nil
    }
}

/// A device's values: by part id, then by setting.
typealias PartValues = [String: [String: JSONValue]]

/// Whom a device's own list of people shows: everyone, the close ones, or
/// the ones picked. Only a filter of what it sees.
enum DeviceBook: Codable, Equatable {
    case all
    case close
    case chosen([String])

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if let ids = try? value.decode([String].self) {
            self = .chosen(ids)
        } else {
            self = (try? value.decode(String.self)) == "close" ? .close : .all
        }
    }

    func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .all: try value.encode("all")
        case .close: try value.encode("close")
        case .chosen(let ids): try value.encode(ids)
        }
    }

    var body: Any {
        switch self {
        case .all: return "all"
        case .close: return "close"
        case .chosen(let ids): return ids
        }
    }
}

/// One part of a device: a ring of LEDs, a buzzer, a button.
struct DevicePart: Codable, Equatable, Identifiable {
    /// Unique in the device; the kind itself when the firmware gave none.
    var id: String
    var kind: String
    /// The settings this part really has, of its kind's.
    var settings: [String] = []
    /// The device's own lists for `effect` and `melody`.
    var effects: [String]? = nil
    var melodies: [String]? = nil
    var leds: Int? = nil
}

extension DevicePart {
    private enum Keys: String, CodingKey {
        case id, kind, settings, effects, melodies, leds
    }

    init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: Keys.self)
        kind = try fields.decode(String.self, forKey: .kind)
        id = (try? fields.decode(String.self, forKey: .id)) ?? kind
        settings = (try? fields.decode([String].self, forKey: .settings)) ?? []
        effects = try? fields.decode([String].self, forKey: .effects)
        melodies = try? fields.decode([String].self, forKey: .melodies)
        leds = try? fields.decode(Int.self, forKey: .leds)
    }

    var known: PartKind? { PartKind(rawValue: kind) }

    func has(_ setting: String) -> Bool { settings.contains(setting) }
}

/// What a device is made of, as it said itself.
struct DeviceAbout: Codable, Equatable {
    var proto: Int = 1
    var model: String? = nil
    var firmware: String? = nil
    /// What it asks to do, read once at setup: receive and/or send.
    var wants: [String]? = nil
    var parts: [DevicePart] = []
}

extension DeviceAbout {
    private enum Keys: String, CodingKey {
        case proto, model, firmware, wants, parts
    }

    /// Lenient: a part that doesn't read is skipped, not the whole device.
    init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: Keys.self)
        proto = (try? fields.decode(Int.self, forKey: .proto)) ?? 1
        model = try? fields.decode(String.self, forKey: .model)
        firmware = try? fields.decode(String.self, forKey: .firmware)
        wants = try? fields.decode([String].self, forKey: .wants)
        parts = []
        guard var list = try? fields.nestedUnkeyedContainer(forKey: .parts) else { return }
        while !list.isAtEnd {
            if let part = try? list.decode(DevicePart.self) {
                parts.append(part)
            } else {
                _ = try? list.decode(JSONValue.self)
            }
        }
    }

    /// The parts the card can draw: a kind of the catalog, its id not seen
    /// before.
    var shownParts: [DevicePart] {
        var seen = Set<String>()
        return parts.filter { $0.known != nil && seen.insert($0.id).inserted }
    }

    /// «Свет», or «Свет · ring2» when the device has two lights.
    func title(_ part: DevicePart) -> String {
        guard let kind = part.known else { return part.id }
        let twins = shownParts.filter { $0.kind == part.kind }.count > 1
        return twins ? kind.title + " · " + part.id : kind.title
    }

    /// «heart-ring 2.1.0», or nothing.
    var modelLine: String {
        [model, firmware].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
    }
}

/// The catalog's kinds of parts.
enum PartKind: String, CaseIterable {
    case light, sound, vibration, motion, `switch`, screen, button

    var title: String {
        switch self {
        case .light: return tr("Свет")
        case .sound: return tr("Звук")
        case .vibration: return tr("Вибрация")
        case .motion: return tr("Движение")
        case .switch: return tr("Выключатель")
        case .screen: return tr("Экран")
        case .button: return tr("Кнопка")
        }
    }

    var symbol: String {
        switch self {
        case .light: return "lightbulb.fill"
        case .sound: return "speaker.wave.2.fill"
        case .vibration: return "iphone.radiowaves.left.and.right"
        case .motion: return "figure.wave"
        case .switch: return "powerplug.fill"
        case .screen: return "display"
        case .button: return "button.programmable"
        }
    }

    var tint: Color {
        switch self {
        case .light: return Theme.star
        case .sound: return Theme.indigo
        case .vibration: return Theme.heart
        case .motion: return Theme.ok
        case .switch: return Theme.link
        case .screen: return Theme.muted
        case .button: return Theme.link
        }
    }

    /// Every kind but a button and a screen can be off, listed or not.
    var canBeOff: Bool { self != .button && self != .screen }
}

/// The catalog's names, the platform's defaults, and a part's line on the card.
enum Catalog {
    static let pink = "#E86A9A"

    static func hex(_ index: Int) -> String {
        String(format: "#%06X", Palette.all[index].color)
    }

    /// A `#RRGGBB` as a color; nil for `random` or anything else.
    static func color(_ hex: String?) -> Color? {
        guard let hex, hex.hasPrefix("#"), hex.count == 7, let value = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        return Color(hex: value)
    }

    /// «розовый» for one of the twelve, the hex itself for any other.
    static func colorName(_ hex: String) -> String {
        if hex == "random" { return tr("каждый раз другой") }
        if let i = Palette.all.indices.first(where: { Catalog.hex($0) == hex.uppercased() }) {
            return Palette.all[i].name.localizedLowercase
        }
        return hex
    }

    /// Names from the catalog are translated; a device's own are shown raw.
    static func effect(_ name: String) -> String {
        switch name {
        case "glow": return tr("Вспышка")
        case "pulse": return tr("Пульс")
        case "heartbeat": return tr("Сердцебиение")
        case "breathe": return tr("Дыхание")
        case "wave": return tr("Волна")
        case "fill": return tr("Заливка")
        case "sparkle": return tr("Искры")
        case "rainbow": return tr("Радуга")
        default: return name
        }
    }

    static func melody(_ name: String) -> String {
        switch name {
        case "short": return tr("Короткая")
        case "two_notes": return tr("Две ноты")
        case "heartbeat": return tr("Сердцебиение")
        default: return name
        }
    }

    static func pattern(_ name: String) -> String {
        switch name {
        case "one": return tr("Один раз")
        case "two": return tr("Два раза")
        case "heartbeat": return tr("Сердцебиение")
        default: return name
        }
    }

    static func switchMode(_ name: String) -> String {
        switch name {
        case "on": return tr("Горит")
        case "blink": return tr("Мигает")
        default: return name
        }
    }

    static func idleView(_ name: String) -> String {
        switch name {
        case "clock": return tr("Время")
        case "heart": return tr("Сердечко")
        case "off": return tr("Ничего")
        default: return name
        }
    }

    static func sleepAfter(_ seconds: Int) -> String {
        switch seconds {
        case 0: return tr("Никогда")
        case 10: return tr("10 секунд")
        case 60: return tr("1 минута")
        case 300: return tr("5 минут")
        default: return seconds_(seconds)
        }
    }

    /// «3 с».
    static func seconds_(_ n: Int) -> String {
        tr("{n} с", ["n": String(n)])
    }

    /// The platform's default where the server gave no value (it always
    /// does; this is for a toy's `about` read before the server saw it).
    static func fallback(_ kind: PartKind, _ setting: String, _ part: DevicePart) -> JSONValue {
        switch (kind, setting) {
        case (_, "on"): return .bool(true)
        case (.light, "color"): return .string(pink)
        case (.light, "brightness"), (.screen, "brightness"): return .int(60)
        case (.light, "effect"), (.screen, "effect"): return part.effects?.first.map(JSONValue.string) ?? .null
        case (.light, "speed"), (.motion, "speed"): return .int(50)
        case (.light, "duration"): return .int(3)
        case (.light, "idle"): return .string("off")
        case (.light, "auto_brightness"): return .bool(false)
        case (.sound, "volume"): return .int(50)
        case (.sound, "melody"): return part.melodies?.first.map(JSONValue.string) ?? .null
        case (.vibration, "strength"): return .int(60)
        case (.vibration, "pattern"): return .string("heartbeat")
        case (.motion, "times"): return .int(3)
        case (.switch, "mode"): return .string("on")
        case (.switch, "duration"): return .int(10)
        case (.screen, "sleep_after"): return .int(60)
        case (.screen, "idle_view"): return .string("heart")
        case (.screen, "rotate"): return .int(0)
        case (.screen, "lang"): return .string("en")
        case (.button, "confirm"): return .bool(true)
        default: return .null
        }
    }

    /// The part's line on the card: «розовый · сердцебиение · 60%».
    static func summary(_ part: DevicePart, _ device: Device, contacts: [Contact]) -> String {
        guard let kind = part.known else { return "" }
        func value(_ setting: String) -> JSONValue { device.value(part, setting) }
        if kind.canBeOff, value("on").bool == false { return tr("выключен") }
        var bits: [String] = []
        switch kind {
        case .light:
            if part.has("color"), let color = value("color").string { bits.append(colorName(color)) }
            if part.has("effect"), let effect = value("effect").string { bits.append(Catalog.effect(effect).localizedLowercase) }
            if part.has("brightness"), let level = value("brightness").int { bits.append("\(level)%") }
            if bits.count < 2, part.has("duration"), let seconds = value("duration").int { bits.append(seconds_(seconds)) }
        case .sound:
            if part.has("melody"), let melody = value("melody").string { bits.append(Catalog.melody(melody).localizedLowercase) }
            if part.has("volume"), let level = value("volume").int { bits.append("\(level)%") }
        case .vibration:
            if part.has("pattern"), let pattern = value("pattern").string { bits.append(Catalog.pattern(pattern).localizedLowercase) }
            if part.has("strength"), let level = value("strength").int { bits.append("\(level)%") }
        case .motion:
            if part.has("times"), let times = value("times").int { bits.append("×\(times)") }
            if part.has("speed"), let level = value("speed").int { bits.append("\(level)%") }
        case .switch:
            if part.has("mode"), let mode = value("mode").string { bits.append(switchMode(mode).localizedLowercase) }
            if part.has("duration"), let seconds = value("duration").int { bits.append(seconds_(seconds)) }
        case .screen:
            if part.has("idle_view"), let view = value("idle_view").string { bits.append(idleView(view).localizedLowercase) }
            if part.has("brightness"), let level = value("brightness").int { bits.append("\(level)%") }
        case .button:
            for (gesture, prefix) in [("press", ""), ("long_press", tr("долго: ")), ("double_press", tr("дважды: "))] where part.has(gesture) {
                switch ButtonTarget(value(gesture)) {
                case .anyone: bits.append(prefix + tr("кому-нибудь"))
                case .contact(let id): bits.append(prefix + (contacts.first { $0.id == id }?.label ?? tr("человеку")))
                case .nothing: if gesture == "press" { bits.append(tr("ничего")) }
                }
            }
        }
        return bits.isEmpty ? tr("включён") : bits.joined(separator: " · ")
    }
}

/// What a press of a button does: a signal's `to`, or nothing.
enum ButtonTarget: Equatable {
    case nothing
    case anyone
    case contact(String)

    init(_ value: JSONValue?) {
        if let id = value?["contact"]?.string {
            self = .contact(id)
        } else if value?["anyone"]?.bool == true {
            self = .anyone
        } else {
            self = .nothing
        }
    }

    var json: JSONValue {
        switch self {
        case .nothing: return .null
        case .anyone: return .object(["anyone": .bool(true)])
        case .contact(let id): return .object(["contact": .string(id)])
        }
    }
}

extension Device {
    /// Talks to this phone over Bluetooth and has no Wi-Fi: the phone talks
    /// to the server for it.
    var throughPhone: Bool { link == "phone" }
    /// Set up over Bluetooth: can be set up again, keeping its name and values.
    var bluetoothSetup: Bool { setup == "bluetooth" }

    /// A setting's value: the server's (always complete), else the platform's.
    func value(_ part: DevicePart, _ setting: String) -> JSONValue {
        if let value = values?[part.id]?[setting] { return value }
        guard let kind = part.known else { return .null }
        return Catalog.fallback(kind, setting, part)
    }

    /// What the owner set has reached the device.
    var isApplied: Bool { rev != nil && rev == applied }

    /// The people its own list shows.
    func people(of contacts: [Contact]) -> [Contact] {
        switch book ?? .all {
        case .all: return contacts
        case .close: return contacts.filter(\.isClose)
        case .chosen(let ids): return contacts.filter { ids.contains($0.id) }
        }
    }

    /// The `settings` message, as the server writes it: for a toy this phone
    /// talks for.
    func settingsMessage(now: Date = Date()) -> [String: Any] {
        let zone = tz.flatMap(TimeZone.init(identifier:)) ?? .current
        return ["type": "settings", "rev": rev ?? "", "name": name, "capabilities": capabilities,
                "tz": zone.identifier, "utc_offset": zone.secondsFromGMT(for: now) / 60,
                "now": ISO8601DateFormatter().string(from: now),
                "values": (values ?? [:]).mapValues { $0.mapValues(\.any) }]
    }
}
