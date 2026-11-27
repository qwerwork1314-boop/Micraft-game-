import Foundation
import UserNotifications

/// Optional, gentle local reminders. Wording is encouraging and never shame-based;
/// nothing is scheduled unless the user turns it on.
enum ReminderScheduler {
    static let hydrationIDs = (0..<4).map { "vf.hydration.\($0)" }
    static let bedtimeID = "vf.bedtime"

    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    static func apply(_ s: UserSettings) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: hydrationIDs + [bedtimeID])
        guard s.hydrationReminders || s.bedtimeReminder else { return }
        guard await requestPermission() else { return }

        if s.hydrationReminders {
            for (i, hour) in [10, 13, 16, 19].enumerated() {
                let c = UNMutableNotificationContent()
                c.title = String(localized: "A sip for your garden 🌿")
                c.body = String(localized: "If you're thirsty, a glass of water is a nice way to look after yourself.")
                let trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: hour), repeats: true)
                try? await center.add(UNNotificationRequest(identifier: hydrationIDs[i], content: c, trigger: trigger))
            }
        }
        if s.bedtimeReminder {
            let c = UNMutableNotificationContent()
            c.title = String(localized: "Wind-down time")
            c.body = String(localized: "Your usual bedtime is coming up. Dim the lights and let the day settle.")
            let trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: s.bedtimeHour, minute: s.bedtimeMinute), repeats: true)
            try? await center.add(UNNotificationRequest(identifier: bedtimeID, content: c, trigger: trigger))
        }
    }

    static func cancelAll() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: hydrationIDs + [bedtimeID])
    }
}
