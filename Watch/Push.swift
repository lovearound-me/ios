import UserNotifications
import WatchKit

/// The watch's own notifications. The watch is a device of the account, so
/// a heart comes to it straight from the server through Apple (docs/schema.md,
/// "Notifications on an iPhone and an Apple Watch"), on the watch's own terms:
/// its «Получать сердечки», its quiet hours and «кто-нибудь на свете» in its
/// card on the phone. The phone's switch, pause and quiet hours don't reach
/// it. Where both take a heart, Apple shows it on the wrist once.
@MainActor
final class WatchPush: NSObject, UNUserNotificationCenterDelegate {
    static let shared = WatchPush()

    private(set) var status: UNAuthorizationStatus = .notDetermined
    /// Apple's address of this app on this watch, as hex.
    private(set) var token: String?

    var onToken: ((String) -> Void)?
    /// A heart came while the app was in front: the glow instead of a banner.
    var onHeart: (() -> Void)?
    /// Its notification was tapped: the app opens and glows.
    var onTap: (() -> Void)? {
        didSet {
            if tappedEarly, let onTap {
                tappedEarly = false
                onTap()
            }
        }
    }

    private var tappedEarly = false

    /// As on the iPhone: a development build's profile says so; a simulator
    /// always uses the sandbox.
    static let sandbox: Bool = {
        #if targetEnvironment(simulator)
        return true
        #else
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .isoLatin1),
              let key = text.range(of: "<key>aps-environment</key>") else { return false }
        return text[key.upperBound...].prefix(100).contains("<string>development</string>")
        #endif
    }()

    func start() {
        UNUserNotificationCenter.current().delegate = self
    }

    var allowed: Bool {
        [.authorized, .provisional, .ephemeral].contains(status)
    }

    /// Asks watchOS once (it asks the person only the first time), then
    /// Apple for the token, which comes to `got(_:)`.
    func ask() async {
        let center = UNUserNotificationCenter.current()
        status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            status = await center.notificationSettings().authorizationStatus
        }
        if allowed {
            WKApplication.shared().registerForRemoteNotifications()
        }
    }

    /// Signed out: Apple stops delivering to this watch.
    func forget() {
        WKApplication.shared().unregisterForRemoteNotifications()
        token = nil
    }

    func got(_ deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        token = hex
        onToken?(hex)
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        await MainActor.run { self.onHeart?() }
        return []
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        await MainActor.run {
            if let onTap = self.onTap {
                onTap()
            } else {
                self.tappedEarly = true
            }
        }
    }
}

final class WatchDelegate: NSObject, WKApplicationDelegate {
    func applicationDidFinishLaunching() {
        MainActor.assumeIsolated { WatchPush.shared.start() }
    }

    func didRegisterForRemoteNotifications(withDeviceToken deviceToken: Data) {
        MainActor.assumeIsolated { WatchPush.shared.got(deviceToken) }
    }

    /// No token (a simulator, no network): the app still glows while open.
    func didFailToRegisterForRemoteNotificationsWithError(_ error: Error) {}
}
