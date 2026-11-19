import AppIntents
import Foundation

/// A person of the book, as widgets, Control Center buttons and Siri name
/// them: the label the owner gave, nothing else.
struct PersonEntity: AppEntity, Identifiable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Person"
    static var defaultQuery = PersonQuery()

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    init(_ person: WidgetData.Person) {
        self.init(id: person.id, name: person.label)
    }
}

struct PersonQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [PersonEntity] {
        (WidgetData.people ?? []).filter { identifiers.contains($0.id) }.map(PersonEntity.init)
    }

    func entities(matching string: String) async throws -> [PersonEntity] {
        (WidgetData.people ?? [])
            .filter { $0.label.localizedCaseInsensitiveContains(string) }
            .map(PersonEntity.init)
    }

    /// Close people first, as in the app.
    func suggestedEntities() async throws -> [PersonEntity] {
        (WidgetData.people ?? []).map(PersonEntity.init)
    }
}

/// A heart to one person, from a widget's bubble, a button or Siri. The
/// app doesn't open.
struct SendHeartIntent: AppIntent {
    static var title: LocalizedStringResource = "Send a heart"
    static var description = IntentDescription("Someone in your book learns that someone is thinking of them. Never who.")
    static var openAppWhenRun = false

    @Parameter(title: "Person")
    var person: PersonEntity

    init() {}

    init(person: PersonEntity) {
        self.person = person
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await HeartSender.send(to: person.id)
        WidgetData.sent(person.id)
        return .result(dialog: IntentDialog(stringLiteral: tr("{name} — улетело ♥", ["name": person.name])))
    }
}

/// «Кому-нибудь на свете»: one random person who takes them, once an hour.
struct SendAnyoneIntent: AppIntent {
    static var title: LocalizedStringResource = "Send a heart to someone in the world"
    static var description = IntentDescription("One random person who takes them, once an hour.")
    static var openAppWhenRun = false

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await HeartSender.sendAnyone()
        WidgetData.sent(WidgetData.anyoneID)
        return .result(dialog: IntentDialog(stringLiteral: tr("Кому-нибудь на свете — улетело ✨")))
    }
}
