// =============================================================================
// #NEW-118 维保提醒订阅 — 基于里程/时间的维保周期提醒
// =============================================================================

import Foundation
import SwiftUI

enum ServiceType: String, CaseIterable, Codable {
    case oil = "机油保养"
    case filter = "空滤更换"
    case spark = "火花塞更换"
    case brake = "刹车片检查"
    case tire = "轮胎换位"
    case coolant = "冷却液更换"
    case inspection = "年检"

    var icon: String {
        switch self {
        case .oil: return "gearshape.fill"
        // 注：这几个名字原来都不存在（"humidity.fill" / "disc.fill" / "circle.fill"），
        // Image(systemName:) 会渲染成空白 —— 已换成真实存在的 symbol。
        case .filter: return "wind"
        case .spark: return "bolt.fill"
        case .brake: return "octagon.fill"
        case .tire: return "circle.dashed"
        case .coolant: return "drop.fill"
        case .inspection: return "doc.fill"
        }
    }
}

struct ServiceReminder: Identifiable, Codable {
    var id = UUID()
    let type: ServiceType
    var nextMileageKm: Double  // 下次保养里程
    var nextDate: Date         // 下次保养日期
    var lastMileageKm: Double  // 上次保养时里程
    var lastDate: Date         // 上次保养日期
    let notes: String
}

class ServiceReminderManager {
    static let shared = ServiceReminderManager()

    var reminders: [ServiceReminder] {
        if let data = UserDefaults.standard.data(forKey: "carkeeper_service_reminders"),
           let decoded = try? JSONDecoder().decode([ServiceReminder].self, from: data) {
            return decoded
        }
        return defaultReminders
    }

    func saveReminders(_ reminders: [ServiceReminder]) {
        if let data = try? JSONEncoder().encode(reminders) {
            UserDefaults.standard.set(data, forKey: "carkeeper_service_reminders")
        }
    }

    func addReminder(_ reminder: ServiceReminder) {
        var list = reminders
        list.append(reminder)
        saveReminders(list)
    }

    func completeService(_ id: UUID, currentMileage: Double, currentDate: Date) {
        var list = reminders
        if let idx = list.firstIndex(where: { $0.id == id }) {
            var r = list[idx]
            r.lastMileageKm = currentMileage
            r.lastDate = currentDate
            r.nextMileageKm = currentMileage + serviceIntervalMiles(r.type).km
            r.nextDate = Calendar.current.date(byAdding: .month, value: serviceIntervalMonths(r.type), to: currentDate) ?? currentDate
            list[idx] = r
            saveReminders(list)
        }
    }

    /// 获取即将到期的提醒（30天内或500km内）
    var upcomingReminders: [ServiceReminder] {
        let now = Date()
        let thirtyDays = Calendar.current.date(byAdding: .day, value: 30, to: now)!
        return reminders.filter { $0.nextDate <= thirtyDays }.sorted { $0.nextDate < $1.nextDate }
    }

    private var defaultReminders: [ServiceReminder] {
        let today = Date()
        let cal = Calendar.current
        return ServiceType.allCases.map { type in
            ServiceReminder(
                type: type,
                nextMileageKm: 10000 + Double(type.hashValue) * 5000,
                nextDate: cal.date(byAdding: .month, value: 6 + type.hashValue * 2, to: today)!,
                lastMileageKm: Double(type.hashValue) * 5000,
                lastDate: cal.date(byAdding: .month, value: -(6 + type.hashValue * 2), to: today)!,
                notes: ""
            )
        }
    }

    private func serviceIntervalMiles(_ type: ServiceType) -> (km: Double, months: Int) {
        switch type {
        case .oil: return (5000, 6)
        case .filter: return (10000, 12)
        case .spark: return (20000, 24)
        case .brake: return (15000, 18)
        case .tire: return (10000, 12)
        case .coolant: return (40000, 48)
        case .inspection: return (60000, 36)
        }
    }

    private func serviceIntervalMonths(_ type: ServiceType) -> Int {
        serviceIntervalMiles(type).months
    }
}

struct ServiceReminderRow: View {
    let reminder: ServiceReminder
    let currentMileage: Double
    var body: some View {
        let daysUntil = Calendar.current.dateComponents([.day], from: Date(), to: reminder.nextDate).day ?? 0
        let kmUntil = reminder.nextMileageKm - currentMileage
        let isUrgent = daysUntil <= 7 || kmUntil <= 500

        HStack(spacing: KanseiSpacing.sm) {
            Image(safeSymbol: reminder.type.icon, fallback: "wrench.and.screwdriver.fill")
                .font(.title2)
                .frame(width: 40, height: 40)
                .background(isUrgent ? Color.red.opacity(0.15) : Color.blue.opacity(0.15))
                .foregroundColor(isUrgent ? .red : .blue)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(reminder.type.rawValue)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(String(format: "距下次 %.0f km / %d 天", kmUntil, max(0, daysUntil)))
                    .font(.caption)
                    .foregroundColor(isUrgent ? .red : .secondary)
            }

            Spacer()

            Button("已完成") {
                // 触发完成操作
            }
            .font(.caption)
            .padding(.horizontal, KanseiSpacing.md)
            .padding(.vertical, Theme.SpacingTokens.xs)
            .background(isUrgent ? Color.orange : Color.blue.opacity(0.2))
            .foregroundColor(isUrgent ? .white : .blue)
            .cornerRadius(Theme.RadiusTokens.sm)
        }
        .glassCard()
        .padding(.vertical, Theme.SpacingTokens.xs)
    }
}
