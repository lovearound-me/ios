import AppIntents
import SwiftUI
import WidgetKit

/// Home screen: «Один человек» (small) and «Близкие» (medium, large), whose
/// bubbles send a heart without opening the app. Lock screen and StandBy:
/// «О тебе думали», a ♥ that glows in my color for an hour after a heart.
/// iOS 18: Control Center buttons (also for the lock screen and the Action
/// button). Nothing here says who sent a heart, when, or how many.
@main
struct LoveAroundWidgets: WidgetBundle {
    var body: some Widget {
        PersonWidget()
        CloseWidget()
        GlowWidget()
        if #available(iOS 18.0, *) {
            PersonControl()
            AnyoneControl()
        }
    }
}

// MARK: The book, as the widgets see it

struct BookEntry: TimelineEntry {
    let date: Date
    /// nil: signed out.
    let people: [WidgetData.Person]?
    /// The bubble showing its ♥ after a tap.
    let sent: String?
}

/// The book with the ♥ of a just-tapped bubble, then without it.
private func bookTimeline() -> Timeline<BookEntry> {
    let now = Date()
    let people = WidgetData.people
    guard let sent = WidgetData.justSent(now: now) else {
        return Timeline(entries: [BookEntry(date: now, people: people, sent: nil)], policy: .never)
    }
    return Timeline(entries: [BookEntry(date: now, people: people, sent: sent.id),
                              BookEntry(date: sent.until, people: people, sent: nil)],
                    policy: .never)
}

/// Made-up people for the widget gallery: Russian names in Russian.
private let sample: [WidgetData.Person] = {
    let ru = Strings.lang == "ru"
    let names = ru ? ["Мама", "Аня", "Оля", "Лёша", "Петя", "Ваня", "Дима", "Света"]
                   : ["Mom", "Anna", "Olivia", "Alex", "Peter", "John", "Dan", "Lucy"]
    let colors = [1, 2, 3, 5, 4, 10, 6, 8]
    return names.indices.map { i in
        WidgetData.Person(id: "\(i + 1)", label: names[i], color: colors[i], close: i < 4)
    }
}()

// MARK: Bubbles

/// A person's bubble, filled with their color, the first letter on it; a ♥
/// for a moment after a tap. A tap sends.
struct Bubble: View {
    let person: WidgetData.Person
    let size: CGFloat
    let sent: Bool
    var named = true

    var body: some View {
        Button(intent: SendHeartIntent(person: PersonEntity(person))) {
            VStack(spacing: 4) {
                ZStack {
                    Circle().fill(Palette.color(person.color).gradient)
                    if sent {
                        Circle().strokeBorder(Color.white, lineWidth: max(2, size * 0.05))
                    }
                    Group {
                        if sent {
                            Image(systemName: "heart.fill")
                        } else {
                            Text(person.initial)
                        }
                    }
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundStyle(Color.white)
                }
                .frame(width: size, height: size)
                if named {
                    Text(person.label)
                        .font(.system(size: max(10, size * 0.22), weight: .medium))
                        .foregroundStyle(WidgetColors.ink)
                        .lineLimit(1)
                        .frame(maxWidth: size * 1.25)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(person.label)
    }
}

/// «Кому-нибудь на свете»: gold, with sparkles.
struct AnyoneBubble: View {
    let size: CGFloat
    let sent: Bool

    var body: some View {
        Button(intent: SendAnyoneIntent()) {
            VStack(spacing: 4) {
                ZStack {
                    Circle().fill(Palette.star.gradient)
                    if sent {
                        Circle().strokeBorder(Color.white, lineWidth: max(2, size * 0.05))
                    }
                    Image(systemName: sent ? "heart.fill" : "sparkles")
                        .font(.system(size: size * 0.38, weight: .semibold))
                        .foregroundStyle(Color.white)
                }
                .frame(width: size, height: size)
                Text(tr("Кому-нибудь"))
                    .font(.system(size: max(10, size * 0.22), weight: .medium))
                    .foregroundStyle(WidgetColors.ink)
                    .lineLimit(1)
                    .frame(maxWidth: size * 1.25)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tr("Кому-нибудь на свете"))
    }
}

enum WidgetColors {
    /// The app's paper and ink (Phone/Theme.swift), light and dark.
    static let paper = Color(light: 0xFFFBF6, dark: 0x2A211D)
    static let ink = Color(light: 0x3B2A23, dark: 0xF3E6DC)
    static let muted = Color(light: 0x6E554A, dark: 0xC7B0A2)
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(UIColor { $0.userInterfaceStyle == .dark ? UIColor(Color(hex: dark)) : UIColor(Color(hex: light)) })
    }
}

/// Signed out, or nobody in the book yet.
struct EmptyBookView: View {
    let signedOut: Bool

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "heart.fill")
                .font(.system(size: 28))
                .foregroundStyle(Palette.color(WidgetData.myColor))
            Text(signedOut ? tr("Войди в Love Around на этом iPhone") : tr("Пока никого нет"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(WidgetColors.ink)
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: «Один человек»

struct PickPersonIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Pick a person"

    @Parameter(title: "Person")
    var person: PersonEntity?

    init() {}
}

struct PersonEntry: TimelineEntry {
    let date: Date
    let person: WidgetData.Person?
    let signedOut: Bool
    let sent: Bool
}

struct PersonProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> PersonEntry {
        PersonEntry(date: Date(), person: sample[0], signedOut: false, sent: false)
    }

    func snapshot(for configuration: PickPersonIntent, in context: Context) async -> PersonEntry {
        context.isPreview ? placeholder(in: context) : entries(for: configuration)[0]
    }

    func timeline(for configuration: PickPersonIntent, in context: Context) async -> Timeline<PersonEntry> {
        let list = entries(for: configuration)
        return Timeline(entries: list, policy: .never)
    }

    /// The chosen person, or the first close one; their ♥ for a moment after a tap.
    private func entries(for configuration: PickPersonIntent) -> [PersonEntry] {
        let now = Date()
        let people = WidgetData.people
        let person = people.flatMap { list in
            list.first { $0.id == configuration.person?.id } ?? list.first
        }
        let entry = { (date: Date, sent: Bool) in
            PersonEntry(date: date, person: person, signedOut: people == nil, sent: sent)
        }
        if let person, let sent = WidgetData.justSent(now: now), sent.id == person.id {
            return [entry(now, true), entry(sent.until, false)]
        }
        return [entry(now, false)]
    }
}

struct PersonWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "person", intent: PickPersonIntent.self, provider: PersonProvider()) { entry in
            Group {
                if let person = entry.person {
                    Bubble(person: person, size: 78, sent: entry.sent)
                } else {
                    EmptyBookView(signedOut: entry.signedOut)
                }
            }
            .containerBackground(WidgetColors.paper, for: .widget)
        }
        .configurationDisplayName("One person")
        .description("A big bubble: a tap sends them a heart.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: «Близкие»

struct BookProvider: TimelineProvider {
    func placeholder(in context: Context) -> BookEntry {
        BookEntry(date: Date(), people: sample, sent: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (BookEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : bookTimeline().entries[0])
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BookEntry>) -> Void) {
        completion(bookTimeline())
    }
}

struct CloseWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "close", provider: BookProvider()) { entry in
            CloseView(entry: entry)
                .containerBackground(WidgetColors.paper, for: .widget)
        }
        .configurationDisplayName("Close people")
        .description("Bubbles of your close people: a tap sends a heart.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct CloseView: View {
    let entry: BookEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let people = entry.people, !people.isEmpty {
            if family == .systemLarge {
                hive(people)
            } else {
                row(people)
            }
        } else {
            EmptyBookView(signedOut: entry.people == nil)
        }
    }

    /// Four in a row.
    private func row(_ people: [WidgetData.Person]) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(people.prefix(4)) { person in
                Bubble(person: person, size: 56, sent: entry.sent == person.id)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    enum Slot {
        case anyone
        case person(WidgetData.Person)
    }

    /// Соты: rows of 3, 4 and 2, «Кому-нибудь» in the middle of the first.
    private func hive(_ people: [WidgetData.Person]) -> some View {
        var slots = people.prefix(8).map(Slot.person)
        slots.insert(.anyone, at: min(1, slots.count))
        let rows = [Array(slots.prefix(3)), Array(slots.dropFirst(3).prefix(4)), Array(slots.dropFirst(7))]
            .filter { !$0.isEmpty }
        return VStack(spacing: 10) {
            Text(tr("О ком думаешь?"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(WidgetColors.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: 14) {
                    ForEach(rows[r].indices, id: \.self) { i in
                        switch rows[r][i] {
                        case .person(let person):
                            Bubble(person: person, size: 56, sent: entry.sent == person.id)
                        case .anyone:
                            AnyoneBubble(size: 56, sent: entry.sent == WidgetData.anyoneID)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: «О тебе думали»

struct GlowEntry: TimelineEntry {
    let date: Date
    let glowing: Bool
    let color: Int
}

struct GlowProvider: TimelineProvider {
    func placeholder(in context: Context) -> GlowEntry {
        GlowEntry(date: Date(), glowing: true, color: WidgetData.myColor)
    }

    func getSnapshot(in context: Context, completion: @escaping (GlowEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : timeline().entries[0])
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GlowEntry>) -> Void) {
        completion(timeline())
    }

    /// Glowing until an hour after the last heart, then not.
    private func timeline() -> Timeline<GlowEntry> {
        let now = Date()
        let color = WidgetData.myColor
        guard let until = WidgetData.glowsUntil(now: now) else {
            return Timeline(entries: [GlowEntry(date: now, glowing: false, color: color)], policy: .never)
        }
        return Timeline(entries: [GlowEntry(date: now, glowing: true, color: color),
                                  GlowEntry(date: until, glowing: false, color: color)],
                        policy: .never)
    }
}

struct GlowWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "glow", provider: GlowProvider()) { entry in
            GlowView(entry: entry)
        }
        .configurationDisplayName("Thought of you")
        .description("The heart glows in your color for an hour after someone thinks of you.")
        .supportedFamilies([.accessoryCircular, .systemSmall])
        // The small one is for StandBy, not the home screen.
        .disfavoredLocations([.homeScreen], for: [.systemSmall])
    }
}

struct GlowView: View {
    let entry: GlowEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let color = Palette.color(entry.color)
        Group {
            if family == .accessoryCircular {
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: entry.glowing ? "heart.fill" : "heart")
                        .font(.system(size: 24, weight: .semibold))
                        .widgetAccentable()
                }
            } else {
                Image(systemName: "heart.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(entry.glowing ? color : color.opacity(0.25))
                    .shadow(color: entry.glowing ? color : .clear, radius: 18)
                    .shadow(color: entry.glowing ? color.opacity(0.6) : .clear, radius: 36)
            }
        }
        .containerBackground(for: .widget) {
            if family == .accessoryCircular {
                Color.clear
            } else {
                RadialGradient(colors: [entry.glowing ? color.opacity(0.35) : .black, .black],
                               center: .center, startRadius: 4, endRadius: 120)
            }
        }
        .accessibilityLabel(entry.glowing ? tr("Кто-то думает о тебе") : "Love Around")
    }
}

// MARK: Control Center, the lock screen's buttons, the Action button

@available(iOS 18.0, *)
struct PickPersonControlIntent: ControlConfigurationIntent {
    static var title: LocalizedStringResource = "Pick a person"

    @Parameter(title: "Person")
    var person: PersonEntity?

    init() {}
}

@available(iOS 18.0, *)
struct PersonControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: "person-control", intent: PickPersonControlIntent.self) { configuration in
            ControlWidgetButton(action: SendHeartIntent(person: configuration.person ?? PersonEntity(id: "", name: ""))) {
                Label(configuration.person?.name ?? tr("Отправить сердечко"), systemImage: "heart.fill")
            }
        }
        .displayName("Send a heart")
        .promptsForUserConfiguration()
    }
}

@available(iOS 18.0, *)
struct AnyoneControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "anyone-control") {
            ControlWidgetButton(action: SendAnyoneIntent()) {
                Label(tr("Кому-нибудь"), systemImage: "sparkles")
            }
        }
        .displayName("Someone in the world")
    }
}
