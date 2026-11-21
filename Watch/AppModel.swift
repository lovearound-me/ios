import AuthenticationServices
import SwiftUI
import WatchKit

/// Everything the watch shows, and the few things it does: sign in (Apple or
/// a code), load the people, send a signal, play an incoming one. Incoming
/// hearts come as the watch's own notifications (Push.swift).
@MainActor
final class AppModel: ObservableObject {
    enum Screen: Equatable {
        case signIn
        /// «Войти через Apple» hit an email that has an account made another way.
        case emailExists
        case code
        case connected
        case main
    }

    /// The bubble for «Кому-нибудь на свете» in `justSent`.
    nonisolated static let anyoneID = "anyone"

    @Published var screen: Screen
    @Published private(set) var session: Session? = nil
    @Published var busy = false
    /// A line under the sign-in buttons: why the last try failed, or that the
    /// watch was disconnected.
    @Published var notice: String? = nil

    // Code sign-in
    @Published private(set) var pairing: API.PairingCode? = nil
    @Published private(set) var pairingExpired = false
    @Published private(set) var pairingError: String? = nil

    // The people
    @Published private(set) var contacts: [Contact] = []
    @Published private(set) var loaded = false
    /// Sending from this watch is switched off on the phone: no people to show.
    @Published private(set) var sendingOff = false
    /// The circle that just sent, filled with a heart for a moment.
    @Published private(set) var justSent: String? = nil
    @Published private(set) var caption: String? = nil
    /// The one a finger holds: its whole name over the screen.
    @Published private(set) var peeking: Target? = nil
    /// The finger slid away while holding: letting go sends nothing.
    private var holdCancelled = false

    /// Settings → «Вид». Stays on this watch.
    @Published var layout: WatchLayout {
        didSet { if demo == nil { WatchLayout.saved = layout } }
    }
    /// Settings → «Убирать само»: a heart's notification leaves the screen by
    /// itself after `SignalNotificationController.shownFor` seconds; off, it
    /// stays until the person closes it. Stays on this watch.
    @Published var notificationGoes: Bool {
        didSet { if demo == nil { UserDefaults.standard.set(notificationGoes, forKey: "notificationGoes") } }
    }
    nonisolated static var savedNotificationGoes: Bool {
        UserDefaults.standard.object(forKey: "notificationGoes") as? Bool ?? true
    }
    /// Settings → «Вибрация»: 1, the ordinary tap; 0, none. Stays on this
    /// watch; the server only hears whether it is none, to send quietly.
    @Published var taps: Int {
        didSet {
            guard demo == nil, taps != oldValue else { return }
            Taps.count = taps
            if (taps == 0) != (oldValue == 0), let token = WatchPush.shared.token {
                Task { await register(token) }
            }
        }
    }

    // An incoming signal
    @Published private(set) var incoming = false
    /// Picks which emoji float up this time.
    @Published private(set) var signalSeed = 0

    /// The screen edges glow in it; stays on this watch, like on the iPhone.
    @Published var myColor: Int {
        didSet {
            guard demo == nil else { return }
            UserDefaults.standard.set(myColor, forKey: "myColor")
            WidgetData.myColor = myColor
        }
    }
    nonisolated static var savedColor: Int { UserDefaults.standard.object(forKey: "myColor") as? Int ?? 0 }

    // Receiving on this watch
    /// Its «Получать сердечки», as the server has it; nil until known.
    @Published private(set) var receiving: Bool? = nil
    /// watchOS doesn't let the app notify: the switch alone does nothing.
    @Published private(set) var notificationsOff = false
    /// Why the last switch didn't take.
    @Published private(set) var receiveProblem: String? = nil
    private var capabilities: [String] = []

    let demo: Demo?
    private var pairingTask: Task<Void, Never>?
    private var appleNonce = ""
    private var sentGeneration = 0

    init() {
        let demo = Demo.fromArguments()
        let saved = demo == nil ? Session.load() : nil
        self.demo = demo
        myColor = Self.savedColor
        layout = WatchLayout.saved
        taps = Taps.count
        notificationGoes = Self.savedNotificationGoes
        screen = demo == nil && saved == nil ? .signIn : .main
        // Every stored property has its value from here on.
        session = saved
        demo?.apply(to: self)
        if demo == nil {
            let push = WatchPush.shared
            push.onToken = { [weak self] token in Task { await self?.register(token) } }
            push.onHeart = { [weak self] in self?.showSignal() }
            // It tapped the wrist already: the glow, without more taps.
            push.onTap = { [weak self] in self?.showSignal(tapping: false) }
            if saved != nil { Task { await startReceiving() } }
        }
    }

    /// Close people first, each group in the owner's order.
    var circles: [Contact] {
        contacts.sorted { a, b in
            a.isClose != b.isClose ? a.isClose : a.position < b.position
        }
    }

    /// What the main screen shows: «Кому-нибудь на свете», then the people.
    var targets: [Target] {
        [.anyone] + circles.map(Target.person)
    }

    // MARK: Sign in with Apple

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
        notice = nil
        Task {
            defer { busy = false }
            do {
                let user = try await AppleSignIn.firebase(identityToken: identityToken, rawNonce: nonce)
                signedIn(try await API.createDevice(firebaseToken: user.idToken, email: user.email), welcome: true)
            } catch AppleSignIn.Failure.emailExists {
                screen = .emailExists
            } catch AppleSignIn.Failure.network {
                notice = tr("Нет связи, проверь интернет")
            } catch {
                notice = tr("Не получилось войти. Попробуй ещё раз.")
            }
        }
    }

    // MARK: Sign in with a code

    func startCode() {
        screen = .code
        pairing = nil
        pairingExpired = false
        pairingError = nil
        pairingTask?.cancel()
        guard demo == nil else { return }
        pairingTask = Task { await runPairing() }
    }

    func cancelCode() {
        pairingTask?.cancel()
        pairingTask = nil
        pairing = nil
        screen = .signIn
    }

    private func runPairing() async {
        let code: API.PairingCode
        do {
            code = try await API.startPairing()
        } catch APIError.status(429, _) {
            pairingError = tr("Слишком много кодов. Попробуй через час.")
            return
        } catch {
            pairingError = tr("Нет связи, проверь интернет")
            return
        }
        guard !Task.isCancelled else { return }
        pairing = code
        let deadline = Date().addingTimeInterval(TimeInterval(code.expires_in))
        let pause = UInt64(max(code.poll_every, 2)) * 1_000_000_000
        while Date() < deadline {
            do {
                try await Task.sleep(nanoseconds: pause)
            } catch {
                return // cancelled
            }
            // A failed poll (no network for a moment) just waits for the next one.
            guard let state = try? await API.pollPairing(secret: code.secret) else { continue }
            switch state {
            case .waiting:
                continue
            case .paired(let session):
                signedIn(session, welcome: true)
                return
            case .gone:
                pairingExpired = true
                return
            }
        }
        pairingExpired = true
    }

    // MARK: Session

    private func signedIn(_ session: Session, welcome: Bool) {
        session.save()
        self.session = session
        notice = nil
        pairing = nil
        Task { await startReceiving() }
        guard welcome else {
            screen = .main
            return
        }
        screen = .connected
        Task {
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            if screen == .connected { screen = .main }
        }
    }

    /// «Выйти»: the watch leaves the account's devices first, while its token
    /// can still say so; then forgets the token.
    func signOutHere() async {
        if demo == nil, let session {
            try? await API(token: session.token).removeSelf()
        }
        signOut()
    }

    /// Forgets this watch's token.
    func signOut(notice: String? = nil) {
        // A demo's «Выйти» only shows the sign-in screen: the watch's real
        // token stays, so a test can't leave a ghost device on the account.
        if demo == nil {
            Session.clear()
            WidgetData.clear()
        }
        session = nil
        contacts = []
        loaded = false
        sendingOff = false
        receiving = nil
        receiveProblem = nil
        capabilities = []
        if demo == nil { WatchPush.shared.forget() }
        self.notice = notice
        screen = .signIn
    }

    // MARK: Receiving

    /// After sign-in and at each launch: watchOS's permission (asked once),
    /// Apple's token for this watch to the server, and the switch's state.
    func startReceiving() async {
        guard demo == nil, session != nil else { return }
        await WatchPush.shared.ask()
        notificationsOff = !WatchPush.shared.allowed
        await loadReceiving()
    }

    private func register(_ pushToken: String) async {
        guard let session else { return }
        let api = API(token: session.token)
        do {
            try await api.registerPush(pushToken, sandbox: WatchPush.sandbox, silent: taps == 0)
        } catch APIError.status(let code, _) where taps == 0 && (code == 400 || code == 422) {
            // A server from before «Без вибрации» rejects the field (422):
            // hearts with a tap beat none.
            try? await api.registerPush(pushToken, sandbox: WatchPush.sandbox, silent: false)
        } catch {}
    }

    private func loadReceiving() async {
        guard let session, let me = try? await API(token: session.token).me() else { return }
        capabilities = me.capabilities
        receiving = me.receives
    }

    /// «Получать сердечки»: the same as «Принимает» in the watch's card on
    /// the phone.
    func setReceiving(_ on: Bool) {
        guard receiving != on else { return }
        receiveProblem = nil
        let before = receiving
        receiving = on
        guard demo == nil, let session else { return }
        var wanted = capabilities.filter { $0 != "receive" }
        if on { wanted.append("receive") }
        Task {
            do {
                let me = try await API(token: session.token).setCapabilities(wanted)
                capabilities = me.capabilities
                receiving = me.receives
                if on, WatchPush.shared.token == nil { await startReceiving() }
            } catch let error as APIError where error.sessionGone {
                signOut(notice: tr("Часы отключены в «Устройствах». Войди снова."))
            } catch APIError.status(400, _) {
                receiving = before
                receiveProblem = tr("Эти часы вошли только для отправки. Выйди и войди снова.")
            } catch APIError.network {
                receiving = before
                receiveProblem = tr("Нет связи, проверь интернет")
            } catch {
                receiving = before
                receiveProblem = tr("Не получилось. Попробуй ещё раз.")
            }
        }
    }

    /// The «Вибрация» switch.
    var vibrates: Bool {
        get { taps > 0 }
        set { taps = newValue ? 1 : 0 }
    }

    // MARK: An incoming signal

    /// The wrist taps («Вибрация»), the glowing edges and the emoji: a heart
    /// that came while the app was in front, a tapped notification,
    /// «Показать», the demo.
    func showSignal(tapping: Bool = true) {
        signalSeed = Int.random(in: 0..<1000)
        incoming = true
        if tapping { Taps.play(taps) }
        let seed = signalSeed
        Task {
            try? await Task.sleep(nanoseconds: 5_500_000_000)
            if signalSeed == seed { incoming = false }
        }
    }

    // MARK: The people

    func refresh() async {
        guard demo == nil, let session else { return }
        Task { await loadReceiving() }
        do {
            contacts = try await API(token: session.token).contacts()
            loaded = true
            shareWithWidgets()
            sendingOff = false
        } catch let error as APIError where error.sessionGone {
            signOut(notice: tr("Часы отключены в «Устройствах». Войди снова."))
        } catch let error as APIError where error.switchedOff {
            contacts = []
            loaded = true
            sendingOff = true
        } catch {
            // Offline: keep what is on screen and try on the next refresh.
        }
    }

    /// The complication and the Smart Stack draw people from this copy.
    private func shareWithWidgets() {
        let people = circles.map { WidgetData.Person(id: $0.id, label: $0.label, color: $0.color, close: $0.isClose) }
        if people != WidgetData.people { WidgetData.save(people: people) }
        if WidgetData.myColor != myColor { WidgetData.myColor = myColor }
    }

    func send(_ target: Target) {
        switch target {
        case .anyone: sendAnyone()
        case .person(let contact): send(contact)
        }
    }

    // MARK: A held finger

    /// A finger is down on someone, not yet long enough to show the name.
    func pressStarted() {
        if peeking == nil { holdCancelled = false }
    }

    /// Held long enough: the whole name shows. Slid away: it hides, and
    /// letting go sends nothing.
    func holding(_ target: Target, moved: CGFloat) {
        guard !holdCancelled else { return }
        if moved > 28 {
            holdCancelled = true
            peeking = nil
            flash(tr("Отменено"))
            return
        }
        if peeking != target {
            peeking = target
            WKInterfaceDevice.current().play(.click)
        }
    }

    /// The finger let go: what it held goes, unless it slid away.
    func released(_ target: Target) {
        defer { holdCancelled = false }
        guard !holdCancelled, peeking == target else { return }
        peeking = nil
        send(target)
    }

    /// A tap on the shown name, if the finger's own gesture was lost.
    func sendPeeked() {
        guard let target = peeking else { return }
        peeking = nil
        send(target)
    }

    func cancelPeek() {
        guard peeking != nil else { return }
        peeking = nil
        flash(tr("Отменено"))
    }

    /// A caption for a moment, nothing sent.
    private func flash(_ text: String) {
        sentGeneration += 1
        let generation = sentGeneration
        caption = text
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if generation == sentGeneration { caption = nil }
        }
    }

    func send(_ contact: Contact) {
        sent(contact.id, tr("{name} — улетело ♥", ["name": contact.label])) { api in
            try await api.signal(contact.id)
        }
    }

    func sendAnyone() {
        sent(Self.anyoneID, tr("Кому-нибудь на свете — улетело ✨")) { api in
            try await api.signalAnyone()
        }
    }

    private func sent(_ id: String, _ text: String, _ call: @escaping (API) async throws -> Void) {
        WKInterfaceDevice.current().play(.click)
        sentGeneration += 1
        let generation = sentGeneration
        justSent = id
        caption = text
        Task {
            if demo == nil, let session {
                do {
                    try await call(API(token: session.token))
                } catch let error as APIError where error.sessionGone {
                    signOut(notice: tr("Часы отключены в «Устройствах». Войди снова."))
                    return
                } catch let error as APIError where error.switchedOff {
                    sendingOff = true
                    caption = tr("Отправка с часов выключена")
                    justSent = nil
                } catch APIError.status(429, _) where id == Self.anyoneID {
                    caption = tr("Кому-нибудь на свете уже улетело в этот час.")
                    justSent = nil
                } catch {
                    caption = tr("Не улетело, проверь интернет")
                    justSent = nil
                    WKInterfaceDevice.current().play(.failure)
                }
            }
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard generation == sentGeneration else { return }
            justSent = nil
            caption = nil
        }
    }

    // MARK: Deleting the account

    /// After Apple's button on the delete screen: deletes the account only
    /// if Apple opened the very account this watch is in. Apple forgets the
    /// app as well (AppleSignIn.revoke).
    func deleteFinished(_ result: Result<ASAuthorization, Error>) {
        guard case .success(let authorization) = result,
              let identityToken = AppleSignIn.identityToken(authorization) else { return }
        let appleCode = AppleSignIn.authorizationCode(authorization)
        let nonce = appleNonce
        busy = true
        notice = nil
        Task {
            defer { busy = false }
            do {
                let user = try await AppleSignIn.firebase(identityToken: identityToken, rawNonce: nonce)
                guard let mine = session?.email, let theirs = user.email,
                      mine.caseInsensitiveCompare(theirs) == .orderedSame else {
                    notice = tr("Это другой аккаунт. Удалить этот можно в Love Around на iPhone: Настройки → Аккаунт.")
                    return
                }
                if let appleCode {
                    await AppleSignIn.revoke(authorizationCode: appleCode, idToken: user.idToken)
                }
                try await API.deleteAccount(firebaseToken: user.idToken)
                signOut(notice: tr("Аккаунт удалён."))
            } catch AppleSignIn.Failure.emailExists {
                notice = tr("Это другой аккаунт. Удалить этот можно в Love Around на iPhone: Настройки → Аккаунт.")
            } catch AppleSignIn.Failure.network {
                notice = tr("Нет связи, проверь интернет")
            } catch {
                notice = tr("Не получилось. Попробуй ещё раз.")
            }
        }
    }

    // MARK: Demo

    func demoSet(session: Session?, contacts: [Contact], pairing: API.PairingCode? = nil,
                 expired: Bool = false, justSent: String? = nil, caption: String? = nil, screen: Screen,
                 layout: WatchLayout = .hive, peeking: Target? = nil) {
        self.layout = layout
        self.peeking = peeking
        self.session = session
        self.receiving = session == nil ? nil : true
        self.contacts = contacts
        self.loaded = true
        self.pairing = pairing
        self.pairingExpired = expired
        self.justSent = justSent
        self.caption = caption
        self.screen = screen
    }
}
