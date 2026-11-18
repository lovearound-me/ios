import AuthenticationServices
import SwiftUI
import WatchKit

/// Everything the watch shows, and the few things it does: sign in (Apple or
/// a code), load the people, send a signal, play an incoming one.
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

    /// The circle for «Кому-нибудь на свете» in `justSent`.
    static let anyoneID = "anyone"

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

    // An incoming signal
    @Published private(set) var incoming = false
    /// Picks which emoji float up this time.
    @Published private(set) var signalSeed = 0

    /// The screen edges glow in it; stays on this watch, like on the Mac.
    @Published var myColor: Int {
        didSet { UserDefaults.standard.set(myColor, forKey: "myColor") }
    }

    let demo: Demo?
    private var pairingTask: Task<Void, Never>?
    private var appleNonce = ""
    private var sentGeneration = 0

    init() {
        let demo = Demo.fromArguments()
        let saved = demo == nil ? Session.load() : nil
        self.demo = demo
        myColor = UserDefaults.standard.object(forKey: "myColor") as? Int ?? 0
        screen = demo == nil && saved == nil ? .signIn : .main
        // Every stored property has its value from here on.
        session = saved
        demo?.apply(to: self)
    }

    /// Close people first, each group in the owner's order.
    var circles: [Contact] {
        contacts.sorted { a, b in
            a.isClose != b.isClose ? a.isClose : a.position < b.position
        }
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

    /// Forgets this watch's token. The device stays in «Устройства» until it
    /// is removed there: a device token can't remove itself.
    func signOut(notice: String? = nil) {
        Session.clear()
        session = nil
        contacts = []
        loaded = false
        sendingOff = false
        self.notice = notice
        screen = .signIn
    }

    // MARK: The people

    func refresh() async {
        guard demo == nil, let session else { return }
        do {
            contacts = try await API(token: session.token).contacts()
            loaded = true
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

    // MARK: An incoming signal

    /// The wrist tap, the glowing edges and the emoji. Comes from a push
    /// notification (the server side is still to do) and from the demo.
    func showSignal() {
        signalSeed = Int.random(in: 0..<1000)
        incoming = true
        WKInterfaceDevice.current().play(.notification)
        let seed = signalSeed
        Task {
            try? await Task.sleep(nanoseconds: 5_500_000_000)
            if signalSeed == seed { incoming = false }
        }
    }

    // MARK: Deleting the account

    /// After «Подтверди через Apple»: deletes the account only if Apple
    /// opened the very account this watch is in.
    func deleteFinished(_ result: Result<ASAuthorization, Error>) {
        guard case .success(let authorization) = result,
              let identityToken = AppleSignIn.identityToken(authorization) else { return }
        let nonce = appleNonce
        busy = true
        notice = nil
        Task {
            defer { busy = false }
            do {
                let user = try await AppleSignIn.firebase(identityToken: identityToken, rawNonce: nonce)
                guard let mine = session?.email, let theirs = user.email,
                      mine.caseInsensitiveCompare(theirs) == .orderedSame else {
                    notice = tr("Это другой аккаунт. Удалить этот можно на {site} → Настройки → Аккаунт.",
                                ["site": Config.webApp])
                    return
                }
                try await API.deleteAccount(firebaseToken: user.idToken)
                signOut(notice: tr("Аккаунт удалён."))
            } catch AppleSignIn.Failure.emailExists {
                notice = tr("Это другой аккаунт. Удалить этот можно на {site} → Настройки → Аккаунт.",
                            ["site": Config.webApp])
            } catch AppleSignIn.Failure.network {
                notice = tr("Нет связи, проверь интернет")
            } catch {
                notice = tr("Не получилось. Попробуй ещё раз.")
            }
        }
    }

    // MARK: Demo

    func demoSet(session: Session?, contacts: [Contact], pairing: API.PairingCode? = nil,
                 expired: Bool = false, justSent: String? = nil, caption: String? = nil, screen: Screen) {
        self.session = session
        self.contacts = contacts
        self.loaded = true
        self.pairing = pairing
        self.pairingExpired = expired
        self.justSent = justSent
        self.caption = caption
        self.screen = screen
    }
}
