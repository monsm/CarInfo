// =============================================================================
// Tokens.swift — 设计令牌的唯一来源（Single Source of Truth）
// =============================================================================
//
// v4 · iOS 原生语言（最终方向）
//
// 三条取值原则（按优先级）：
//   1. 能用系统语义值的，绝不自造：颜色、字号、分隔线、圆角都取 iOS 真值。
//      `WT.Palette`（Shared/WidgetTokens.swift）是同一套值的世界面副本，
//      小组件 / 实时活动与 App 由编译器保证不漂移 —— App 侧一律从这里转发。
//   2. 强调色全局唯一（系统蓝）。旧的「时间感知琥珀金」已整体废弃：
//      一个 App 同时挂两套强调色，等于没有强调色。
//   3. 文字只有三档（label / 60% / 30%），且必须**跟随浅色/深色** ——
//      旧值把 primary/secondary/tertiary 写成固定白色，浅色模式下不可读。
//
// 结构约定：命名空间一律挂在顶层类型上（TokensXxx），不嵌套 ——
// 历史上把泛用名嵌进项目命名空间，结果把 SwiftUI 的 `Color` 劫持掉了；
// `scan/shadowguard.py`（默认档 + --strict）会拦下这类形状。
//
// 已废弃并删除（含各自的调用点迁移）：
//   TimeOfDay / ambient 时间感知色系、amber 家族、deepBlack / daySurface、
//   呼吸动效（TokensMotion.breathe / kanseiBreathe）—— v4 规定：
//   界面里所有会动、会发光的东西都必须对应一个真实状态。
//
// v5 · 可切换的艺术主题（ArtTheme.swift）：
//   下面的颜色值不再直接写死，而是从**当前主题**读（ArtThemeStore.spec）。
//   `.native` 主题的取值与 v4 逐值相同 —— 默认不切换时界面与之前完全一致。
//   换主题 = 换值，不是换名字：全 App 的调用点（`TokensPalette.accent` 之类）一行不改。
//   重绘由 CarKeeperApp 的 root 上的 `.id(主题)` 触发（静态计算值本身不产生依赖）。
// =============================================================================
import SwiftUI
import UIKit

// MARK: - 颜色令牌（单一来源）
enum TokensPalette {
    /// 当前主题的全部取值。**唯一读取点** —— 下面每个颜色都从这里转发。
    /// （计算属性，无可变静态存储：不引入并发风险。）
    static var spec: ArtThemeSpec { ArtThemeStore.spec }

    // ---- 表面 ----
    /// 页面画布（原生主题 = systemGroupedBackground，亮 #F2F2F7 / 暗 #000）
    static var canvas: Color { spec.canvas }
    /// 一级分组表面（原生主题 = secondarySystemGroupedBackground）
    static var surface: Color { spec.surface }
    /// 内凹 / 抬升表面
    static var raised: Color { spec.raised }
    /// 发丝分隔线
    static var hairline: Color { spec.hairline }
    /// 光条 / 进度轨道
    static var track: Color { spec.track }
    /// 铺在强调色之上的文字色。**不是全局常量** —— 琥珀底配白字不可读（1.9:1）。
    static var labelOnTint: Color { spec.onAccent }
    /// 光从哪来（原生/夜光 = 暖白，纸上 = 朱红，巨字 = 近白）。
    /// 用在「电量就是光」的光条起点、以及光池/光晕——**不要再用写死的 Color.white**：
    /// 纸上主题里它是朱红，白色会在纸面上戳出一个洞。
    static var lightSource: Color { spec.lightSource }
    /// 车灯光带渐变（原生主题 = 白 → 浅蓝 → 系统蓝）：只在「电量就是光」的地方出现
    static var lightBar: LinearGradient {
        LinearGradient(colors: spec.lightBar, startPoint: .leading, endPoint: .trailing)
    }
    /// 平坦画布渐变（滚动背景用）。v4 只有一个画布，没有氛围渐变。
    static var canvasGradient: LinearGradient {
        LinearGradient(colors: [canvas, canvas], startPoint: .top, endPoint: .bottom)
    }

    // ---- 文字三档 ----
    static var primary: Color { spec.label }
    static var secondary: Color { spec.labelSecondary }
    static var tertiary: Color { spec.labelTertiary }

    // ---- 强调色（每个主题只有一个）----
    static var accent: Color { spec.accent }
    /// 兼容旧调用名的别名。**不再是时间感知色** —— 金色方案已整体废弃。
    static var ambient: Color { accent }

    // ---- 语义状态色（界面上唯一的「彩色」来源）----
    static var success: Color { spec.success }
    static var warning: Color { spec.warning }
    static var error: Color { spec.error }
    /// 充电 / 电驱（EV 语义，不等于 success）
    static var info: Color { spec.info }

    // ---- 兼容名（历史调用点保留）----
    /// 旧名：夜间表面。v4 只有「系统表面」一种，跟随主题。
    static var nightSurface: Color { spec.surface }
    /// 页面底色（旧名）
    static var background: Color { canvas }
    /// 浅填充（输入框、未选中的底）。
    /// 原来这里是写死的 `Color(uiColor: .quaternarySystemFill)` —— 于是所有输入框
    /// 在四套主题里都是同一块系统灰。现在它读主题（原生主题的值与原来逐值相同）。
    static var fillSubtle: Color { spec.fillSubtle }
    /// 兼容旧名：`glassLight` 与 `fillSubtle` 本来**是同一个值**（重复声明），
    /// 合成一个取值、保留两个名字，等于让 ~30 处调用点零改动地跟随主题。
    static var glassLight: Color { spec.fillSubtle }
    static var glassBorder: Color { spec.hairline }
    /// 浮层高光边。原来写死 `Color.white.opacity(0.15)`。
    static var glassHighlight: Color { spec.glassHighlight }

    /// 状态类名（ok / warn / charge…）→ 颜色。
    /// 原生主题下与小组件的 `WT.Palette.status(_:)` 逐个等价（同一套判定），
    /// 换成艺术主题时改走主题的语义色。
    static func statusColor(_ cls: String) -> Color {
        switch cls {
        case "ok", "normal": return success
        case "warn", "warning": return warning
        case "bad", "fault", "abnormal", "danger": return error
        case "charge", "charging": return info
        case "acc", "accent": return accent
        default: return secondary
        }
    }

    /// 这套主题允不允许"光"（发光 / 光晕）。纸上不允许 —— 纸张没有发光。
    static var allowsGlow: Bool { spec.allowsGlow }
    /// 标题是不是走宋体（印刷物的做法）
    static var usesSerifTitles: Bool { spec.usesSerifTitles }
    /// 画布装饰（光池 / 纸纹 / 发丝网格）
    static var decor: CanvasDecor { spec.decor }
}

// MARK: - 间距（4 的倍数，页面边距 20）
enum TokensSpacing {
    static let xxs = CGFloat(2)
    static let xs = CGFloat(4)
    static let sm = CGFloat(8)
    static let md = CGFloat(16)
    static let lg = CGFloat(24)
    static let xl = CGFloat(32)
    static let xxl = CGFloat(48)
    static let xxxl = CGFloat(64)
    static let huge = CGFloat(88)
    static let page = CGFloat(20)
    /// HIG 最小触控目标（不是间距刻度的一档，故不参与缩放）
    static let row = CGFloat(44)
}

// MARK: - 圆角（与小组件 WT.RadiusTokens 同值）
enum TokensRadius {
    static let small = CGFloat(8)
    /// inset-grouped 分组面
    static let medium = CGFloat(12)
    /// 大面（hero / sheet）
    static let large = CGFloat(20)
    static let pill = CGFloat(999)
}

// MARK: - 字号
//
// 两族并存是**有意的**：
//   • 系统语义阶梯（largeTitle/title/body/footnote…）跟随 Dynamic Type，是正文骨架
//   • 固定尺寸字体（hero/heading/subtitle/micro 与仪表数字 display/metric/data…）不随字号缩放，
//     用于「数字不跳动、版式不位移」的场景
enum TokensTypo {
    // ---- 系统语义阶梯（跟随 Dynamic Type）----
    static let largeTitle = Font.largeTitle.weight(.bold)      // 34 / 700
    static let title = Font.title.weight(.semibold)            // 28 / 600
    static let title2 = Font.title2.weight(.semibold)          // 22 / 600
    static let title3 = Font.title3.weight(.semibold)          // 20 / 600
    static let headline = Font.headline                        // 17 / 600
    static let body = Font.body                                // 17 / 400
    static let callout = Font.callout                          // 16
    static let subheadline = Font.subheadline                  // 15
    static let footnote = Font.footnote                        // 13
    static let caption = Font.caption                          // 12
    static let caption2 = Font.caption2                        // 11
    /// 分组标题（iOS 的 section header：13pt、二级灰、大写由视图层加）
    static let sectionLabel = Font.footnote

    // ---- 固定尺寸标题（不随 Dynamic Type）----
    static var hero: Font { Font.system(size: 48, weight: .light).monospacedDigit() }
    /// 24pt 半粗标题。旧名 `TokensTypo.heading` —— 让位给系统语义阶梯里的 `title`（28pt 且跟随字号）。
    static var heading: Font { Font.system(size: 24, weight: .semibold) }
    static var subtitle: Font { Font.system(size: 17, weight: .regular) }
    static var micro: Font { Font.system(size: 11, weight: .regular) }

    // ---- 仪表数字：等宽数字（换数不跳动）----
    /// 超大数字（首屏 SOC / 关键指标）：**字重差**是「仪器感」的来源 ——
    /// 超细字重 + 负字距（字距在 DSBigNumber 里加），不靠颜色、不靠发光。
    static func display(_ size: CGFloat = 72) -> Font {
        .system(size: size, weight: ArtThemeStore.spec.displayWeight).monospacedDigit()
    }
    /// 超大数字的字距（不随 Dynamic Type 的那一档）。
    /// 原生 −0.5（几乎看不出）、巨字 −1.8（字号越大越要收紧，否则数字会散开）。
    static var displayTracking: CGFloat { ArtThemeStore.spec.displayTracking }
    /// 中等数字（页面头部大数值）
    static func metric(_ size: CGFloat = 34) -> Font {
        .system(size: size, weight: .light).monospacedDigit()
    }
    /// 行内数字（列表数值，iOS 正文尺寸）
    static let data = Font.system(size: 17).monospacedDigit()
    static let dataSmall = Font.system(size: 15).monospacedDigit()
    /// 指定尺寸的等宽数字：图例、次要读数这类「比 dataSmall 还要小但必须等宽」的地方。
    /// ⚠️ data / dataSmall 是**属性**（固定尺寸），digits 是**函数**（带尺寸参数）——
    /// 写成 TokensTypo.data(13) 会编译报错（cannot call value of non-function type 'Font'）。
    static func digits(_ size: CGFloat) -> Font {
        .system(size: size).monospacedDigit()
    }
}

// MARK: - 动效（只服务状态变化）
//
// v4 规则：没有涟漪、没有光晕、没有扫光、没有呼吸、没有粒子。
// 常驻运动只有一个 —— 充电时能量沿电缆流动（它本来就在流，见 DSLightBar 的 glow）。
// 其余全是一次性：入场（reveal）、数值变化（value）、绘制（draw）。
enum TokensMotion {
    static let tap = Animation.spring(response: 0.25, dampingFraction: 0.7)
    static let page = Animation.spring(response: 0.5, dampingFraction: 0.8)
    static let reveal = Animation.spring(response: 0.6, dampingFraction: 0.85)
    static let count = Animation.spring(response: 0.4, dampingFraction: 0.6)
    static let press = Animation.spring(response: 0.30, dampingFraction: 0.86)
    static let value = Animation.spring(response: 0.36, dampingFraction: 0.88)
    static let screen = Animation.spring(response: 0.42, dampingFraction: 0.90)
    static let fade = Animation.easeOut(duration: 0.20)
    /// 一次性绘制（光条从 0 长到位）
    static let draw = Animation.easeOut(duration: 1.1)
}

// MARK: - 触觉
enum TokensHaptic {
    static func select() { UISelectionFeedbackGenerator().selectionChanged() }
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func error() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    static func heavy() { UIImpactFeedbackGenerator(style: .heavy).impactOccurred() }
    /// 一个布尔决定成功/失败反馈。
    /// 参数命名避开 `success`，否则会遮蔽同名的静态方法。
    static func result(_ ok: Bool) {
        if ok { success() } else { error() }
    }
}

// MARK: - 发丝线（1px 级别的边框与内缩，不是间距刻度）
enum TokensHair {
    /// 发丝线（iOS 分隔线厚度）
    static let line: CGFloat = 0.5
    static let border: CGFloat = 1
    /// 分隔线内缩（与行内容左对齐）
    static let inset: CGFloat = 16
}

// MARK: - 尺寸（触控目标与图标，不是间距刻度）
enum TokensSize {
    static let tap: CGFloat = 44
    /// 主按钮（iOS 实心胶囊）
    static let button: CGFloat = 50
    static let iconSm: CGFloat = 13
    static let icon: CGFloat = 17
    static let iconLg: CGFloat = 22
    static let tileIcon: CGFloat = 22
    /// 行内图标列宽（iOS 设置行）
    static let iconColumn: CGFloat = 29
    static let barHeight: CGFloat = 56
}
