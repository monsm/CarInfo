// =============================================================================
// SmartChargeScheduler — #NEW-110 智能充电建议
// 根据历史数据和电价时段，推荐最佳充电时机
// =============================================================================

import Foundation
import UserNotifications

struct ChargeRecommendation {
    let time: Date
    let reason: String
    let estimatedCost: Double
    let savingsPercent: Int
}

class SmartChargeScheduler {
    static let shared = SmartChargeScheduler()

    // 电价峰谷时段（简化版）
    struct PricePeriod {
        let startHour: Int
        let endHour: Int
        let rate: Double  // 元/kWh
        let type: String  // "peak", "valley", "offpeak"
    }

    private let pricePeriods = [
        PricePeriod(startHour: 8, endHour: 11, rate: 1.2, type: "peak"),      // 尖峰
        PricePeriod(startHour: 11, endHour: 15, rate: 0.8, type: "offpeak"),  // 平段
        PricePeriod(startHour: 15, endHour: 18, rate: 1.1, type: "peak"),     // 高峰
        PricePeriod(startHour: 18, endHour: 22, rate: 0.6, type: "valley"),   // 谷段
        PricePeriod(startHour: 22, endHour: 8,  rate: 0.4, type: "valley"),   // 深谷
    ]

    private init() {}

    /// 获取最佳充电时段建议
    func getBestChargeTime() -> ChargeRecommendation? {
        let now = Date()
        let calendar = Calendar.current
        let currentHour = calendar.component(.hour, from: now)

        // 找到当前电价时段
        let currentPeriod = pricePeriods.first { $0.startHour <= currentHour && currentHour < $0.endHour } ?? pricePeriods.last!

        // 找最便宜的时段
        let cheapestPeriod = pricePeriods.min(by: { $0.rate < $1.rate })!

        // 计算预计费用（假设充电30kWh）
        let chargeAmount = 30.0
        let estimatedCost = chargeAmount * cheapestPeriod.rate
        let savings = (currentPeriod.rate - cheapestPeriod.rate) / currentPeriod.rate * 100

        // 构建下次推荐时间
        let nextChargeTime = calendar.date(from: DateComponents(
            year: calendar.component(.year, from: now),
            month: calendar.component(.month, from: now),
            day: calendar.component(.day, from: now),
            hour: cheapestPeriod.startHour,
            minute: 0
        )) ?? now

        let reason = "谷电时段 (\(cheapestPeriod.startHour):00-\(cheapestPeriod.endHour):00) 电价最便宜，建议此时充电"

        return ChargeRecommendation(
            time: nextChargeTime,
            reason: reason,
            estimatedCost: estimatedCost,
            savingsPercent: Int(max(0, savings))
        )
    }

    /// 请求充电提醒通知权限
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

    /// 调度充电提醒
    func scheduleChargeReminder() async {
        let center = UNUserNotificationCenter.current()
        let items = await center.pendingNotificationRequests()

        // 清除旧提醒
        for item in items {
            center.removePendingNotificationRequests(withIdentifiers: [item.identifier])
        }

        // 创建新提醒
        let content = UNMutableNotificationContent()
        content.title = "💡 智能充电建议"
        content.body = "建议在 22:00-08:00 谷电时段充电，可节省约 30% 电费"
        content.sound = .default
        content.badge = 1

        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = 21  // 晚上9点提醒
        components.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: "charge_reminder", content: content, trigger: trigger)

        do {
            try await center.add(request)
        } catch {
            print("Failed to schedule charge reminder: \(error)")
        }
    }
}
