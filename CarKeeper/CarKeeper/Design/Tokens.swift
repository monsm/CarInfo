// =============================================================================
// Tokens.swift — 设计令牌的唯一来源（Single Source of Truth）
// =============================================================================
//
// 本文件合并了此前四套重叠的令牌层：
//   1. `enum DS` 里的令牌子命名空间（Palette / Typo / Space / RadiusTokens / MotionTokens / Hair / SizeTokens）
//   2. `Kansei.swift` 的 Kansei* 命名空间（Palette / Spacing / Radius / Motion / Haptic / Typo）
//   3. `Theme` 里的令牌子命名空间（SpacingTokens / RadiusTokens / ShadowTokens / Spring / Duration）
//   4. `Theme` 本身的别名（brand/ok/warn/bad/charge/acc/na、h1…h4、d0…d5、mono、Colors…）
//
// 合并规则：
//   • 命名空间一律挂在**顶层类型**上（TokensXxx），不嵌套 —— 嵌套类型名会遮蔽外层同名符号，
//     历史上 `extension Kansei { enum Color { … } }` 就因此把 `SwiftUI.Color` 劫持掉了。
//     `TokensPalette` 里刻意裸写 `Color`：谁要是再往里嵌套一个 `Color`，本文件立刻编译失败。
//     `scan/shadowguard.py`（默认档 + --strict）会拦下这类形状。
//   • 刻度采用 Kansei 刻度：间距 md 16 / lg 24、圆角 medium 16 / large 24、字体 title 24。
//     原 DS 刻度（md 12 / lg 16）已按同名档位映射过来，因此间距整体变松是**有意的**。
//   • 只保留仍被引用的 DS 成员；DS.Palette 里那一批无引用的旧成员（hairline/tint/label… 已由
//     Kansei 色系与 `Theme.*` 别名取代）与 DS.Elev（全为 .clear 的占位）一并删除。
// =============================================================================
import SwiftUI
import UIKit

// MARK: - 时间感知配色

enum TimeOfDay {
    case dawn, morning, noon, afternoon, dusk, night

    static var current: TimeOfDay {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<8: return .dawn
        case 8..<12: return .morning
        case 12..<15: return .noon
        case 15..<18: return .afternoon
        case 18..<21: return .dusk
        default: return .night
        }
    }
}

// MARK: - 颜色令牌（单一来源）
//
// 两族并存是**有意的**，不是重复：
//   • ok/warn/bad/charge/canvas/surface/hairline… —— 系统语义色（跟随浅色/深色，和小组件共用 WT.Palette）
//   • success/warning/error/info/amber/primary… —— 固定 RGB 的情感色（深色表面、光带、状态强调）
// 两者取值不同、用途不同；合并成一族会把「自适应浅色/深色」这一能力丢掉。
enum TokensPalette {
    // ---- 系统语义色（与小组件共用同一份真值，见 Shared/WidgetTokens.swift）----
    /// 页面画布：systemGroupedBackground（亮 #F2F2F7 / 暗 #000）
    static let canvas = WT.Palette.canvas
    /// 一级分组表面：secondarySystemGroupedBackground（亮 #FFF / 暗 #1C1C1E）
    static let surface = WT.Palette.surface
    /// 光条 / 进度轨道
    static let track = WT.Palette.track
    static let labelOnTint = Color.white
    /// 车灯光带渐变（白 → 浅蓝 → 系统蓝），只出现在「电量就是光」的地方
    static let lightBar = WT.Palette.lightBar
    /// 兼容旧调用：平坦画布渐变（v4 只有一个画布，没有气氛渐变）
    static let canvasGradient = LinearGradient(
        colors: [canvas, canvas], startPoint: .top, endPoint: .bottom
    )

    // ---- 情感色（固定 RGB）----
    static let amber = Color(red: 1.0, green: 0.62, blue: 0.0)
    static let amberDark = Color(red: 0.85, green: 0.45, blue: 0.0)
    static let amberLight = Color(red: 1.0, green: 0.82, blue: 0.4)
    static let deepBlack = Color.black
    static let nightSurface = Color(red: 0.06, green: 0.06, blue: 0.08)
    static let daySurface = Color(red: 0.97, green: 0.97, blue: 0.98)
    static let success = Color(red: 0.15, green: 0.85, blue: 0.45)
    static let warning = amber
    static let error = Color(red: 1.0, green: 0.25, blue: 0.25)
    static let info = Color(red: 0.2, green: 0.6, blue: 1.0)
    static let glassLight = Color.white.opacity(0.08)
    static let glassBorder = Color.white.opacity(0.12)
    static let glassHighlight = Color.white.opacity(0.15)
    static let primary = Color.white
    static let secondary = Color.white.opacity(0.7)
    static let tertiary = Color.white.opacity(0.4)
    static let fillSubtle = glassLight.opacity(0.5)

    /// 时间感知主色调：清晨 / 正午 / 黄昏 / 夜里各有温度。
    static var ambient: Color {
        switch TimeOfDay.current {
        case .dawn: return Color(red: 1.0, green: 0.55, blue: 0.2)
        case .morning: return amber
        case .noon: return Color(red: 0.9, green: 0.7, blue: 0.1)
        case .afternoon: return amberDark
        case .dusk: return Color(red: 0.8, green: 0.3, blue: 0.2)
        case .night: return Color(red: 0.3, green: 0.5, blue: 0.8)
        }
    }

    static var background: Color {
        TimeOfDay.current == .night ? nightSurface : daySurface
    }

    /// 状态类名（ok / warn / charge…）→ 颜色。
    static func statusColor(_ cls: String) -> Color {
        switch cls {
        case "ok", "normal": return .green
        case "warn", "warning": return warning
        case "bad", "fault", "abnormal", "danger": return error
        case "charge", "charging": return info
        case "acc", "accent": return ambient
        default: return secondary
        }
    }
}

// MARK: - 间距（Kansei 刻度：4 的倍数，md 16 / lg 24）
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

// MARK: - 圆角（三档 + 胶囊）
enum TokensRadius {
    static let small = CGFloat(8)
    static let medium = CGFloat(16)
    static let large = CGFloat(24)
    static let pill = CGFloat(999)
}

// MARK: - 字号
//
// 两族并存同样是**有意的**：
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

    // ---- 固定尺寸标题（不随 Dynamic Type；Kansei 刻度）----
    static var hero: Font { Font.system(size: 48, weight: .light).monospacedDigit() }
    /// 24pt 半粗标题。旧名 `TokensTypo.heading` —— 让位给系统语义阶梯里的 `title`（28pt 且跟随字号）。
    static var heading: Font { Font.system(size: 24, weight: .semibold) }
    static var subtitle: Font { Font.system(size: 17, weight: .regular) }
    static var micro: Font { Font.system(size: 11, weight: .regular) }

    // ---- 仪表数字：等宽数字（换数不跳动）----
    /// 超大数字（首屏 SOC / 关键指标）：字重 100 是「仪器感」的来源
    static func display(_ size: CGFloat = 72) -> Font {
        .system(size: size, weight: .ultraLight).monospacedDigit()
    }
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
enum TokensMotion {
    static var breathe: Animation {
        Animation.easeInOut(duration: 5.0).repeatForever(autoreverses: true)
    }
    // ---- Kansei 刻度 ----
    static let tap = Animation.spring(response: 0.25, dampingFraction: 0.7)
    static let page = Animation.spring(response: 0.5, dampingFraction: 0.8)
    static let reveal = Animation.spring(response: 0.6, dampingFraction: 0.85)
    static let count = Animation.spring(response: 0.4, dampingFraction: 0.6)
    // ---- DS 刻度（反馈快、状态变化稳、不过冲）----
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
    /// 旧 `TokensHaptic.result(_:)`：一个布尔决定成功/失败反馈。
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

// MARK: - 情感化 View 扩展
extension View {
    func kanseiBackground() -> some View {
        self.background(TokensPalette.background)
    }
    func kanseiTint() -> some View {
        self.foregroundColor(TokensPalette.primary)
    }
    /// 呼吸动效：用于载入、充电等待这类「正在进行」的状态。
    func kanseiBreathe(opacity: Double = 1.0, scale: CGFloat = 1.1) -> some View {
        self.modifier(KanseiBreatheModifier(opacity: opacity, scale: scale))
    }
}

// MARK: - KanseiBreatheModifier
struct KanseiBreatheModifier: ViewModifier {
    var opacity: Double
    var scale: CGFloat
    @State private var animProgress: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .opacity(opacity * (0.5 + 0.5 * animProgress))
            .scaleEffect(animProgress * (scale - 1) + 1)
            .onAppear {
                withAnimation(TokensMotion.breathe) { animProgress = 1.0 }
            }
    }
}
