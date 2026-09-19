// =============================================================================
// N15-N20 智能通知管理器 — 充电提醒/胎压异常/保养提醒/行程摘要/充电完成/DND
// =============================================================================

import Foundation
import UserNotifications

enum NotificationType: String, CaseIterable {
    case chargeLow = "charge_low"
    case chargeFull = "charge_full"
    case tirePressure = "tire_pressure"
    case serviceDue = "service_due"
    case tripComplete = "trip_complete"
    case dndDriving = "dnd_driving"
    
    var soundName: String { "carkeeper_alert.aiff" }
    var category: String { rawValue }
}

class SmartNotificationManager: ObservableObject {
    static let shared = SmartNotificationManager()
    
    private let center = UNUserNotificationCenter.current()
    
    // 充电相关
    var chargeLowThreshold: Int = 20
    var chargeFullNotifyEnabled: Bool = true
    var chargeLowNotifyEnabled: Bool = true
    
    // 胎压相关
    var tirePressureAlertEnabled: Bool = true
    var tirePressureLowThreshold: Double = 2.0
    var tirePressureHighThreshold: Double = 3.2
    
    // 保养相关
    var serviceRemindersEnabled: Bool = true
    
    // DND 驾驶模式
    var dndEnabled: Bool = false
    var dndSpeedThreshold: Double = 30.0
    
    private init() {}
    
    func requestAuthorization() async -> Bool {
        do {
            try await center.requestAuthorization(options: [.alert, .sound, .badge])
            return true
        } catch {
            return false
        }
    }
    
    func registerCategories() {
        let chargeActions = [
            UNNotificationAction(identifier: "ACTION_CHARGE_NOW", title: "立即充电", options: [.foreground]),
            UNNotificationAction(identifier: "ACTION_CHARGE_LATER", title: "稍后充电", options: [.destructive])
        ]
        let tireAction = UNNotificationAction(identifier: "ACTION_CHECK_TIRES", title: "查看胎压", options: [.foreground])
        let dndAction = UNNotificationAction(identifier: "ACTION_TOGGLE_DND", title: "关闭勿扰", options: [])
        
        let chargeCategory = UNNotificationCategory(
            identifier: NotificationType.chargeLow.category,
            actions: chargeActions, intentIdentifiers: [],
            options: []
        )
        let tireCategory = UNNotificationCategory(
            identifier: NotificationType.tirePressure.category,
            actions: [tireAction], intentIdentifiers: [],
            options: []
        )
        let dndCategory = UNNotificationCategory(
            identifier: NotificationType.dndDriving.category,
            actions: [dndAction], intentIdentifiers: [],
            options: []
        )
        
        center.setNotificationCategories([chargeCategory, tireCategory, dndCategory])
    }
    
    func sendNotification(
        type: NotificationType,
        title: String,
        body: String,
        subtitle: String? = nil,
        userInfo: [String: Any] = [:]
    ) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if let sub = subtitle { content.subtitle = sub }
        content.categoryIdentifier = type.category
        content.sound = .default
        content.userInfo = userInfo
        
        let request = UNNotificationRequest(
            identifier: "\(type.rawValue)_\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        center.add(request)
    }
    
    // N15 智能充电提醒
    func checkChargeNotification(soc: Int?, charging: Bool?, lastCheck: Date?) {
        guard let soc = soc, !charging else { return }
        let fourHoursAgo = Date().addingTimeInterval(-4 * 3600)
        guard let last = lastCheck, last > fourHoursAgo else {
            sendNotification(
                type: .chargeLow,
                title: "电量不足",
                body: "剩余电量 \(soc)%，请及时充电",
                subtitle: "建议尽快补能",
                userInfo: ["action": "charge_now"]
            )
            UserDefaults.standard.set(Date(), forKey: "carkeeper_last_charge_alert")
            return
        }
    }
    
    // N19 充电完成通知
    func notifyChargeComplete(soc: Int, range: Int) {
        guard UserDefaults.standard.bool(forKey: "carkeeper_charge_complete_notify") else { return }
        sendNotification(
            type: .chargeFull,
            title: "充电完成",
            body: "已充满至 \(soc)%，续航约 \(range) km",
            userInfo: ["action": "charge_complete"]
        )
    }
    
    // N16 胎压异常推送
    func checkTirePressure(tirePressures: [String: Double]?) {
        guard let pressures = tirePressures, tirePressureAlertEnabled else { return }
        let anomalies = pressures.compactMap { name, pressure -> (name: String, pressure: Double)? in
            guard pressure < tirePressureLowThreshold || pressure > tirePressureHighThreshold else { return nil }
            return (name, pressure)
        }
        guard !anomalies.isEmpty else { return }
        let names = anomalies.map { $0.name }.joined(separator: "、")
        sendNotification(
            type: .tirePressure,
            title: "胎压异常",
            body: "\(names) 胎压异常，请检查轮胎",
            userInfo: ["anomalies": anomalies.map { "\($0.name):\($0.pressure)" }]
        )
    }
    
    // N17 保养到期双重提醒
    func checkServiceDue(nextDate: Date?) {
        guard let next = nextDate, serviceRemindersEnabled else { return }
        let cal = Calendar.current
        let sevenDays = cal.date(byAdding: .day, value: 7, to: Date())!
        let today = cal.startOfDay(for: Date())
        let nextDay = cal.startOfDay(for: next)
        
        if nextDay >= today && nextDay <= sevenDays {
            let daysLeft = cal.dateComponents([.day], from: Date(), to: next).day ?? 0
            sendNotification(
                type: .serviceDue,
                title: "保养提醒",
                body: "距离下次保养还有 \(daysLeft) 天，请提前预约",
                userInfo: ["action": "schedule_service", "daysLeft": daysLeft]
            )
        } else if nextDay == today {
            sendNotification(
                type: .serviceDue,
                title: "保养到期",
                body: "您的车辆已到保养日期，请尽快预约服务",
                userInfo: ["action": "schedule_service"]
            )
        }
    }
    
    // N18 行程结束摘要
    func notifyTripComplete(distanceKm: Double, energyKWh: Double, durationMin: Double, socStart: Int, socEnd: Int) {
        let savings = energyKWh * 0.6
        sendNotification(
            type: .tripComplete,
            title: "行程完成",
            body: "\(Int(distanceKm))km · \(String(format: "%.1f", energyKWh))kWh · ¥\(String(format: "%.2f", savings)) · \(Int(durationMin))分钟",
            userInfo: [
                "distance": distanceKm, "energy": energyKWh,
                "duration": durationMin, "socStart": socStart, "socEnd": socEnd
            ]
        )
    }
    
    // N20 DND 驾驶模式
    func enableDDrivingMode() {
        dndEnabled = true
        UserDefaults.standard.set(true, forKey: "carkeeper_dnd_mode")
        sendNotification(
            type: .dndDriving,
            title: "驾驶模式已开启",
            body: "您将不会收到非紧急通知",
            userInfo: ["action": "toggle_dnd"]
        )
    }
    
    func disableDDrivingMode() {
        dndEnabled = false
        UserDefaults.standard.set(false, forKey: "carkeeper_dnd_mode")
    }
}

// MARK: - AppStore 扩展
extension AppStore {
    var lastChargeAlertTime: Date? {
        get { UserDefaults.standard.object(forKey: "carkeeper_last_charge_alert") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "carkeeper_last_charge_alert") }
    }
    
    func checkNotificationsIfNeeded() {
        let notif = SmartNotificationManager.shared
        guard let car = car, let energy = car["energy"] as? [String: Any] else { return }
        
        let soc = energy["socPct"] as? Int ?? energy["soc_pct"] as? Int ?? 0
        let charging = energy["charging"] as? Bool ?? false
        
        notif.checkChargeNotification(soc: soc, charging: charging, lastCheck: lastChargeAlertTime)
        
        if let nextDate = UserDefaults.standard.object(forKey: "carkeeper_next_service_date") as? Date {
            notif.checkServiceDue(nextDate: nextDate)
        }
    }
}
