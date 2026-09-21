// =============================================================================
// Kansei.swift — 情感化设计令牌（Kansei = 感性）
// 为长安车管家注入温度与灵魂：时间感知配色 + 呼吸动效 + 触觉反馈
//
// 结构约定（重要）：令牌一律挂在**顶层类型**上 ——
//   KanseiPalette / KanseiSpacing / KanseiRadius / KanseiMotion / KanseiHaptic / KanseiTypo
//
// 这里刻意不声明名为 `Kansei` 的类型，也不在任何类型里嵌套与 SDK 同名的类型。
// 历史事故：`extension Kansei { enum Color { … } }` 会在 `struct Kansei` 作用域内
// 遮蔽 `SwiftUI.Color`，于是裸写 `Color` 被解析成那个「没有 case 的枚举」，
// 满屏 cannot be constructed / has no member 'white'。
// 现在 `Kansei.X` 连编译都过不了；`KanseiPalette` 里也刻意裸写 `Color`——
// 谁要是再往里嵌套一个 `Color`，本文件会立刻编译失败（自带绊线）。
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
enum KanseiPalette {
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

// MARK: - 间距
enum KanseiSpacing {
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
}

// MARK: - 圆角
enum KanseiRadius {
    static let small = CGFloat(8)
    static let medium = CGFloat(16)
    static let large = CGFloat(24)
    static let pill = CGFloat(999)
}

// MARK: - 动效
enum KanseiMotion {
    static var breathe: Animation {
        Animation.easeInOut(duration: 5.0).repeatForever(autoreverses: true)
    }
    static let tap = Animation.spring(response: 0.25, dampingFraction: 0.7)
    static let page = Animation.spring(response: 0.5, dampingFraction: 0.8)
    static let reveal = Animation.spring(response: 0.6, dampingFraction: 0.85)
    static let count = Animation.spring(response: 0.4, dampingFraction: 0.6)
}

// MARK: - 触觉
enum KanseiHaptic {
    static func select() { UISelectionFeedbackGenerator().selectionChanged() }
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func error() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    static func heavy() { UIImpactFeedbackGenerator(style: .heavy).impactOccurred() }
}

// MARK: - 字体
enum KanseiTypo {
    static var display: Font { Font.system(size: 72, weight: .thin).monospacedDigit() }
    static var hero: Font { Font.system(size: 48, weight: .light).monospacedDigit() }
    static var title: Font { Font.system(size: 24, weight: .semibold) }
    static var subtitle: Font { Font.system(size: 17, weight: .regular) }
    static var caption: Font { .caption }
    static var caption2: Font { .caption2 }
    static var footnote: Font { .footnote }
    static var subheadline: Font { .subheadline }
    static var body: Font { .body }
    static var micro: Font { Font.system(size: 11, weight: .regular) }
}

// MARK: - View extensions for Kansei colors
extension View {
    func kanseiBackground() -> some View {
        self.background(KanseiPalette.background)
    }
    func kanseiTint() -> some View {
        self.foregroundColor(KanseiPalette.primary)
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
                withAnimation(KanseiMotion.breathe) { animProgress = 1.0 }
            }
    }
}
