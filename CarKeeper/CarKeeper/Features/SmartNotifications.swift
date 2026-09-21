// =============================================================================
// E39-E44 智能通知升级
// =============================================================================

import SwiftUI
import UserNotifications
import CoreLocation

// MARK: - E39 地理围栏通知
class GeofenceNotificationManager: ObservableObject {
    static let shared = GeofenceNotificationManager()

    @Published var enabledLocations: [String: (lat: Double, lng: Double, name: String)] = [:]

    func scheduleGeofenceNotification(for name: String, lat: Double, lng: Double, radius: Double = 150) {
        let center = CLLocationCoordinate2D(latitude: lat, longitude: lng)
        let region = CLCircularRegion(center: center, radius: radius, identifier: name)
        region.notifyOnEntry = true
        region.notifyOnExit = true

        let content = UNMutableNotificationContent()
        content.title = "位置提醒"
        content.body = "您已\(region.notifyOnEntry ? "进入" : "离开") \(name)"
        content.sound = .default

        let request = UNNotificationRequest(identifier: "geofence_\(name)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

// MARK: - E40 充电前N分钟提醒
class PreChargeReminder: ObservableObject {
    static let shared = PreChargeReminder()

    func scheduleReminder(minutesBefore: Int, chargeCompleteTime: Date) {
        let triggerTime = chargeCompleteTime.addingTimeInterval(-Double(minutesBefore * 60))

        let content = UNMutableNotificationContent()
        content.title = "充电提醒"
        content.body = "将在\(minutesBefore)分钟后充满，请准备离店"
        content.sound = .default

        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: triggerTime)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(
            identifier: "charge_reminder_\(UUID().uuidString)",
            content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }
}

// MARK: - E41 恶劣天气预警
class WeatherAlertManager: ObservableObject {
    static let shared = WeatherAlertManager()

    @Published var activeAlerts: [WeatherAlert] = []

    func checkWeatherAlert() {
        // 简化实现：实际应调用天气API
        let alert = WeatherAlert(
            type: .rain,
            message: "预计未来2小时有降雨，请注意行车安全",
            timestamp: Date()
        )
        activeAlerts.append(alert)
    }
}

struct WeatherAlert: Identifiable {
    let id = UUID()
    let type: WeatherAlertType
    let message: String
    let timestamp: Date
}

enum WeatherAlertType {
    case rain, ice, highTemp, storm
    var icon: String {
        switch self {
        case .rain: return "cloud.rain.fill"
        case .ice: return "snowflake.fill"
        case .highTemp: return "sun.max.fill"
        case .storm: return "cloud.bolt.rain.fill"
        }
    }
}

// MARK: - E42 低电量路线规划
struct LowBatteryRoutePlan: View {
    let currentSOC: Int
    let nearbyStations: [ChargingStation]

    var body: some View {
        if nearbyStations.isEmpty {
            Text("附近暂无充电站")
                .frame(maxWidth: .infinity)
                .glassCard()
        } else {
            List(Array(nearbyStations.prefix(3))) { station in
                HStack {
                    Image(systemName: "bolt.fill")
                        .foregroundColor(.green)
                    VStack(alignment: .leading) {
                        Text(station.name)
                            .font(.subheadline)
                        Text("\(station.distance) km")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("导航") {}
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(TokensPalette.ambient)
                        .foregroundColor(TokensPalette.labelOnTint)
                        .cornerRadius(8)
                }
            }
        }
    }
}

struct ChargingStation: Identifiable {
    let id = UUID()
    let name: String
    let distance: Double // km
    let available: Bool
}

// MARK: - E43 定时提醒
class ScheduledReminderManager: ObservableObject {
    static let shared = ScheduledReminderManager()

    func scheduleDailyReport(hour: Int, minute: Int) {
        var components = DateComponents()
        components.hour = hour
        components.minute = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)

        let content = UNMutableNotificationContent()
        content.title = "每日车况简报"
        content.body = "您的车辆状态良好，SOC: 75%"
        content.sound = .default

        let request = UNNotificationRequest(identifier: "daily_report", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }
}

// MARK: - E44 通知分组
class NotificationGroupManager: ObservableObject {
    static let shared = NotificationGroupManager()

    func setupNotificationCategories() {
        let chargeCategory = UNNotificationCategory(
            identifier: "carkeeper_charge",
            actions: [
                UNNotificationAction(identifier: "acknowledge", title: "知道了", options: []),
            ],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        UNUserNotificationCenter.current().setNotificationCategories([chargeCategory])
    }
}
