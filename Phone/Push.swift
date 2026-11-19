import UIKit
import UserNotifications

/// Notifications: iOS's permission, this iPhone's token for them, and what a
/// heart does when the app is in front or its notification is tapped. The
/// server sends each heart as a bare «♥» (Notify/ writes the text), only
/// while this iPhone takes hearts, outside its pause and quiet hours.
@MainActor
final class Push: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = Push()

    @Published private(set) var status: UNAuthorizationStatus = .notDetermined
    /// Apple's address of this app on this iPhone, as hex.
    @Published private(set) var token: String?

    /// A heart came while the app was in front: glow instead of a banner.
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
    var onToken: (() -> Void)?

    /// Tapped before the app had set `onTap`, as when the tap launches it.
    private var tappedEarly = false

    /// Whether Apple's sandbox sends this build's notifications: a build
    /// installed from Xcode or over the cable, signed for development, says
    /// so in its profile; TestFlight and the App Store carry none.
    static let sandbox: Bool = {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .isoLatin1),
              let key = text.range(of: "<key>aps-environment</key>") else { return false }
        return text[key.upperBound...].prefix(100).contains("<string>development</string>")
    }()

    /// From `application(_:didFinishLaunchingWithOptions:)`: a tap that
    /// launches the app arrives right after.
    func start() {
        UNUserNotificationCenter.current().delegate = self
    }

    var allowed: Bool {
        [.authorized, .provisional, .ephemeral].contains(status)
    }

    /// What iOS allows now (it can change in the Settings app); once
    /// allowed, asks Apple for the token, which comes to `got(_:)`.
    func refresh() async {
        status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        if allowed {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    /// iOS asks the person once; later only the Settings app changes it.
    func ask() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        await refresh()
    }

    func got(_ deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        guard hex != token else { return }
        token = hex
        onToken?()
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

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        Push.shared.start()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Push.shared.got(deviceToken)
    }

    /// No token (a simulator without a signed build, no network): the app
    /// still glows while open.
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {}
}
