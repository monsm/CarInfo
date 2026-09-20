// =============================================================================
// Kansei.swift — 情感化设计令牌（Kansei = 感性）
// 为长安车管家注入温度与灵魂：时间感知配色 + 呼吸动效 + 触觉反馈
// =============================================================================
import SwiftUI
import UIKit

// MARK: - 时间感知配色
enum TimeOfDay {
    case dawn    // 05:00-07:59
    case morning // 08:00-11:59
    case noon    // 12:00-14:59
    case afternoon // 15:00-17:59
    case dusk    // 18:00-20:59
    case night   // 21:00-04:59

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

struct Kansei {
    // MARK: - 品牌色（琥珀金 — 高端车机质感）
    enum Color {
        // 主色：琥珀金渐变
        static let amber = Color(red: 1.0, green: 0.62, blue: 0.0)     // #FF9F00
        static let amberDark = Color(red: 0.85, green: 0.45, blue: 0.0) // #D97300
        static let amberLight = Color(red: 1.0, green: 0.82, blue: 0.4) // #FFD266

        // 深色背景
        static let deepBlack = Color.black
        static let nightSurface = Color(red: 0.06, green: 0.06, blue: 0.08) // #0F0F14
        static let daySurface = Color(red: 0.97, green: 0.97, blue: 0.98)   // #F7F7FA

        // 语义色（高对比度，适合深色背景）
        static let success = Color(red: 0.15, green: 0.85, blue: 0.45)   // #26D873
        static let warning = amber
        static let error = Color(red: 1.0, green: 0.25, blue: 0.25)      // #FF4040
        static let info = Color(red: 0.2, green: 0.6, blue: 1.0)          // #3399FF

        // 玻璃材质色
        static let glassLight = Color.white.opacity(0.08)
        static let glassBorder = Color.white.opacity(0.12)
        static let glassHighlight = Color.white.opacity(0.15)

        // 文字色
        static let primary = Color.white
        static let secondary = Color.white.opacity(0.7)
        static let tertiary = Color.white.opacity(0.4)

        // 时间感知主色
        static var ambient: Color {
            let tod = TimeOfDay.current
            switch tod {
            case .dawn: return Color(red: 1.0, green: 0.55, blue: 0.2)    // 暖橙晨辉
            case .morning: return amber                                    // 琥珀金
            case .noon: return Color(red: 0.9, green: 0.7, blue: 0.1)     // 亮金
            case .afternoon: return amberDark                             // 深琥珀
            case .dusk: return Color(red: 0.8, green: 0.3, blue: 0.2)     // 暮光红橙
            case .night: return Color(red: 0.3, green: 0.5, blue: 0.8)    // 午夜蓝
            }
        }

        // 时间感知背景
        static var background: Color {
            let tod = TimeOfDay.current
            switch tod {
            case .night: return nightSurface
            default: return daySurface
            }
        }
    }

    // MARK: - 动效
    enum Motion {
        // 品牌呼吸动画（10秒周期）
        static var breathe: Animation {
            Animation.easeInOut(duration: 5.0)
                .repeatForever(autoreverses: true)
        }

        // 轻触反馈
        static let tap = Animation.spring(response: 0.25, dampingFraction: 0.7)

        // 页面切换
        static let page = Animation.spring(response: 0.5, dampingFraction: 0.8)

        // 数据入场
        static let reveal = Animation.spring(response: 0.6, dampingFraction: 0.85)

        // 数字滚动
        static let count = Animation.spring(response: 0.4, dampingFraction: 0.6)
    }

    // MARK: - 触觉
    enum Haptic {
        static func success() {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        static func error() {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
        static func warning() {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
        static func press() {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        static func select() {
            UISelectionFeedbackGenerator().selectionChanged()
        }
        static func heavyPress() {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        }
    }

    // MARK: - 排版
    enum Type {
        static let display = Font.system(size: 72, weight: .thin).monospacedDigit()
        static let hero = Font.system(size: 48, weight: .light).monospacedDigit()
        static let title = Font.system(size: 24, weight: .semibold)
        static let subtitle = Font.system(size: 17, weight: .regular)
        static let caption = Font.system(size: 13, weight: .regular)
        static let micro = Font.system(size: 11, weight: .regular)
    }

    // MARK: - 间距
    enum Spacing {
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
    enum Radius {
        static let small = CGFloat(8)
        static let medium = CGFloat(16)
        static let large = CGFloat(24)
        static let pill = CGFloat(999)
    }
}

// MARK: - 时间感知主题适配
extension View {
    /// 根据时间自动调整主色调
    func kanseiTint() -> some View {
        self.foregroundColor(Kansei.Color.primary)
    }

    /// 呼吸光效修饰符
    func kanseiBreathe(opacity: Double = 0.3, scale: CGFloat = 1.0) -> some View {
        self.modifier(KanseiBreatheModifier(opacity: opacity, scale: scale))
    }
}

// MARK: - DS.Palette / Theme 兼容别名（渐进迁移）
// 旧代码引用的 DS.Palette.* 和 Theme.* 全部重定向到 Kansei
enum DS {
    enum Palette {
        static let canvas = Kansei.Color.background
        static let surface = Kansei.Color.nightSurface
        static let surfaceRaised = Kansei.Color.nightSurface.opacity(0.6)
        static let surfaceSunken = Kansei.Color.glassLight
        static let hairline = Kansei.Color.glassBorder
        static let hairlineStrong = Kansei.Color.glassBorder
        static let track = Kansei.Color.glassBorder
        static let fill = Kansei.Color.glassLight
        static let fillSubtle = Kansei.Color.glassLight.opacity(0.5)
        static let label = Kansei.Color.primary
        static let labelSecondary = Kansei.Color.secondary
        static let labelTertiary = Kansei.Color.tertiary
        static let labelQuaternary = Kansei.Color.tertiary.opacity(0.6)
        static let labelOnTint = .white
        static let tint = Kansei.Color.ambient
        static let tintSoft = Kansei.Color.ambient.opacity(0.15)
        static let ok = Kansei.Color.success
        static let warn = Kansei.Color.warning
        static let bad = Kansei.Color.error
        static let charge = Kansei.Color.info
        static let lightBar = LinearGradient(
            colors: [.white, Kansei.Color.info.opacity(0.75), Kansei.Color.info],
            startPoint: .leading, endPoint: .trailing
        )
        static let canvasGradient = LinearGradient(colors: [canvas, canvas], startPoint: .top, endPoint: .bottom)
        static let heroFill = LinearGradient(
            colors: [surface, surface],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        static let onHero = Kansei.Color.primary
        static let onHeroSecondary = Kansei.Color.secondary
        static let onHeroTertiary = Kansei.Color.tertiary
        static let onHeroLine = Kansei.Color.glassBorder
    }
    enum Space {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
        static let xxxl: CGFloat = 64
        static let huge: CGFloat = 88
        static let page: CGFloat = Kansei.Spacing.page
        static let gap: CGFloat = Kansei.Spacing.lg
        static let cardPadding: CGFloat = Kansei.Spacing.md
        static let row: CGFloat = 44
    }
    enum Radius {
        static let small: CGFloat = Kansei.Radius.small
        static let card: CGFloat = Kansei.Radius.medium
        static let hero: CGFloat = Kansei.Radius.large
        static let capsule: CGFloat = Kansei.Radius.pill
    }
    enum Hair {
        static let line: CGFloat = 0.5
        static let border: CGFloat = 1
        static let inset: CGFloat = Kansei.Spacing.md
    }
    enum Motion {
        static let press = Kansei.Motion.tap
        static let value = Kansei.Motion.count
        static let screen = Kansei.Motion.page
        static let fade = Animation.easeOut(duration: 0.2)
        static let draw = Animation.spring(response: 0.5, dampingFraction: 0.7)
    }
    enum Size {
        static let tap: CGFloat = 44
        static let button: CGFloat = 50
        static let iconSm: CGFloat = 13
        static let icon: CGFloat = 17
        static let iconLg: CGFloat = 22
        static let tileIcon: CGFloat = 22
        static let iconColumn: CGFloat = 29
        static let barHeight: CGFloat = 56
    }
    enum Elev {
        static let card = Color.clear
        static let cardFar = Color.clear
        static let hero = Color.clear
    }
    enum Typo {
        static func display(_ size: CGFloat = 72) -> Font { .system(size: size, weight: .ultraLight).monospacedDigit() }
        static func metric(_ size: CGFloat = 34) -> Font { .system(size: size, weight: .light).monospacedDigit() }
        static let data = Font.system(size: 17).monospacedDigit()
        static let dataSmall = Font.system(size: 15).monospacedDigit()
        static func digits(_ size: CGFloat) -> Font { .system(size: size).monospacedDigit() }
        static let largeTitle = Font.largeTitle.weight(.bold)
        static let title = Font.title.weight(.semibold)
        static let title2 = Font.title2.weight(.semibold)
        static let title3 = Font.title3.weight(.semibold)
        static let headline = Font.headline
        static let body = Font.body
        static let callout = Font.callout
        static let subheadline = Font.subheadline
        static let footnote = Font.footnote
        static let caption = Font.caption
        static let caption2 = Font.caption2
        static let sectionLabel = Font.footnote
    }
    static func status(_ cls: String) -> Color {
        switch cls {
        case "ok", "normal": return .green
        case "warn", "warning": return Kansei.Color.warning
        case "bad", "fault", "abnormal", "danger": return Kansei.Color.error
        case "charge", "charging": return Kansei.Color.info
        case "acc", "accent": return Kansei.Color.ambient
        default: return Kansei.Color.secondary
        }
    }
    static func statusOnDark(_ cls: String) -> Color { DS.status(cls) }
}

enum Theme {
    enum Colors {
        static var accent: Color { Kansei.Color.ambient }
        static var brand: Color { Kansei.Color.ambient }
        static var brandLight: Color { Kansei.Color.amberLight }
        static var brandDark: Color { Kansei.Color.amberDark }
        static var background: Color { Kansei.Color.background }
        static var cardBg: Color { Kansei.Color.nightSurface }
        static var primary: Color { Kansei.Color.primary }
        static var secondary: Color { Kansei.Color.secondary }
        static var tertiary: Color { Kansei.Color.tertiary }
        static var border: Color { Kansei.Color.glassBorder }
        static var fill: Color { Kansei.Color.glassLight }
        static var ok: Color { Kansei.Color.success }
        static var warn: Color { Kansei.Color.warning }
        static var bad: Color { Kansei.Color.error }
        static var tint: Color { Kansei.Color.ambient }
        static var charge: Color { Kansei.Color.info }
    }
    enum Spacing {
        static let xs: CGFloat = Kansei.Spacing.xs
        static let sm: CGFloat = Kansei.Spacing.sm
        static let md: CGFloat = Kansei.Spacing.md
        static let lg: CGFloat = Kansei.Spacing.lg
        static let xl: CGFloat = Kansei.Spacing.xl
        static let xxl: CGFloat = Kansei.Spacing.xxl
        static let xxxl: CGFloat = Kansei.Spacing.xxl * 1.5
        static let hero: CGFloat = Kansei.Spacing.xxl
        static let page: CGFloat = Kansei.Spacing.page
        static let cardSpacing: CGFloat = Kansei.Spacing.lg
        static let cardPadding: CGFloat = Kansei.Spacing.md
        static let gridGap: CGFloat = Kansei.Spacing.sm
    }
    enum Radius {
        static let tiny: CGFloat = Kansei.Radius.small
        static let small: CGFloat = Kansei.Radius.small
        static let medium: CGFloat = Kansei.Radius.medium
        static let large: CGFloat = Kansei.Radius.large
        static let hero: CGFloat = Kansei.Radius.large
        static let ultra: CGFloat = Kansei.Radius.large
        static let full: CGFloat = 50
    }
    enum ColorSystem {
        static let background: Color = Kansei.Color.background
        static let cardBg: Color = Kansei.Color.nightSurface
        static let surfaceRaised: Color = Kansei.Color.nightSurface.opacity(0.6)
        static let overlay: Color = Kansei.Color.nightSurface
        static let glass: Color = Kansei.Color.nightSurface
        static let primary: Color = Kansei.Color.primary
        static let secondary: Color = Kansei.Color.secondary
        static let tertiary: Color = Kansei.Color.tertiary
        static let border: Color = Kansei.Color.glassBorder
        static let fill: Color = Kansei.Color.glassLight
        static let shadowLight: Color = .black.opacity(0.05)
        static let shadowMedium: Color = .black.opacity(0.08)
        static let shadowStrong: Color = .black.opacity(0.12)
    }
    enum Shadow {
        static let none = ShadowStyle(color: .clear, radius: 0, x: 0, y: 0)
        static let light = ShadowStyle(color: Kansei.Color.glassHighlight, radius: 4, x: 0, y: 1)
        static let medium = ShadowStyle(color: .black.opacity(0.08), radius: 10, x: 0, y: 3)
        static let strong = ShadowStyle(color: .black.opacity(0.12), radius: 18, x: 0, y: 6)
    }
    static var d1: Font { Kansei.Type.display }
    static var d2: Font { .system(size: 52, weight: .thin).monospacedDigit() }
    static var d3: Font { .system(size: 34, weight: .light).monospacedDigit() }
    static var d4: Font { .system(size: 26, weight: .light).monospacedDigit() }
    static var d5: Font { .system(size: 20, weight: .light).monospacedDigit() }
    static var h1: Font { .largeTitle }
    static var h2: Font { .title }
    static var h3: Font { .title3 }
    static var h4: Font { .headline }
    static var body: Font { .body }
    static var bodyMd: Font { .system(size: 15) }
    static var bodySm: Font { .subheadline }
    static var bodyLg: Font { .callout }
    static var caption: Font { .caption }
    static var footnote: Font { .footnote }
    static var micro: Font { .caption2 }
    static var mono: Font { .system(size: 15).monospacedDigit() }
    static var monoLg: Font { .system(size: 17).monospacedDigit() }
    static var d0: Font { .system(size: 42, weight: .thin).monospacedDigit() }
    static var d0b: Font { .system(size: 28, weight: .light).monospacedDigit() }
    static var heroNum: Font { .system(size: 52, weight: .thin).monospacedDigit() }
    static func font(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
    static func font(_ f: Font) -> Font { f }
    static func statusColor(_ cls: String) -> Color {
        switch cls {
        case "ok", "charge": return Kansei.Color.success
        case "warn": return Kansei.Color.warning
        case "bad": return Kansei.Color.error
        default: return Kansei.Color.secondary
        }
    }
    static var subheadline: Font { .subheadline }
    static func lineHeight(_ size: CGFloat) -> CGFloat {
        switch size {
        case 80, 52: return size * 1.1
        case 34, 28: return size * 1.15
        case 20, 17: return size * 1.29
        default: return size * 1.4
        }
    }
    enum Spring {
        static let responseBase: Double = 0.45
        static let dampingFraction: Double = 0.8
        static let duration: Double = 0.5
        static var standard: Animation {
            Animation.spring(response: responseBase,
                             dampingFraction: dampingFraction, blendDuration: duration)
        }
        static var quick: Animation { Animation.spring(response: 0.3, dampingFraction: 0.7, blendDuration: 0.25) }
        static var slow: Animation { Animation.spring(response: 0.6, dampingFraction: 0.9, blendDuration: 0.5) }
        static var smooth: Animation { Animation.easeInOut(duration: 0.35) }
    }
    enum Duration {
        static let instant: Double = 0.1
        static let fast: Double = 0.2
        static let normal: Double = 0.3
        static let slow: Double = 0.5
        static let springFast: Animation = Kansei.Motion.tap
        static let springNormal: Animation = Kansei.Motion.count
        static let springSlow: Animation = Kansei.Motion.page
    }
}

struct KanseiBreatheModifier: ViewModifier {
    var opacity: Double
    var scale: CGFloat
    @State private var animProgress: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .opacity(opacity * (0.5 + 0.5 * animProgress))
            .scaleEffect(animProgress * (scale - 1) + 1)
            .onAppear {
                withAnimation(Kansei.Motion.breathe) {
                    animProgress = 1.0
                }
            }
    }
}
