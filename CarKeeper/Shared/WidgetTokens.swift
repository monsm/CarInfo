// =============================================================================
//  WT — Widget / 实时活动与 App 共享的唯一设计令牌
// =============================================================================
//  为什么单独一份：小组件与实时活动是**独立扩展**，不编译 App 的 Design/DS.swift。
//  但「和 App 内是同一套排版与颜色」是硬要求，所以 v4 的令牌值只写在**这一处**，
//  扩展直接用 WT.*，App 的 TokensPalette 也从这里取 ——
//  两边由编译器保证不会漂移（改一个数，App 与小组件同时改）。
//
//  取值全部来自 iOS 真值（系统色 + iOS 字号阶梯），不是"设计手感"：
//    强调色 #007AFF /  #0A84FF（系统蓝）    语义色 = 系统绿橙红
//    画布 systemGroupedBackground            表面 secondarySystemGroupedBackground
//    发丝线 UIColor.separator                数字走超细字重 + 等宽（换数不跳动）
// =============================================================================

import SwiftUI
import UIKit

enum WT {

    // MARK: - 1. 颜色（Palette）

    enum Palette {
        /// 页面画布：systemGroupedBackground（亮 #F2F2F7 / 暗 #000）
        static let canvas = Color(uiColor: UIColor.systemGroupedBackground)
        /// 一级分组表面：secondarySystemGroupedBackground（亮 #FFF / 暗 #1C1C1E）
        static let surface = Color(uiColor: UIColor.secondarySystemGroupedBackground)
        /// 发丝分隔线：UIColor.separator 真值
        static let hairline = Color(uiColor: UIColor.separator)

        // ---- 文字：只有三档不透明度（label / 60% / 30%）----
        static let label = Color(uiColor: .label)
        static let labelSecondary = Color(uiColor: .secondaryLabel)
        static let labelTertiary = Color(uiColor: .tertiaryLabel)
        /// 光条 / 进度轨道
        static let track = Color(uiColor: .quaternaryLabel)

        // ---- 强调色（全局唯一）：iOS 系统蓝 ----
        static let tint = dynamic(
            light: (0.000, 0.478, 1.000),   // #007AFF
            dark: (0.039, 0.518, 1.000)     // #0A84FF
        )

        // ---- 语义状态色：界面里唯一的"彩色"来源 ----
        static let ok = dynamic(
            light: (0.204, 0.780, 0.349),   // #34C759
            dark: (0.188, 0.820, 0.345)     // #30D158
        )
        static let warn = dynamic(
            light: (1.000, 0.584, 0.000),   // #FF9500
            dark: (1.000, 0.624, 0.039)     // #FF9F0A
        )
        static let bad = dynamic(
            light: (1.000, 0.231, 0.188),   // #FF3B30
            dark: (1.000, 0.271, 0.227)     // #FF453A
        )
        /// 充电 / 电驱（EV 语义，不等于 ok）
        static let charge = dynamic(
            light: (0.000, 0.780, 0.745),
            dark: (0.400, 0.839, 1.000)
        )
        /// 铺在**彩色面之上**的文字色（小组件的彩色底、地图主面的深色）。
        /// 它在两种外观下都是白 —— 因为它站的那块底是彩色的，不是画布。
        /// （App 内对应的是 `TokensPalette.labelOnTint`，两者同名同义。）
        static let onAccent = Color.white

        /// 状态字符串 → 颜色（与 App 的 TokensPalette.statusColor 同一套判定）
        static func status(_ cls: String) -> Color {
            switch cls {
            case "ok", "normal": return ok
            case "warn", "warning": return warn
            case "bad", "fault", "abnormal", "danger": return bad
            case "charge", "charging": return charge
            case "acc", "accent": return tint
            default: return labelSecondary
            }
        }

        /// 光条渐变（白 → 浅蓝 → 强调色）：只在"电量就是光"的地方出现
        static let lightBar = LinearGradient(
            colors: [Color.white, Color(red: 0.612, green: 0.776, blue: 1.000), tint],
            startPoint: .leading,
            endPoint: .trailing
        )

        static func dynamic(
            light: (CGFloat, CGFloat, CGFloat),
            dark: (CGFloat, CGFloat, CGFloat)
        ) -> Color {
            Color(uiColor: UIColor { traits in
                traits.userInterfaceStyle == .dark
                ? UIColor(red: dark.0, green: dark.1, blue: dark.2, alpha: 1)
                : UIColor(red: light.0, green: light.1, blue: light.2, alpha: 1)
            })
        }
    }

    // MARK: - 2. 字体（Typo）— 与 TokensTypo 同名同值

    enum Typo {
        /// 仪表数字：超细字重 + 等宽。字重差是"仪器感"的来源，不靠颜色。
        /// 小组件的画布比手机屏小得多，所以只调**尺寸**（44/56），字重与等宽规则一致。
        static func display(_ size: CGFloat) -> Font {
            .system(size: size, weight: .ultraLight).monospacedDigit()
        }
        static func metric(_ size: CGFloat) -> Font {
            .system(size: size, weight: .light).monospacedDigit()
        }
        /// 指定尺寸的等宽数字：图例、次要读数这类「比 data(15) 还小但必须等宽」的地方
        static func data(_ size: CGFloat = 15) -> Font {
            .system(size: size).monospacedDigit()
        }
        /// 定尺文字（**不随 Dynamic Type**）：画布是固定几何（小组件、实时活动的圆形 Logo）时用。
        /// 与 App 侧的 `TokensTypo.fixed` 同名同义 —— 两边都只能从令牌文件里出尺寸。
        static func fixed(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
            .system(size: size, weight: weight)
        }

        // 文本：系统语义样式 → 自动跟随 Dynamic Type
        static let largeTitle = Font.largeTitle.weight(.bold)
        static let title3 = Font.title3.weight(.semibold)
        static let headline = Font.headline
        static let body = Font.body
        static let callout = Font.callout
        static let subheadline = Font.subheadline
        static let footnote = Font.footnote        // 13
        static let caption = Font.caption          // 12
        static let caption2 = Font.caption2        // 11
        /// 分组标题 / 标签（大写 + 字距由视图层加）
        static let sectionLabel = Font.caption
    }

    // MARK: - 3. 网格（与 TokensSpacing 同值）

    enum Space {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
        /// 小组件内边距（画布只有 155pt 宽，比页面 20pt 收一档）
        static let widget: CGFloat = 16
        /// 行高（HIG 最小触控目标）
        static let row: CGFloat = 44
    }

    // MARK: - 4. 圆角（只有三档 + 胶囊）

    /// 圆角令牌。`Tokens` 后缀是刻意保留的：通用词一旦成为嵌套类型名，就会在本作用域内
    /// 遮蔽将来可能出现的同名 SDK 类型（`Kansei.Color` 事故的同款；scan/shadowguard.py --strict 拦这种形状）。
    enum RadiusTokens {
        static let small: CGFloat = 8
        static let card: CGFloat = 12
        static let hero: CGFloat = 20
        static let capsule: CGFloat = 999
    }

    /// 车况页与小组件共用的深链（App 已注册 carkeeper:// scheme）
    enum DeepLink {
        /// 充电页（Tab 充电）：充电进度组件与实时活动的点击目标
        static let battery = URL(string: "carkeeper://battery")
        /// 车辆档案：状态组件的点击目标
        static let vehicle = URL(string: "carkeeper://vehicle")
    }
}

// =============================================================================
// MARK: - 车辆快照（App → 小组件 / 实时活动的唯一数据契约）
// =============================================================================
//  为什么不用 7 个零散键：键名写错不会报错，只会安静地显示 0。
//  一个 Codable 结构体 + 一个键，两端由编译器对齐字段。
//  ⚠️ 字段一旦发布不要删改类型，只能新增（旧版本 App 与旧小组件可能同时在跑）。
// =============================================================================

struct VehicleSnapshot: Codable, Equatable {
    var soc: Int = 0
    var rangeKm: Int = 0
    var cabinTemp: String = "--"
    var locked: Bool = true
    var charging: Bool = false
    var chargePower: Double? = nil
    var timeToFull: String? = nil
    var offline: Bool = false
    var mileageKm: Int = 0
    /// 语义色分类：ok / charge / warn / bad / na（与 App 的 e.chargeCls 同一套）
    var chargeCls: String = "na"
    var updatedAt: Date = .distantPast
    // 车辆位置（单位：度，GCJ-02 坐标系，与车端报文一致）
    var lat: Double? = nil
    var lng: Double? = nil

    var fraction: Double { max(0, min(1, Double(soc) / 100)) }
    var lowBattery: Bool { soc < 20 }
    /// 是否真的拿到过数据。
    /// ⚠️ 取不到数据时界面要显示"尚未同步"，**不能展示占位数据** ——
    /// 侧载 / 没有 App Group 能力时同步不到，那时显示一个假的 68% 比空白更坏。
    var hasData: Bool { updatedAt != .distantPast }
    var powerText: String {
        guard let p = chargePower, p > 0.05 else { return "--" }
        return String(format: "%.1f kW", p)
    }
    /// 充电中且电量偏低 → 用 bad，其余走 charge/ok
    var chargingCls: String {
        if !charging { return lowBattery ? "warn" : "na" }
        return lowBattery ? "warn" : "charge"
    }

    /// 除时间戳外内容是否一致。
    /// ⚠️ 不能拿整个结构体做相等判断：`updatedAt` 每次都变，
    /// 那会让"内容没变"永远判定为"变了"，直接把小组件的刷新预算烧光。
    func sameData(as other: VehicleSnapshot) -> Bool {
        soc == other.soc
            && rangeKm == other.rangeKm
            && cabinTemp == other.cabinTemp
            && locked == other.locked
            && charging == other.charging
            && chargePower == other.chargePower
            && timeToFull == other.timeToFull
            && offline == other.offline
            && mileageKm == other.mileageKm
            && chargeCls == other.chargeCls
            && lat == other.lat
            && lng == other.lng
    }

    /// 占位数据（组件库预览、以及还没同步过数据时的兜底）
    static let placeholder = VehicleSnapshot(
        soc: 68, rangeKm: 320, cabinTemp: "22℃", locked: true, charging: true,
        chargePower: 12.4, timeToFull: "1 小时 10 分", offline: false,
        mileageKm: 24860, chargeCls: "charge", updatedAt: Date(), lat: 30.52, lng: 114.23
    )
}

// =============================================================================
// MARK: - App Group 读写（App 与扩展共用）
// =============================================================================

enum SharedStore {
    /// ⚠️ 必须与 entitlements / project.yml / WatchApp 完全一致
    static let appGroupId = "group.com.you.CarKeeper"
    static let snapshotKey = "snapshot_v1"

    /// 没有 App Group 能力（未签名 / 侧载重签）时退回本 App 的 UserDefaults：
    /// 不会崩，只是不共享 —— 与 AppStore 里原来的注释同一套取舍。
    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupId) ?? .standard
    }

    /// 写入快照。返回值表示**内容是否发生了有意义的变化**（时间戳不算），
    /// 调用方据此决定要不要刷新小组件 / 动实时活动：
    /// 车况每 60 秒轮询一次，无条件刷新会把小组件的刷新预算（每天只几十次）用完。
    /// 快照本身**每次都写**：小组件下次自然刷新时能读到最新的同步时间。
    @discardableResult
    static func write(_ snapshot: VehicleSnapshot) -> Bool {
        let previous = read()
        let changed = previous.map { !$0.sameData(as: snapshot) } ?? true
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .secondsSince1970
        if let data = try? enc.encode(snapshot) {
            defaults.set(data, forKey: snapshotKey)
        }
        return changed
    }

    /// 退出登录时清掉快照：
    /// App Group 是共享容器，不清理会把上一个账号的车辆数据留在小组件上（隐私问题，不是美观问题）。
    static func clear() {
        defaults.removeObject(forKey: snapshotKey)
    }

    static func read() -> VehicleSnapshot? {
        let d = defaults
        guard let data = d.data(forKey: snapshotKey) else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .secondsSince1970
        return try? dec.decode(VehicleSnapshot.self, from: data)
    }
}
