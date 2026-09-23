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

    /// 默认维保周期（用户还没有任何记录时的那份底）。
    ///
    /// **曾经用 `ServiceType.hashValue` 参与算术**，而 `hashValue` 是**每进程随机种子**
    /// （既不是固定值，也不是枚举序号）：
    ///   · `6 + hashValue * 2` 经常直接**整数溢出** → 进程 SIGTRAP；
    ///   · 就算没溢出，`date(byAdding: .month, value: 4.6e18)` 也返回 nil，
    ///     而代码用了 `!` → 同样炸。
    ///
    /// 2026-09-23 的真机崩溃报告就是这条（`EXC_BREAKPOINT`，栈：
    /// `VehicleTipsSection.body → tips → ServiceReminderManager.reminders → defaultReminders`）：
    /// 它把「切到车辆档」变成了一次闪退。注意它崩在**默认值**上 ——
    /// 只要用户没存过提醒（也就是绝大多数人），进那一档就必崩。
    ///
    /// 现在默认值**全是确定的**：每个类型用它自己的周期表（`serviceIntervalMiles`），
    /// 上次保养 = 今天往前一个周期，下次 = 今天往后一个周期，里程从 0 起算 ——
    /// 不编数据（hashValue 那版会给出 4.6e19 km 这种数字），也不做任何会崩的计算。
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

    private func serviceIntervalMonths(_ type: ServiceType) -> Int {
        serviceIntervalMiles(type).months
    }
}

