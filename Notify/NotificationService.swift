import UserNotifications

/// A heart's notification arrives from the server as a bare «♥»; this
/// writes it the way Settings → «Уведомление» says, new emoji each time. If
/// iOS gives up on it, the «♥» shows as it came.
final class NotificationService: UNNotificationServiceExtension {
    override func didReceive(_ request: UNNotificationRequest,
                             withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        guard request.content.userInfo["kind"] as? String == "signal",
              let content = request.content.mutableCopy() as? UNMutableNotificationContent else {
            contentHandler(request.content)
            return
        }
        content.body = NotifyLook.current.text()
        contentHandler(content)
    }
}
