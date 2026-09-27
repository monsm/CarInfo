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

    //  `saveReminders` / `addReminder` / `completeService` 三个写入器已删
    //  （2026-09-26 第三十一轮审核）：**全仓零个调用点**。
    //  这条链的后果比「多三行死码」重：`carkeeper_service_reminders` 这个键
    //  因此**从来没有被写过** —— 上面 `reminders` 读到的永远是 `defaultReminders`
    //  （出厂周期表）。界面上的「上次/下次保养」是**别的**来源（车厂计划的字段
    //  加本机那一对里程键，见 `AppStore.maintenancePlan`），与这份提醒表不是同一件事。
    //  ⚠️ 反过来说清楚：**「这保养做完了」这个动作在全 App 没有入口**。
    //  要把它做出来，是接一个调用点（一句确认 + 一次 `completeService`），
    //  不是把这三行留着 —— 留着只会让读的人以为已经有人在做这件事。

    /// 默认维保周期（用户还没有任何记录时的那份底）。
    ///
    /// **曾经用 `ServiceType.hashValue` 参与算术**，而 `hashValue` 是**每进程随机种子**
    /// （既不是固定值，也不是枚举序号）：
    ///   · `6 + hashValue * 2` 经常直接**整数溢出** → 进程 SIGTRAP；
    ///   · 就算没溢出，`date(byAdding: .month, value: 4.6e18)` 也返回 nil，
    ///     而代码用了 `!` → 同样炸。
    ///
    /// 2026-09-23 的真机崩溃报告就是这条（`EXC_BREAKPOINT`，栈：
    /// `VehicleTipsSection.body → tips → ServiceReminderManager.reminders → defaultReminders`
    /// —— 那张卡 2026-09-27 已删，这条栈是真机报告里的原文，一字未改）：
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

    //  `serviceIntervalMonths(_:)` 随着它唯一的调用者（`completeService`，上面那段）
    //  一起删（2026-09-26 第三十一轮审核）。同一条周期表的 `.months` 那一半仍在上面的
    //  元组里（`defaultReminders` 用得到）—— 删的是包一层的那两行，不是周期表本身。
}

