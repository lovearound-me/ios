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
            .filter { Self.sounds($0.label, like: string) }
            .map(PersonEntity.init)
    }

    /// Whether a name Siri heard is this person's: in Latin letters on both
    /// sides (English Siri hears «Вадим» as "Vadim"), and with another ending
    /// (Russian Siri hears «Вадиму», «Маме»).
    static func sounds(_ label: String, like said: String) -> Bool {
        let a = plain(label), b = plain(said)
        guard !a.isEmpty, !b.isEmpty else { return false }
        if a.contains(b) || b.contains(a) { return true }
        let shorter = min(a.count, b.count)
        guard shorter >= 3 else { return false }
        return a.prefix(shorter - 1) == b.prefix(shorter - 1)
    }

    private static func plain(_ text: String) -> String {
        let latin = text.applyingTransform(.toLatin, reverse: false) ?? text
        let bare = latin.applyingTransform(.stripDiacritics, reverse: false) ?? latin
        return bare.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    /// Close people first, as in the app.
    func suggestedEntities() async throws -> [PersonEntity] {
        (WidgetData.people ?? []).map(PersonEntity.init)
    }
}

/// A heart to one person, from a widget's bubble or a button. The app
/// doesn't open. Plain strings, not a PersonEntity: a widget's button
/// couldn't hand an entity to the extension ("PersonEntity is not a
/// registered AppEntity identifier", and nothing was sent). Siri has its
/// own intent with the entity (Phone/Shortcuts.swift).
struct SendHeartIntent: AppIntent {
    static var title: LocalizedStringResource = "Send a heart"
    static var description = IntentDescription("Someone in your book learns that someone is thinking of them. Never who.")
    static var openAppWhenRun = false
    static var isDiscoverable = false

    @Parameter(title: "Person")
    var contactID: String

    @Parameter(title: "Name")
    var name: String

    init() {}

    init(contactID: String, name: String) {
        self.contactID = contactID
        self.name = name
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        // A button whose person was removed from the book: nothing to send.
        guard !contactID.isEmpty else { throw HeartSender.Failure.refused }
        try await HeartSender.send(to: contactID)
        WidgetData.sent(contactID)
        return .result(dialog: IntentDialog(stringLiteral: tr("{name} — улетело ♥", ["name": name])))
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

/// The person picker of a widget's or a button's settings: the contact id
/// as a plain string, with the name as its title. A PersonEntity there was
/// listed but never came back to the extension ("PersonEntity is not a
/// registered AppEntity identifier"): the button got no one and the server
/// answered 400.
struct PersonOptions: DynamicOptionsProvider {
    func results() async throws -> ItemCollection<String> {
        let people = WidgetData.people ?? []
        return ItemCollection(sections: [
            ItemSection(items: people.map { IntentItem($0.id, title: "\($0.label)") }),
        ])
    }
}

extension WidgetData {
    /// The person a picker chose, if they are still in the book.
    static func person(_ id: String?) -> Person? {
        guard let id else { return nil }
        return people?.first { $0.id == id }
    }
}
