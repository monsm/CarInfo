
import Foundation
import UserNotifications

class InsuranceReminderScheduler {
    static let shared = InsuranceReminderScheduler()

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
            return false
        }
    }

    func scheduleInsuranceReminder(insuranceEndDate: Date?) async {
        let center = UNUserNotificationCenter.current()
        let ids = ["insurance_30days", "insurance_7days"]
        center.removePendingNotificationRequests(withIdentifiers: ids)

        guard let endDate = insuranceEndDate, endDate > Date() else { return }

        let calendar = Calendar.current
        let daysRemaining = calendar.dateComponents([.day], from: Date(), to: endDate).day ?? 0

        if daysRemaining > 7 {
            await createReminder(identifier: "insurance_30days",
                                 title: "车险即将到期",
                                 body: "还有 30 天到期，可以开始比价续保了。",
                                 daysBefore: 30, endDate: endDate)
        }
        await createReminder(identifier: "insurance_7days",
                             title: "车险还有 7 天到期",
                             body: "请尽快续保，脱保期间上路是违法的。",
                             daysBefore: 7, endDate: endDate)
    }

    private func createReminder(identifier: String,
                                title: String,
                                body: String,
                                daysBefore: Int,
                                endDate: Date) async {
        let calendar = Calendar.current
        guard let fireDay = calendar.date(byAdding: .day, value: -daysBefore, to: endDate) else { return }
        let today9 = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: Date())
        let fireAt = max(fireDay, today9 ?? fireDay)
        guard fireAt > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireAt)
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            RawLogStore.shared.logError(method: "NOTIFY", url: "insurance",
                                        message: "安排保险到期提醒失败：\(error)")
        }
    }

    func clearAllReminders() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["insurance_30days", "insurance_7days"])
    }
}
