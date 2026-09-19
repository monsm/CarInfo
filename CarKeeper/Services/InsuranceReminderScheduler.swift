// =============================================================================
// #NEW-119 保险到期提醒 — 车险到期前 30/7 天提醒
// =============================================================================

import Foundation
import UserNotifications

class InsuranceReminderScheduler {
    static let shared = InsuranceReminderScheduler()
    
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
            return false
        }
    }
    
    /// 调度保险到期提醒
    func scheduleInsuranceReminder(insuranceEndDate: Date?) async {
        guard let endDate = insuranceEndDate else { return }
        
        let center = UNUserNotificationCenter.current()
        let calendar = Calendar.current
        let now = Date()
        
        // 计算剩余天数
        let components = calendar.dateComponents([.day], from: now, to: endDate)
        let daysRemaining = components.day ?? 0
        
        // 30天提醒
        if daysRemaining <= 30 && daysRemaining > 20 {
            await createReminder(
                identifier: "insurance_30days",
                title: "⚠️ 车险即将到期",
                body: "您的车险还有 \(daysRemaining) 天到期，请及时续保",
                date: endDate
            )
        }
        
        // 7天提醒
        if daysRemaining <= 7 && daysRemaining > 0 {
            await createReminder(
                identifier: "insurance_7days",
                title: "🚨 车险即将到期",
                body: "您的车险还有 \(daysRemaining) 天到期，请立即续保！",
                date: endDate
            )
        }
    }
    
    private func createReminder(identifier: String, title: String, body: String, date: Date) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.badge = 1
        
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: DateComponents(hour: 9, minute: 0),
            repeats: false
        )
        
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )
        
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            print("Failed to schedule insurance reminder: \(error)")
        }
    }
    
    /// 清除所有提醒
    func clearAllReminders() async {
        await UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
}
