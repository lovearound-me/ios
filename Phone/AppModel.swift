import AuthenticationServices
import SwiftUI
import UIKit

/// What the iPhone shows and does: the account, the book, the devices,
/// signals out and in. The logic is the Mac app's (mac/Sources/Needed/AppModel.swift).
@MainActor
final class AppModel: ObservableObject {
    enum Tab: Hashable {
        case hearts, book, toys, settings
    }

    enum PauseLength {
        case hour, untilMorning, untilResumed
    }

    /// The add sheet, opened by «+» or by a lovearound://add link.
    struct Adding: Identifiable {
        let id = UUID()
        var invite: String
    }

    /// The pairing sheet, opened by «Подключить по коду» or by the QR on a
    /// watch or a lamp (lovearound.me/login/devices#482913), digits filled in.
    struct Pairing: Identifiable {
        let id = UUID()
        var code: String
    }

    /// A line over the tab bar for a moment: what failed, or «Скопировано».
    struct Toast: Equatable {
        let text: String
        var failed = false
    }

    /// A signal just went: the app's edges glow in the person's color and
    /// emoji float up, as on the Mac. Stars for «Кому-нибудь на свете».
    struct Outgoing: Equatable {
        let id = UUID()
        let color: Color
        let stars: Bool
        let seed: Int
        /// For VoiceOver and the tests: «Аня — улетело ♥».
        let text: String
    }

    /// The circle for «Кому-нибудь на свете» in `justSent`.
    static let anyoneID = "anyone"
    /// «Рядом» holds 12 at most: the server refuses a 13th.
    static let maxClose = 12

    let auth = Auth()
    let api: API
    let stream: Stream
    let demo: Demo?

    @Published private(set) var signedIn = false
    @Published private(set) var email: String?
    @Published private(set) var provider: String?
    @Published private(set) var inviteURL: String? { didSet { keepForNextStart() } }
    @Published private(set) var contacts: [Contact] = [] { didSet { keepForNextStart() } }
    @Published private(set) var loaded = false
    @Published private(set) var devices: [Device] = [] { didSet { keepForNextStart() } }
    @Published private(set) var devicesLoaded = false
    @Published private(set) var devicesProblem: String?
    /// The device cards open in «Игрушки», by id (a demo opens one itself).
    @Published var toysPath: [String] = []
    /// The pages open in «Настройки».
    @Published var settingsPath: [SettingsPage] = []

    @Published var tab: Tab = .hearts
    @Published var adding: Adding?
    @Published var pairing: Pairing?
    /// «＋» among the circles: who of the book goes into «Рядом».
    @Published var choosingClose = false
    /// «Новый человек по ссылке» in that sheet: the add sheet comes once it closes.
    var addByLinkNext = false
    @Published private(set) var toast: Toast?
    @Published private(set) var outgoing: Outgoing?
    /// The circle that just sent, filled for a moment.
    @Published private(set) var justSent: String?
    /// Why the sign-in failed, under its buttons.
    @Published var signInProblem: String?
    @Published var busy = false
    /// The site's sign-in page is open in Safari and has not answered yet.
    @Published var waitingForBrowser = false
    /// The server has been out of reach for a few seconds: signals don't come.
    @Published private(set) var offline = false

    // An incoming signal
    @Published private(set) var incoming = false
    @Published private(set) var signalSeed = 0

    /// The screen edges glow in it when a signal comes; stays on this phone.
    @Published var myColor: Int { didSet { defaults.set(myColor, forKey: "myColor") } }
    /// Off: this iPhone keeps no stream open, so nothing glows here; the
    /// account's other devices get signals as before. Stays on this phone.
    @Published var receiveHere: Bool {
        didSet {
            defaults.set(receiveHere, forKey: "receiveHere")
            guard demo == nil, signedIn else { return }
            if receiveHere {
                stream.start()
            } else {
                stream.stop()
                goingOffline?.cancel()
                offline = false
            }
            syncPush()
        }
    }
    /// Take signals from «Кому-нибудь на свете» too: the server asks the stream.
    @Published var acceptAnyone: Bool {
        didSet {
            defaults.set(acceptAnyone, forKey: "acceptAnyone")
            stream.anyone = acceptAnyone
            stream.restart()
            syncPush()
        }
    }
    @Published private(set) var anyoneSentAt: Date? { didSet { defaults.set(anyoneSentAt, forKey: "anyoneSentAt") } }
    @Published private(set) var pausedUntil: Date? {
        didSet {
            defaults.set(pausedUntil, forKey: "pausedUntil")
            syncPush()
        }
    }
    /// A daily window when this iPhone neither glows nor notifies, and
    /// nothing comes later. Stays on this phone; the server gets it for the
    /// notifications. Its other devices have their own.
    @Published var quietHours: QuietHours? {
        didSet {
            defaults.set(quietHours.flatMap { try? JSONEncoder().encode($0) }, forKey: "quietHours")
            syncPush()
        }
    }
    /// How a heart's notification reads; the notification extension reads it.
    @Published var notifyLook: NotifyLook { didSet { NotifyLook.current = notifyLook } }
    /// «Со словами»: «Кто-то думает о тебе» after the emoji.
    @Published var notifyWords: Bool { didSet { NotifyLook.withWords = notifyWords } }
    /// When each contact last got a signal from here: the book puts them first.
    private var lastSent: [String: Date] { didSet { defaults.set(lastSent, forKey: "lastSent") } }

    private let defaults = UserDefaults.standard
    private var appleNonce = ""
    private var pendingAdd: String?
    private var pendingPair: String?
    private var toastGeneration = 0
    private var outgoingGeneration = 0
    private var goingOffline: Task<Void, Never>?
    private var saving: Task<Void, Never>?
    private var reorderSave: Task<Void, Never>?
    private var cacheSave: Task<Void, Never>?
    let push = Push.shared
    private var pushSync: Task<Void, Never>?
    /// What the server last took for this iPhone's notifications.
    private var pushSent: [String: String]?

    init() {
        api = API(auth: auth)
        stream = Stream(auth: auth)
        demo = Demo.fromArguments()
        myColor = defaults.object(forKey: "myColor") as? Int ?? 1
        receiveHere = defaults.object(forKey: "receiveHere") as? Bool ?? true
        acceptAnyone = defaults.object(forKey: "acceptAnyone") as? Bool ?? true
        anyoneSentAt = defaults.object(forKey: "anyoneSentAt") as? Date
        pausedUntil = defaults.object(forKey: "pausedUntil") as? Date
        quietHours = (defaults.data(forKey: "quietHours")).flatMap { try? JSONDecoder().decode(QuietHours.self, from: $0) }
        notifyLook = NotifyLook.current
        notifyWords = NotifyLook.withWords
        lastSent = defaults.dictionary(forKey: "lastSent") as? [String: Date] ?? [:]

        stream.anyone = acceptAnyone
        stream.onSignal = { [weak self] in self?.receive() }
        stream.onAuthLost = { [weak self] in self?.signOut() }
        stream.onOnline = { [weak self] up in self?.connectionChanged(up) }
        stream.onSync = { [weak self] in
            Task {
                // Not halfway through saving a new order: that would show it half-applied.
                await self?.saving?.value
                await self?.reload()
            }
        }

        if let demo {
            demo.apply(to: self)
        } else {
            if let session = auth.session {
                signedIn = true
                email = session.email
                drawLastSeen()
            }
            push.onHeart = { [weak self] in self?.receive() }
            push.onToken = { [weak self] in self?.syncPush() }
            push.onTap = { [weak self] in self?.tapped() }
        }
    }

    // MARK: In front and behind

    /// The app came to the front: iOS keeps no socket behind, so connect again.
    func becameActive() {
        guard demo == nil, signedIn else { return }
        if let until = pausedUntil, until <= Date() { pausedUntil = nil }
        if receiveHere { stream.start() }
        Task { await reload() }
        Task { await refreshPush() }
    }

    func wentToBackground() {
        guard demo == nil else { return }
        stream.stop()
        goingOffline?.cancel()
        offline = false
    }

    func reload() async {
        guard demo == nil, signedIn else { return }
        do {
            let me = try await api.me()
            inviteURL = me.invite_url
            contacts = try await api.contacts()
            loaded = true
            keepForNextStart()
            provider = auth.provider
        } catch let error as AuthError where error.endsSession {
            signOut()
        } catch {
            if !loaded { show(tr("Нет связи с сервером. Попробуем ещё раз чуть позже."), failed: true) }
        }
    }

    private func connectionChanged(_ up: Bool) {
        goingOffline?.cancel()
        if up {
            offline = false
        } else {
            goingOffline = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if !Task.isCancelled { offline = true }
            }
        }
    }

    // MARK: Signals out

    func send(_ contact: Contact) {
        lastSent[contact.id] = Date()
        sent(contact.id, Palette.color(contact.color), tr("{name} — улетело ♥", ["name": contact.label])) { api in
            try await api.signal(contact.id)
        }
    }

    /// One random person who takes them, once an hour. The server spends the
    /// hour on the try even with nobody online, so «улетело» is all the
    /// sender ever learns.
    func sendToAnyone() {
        guard anyoneWait() == nil else { return }
        anyoneSentAt = Date()
        sent(Self.anyoneID, Theme.star, tr("Кому-нибудь на свете — улетело ✨")) { api in
            try await api.signalAnyone()
        }
    }

    private func sent(_ id: String, _ color: Color, _ text: String, _ call: @escaping (API) async throws -> Void) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        justSent = id
        glow(Outgoing(color: color, stars: id == Self.anyoneID, seed: Int.random(in: 0..<1000), text: text))
        guard demo == nil else { return }
        Task {
            do {
                try await call(api)
            } catch let error as AuthError where error.endsSession {
                justSent = nil
                signOut()
            } catch APIError.status(429, _) where id == Self.anyoneID {
                // Sent from another device this hour, at a time not known
                // here: wait about an hour from now.
                justSent = nil
                show(tr("Кому-нибудь на свете уже улетело в этот час."))
            } catch {
                justSent = nil
                if id == Self.anyoneID { anyoneSentAt = nil }
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                show(tr("Не улетело, проверь интернет"), failed: true)
            }
        }
    }

    /// Whole minutes until the next signal to anyone, or nil if it can go now.
    func anyoneWait(at now: Date = Date()) -> Int? {
        guard let anyoneSentAt else { return nil }
        let left = anyoneSentAt.addingTimeInterval(3600).timeIntervalSince(now)
        return left > 0 ? Int((left / 60).rounded(.up)) : nil
    }

    /// The glow and the emoji for a signal that went; a new one starts over.
    func glow(_ out: Outgoing) {
        outgoingGeneration += 1
        let generation = outgoingGeneration
        outgoing = out
        UIAccessibility.post(notification: .announcement, argument: out.text)
        Task {
            try? await Task.sleep(nanoseconds: SendGlow.seconds)
            guard generation == outgoingGeneration else { return }
            outgoing = nil
            justSent = nil
        }
    }

    func show(_ text: String, failed: Bool = false) {
        toastGeneration += 1
        let generation = toastGeneration
        toast = Toast(text: text, failed: failed)
        Task {
            try? await Task.sleep(nanoseconds: failed ? 4_000_000_000 : 2_500_000_000)
            guard generation == toastGeneration else { return }
            toast = nil
        }
    }

    // MARK: Signals in

    /// From the stream, or a notification while the app is in front; both
    /// come for one heart, so a second one while it glows is the same heart.
    private func receive() {
        // Not shown, and not kept for later: a signal is about the moment.
        guard receiveHere, !isPaused, !isQuiet, !incoming else { return }
        showSignal()
    }

    /// A heart's notification was tapped: the app opens glowing.
    private func tapped() {
        guard signedIn, !incoming else { return }
        Task {
            // Once the app is on screen, not under the launch.
            try? await Task.sleep(nanoseconds: 400_000_000)
            showSignal()
        }
    }

    /// The glowing edges, the hearts, a tap in the hand.
    func showSignal() {
        signalSeed = Int.random(in: 0..<1000)
        incoming = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        let seed = signalSeed
        Task {
            try? await Task.sleep(nanoseconds: 5_500_000_000)
            if signalSeed == seed { incoming = false }
        }
    }

    func dismissSignal() {
        incoming = false
    }

    // MARK: Pause

    var isPaused: Bool {
        guard let pausedUntil else { return false }
        return pausedUntil > Date()
    }

    var pauseText: String {
        guard let pausedUntil, isPaused else { return "" }
        if pausedUntil == .distantFuture { return tr("Пауза, пока не снимешь") }
        let time = pausedUntil.formatted(date: .omitted, time: .shortened)
        return Calendar.current.isDateInToday(pausedUntil) ? tr("Пауза до {time}", ["time": time]) : tr("Пауза до завтра, {time}", ["time": time])
    }

    func pause(_ length: PauseLength) {
        switch length {
        case .hour:
            pausedUntil = Date().addingTimeInterval(3600)
        case .untilMorning:
            let calendar = Calendar.current
            let today8 = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: Date())!
            pausedUntil = today8 > Date() ? today8 : calendar.date(byAdding: .day, value: 1, to: today8)!
        case .untilResumed:
            pausedUntil = .distantFuture
        }
    }

    func resume() {
        pausedUntil = nil
    }

    var isQuiet: Bool {
        quietHours?.contains(Date()) == true
    }

    // MARK: Notifications

    /// iOS's permission (asked once, right after signing in), then the token.
    func refreshPush() async {
        guard demo == nil, signedIn else { return }
        await push.refresh()
        if push.status == .notDetermined && receiveHere {
            await push.ask()
        }
        syncPush()
    }

    func askForNotifications() async {
        await push.ask()
        syncPush()
    }

    /// Tells the server where and when this iPhone takes notifications, or
    /// that it takes none. After a moment, so a turned wheel sends once.
    func syncPush() {
        guard demo == nil, signedIn, let token = push.token else { return }
        pushSync?.cancel()
        pushSync = Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            let state = pushState(token)
            guard state != pushSent else { return }
            do {
                // A new token (the app reinstalled, a build from the other
                // environment): the old one goes, or it would get the same hearts.
                if let old = defaults.string(forKey: "pushToken"), old != token {
                    try? await api.deletePush(token: old)
                }
                defaults.set(token, forKey: "pushToken")
                if receiveHere {
                    try await api.putPush(token: token, sandbox: Push.sandbox, anyone: acceptAnyone,
                                          pausedUntil: isPaused ? pausedUntil : nil, quietHours: quietHours)
                } else {
                    try await api.deletePush(token: token)
                }
                pushSent = state
            } catch {
                // Tried again when the app next comes to the front.
            }
        }
    }

    private func pushState(_ token: String) -> [String: String] {
        guard receiveHere else { return ["token": token, "off": "1"] }
        return ["token": token, "anyone": acceptAnyone ? "1" : "0",
                "paused": isPaused ? (pausedUntil?.timeIntervalSince1970).map { String($0) } ?? "" : "",
                "quiet": quietHours.map { "\($0.from)-\($0.to)-\($0.tz)" } ?? ""]
    }

    // MARK: The book

    /// The circles, in the order set by hand.
    var closeContacts: [Contact] {
        contacts.filter(\.isClose)
    }

    /// Everyone else, the most recently signalled first, then by name.
    var otherContacts: [Contact] {
        contacts.filter { !$0.isClose }.sorted { a, b in
            let (ta, tb) = (lastSent[a.id] ?? .distantPast, lastSent[b.id] ?? .distantPast)
            return ta != tb ? ta > tb : a.label.localizedStandardCompare(b.label) == .orderedAscending
        }
    }

    /// The home screen's circles: the close ones, or, with nobody close yet,
    /// the first of the book.
    var homeCircles: [Contact] {
        let close = closeContacts
        return close.isEmpty ? Array(otherContacts.prefix(9)) : close
    }

    var closeFull: Bool {
        closeContacts.count >= Self.maxClose
    }

    /// For a new contact, as the server picks: a color nobody in the book has
    /// yet, at random; any one once all are taken.
    var freeColor: Int {
        let used = Set(contacts.compactMap(\.color))
        let free = Palette.all.indices.filter { !used.contains($0) }
        return (free.isEmpty ? Array(Palette.all.indices) : free).randomElement() ?? 0
    }

    func addContact(code: String, label: String, color: Int, close: Bool) async throws {
        if demo != nil {
            contacts.append(Contact(id: UUID().uuidString, label: label, position: contacts.count,
                                    close: close, color: color, invite_url: "https://lovearound.me/i/\(code)"))
            return
        }
        var contact = try await api.addContact(code: code, label: label, close: close, color: color)
        contact.color = contact.color ?? color
        contacts.append(contact)
    }

    func updateContact(_ contact: Contact, label: String, color: Int, close: Bool) async throws {
        let colorChanged = color != (contact.color ?? 0)
        if demo == nil, label != contact.label || close != contact.isClose || colorChanged {
            try await api.updateContact(contact.id,
                                        label: label != contact.label ? label : nil,
                                        close: close != contact.isClose ? close : nil,
                                        color: colorChanged ? color : nil)
        }
        if let index = contacts.firstIndex(where: { $0.id == contact.id }) {
            contacts[index].label = label
            contacts[index].close = close
            contacts[index].color = color
        }
    }

    func remove(_ contact: Contact) async throws {
        if demo == nil {
            try await api.deleteContact(contact.id)
        }
        contacts.removeAll { $0.id == contact.id }
        lastSent[contact.id] = nil
    }

    /// Into «Рядом» or out of it: shown at once, saved behind.
    func setClose(_ contact: Contact, _ close: Bool) {
        guard let index = contacts.firstIndex(where: { $0.id == contact.id }) else { return }
        if close && closeFull {
            show(tr("Рядом уже 12 человек: сначала убери кого-нибудь."), failed: true)
            return
        }
        contacts[index].close = close
        guard demo == nil else { return }
        let previous = saving
        saving = Task {
            await previous?.value
            do {
                try await api.updateContact(contact.id, close: close)
            } catch {
                show((error as? APIError)?.tooManyClose == true ? error.localizedDescription : tr("Не получилось сохранить"), failed: true)
                await reload()
            }
        }
    }

    /// «＋» among the circles. With nobody in the book there is nobody to
    /// pick: the add sheet at once.
    func addToClose() {
        if contacts.isEmpty {
            adding = Adding(invite: "")
        } else {
            choosingClose = true
        }
    }

    /// The «Рядом» picker closed: «Новый человек по ссылке» opens the add sheet.
    func closePickerClosed() {
        guard addByLinkNext else { return }
        addByLinkNext = false
        adding = Adding(invite: "")
    }

    /// A drag among the circles in the book.
    func moveClose(from source: IndexSet, to destination: Int) {
        var close = closeContacts
        close.move(fromOffsets: source, toOffset: destination)
        // The close ones keep their slots in the whole list, in the new order.
        let slots = contacts.indices.filter { contacts[$0].isClose }
        for (slot, person) in zip(slots, close) {
            contacts[slot] = person
        }
        reorderSave?.cancel()
        reorderSave = Task { @MainActor in
            // A moment after the last change, so several moves are one save.
            try? await Task.sleep(nanoseconds: 700_000_000)
            if !Task.isCancelled { savePositions() }
        }
    }

    private func savePositions() {
        let changed = contacts.indices.filter { contacts[$0].position != $0 }
        for index in changed {
            contacts[index].position = index
        }
        let updates = changed.map { (contacts[$0].id, $0) }
        guard !updates.isEmpty, demo == nil else { return }
        let previous = saving
        saving = Task {
            await previous?.value
            do {
                for (id, position) in updates {
                    try await api.updateContact(id, position: position)
                }
            } catch {
                show(tr("Не получилось сохранить порядок"), failed: true)
                await reload()
            }
        }
    }

    /// The code of an invite link (or the bare code), as typed.
    static func inviteID(from text: String) -> String? {
        var text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for marker in ["/i/", "lovearound://add/", "needed://add/"] {
            if let range = text.range(of: marker, options: .backwards) {
                text = String(text[range.upperBound...])
            }
        }
        // The link ends at a space, a new line or a dot after it in a message:
        // "…/i/GSSV7-A33HN.", "…/i/GSSV7-A33HN\nДобавь меня…".
        text = text.components(separatedBy: CharacterSet(charactersIn: "/?#").union(.whitespacesAndNewlines)).first ?? ""
        text = text.trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.symbols))
        // 10 characters of the server's alphabet, dashes anywhere (`GSSV7-A33HN`).
        // The server never says whether a code is taken, so this is the only
        // check a typo gets: no 0, 1, I, L, O or U.
        let alphabet = Set("23456789ABCDEFGHJKMNPQRSTVWXYZ")
        let code = text.uppercased().filter { $0 != "-" }
        guard code.count == 10, code.allSatisfy(alphabet.contains) else { return nil }
        return text
    }

    /// The person's own Love ID, which can't be added to their own book.
    func isOwn(_ code: String) -> Bool {
        let bare = { (code: String) in code.uppercased().filter { $0 != "-" } }
        guard let own = inviteURL.flatMap(Self.inviteID(from:)) else { return false }
        return bare(own) == bare(code)
    }

    var shareText: String {
        tr("Добавь меня по этой ссылке и нажимай сердечко, когда думаешь обо мне ♥") + "\n" + (inviteURL ?? "")
    }

    // MARK: Devices

    func loadDevices() async {
        guard demo == nil else { return }
        do {
            devices = try await api.devices()
            devicesLoaded = true
            keepForNextStart()
            devicesProblem = nil
        } catch let error as AuthError where error.endsSession {
            signOut()
        } catch {
            devicesProblem = tr("Не получилось загрузить устройства")
        }
    }

    /// A board of one's own: its token comes back once, to paste into the firmware.
    func addBoard(name: String, capabilities: [String]) async throws -> String {
        if demo != nil {
            devices.append(Device(id: UUID().uuidString, kind: "custom", name: name, capabilities: capabilities, last_seen_at: nil))
            return "dev_demo_7Hq2kLx9WbN4sP0aZr"
        }
        let (device, token) = try await api.addDevice(name: name, capabilities: capabilities)
        devices.append(device)
        return token
    }

    func removeDevice(_ device: Device) async {
        if demo == nil {
            do {
                try await api.deleteDevice(device.id)
            } catch {
                show(tr("Не получилось отключить, попробуй ещё раз"), failed: true)
                return
            }
        }
        devices.removeAll { $0.id == device.id }
        toysPath.removeAll { $0 == device.id }
    }

    /// Saves a change to a device and shows it as the server now has it;
    /// false if it didn't take (a toast says so).
    @discardableResult
    func changeDevice(_ id: String, _ change: DeviceChange) async -> Bool {
        guard let i = devices.firstIndex(where: { $0.id == id }) else { return false }
        // Shown at once; put back if the server says no.
        let before = devices[i]
        devices[i] = change.applied(to: before)
        if demo != nil {
            return true
        }
        do {
            let updated = try await api.updateDevice(id, change)
            if let j = devices.firstIndex(where: { $0.id == id }) {
                devices[j] = updated
            }
            return true
        } catch let error as AuthError where error.endsSession {
            signOut()
        } catch {
            if let j = devices.firstIndex(where: { $0.id == id }) {
                devices[j] = before
            }
            show(tr("Не получилось сохранить"), failed: true)
        }
        return false
    }

    /// A board's new token, shown once; the old one stops working at once.
    func newDeviceToken(_ device: Device) async throws -> String {
        if demo != nil {
            return "dev_demo_7Hq2kLx9WbN4sP0aZr4mT8vW3cJ6yQ1n"
        }
        return try await api.newDeviceToken(device.id)
    }

    func findPairing(_ code: String) async throws -> PairingCard {
        if demo != nil {
            return PairingCard(name: "Apple Watch", kind: "watch", capabilities: ["receive", "send"])
        }
        return try await api.findPairing(code)
    }

    func confirmPairing(_ code: String) async throws {
        if demo == nil {
            try await api.confirmPairing(code)
        }
        await loadDevices()
    }

    // MARK: Links

    func handle(url: URL) {
        // The QR of a device and a Love ID, as https links (universal links,
        // once lovearound.me says the app may take them).
        if url.scheme == "https", url.host == "lovearound.me" {
            if let code = Self.pairCode(from: url) {
                openPairing(code)
            } else if url.path.contains("/i/"), let invite = Self.inviteID(from: url.absoluteString) {
                openAdding(invite)
            }
            return
        }
        guard url.scheme == Config.urlScheme else { return }
        switch url.host {
        case "pair":
            if let code = Self.pairCode(from: url) { openPairing(code) }
        case "add":
            // The whole link, not url.path: its leading "/" would leave inviteID an empty id.
            guard let invite = Self.inviteID(from: url.absoluteString) else { return }
            openAdding(invite)
        case "signin":
            // Safari can hand the same link over twice; the first one signs in
            // and uses up the state, so a late copy is no news.
            if signedIn && !waitingForBrowser { return }
            Task {
                do {
                    try await auth.completeBrowser(url)
                    didSignIn()
                } catch {
                    if !signedIn { signInProblem = error.localizedDescription }
                }
                waitingForBrowser = false
            }
        default:
            break
        }
    }

    private func openAdding(_ invite: String) {
        guard signedIn else { pendingAdd = invite; return }
        tab = .book
        pairing = nil
        adding = Adding(invite: invite)
    }

    private func openPairing(_ code: String) {
        guard signedIn else { pendingPair = code; return }
        tab = .toys
        adding = nil
        pairing = Pairing(code: code)
    }

    /// The six digits of lovearound.me/login/devices#482913 (the watch's QR)
    /// or lovearound://pair/482913.
    static func pairCode(from url: URL) -> String? {
        let candidate: String?
        if url.scheme == "https" {
            guard url.path.hasPrefix("/login/devices") else { return nil }
            candidate = url.fragment
        } else {
            candidate = url.pathComponents.last
        }
        guard let code = candidate?.filter({ $0 != " " }), code.count == 6, code.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return code
    }

    // MARK: Account

    func prepareApple(_ request: ASAuthorizationAppleIDRequest) {
        appleNonce = AppleSignIn.newNonce()
        request.requestedScopes = [.email]
        request.nonce = AppleSignIn.sha256(appleNonce)
    }

    func appleFinished(_ result: Result<ASAuthorization, Error>) {
        // Cancelled by the person: nothing to say.
        guard case .success(let authorization) = result,
              let identityToken = AppleSignIn.identityToken(authorization) else { return }
        let nonce = appleNonce
        busy = true
        signInProblem = nil
        Task {
            defer { busy = false }
            do {
                let user = try await AppleSignIn.firebase(identityToken: identityToken, rawNonce: nonce)
                try auth.adopt(apple: user)
                didSignIn()
            } catch AppleSignIn.Failure.emailExists {
                signInProblem = tr("С этой почтой уже есть аккаунт. Войди так же, как в прошлый раз.")
            } catch AppleSignIn.Failure.network {
                signInProblem = tr("Нет связи, проверь интернет")
            } catch {
                signInProblem = tr("Не получилось войти. Попробуй ещё раз.")
            }
        }
    }

    /// Google or email: the site's page in Safari, which comes back here.
    func signInInBrowser() {
        signInProblem = nil
        waitingForBrowser = true
        UIApplication.shared.open(auth.browserSignInURL())
    }

    private func didSignIn() {
        signInProblem = nil
        waitingForBrowser = false
        signedIn = true
        email = auth.session?.email
        provider = auth.provider
        tab = .hearts
        if receiveHere { stream.start() }
        Task { await reload() }
        Task { await refreshPush() }
        if let invite = pendingAdd {
            pendingAdd = nil
            openAdding(invite)
        } else if let code = pendingPair {
            pendingPair = nil
            openPairing(code)
        }
    }

    /// «Выйти»: this iPhone stops taking the account's notifications first,
    /// while it still can say so.
    func signOutHere() async {
        if demo == nil, let token = push.token {
            pushSync?.cancel()
            try? await api.deletePush(token: token)
        }
        signOut()
    }

    func signOut() {
        stream.stop()
        pushSync?.cancel()
        pushSent = nil
        cacheSave?.cancel()
        try? FileManager.default.removeItem(at: Self.cacheURL)
        auth.signOut()
        goingOffline?.cancel()
        offline = false
        signedIn = false
        email = nil
        provider = nil
        inviteURL = nil
        contacts = []
        loaded = false
        devices = []
        devicesLoaded = false
        toysPath = []
        adding = nil
        choosingClose = false
        outgoing = nil
        settingsPath = []
        tab = .hearts
    }

    func deleteAccount() async throws {
        if demo == nil {
            try await api.deleteMe()
        }
        lastSent = [:]
        // Not carried over to an account made here next.
        pausedUntil = nil
        anyoneSentAt = nil
        signOut()
    }

    var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    // MARK: What was there last time

    /// The book, the devices and the Love ID as the server last gave them:
    /// drawn at once on the next start, then replaced by the server's, so the
    /// screens don't start empty and fill in. On this iPhone only, and gone
    /// on signing out.
    private struct LastSeen: Codable {
        var invite: String?
        var contacts: [Contact]
        var devices: [Device]?
    }

    private static var cacheURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("last-seen.json")
    }

    private func drawLastSeen() {
        guard let data = try? Data(contentsOf: Self.cacheURL),
              let last = try? JSONDecoder().decode(LastSeen.self, from: data) else { return }
        inviteURL = last.invite
        contacts = last.contacts
        loaded = true
        if let devices = last.devices {
            self.devices = devices
            devicesLoaded = true
        }
    }

    /// After a moment: a new order changes many contacts one by one.
    private func keepForNextStart() {
        guard demo == nil, signedIn, loaded else { return }
        cacheSave?.cancel()
        let last = LastSeen(invite: inviteURL, contacts: contacts, devices: devicesLoaded ? devices : nil)
        cacheSave = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled, let data = try? JSONEncoder().encode(last) else { return }
            let url = Self.cacheURL
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }

    // MARK: Demo

    func demoSet(signedIn: Bool, contacts: [Contact], devices: [Device] = [], tab: Tab = .hearts,
                 justSent: String? = nil, outgoing: Outgoing? = nil, anyoneSentAt: Date? = nil, pausedUntil: Date? = nil,
                 receiveHere: Bool = true, quietHours: QuietHours? = nil) {
        self.signedIn = signedIn
        email = signedIn ? "anna@example.com" : nil
        provider = signedIn ? "apple.com" : nil
        inviteURL = signedIn ? "https://lovearound.me/i/GSSV7-A33HN" : nil
        self.contacts = contacts
        loaded = signedIn
        self.devices = devices
        devicesLoaded = signedIn
        self.tab = tab
        self.justSent = justSent
        self.outgoing = outgoing
        toast = nil
        self.anyoneSentAt = anyoneSentAt
        self.receiveHere = receiveHere
        self.pausedUntil = pausedUntil
        self.quietHours = quietHours
        lastSent = [:]
    }
}
