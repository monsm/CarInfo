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

    /// 调度保险到期提醒（到期前 30 天与 7 天，各一条，早上 9:00）。
    ///
    /// 旧版有两个毛病，都是「看起来在提醒、其实不会/会误报」：
    ///   ① 窗口写成了 `days <= 30 && days > 20`、`days <= 7 && days > 0` —— 只有恰好
    ///      落在那几天里被调用才排得上，越过了就永远不响；
    ///   ② 触发器只写了 `DateComponents(hour: 9, minute: 0)`，**完全丢掉了到期日**，
    ///      所以无论保单什么时候到期，都是「明天 9:00」响一次。
    /// 现在按到期日倒推真实日期（已经过去的日期就不排了）。
    func scheduleInsuranceReminder(insuranceEndDate: Date?) async {
        let center = UNUserNotificationCenter.current()
        let ids = ["insurance_30days", "insurance_7days"]
        center.removePendingNotificationRequests(withIdentifiers: ids)

        guard let endDate = insuranceEndDate, endDate > Date() else { return }

        let calendar = Calendar.current
        // 到期前一天也算「已到期」，所以 7 天提醒在剩 7 天时发即可
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

    /// 在「到期日 - daysBefore」当天 9:00 触发
    private func createReminder(identifier: String,
                                title: String,
                                body: String,
                                daysBefore: Int,
                                endDate: Date) async {
        let calendar = Calendar.current
        guard let fireDay = calendar.date(byAdding: .day, value: -daysBefore, to: endDate) else { return }
        // 这个点已经过去了（比如今天就剩 5 天，却要排 7 天前的那条）：改到今天 9:00
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
            // 同 `MaintenanceReminderScheduler`：排提醒失败要留痕，而 `print` 留不下任何痕。
            // 这一条尤其重要：用户若没收到到期提醒，唯一能查的就是这本日志。
            RawLogStore.shared.logError(method: "NOTIFY", url: "insurance",
                                        message: "安排保险到期提醒失败：\(error)")
        }
    }

    /// 撤掉**本调度器**排的提醒。
    /// 此前用的是 `removeAllPendingNotificationRequests()` —— 那会连保养提醒、
    /// 智能提醒一起清掉，超出了这个名字承诺的范围。
    func clearAllReminders() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["insurance_30days", "insurance_7days"])
    }
}
