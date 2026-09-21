// =============================================================================
// Kansei.swift — 情感化设计令牌（Kansei = 感性）
// 为长安车管家注入温度与灵魂：时间感知配色 + 呼吸动效 + 触觉反馈
//
// ⚠️ 维护约定：本文件里的颜色构造函数一律写全 `SwiftUI.Color`。
//    原因：文件尾部用 `extension Kansei { enum Color { … } }` 提供了
//    `Kansei.Color.*` 兼容命名空间；嵌套类型 `Kansei.Color` 会在
//    `struct Kansei` 内部遮蔽 `SwiftUI.Color`，写成裸 `Color` 会被解析成
//    这个「没有 case 的枚举」，于是报 cannot be constructed / has no member。
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

// MARK: - Kansei design tokens
// 所有颜色令牌都是直接返回 SwiftUI.Color 的静态属性。
struct Kansei {
    // MARK: - Color tokens
    static let amber = SwiftUI.Color(red: 1.0, green: 0.62, blue: 0.0)
    static let amberDark = SwiftUI.Color(red: 0.85, green: 0.45, blue: 0.0)
    static let amberLight = SwiftUI.Color(red: 1.0, green: 0.82, blue: 0.4)
    static let deepBlack = SwiftUI.Color.black
    static let nightSurface = SwiftUI.Color(red: 0.06, green: 0.06, blue: 0.08)
    static let daySurface = SwiftUI.Color(red: 0.97, green: 0.97, blue: 0.98)
    static let success = SwiftUI.Color(red: 0.15, green: 0.85, blue: 0.45)
    static let warning = amber
    static let error = SwiftUI.Color(red: 1.0, green: 0.25, blue: 0.25)
    static let info = SwiftUI.Color(red: 0.2, green: 0.6, blue: 1.0)
    static let glassLight = SwiftUI.Color.white.opacity(0.08)
    static let glassBorder = SwiftUI.Color.white.opacity(0.12)
    static let glassHighlight = SwiftUI.Color.white.opacity(0.15)
    static let primary = SwiftUI.Color.white
    static let secondary = SwiftUI.Color.white.opacity(0.7)
    static let tertiary = SwiftUI.Color.white.opacity(0.4)
    static let fillSubtle = glassLight.opacity(0.5)

    static var ambient: SwiftUI.Color {
        switch TimeOfDay.current {
        case .dawn: return SwiftUI.Color(red: 1.0, green: 0.55, blue: 0.2)
        case .morning: return amber
        case .noon: return SwiftUI.Color(red: 0.9, green: 0.7, blue: 0.1)
        case .afternoon: return amberDark
        case .dusk: return SwiftUI.Color(red: 0.8, green: 0.3, blue: 0.2)
        case .night: return SwiftUI.Color(red: 0.3, green: 0.5, blue: 0.8)
        }
    }

    static var background: SwiftUI.Color {
        TimeOfDay.current == .night ? nightSurface : daySurface
    }

    static func statusColor(_ cls: String) -> SwiftUI.Color {
        switch cls {
        case "ok", "normal": return .green
        case "warn", "warning": return warning
        case "bad", "fault", "abnormal", "danger": return error
        case "charge", "charging": return info
        case "acc", "accent": return ambient
        default: return secondary
        }
    }

    // MARK: - Motion
    static var breathe: Animation {
        Animation.easeInOut(duration: 5.0).repeatForever(autoreverses: true)
    }
    static let tap = Animation.spring(response: 0.25, dampingFraction: 0.7)
    static let page = Animation.spring(response: 0.5, dampingFraction: 0.8)
    static let reveal = Animation.spring(response: 0.6, dampingFraction: 0.85)
    static let count = Animation.spring(response: 0.4, dampingFraction: 0.6)

    // MARK: - Haptic
    static func hapticSuccess() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func hapticError() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
    static func hapticWarning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    static func hapticPress() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func hapticSelect() { UISelectionFeedbackGenerator().selectionChanged() }
    static func hapticHeavy() { UIImpactFeedbackGenerator(style: .heavy).impactOccurred() }

    // MARK: - Spacing
    static let spacingXs = CGFloat(4)
    static let spacingSm = CGFloat(8)
    static let spacingMd = CGFloat(16)
    static let spacingLg = CGFloat(24)
    static let spacingXl = CGFloat(32)
    static let spacingXxl = CGFloat(48)
    static let spacingXxxl = CGFloat(64)
    static let spacingHuge = CGFloat(88)
    static let spacingPage = CGFloat(20)

    // MARK: - Radius
    static let radiusSmall = CGFloat(8)
    static let radiusMedium = CGFloat(16)
    static let radiusLarge = CGFloat(24)
    static let radiusPill = CGFloat(999)
}

// MARK: - Typography accessor
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
        self.background(Kansei.background)
    }
    func kanseiTint() -> some View {
        self.foregroundColor(Kansei.primary)
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
                withAnimation(Kansei.breathe) { animProgress = 1.0 }
            }
    }
}

// MARK: - Dotted-namespace compat（Kansei.Color.* / Spacing / Radius / Motion / Haptic）
//
// 这些命名空间只是别名，委托给上面的平坦令牌；新增令牌时两边都要加。
extension Kansei {
    enum Color {
        static var amber: SwiftUI.Color { Kansei.amber }
        static var amberDark: SwiftUI.Color { Kansei.amberDark }
        static var amberLight: SwiftUI.Color { Kansei.amberLight }
        static var deepBlack: SwiftUI.Color { Kansei.deepBlack }
        static var nightSurface: SwiftUI.Color { Kansei.nightSurface }
        static var daySurface: SwiftUI.Color { Kansei.daySurface }
        static var success: SwiftUI.Color { Kansei.success }
        static var warning: SwiftUI.Color { Kansei.warning }
        static var error: SwiftUI.Color { Kansei.error }
        static var info: SwiftUI.Color { Kansei.info }
        static var glassLight: SwiftUI.Color { Kansei.glassLight }
        static var glassBorder: SwiftUI.Color { Kansei.glassBorder }
        static var glassHighlight: SwiftUI.Color { Kansei.glassHighlight }
        static var primary: SwiftUI.Color { Kansei.primary }
        static var secondary: SwiftUI.Color { Kansei.secondary }
        static var tertiary: SwiftUI.Color { Kansei.tertiary }
        static var fillSubtle: SwiftUI.Color { Kansei.fillSubtle }
        static var ambient: SwiftUI.Color { Kansei.ambient }
        static var background: SwiftUI.Color { Kansei.background }
    }

    enum Spacing {
        static var xxs: CGFloat { 2 }
        static var xs: CGFloat { Kansei.spacingXs }
        static var sm: CGFloat { Kansei.spacingSm }
        static var md: CGFloat { Kansei.spacingMd }
        static var lg: CGFloat { Kansei.spacingLg }
        static var xl: CGFloat { Kansei.spacingXl }
        static var xxl: CGFloat { Kansei.spacingXxl }
        static var xxxl: CGFloat { Kansei.spacingXxxl }
        static var page: CGFloat { Kansei.spacingPage }
    }

    enum Radius {
        static var small: CGFloat { Kansei.radiusSmall }
        static var medium: CGFloat { Kansei.radiusMedium }
        static var large: CGFloat { Kansei.radiusLarge }
        static var pill: CGFloat { Kansei.radiusPill }
    }

    enum Motion {
        static var breathe: Animation { Kansei.breathe }
        static var tap: Animation { Kansei.tap }
        static var count: Animation { Kansei.count }
        static var page: Animation { Kansei.page }
        static var reveal: Animation { Kansei.reveal }
    }

    enum Haptic {
        static func select() { Kansei.hapticSelect() }
        static func tap() { Kansei.hapticPress() }
        static func success() { Kansei.hapticSuccess() }
        static func error() { Kansei.hapticError() }
        static func warning() { Kansei.hapticWarning() }
        static func heavy() { Kansei.hapticHeavy() }
    }
}
