
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
    var nextMileageKm: Double
    var nextDate: Date
    var lastMileageKm: Double
    var lastDate: Date
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


    private var defaultReminders: [ServiceReminder] {
        let today = Date()
        let cal = Calendar.current
        return ServiceType.allCases.map { type in
            let interval = serviceIntervalMiles(type)
            return ServiceReminder(
                type: type,
                nextMileageKm: interval.km,
                nextDate: cal.date(byAdding: .month, value: interval.months, to: today) ?? today,
                lastMileageKm: 0,
                lastDate: cal.date(byAdding: .month, value: -interval.months, to: today) ?? today,
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

}

