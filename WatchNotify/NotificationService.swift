import UserNotifications

/// The watch's own notification of a heart, before it shows: notes the
/// moment in the app group, so the complication's ♥ glows for an hour.
/// The notification itself stays as the server sent it.
final class NotificationService: UNNotificationServiceExtension {
    override func didReceive(_ request: UNNotificationRequest,
                             withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        if request.content.userInfo["kind"] as? String == "signal" {
            WidgetData.heartCame()
        }
        contentHandler(request.content)
    }
}
