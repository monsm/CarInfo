
import Foundation
import UserNotifications

class MaintenanceReminderScheduler {
    static let shared = MaintenanceReminderScheduler()

    private let remindWithinKm = 2000

    private let requestId = "maintenance_due"

    private init() {}

    func requestNotificationPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        guard settings.authorizationStatus == .notDetermined else {
            return settings.authorizationStatus == .authorized
        }

        do {
            try await center.requestAuthorization(options: [.alert, .sound, .badge])
            return true
        } catch {
            RawLogStore.shared.logError(method: "NOTIFY", url: "maintenance",
                                        message: "申请通知授权失败：\(error)")
            return false
        }
    }

    func scheduleMaintenanceReminder(lastServiceMileage: Int,
                                     currentMileage: Int,
                                     interval: Int = AppStore.defaultServiceInterval) async {
        let center = UNUserNotificationCenter.current()
        let nextMileage = lastServiceMileage + interval
        let remainingMileage = nextMileage - currentMileage

        guard remainingMileage <= remindWithinKm && remainingMileage > -2000 else {
            center.removePendingNotificationRequests(withIdentifiers: [requestId])
            return
        }

        let content = UNMutableNotificationContent()
        content.sound = .default
        if remainingMileage > 0 {
            content.title = "保养提醒"
            content.body = "距下次保养还剩 \(remainingMileage) km（上次保养 \(lastServiceMileage) km，"
                + "间隔 \(interval) km）。"
        } else {
            content.title = "已到保养里程"
            content.body = "当前 \(currentMileage) km，已超出计划 \(-remainingMileage) km。"
        }

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: DateComponents(hour: 9, minute: 0),
            repeats: true
        )
        try? await center.add(UNNotificationRequest(identifier: requestId,
                                                   content: content,
                                                   trigger: trigger))
    }

    func clearAllReminders() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [requestId])
    }
}
