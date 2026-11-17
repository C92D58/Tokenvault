import UserNotifications

/// Schedules local notifications for tokens expiring within 7 days.
enum NotificationService {
    /// Request notification permission.
    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            if granted { print("[TokenVault] Notification permission granted") }
        }
    }

    /// Schedule expiry reminders for all active tokens.
    static func scheduleExpiryReminders(for tokens: [TokenItem]) {
        let center = UNUserNotificationCenter.current()

        // Remove old pending notifications
        center.removeAllPendingNotificationRequests()

        let soon = tokens.filter { !$0.isDeleted && $0.expiresSoon }
        let expired = tokens.filter { !$0.isDeleted && $0.isExpired }

        // Notify for already-expired tokens (once)
        for token in expired {
            let content = UNMutableNotificationContent()
            content.title = L("Token 已過期")
            content.body = L("「%@」已經過期，請更新。", token.name)
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: "expired-\(token.id.uuidString)",
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 60, repeats: false)
            )
            center.add(request)
        }

        // Schedule for each expiring token at the exact expiry date
        for token in soon {
            guard let expiry = token.expiresAt else { continue }

            let content = UNMutableNotificationContent()
            content.title = L("Token 即將到期")
            content.body = L("「%@」將於 %@ 到期", token.name, expiry.formatted(date: .abbreviated, time: .omitted))

            // Fire 1 day before expiry (but not in the past)
            let fireDate = Calendar.current.date(byAdding: .day, value: -1, to: expiry) ?? expiry
            guard fireDate > Date() else { continue }

            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let request = UNNotificationRequest(
                identifier: "expiring-\(token.id.uuidString)",
                content: content,
                trigger: trigger
            )
            center.add(request)
        }
    }
}
