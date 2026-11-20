import UserNotifications

/// A heart's notification arrives from the server as a bare «♥»; this
/// writes it the way Settings → «Уведомление» says, new emoji each time,
/// silent if «Вибрация» is off. If
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
        // «Вибрация» off: no sound, and so no vibration.
        if !NotifyLook.vibrates { content.sound = nil }
        contentHandler(content)
    }
}
