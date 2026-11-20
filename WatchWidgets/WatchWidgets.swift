import AppIntents
import SwiftUI
import WidgetKit

/// On the watch face: a ♥ in my color, round (A) or in a corner (Б), that
/// opens the app. In the Smart Stack:
/// four close people; a tap opens the app. watchOS 26: Control Center and
/// Action button buttons that send. Never who, when, or how many.
@main
struct LoveAroundWatchWidgets: WidgetBundle {
    var body: some Widget {
        HeartComplication()
        CloseStackWidget()
        if #available(watchOS 26.0, *) {
            WatchPersonControl()
            WatchAnyoneControl()
        }
    }
}

// MARK: ♥ on the watch face

struct HeartEntry: TimelineEntry {
    let date: Date
    let color: Int
}

struct HeartProvider: TimelineProvider {
    func placeholder(in context: Context) -> HeartEntry {
        HeartEntry(date: Date(), color: WidgetData.myColor)
    }

    func getSnapshot(in context: Context, completion: @escaping (HeartEntry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HeartEntry>) -> Void) {
        completion(Timeline(entries: [placeholder(in: context)], policy: .never))
    }
}

/// A ♥ in my color, round (A) or in a corner (Б): a tap opens the app.
struct HeartComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "glow", provider: HeartProvider()) { entry in
            HeartMark(entry: entry)
        }
        .configurationDisplayName("Love Around")
        .description("A heart on the watch face: a tap opens Love Around.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner])
    }
}

struct HeartMark: View {
    let entry: HeartEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let heart = Image(systemName: "heart.fill")
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(Palette.color(entry.color))
            .widgetAccentable()
        Group {
            if family == .accessoryCorner {
                heart
            } else {
                ZStack {
                    AccessoryWidgetBackground()
                    heart
                }
            }
        }
        .containerBackground(Color.clear, for: .widget)
        .accessibilityLabel("Love Around")
    }
}

// MARK: Smart Stack

struct BookEntry: TimelineEntry {
    let date: Date
    let people: [WidgetData.Person]?
}

struct BookProvider: TimelineProvider {
    private static let sample: [WidgetData.Person] = {
        let names = Strings.lang == "ru" ? ["Мама", "Аня", "Оля", "Лёша"] : ["Mom", "Anna", "Olivia", "Alex"]
        let colors = [1, 2, 3, 5]
        return names.indices.map { WidgetData.Person(id: "\($0)", label: names[$0], color: colors[$0], close: true) }
    }()

    func placeholder(in context: Context) -> BookEntry {
        BookEntry(date: Date(), people: Self.sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (BookEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : timeline().entries[0])
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BookEntry>) -> Void) {
        completion(timeline())
    }

    private func timeline() -> Timeline<BookEntry> {
        Timeline(entries: [BookEntry(date: Date(), people: WidgetData.people)], policy: .never)
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
                Image(systemName: "heart.fill")
                    .foregroundStyle(Palette.color(WidgetData.myColor))
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
