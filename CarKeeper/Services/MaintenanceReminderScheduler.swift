// =============================================================================
// #NEW-118 维保提醒订阅 — 保养到期前 N 天推送通知
// =============================================================================

import Foundation
import UserNotifications

class MaintenanceReminderScheduler {
    static let shared = MaintenanceReminderScheduler()

    // 保养提醒阈值（提前天数）
    private let mileageThresholds = [1000, 500, 100]

    private init() {}

    /// 请求通知权限
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
            print("Notification permission failed: \(error)")
            return false
        }
    }

    /// 调度保养提醒
    func scheduleMaintenanceReminder(lastServiceMileage: Int, nextServiceMileage: Int? = nil) async {
        let center = UNUserNotificationCenter.current()
        let currentMileage = UserDefaults.standard.integer(forKey: "carkeeper_current_mileage")
        let nextMileage = nextServiceMileage ?? (lastServiceMileage + 10000)

        // 计算剩余里程
        let remainingMileage = nextMileage - currentMileage

        for threshold in mileageThresholds {
            if remainingMileage <= threshold && remainingMileage > threshold - 500 {
                let content = UNMutableNotificationContent()
                content.title = "🚗 保养提醒"
                content.body = "您的车辆距离下次保养仅剩 \(remainingMileage) km，请及时安排保养"
                content.sound = .default
                content.badge = 1

                // 每天检查一次
                let trigger = UNCalendarNotificationTrigger(
                    dateMatching: DateComponents(hour: 9, minute: 0),
                    repeats: true
                )

                let request = UNNotificationRequest(
                    identifier: "maintenance_\(threshold)",
                    content: content,
                    trigger: trigger
                )

                try? await center.add(request)
            }
        }
    }

    /// 清除所有提醒
    func clearAllReminders() async {
        let center = UNUserNotificationCenter.current()
        await center.removeAllPendingNotificationRequests()
    }
}
