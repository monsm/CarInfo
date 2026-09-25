// =============================================================================
// #NEW-118 维保提醒订阅 — 保养到期前 N 天推送通知
// =============================================================================

import Foundation
import UserNotifications

class MaintenanceReminderScheduler {
    static let shared = MaintenanceReminderScheduler()

    /// 提前多少公里开始提醒。此前这里是一个阈值数组 + 500 km 宽的窗口
    /// （`remaining <= t && remaining > t - 500`）：只有 App 恰好在那一小段里
    /// 被打开过一次才会响，越过了就永远不会响。现在只留一个「开始提醒的距离」。
    private let remindWithinKm = 2000

    private let requestId = "maintenance_due"

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
            // 2026-09-25 地毯式审核：这里原本是 `print(…)` —— 全仓仅有的两个 print 之一。
            // print 只进 Xcode 控制台（且只在连调试器时），用户看不到、诊断页也看不到，
            // 等于「请求授权失败了」这件事在任何地方都不存在。改用诊断页正在读的那本日志
            // （`RawLogStore` 会打码、限长，并同时写一条系统日志）。
            RawLogStore.shared.logError(method: "NOTIFY", url: "maintenance",
                                        message: "申请通知授权失败：\(error)")
            return false
        }
    }

    /// 调度保养提醒。
    ///
    /// 里程由调用方传入（`AppStore.recordHistory()` 从车端报文里读），不再偷偷去
    /// UserDefaults 取一个没人写过的键 —— 那正是这条提醒永远不可能响的原因。
    ///
    /// 触发时机：我们**只知道公里数、不知道哪一天跑到**，所以用每天 9:00 重复提醒，
    /// 并在每次里程更新时用同一个 id **替换**掉旧的（id 相同 → 内容刷新而不是叠加）。
    /// 离开提醒区间（还差很远、或已经过了）就把待发提醒撤掉，不纠缠。
    func scheduleMaintenanceReminder(lastServiceMileage: Int,
                                     currentMileage: Int,
                                     interval: Int = AppStore.defaultServiceInterval) async {
        let center = UNUserNotificationCenter.current()
        let nextMileage = lastServiceMileage + interval
        let remainingMileage = nextMileage - currentMileage

        // 不在提醒区间：撤掉待发的那条（包括已经过头很多的情况）
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

        // 每天 9:00 检查一次；内容里的公里数是**调度那一刻**的值，
        // 所以每次里程变化都会重发一次（同一个 id，替换而非叠加）。
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: DateComponents(hour: 9, minute: 0),
            repeats: true
        )
        try? await center.add(UNNotificationRequest(identifier: requestId,
                                                   content: content,
                                                   trigger: trigger))
    }

    /// 撤掉本调度器自己排的提醒。
    /// 此前这里是 `removeAllPendingNotificationRequests()` —— 名字叫「清除所有提醒」，
    /// 它真的会清掉**全 App 所有**待发通知（包括保险到期、智能提醒）。只撤自己的。
    func clearAllReminders() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [requestId])
    }
}
