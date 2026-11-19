import UserNotifications

/// A heart's notification arrives from the server as a bare «♥»; this
/// writes it the way Settings → «Уведомление» says, new emoji each time,
/// silent if «Вибрация» is none. If
/// iOS gives up on it, the «♥» shows as it came.
final class NotificationService: UNNotificationServiceExtension {
    override func didReceive(_ request: UNNotificationRequest,
                             withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        guard request.content.userInfo["kind"] as? String == "signal",
              let content = request.content.mutableCopy() as? UNMutableNotificationContent else {
            contentHandler(request.content)
            return
        }
        content.body = NotifyLook.current.text(words: NotifyLook.withWords)
        // «Вибрация» set to none: no sound, and so no vibration.
        if NotifyLook.taps == 0 { content.sound = nil }
        contentHandler(content)
    }
}
