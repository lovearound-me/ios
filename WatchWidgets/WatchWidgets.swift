import AppIntents
import SwiftUI
import WidgetKit

/// On the watch face: «О тебе думали», a ♥ that glows in my color for an
/// hour after a heart, round (A) or in a corner (Б). In the Smart Stack:
/// four close people; a tap opens the app. watchOS 26: Control Center and
/// Action button buttons that send. Never who, when, or how many.
@main
struct LoveAroundWatchWidgets: WidgetBundle {
    var body: some Widget {
        GlowComplication()
        CloseStackWidget()
        if #available(watchOS 26.0, *) {
            WatchPersonControl()
            WatchAnyoneControl()
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

struct GlowComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "glow", provider: GlowProvider()) { entry in
            GlowMark(entry: entry)
        }
        .configurationDisplayName("Thought of you")
        .description("The heart glows in your color for an hour after someone thinks of you.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner])
    }
}

struct GlowMark: View {
    let entry: GlowEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let color = Palette.color(entry.color)
        let heart = Image(systemName: entry.glowing ? "heart.fill" : "heart")
            .foregroundStyle(entry.glowing ? color : Color.gray)
            .shadow(color: entry.glowing ? color : .clear, radius: 6)
            .widgetAccentable()
        Group {
            if family == .accessoryCorner {
                heart.font(.system(size: 22, weight: .semibold))
            } else {
                ZStack {
                    AccessoryWidgetBackground()
                    heart.font(.system(size: 22, weight: .semibold))
                }
            }
        }
        .containerBackground(Color.clear, for: .widget)
        .accessibilityLabel(entry.glowing ? tr("Кто-то думает о тебе") : "Love Around")
    }
}

// MARK: Smart Stack

struct BookEntry: TimelineEntry {
    let date: Date
    let people: [WidgetData.Person]?
    let glowing: Bool
}

struct BookProvider: TimelineProvider {
    private static let sample: [WidgetData.Person] = {
        let names = Strings.lang == "ru" ? ["Мама", "Аня", "Оля", "Лёша"] : ["Mom", "Anna", "Olivia", "Alex"]
        let colors = [1, 2, 3, 5]
        return names.indices.map { WidgetData.Person(id: "\($0)", label: names[$0], color: colors[$0], close: true) }
    }()

    func placeholder(in context: Context) -> BookEntry {
        BookEntry(date: Date(), people: Self.sample, glowing: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (BookEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : timeline().entries[0])
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BookEntry>) -> Void) {
        completion(timeline())
    }

    private func timeline() -> Timeline<BookEntry> {
        let now = Date()
        let people = WidgetData.people
        guard let until = WidgetData.glowsUntil(now: now) else {
            return Timeline(entries: [BookEntry(date: now, people: people, glowing: false)], policy: .never)
        }
        return Timeline(entries: [BookEntry(date: now, people: people, glowing: true),
                                  BookEntry(date: until, people: people, glowing: false)],
                        policy: .never)
    }
}

struct CloseStackWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "close", provider: BookProvider()) { entry in
            CloseStackView(entry: entry)
                .containerBackground(Color(white: 0.12), for: .widget)
        }
        .configurationDisplayName("Close people")
        .description("Your close people; a tap opens Love Around.")
        .supportedFamilies([.accessoryRectangular])
    }
}

struct CloseStackView: View {
    let entry: BookEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(verbatim: "Love Around")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Image(systemName: entry.glowing ? "heart.fill" : "heart")
                    .foregroundStyle(entry.glowing ? Palette.color(WidgetData.myColor) : Color.gray)
                    .font(.system(size: 13))
            }
            if let people = entry.people, !people.isEmpty {
                HStack(spacing: 6) {
                    ForEach(people.prefix(4)) { person in
                        VStack(spacing: 1) {
                            ZStack {
                                Circle().fill(Palette.color(person.color).gradient)
                                Text(person.initial)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Color.white)
                            }
                            .frame(width: 30, height: 30)
                            Text(person.label)
                                .font(.system(size: 9))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            } else {
                Text(entry.people == nil ? tr("Войди в Love Around на часах") : tr("Пока никого нет"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: Control Center and the Action button (watchOS 26)

@available(watchOS 26.0, *)
struct PickPersonControlIntent: ControlConfigurationIntent {
    static var title: LocalizedStringResource = "Pick a person"

    @Parameter(title: "Person", optionsProvider: PersonOptions())
    var personID: String?

    init() {}
}

@available(watchOS 26.0, *)
struct WatchPersonControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: "person-control", intent: PickPersonControlIntent.self) { configuration in
            let person = WidgetData.person(configuration.personID)
            ControlWidgetButton(action: SendHeartIntent(contactID: person?.id ?? "", name: person?.label ?? "")) {
                Label(person?.label ?? tr("Отправить сердечко"), systemImage: "heart.fill")
            }
        }
        .displayName("Send a heart")
        .promptsForUserConfiguration()
    }
}

@available(watchOS 26.0, *)
struct WatchAnyoneControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "anyone-control") {
            ControlWidgetButton(action: SendAnyoneIntent()) {
                Label(tr("Кому-нибудь"), systemImage: "sparkles")
            }
        }
        .displayName("Someone in the world")
    }
}
