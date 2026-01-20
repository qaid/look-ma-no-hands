import Foundation
import UserNotifications

class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()

    private override init() {
        super.init()
        // Set self as delegate to handle notifications while app is active
        UNUserNotificationCenter.current().delegate = self
    }

    /// Request notification permission from the user
    func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            return try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            print("Notification permission error: \(error)")
            return false
        }
    }

    /// Check if notifications are authorized
    func isAuthorized() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus == .authorized
    }

    /// Send a notification
    func sendNotification(title: String, body: String, identifier: String = UUID().uuidString) async {
        let center = UNUserNotificationCenter.current()

        // Check authorization status
        let settings = await center.notificationSettings()
        print("NotificationService: Authorization status: \(settings.authorizationStatus.rawValue)")
        print("NotificationService: Alert setting: \(settings.alertSetting.rawValue)")

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil // Immediate delivery
        )

        print("NotificationService: Attempting to send notification: \(title)")

        do {
            try await center.add(request)
            print("NotificationService: Notification added successfully")
        } catch {
            print("NotificationService: Failed to send notification: \(error)")
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Called when a notification is delivered while the app is in the foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        print("NotificationService: Notification will present in foreground")
        // Show banner and play sound even when app is active
        completionHandler([.banner, .sound])
    }
}
