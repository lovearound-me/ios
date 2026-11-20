import AppIntents
import SwiftUI
import WidgetKit

/// Home screen: «Один человек» (small) and «Близкие» (medium, large), whose
/// bubbles send a heart without opening the app. iOS 18: Control Center buttons (also for the lock screen and the Action
/// button). Nothing here says who sent a heart, when, or how many.
@main
struct LoveAroundWidgets: WidgetBundle {
    var body: some Widget {
        PersonWidget()
        CloseWidget()
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
    /// The medium one's four: 0 is the first.
    var page = 0
}

/// The book now, then as the ♥ of a just-tapped bubble goes out and the
/// medium one goes back to its first four.
private func bookTimeline() -> Timeline<BookEntry> {
    let now = Date()
    let people = WidgetData.people
    let sent = WidgetData.justSent(now: now)
    let page = WidgetData.page(now: now)
    let changes = Set([sent?.until, page.until].compactMap { $0 }).sorted()
    let entries = ([now] + changes).map { date in
        BookEntry(date: date, people: people,
                  sent: WidgetData.justSent(now: date)?.id,
                  page: WidgetData.page(now: date).index)
    }
    return Timeline(entries: entries, policy: .never)
}

/// «›» on the medium «Близкие»: the next four close people.
struct NextPageIntent: AppIntent {
    static var title: LocalizedStringResource = "Next people"
    static var isDiscoverable = false

    init() {}

    func perform() async throws -> some IntentResult {
        WidgetData.nextPage()
        return .result()
    }
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
        Button(intent: SendHeartIntent(contactID: person.id, name: person.label)) {
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

    @Parameter(title: "Person", optionsProvider: PersonOptions())
    var personID: String?

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
            list.first { $0.id == configuration.personID } ?? list.first
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

    /// Four in a row; with more than four close people, «›» and dots above
    /// them show the next four.
    @ViewBuilder
    private func row(_ people: [WidgetData.Person]) -> some View {
        if let paged = WidgetData.pagedPeople(people) {
            let pages = WidgetData.pageCount(people)
            let page = min(entry.page, pages - 1)
            let four = Array(paged.dropFirst(page * WidgetData.pageSize).prefix(WidgetData.pageSize))
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    Text(tr("Близкие"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(WidgetColors.muted)
                    Spacer()
                    HStack(spacing: 4) {
                        ForEach(0..<pages, id: \.self) { i in
                            Circle()
                                .fill(i == page ? WidgetColors.ink : WidgetColors.muted.opacity(0.4))
                                .frame(width: 5, height: 5)
                        }
                    }
                    .accessibilityHidden(true)
                    Button(intent: NextPageIntent()) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(WidgetColors.ink)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(WidgetColors.muted.opacity(0.18)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tr("Следующие"))
                }
                bubbles(four, size: 50, keepPlaces: true)
            }
        } else {
            bubbles(Array(people.prefix(WidgetData.pageSize)), size: 56)
        }
    }

    private func bubbles(_ people: [WidgetData.Person], size: CGFloat, keepPlaces: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(people) { person in
                Bubble(person: person, size: size, sent: entry.sent == person.id)
                    .frame(maxWidth: .infinity)
            }
            // A last page of one or two keeps the bubbles where they were.
            if keepPlaces {
                ForEach(people.count..<WidgetData.pageSize, id: \.self) { _ in
                    Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                }
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

// MARK: Control Center, the lock screen's buttons, the Action button

@available(iOS 18.0, *)
struct PickPersonControlIntent: ControlConfigurationIntent {
    static var title: LocalizedStringResource = "Pick a person"

    @Parameter(title: "Person", optionsProvider: PersonOptions())
    var personID: String?

    init() {}
}

@available(iOS 18.0, *)
struct PersonControl: ControlWidget {
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
