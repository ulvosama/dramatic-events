import Foundation
import UserNotifications

/// Wraps `UNUserNotificationCenter` for the "meeting is live" alert.
/// Useful when the menu bar is hidden (fullscreen apps, mission control).
enum NotificationManager {

    /// Requests notification permission. Safe to call repeatedly; the system
    /// only prompts once, then returns the cached decision. No-op if the user
    /// denied — we just won't be able to fire alerts.
    static func requestAuthorization() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, error in
                if let error = error {
                    NSLog("⚠️ Notification authorization error: \(error)")
                }
            }
    }

    /// Fires an immediate banner for a meeting that just went live.
    /// Silent on the audio side — we already play the meeting sound through
    /// `SoundPlayer`. Setting `sound = nil` on the content avoids a double-ding.
    static func notifyLive(title: String) {
        let content = UNMutableNotificationContent()
        content.title = "Meeting starting"
        content.body  = title
        content.sound = nil

        let req = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil)

        UNUserNotificationCenter.current().add(req) { error in
            if let error = error {
                NSLog("⚠️ Could not deliver live notification: \(error)")
            }
        }
    }
}
