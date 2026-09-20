// =============================================================================
//  ChargingActivityAttributes — 实时活动的数据契约
// =============================================================================
//  ⚠️ 这个类型必须被 **App 与小组件扩展同时编译**（project.yml 里两边都收了 Shared/）：
//    · App 侧用它 Activity.request / update / end
//    · 扩展侧用它 ActivityConfiguration(for:) 渲染锁屏与灵动岛
//  放在 App 里则扩展看不见，放在扩展里则 App 看不见 —— 两种都会导致实时活动永远不出现。
//
//  静态属性（attributes）= 整个活动生命周期内不变的值
//  动态属性（ContentState）= 每次 update 会变的值
// =============================================================================

import Foundation
import ActivityKit

struct ChargingActivityAttributes: ActivityAttributes {

    struct ContentState: Codable, Hashable {
        /// 剩余电量 %
        var soc: Int
        /// 剩余续航 km
        var rangeKm: Int
        /// 充电功率 kW（0 表示未上报）
        var powerKW: Double
        /// 预计充满（服务端已算好的可读文本）
        var timeToFull: String?
        /// 是否仍在充电（false = 已拔枪但活动还没结束）
        var charging: Bool
        /// 语义色分类：ok / charge / warn / bad / na（与 App 内同一套）
        var cls: String
        /// 数据时刻：界面上"更新于"用
        var updatedAt: Date

        var fraction: Double { max(0, min(1, Double(soc) / 100)) }
        var lowBattery: Bool { soc < 20 }
        var powerText: String {
            powerKW > 0.05 ? String(format: "%.1f kW", powerKW) : "--"
        }
    }

    /// 车牌 / 车辆名：活动期间不变，所以放静态属性
    var plate: String
    /// 开始充电的时刻：锁屏上用它显示充电时长
    var startedAt: Date
}
