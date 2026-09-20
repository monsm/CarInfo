// =============================================================================
// Kansei.swift — 情感化设计令牌（Kansei = 感性）
// 为长安车管家注入温度与灵魂：时间感知配色 + 呼吸动效 + 触觉反馈
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
// All color tokens are direct static properties returning SwiftUI.Color
struct Kansei {
    // MARK: - Color tokens
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

    // MARK: - Typography (backtick to avoid Swift Type expression conflict)
    static var `Type`: KanseiTypo { KanseiTypo() }

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
struct KanseiTypo {
    var display: Font { Font.system(size: 72, weight: .thin).monospacedDigit() }
    var hero: Font { Font.system(size: 48, weight: .light).monospacedDigit() }
    var title: Font { Font.system(size: 24, weight: .semibold) }
    var subtitle: Font { Font.system(size: 17, weight: .regular) }
    var caption: Font { .caption }
    var footnote: Font { .footnote }
    var subheadline: Font { .subheadline }
    var micro: Font { Font.system(size: 11, weight: .regular) }
}

// MARK: - View extensions for Kansei colors
extension View {
    func kanseiBackground() -> some View {
        self.background(Kansei.background)
    }
    func kanseiTint() -> some View {
        self.foregroundColor(Kansei.primary)
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

// MARK: - DS.Palette / Theme compat aliases
enum DS {
    enum Palette {
        static let canvas = Kansei.background
        static let surface = Kansei.nightSurface
        static let surfaceRaised = Kansei.nightSurface.opacity(0.6)
        static let surfaceSunken = Kansei.glassLight
        static let hairline = Kansei.glassBorder
        static let hairlineStrong = Kansei.glassBorder
        static let track = Kansei.glassBorder
        static let fill = Kansei.glassLight
        static let fillSubtle = Kansei.fillSubtle
        static let label = Kansei.primary
        static let labelSecondary = Kansei.secondary
        static let labelTertiary = Kansei.tertiary
        static let labelQuaternary = Kansei.tertiary.opacity(0.6)
        static let labelOnTint: Color = .white
        static let tint = Kansei.ambient
        static let tintSoft = Kansei.ambient.opacity(0.15)
        static let ok = Kansei.success
        static let warn = Kansei.warning
        static let bad = Kansei.error
        static let charge = Kansei.info
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
        static let page: CGFloat = Kansei.spacingPage
        static let gap: CGFloat = Kansei.spacingLg
        static let cardPadding: CGFloat = Kansei.spacingMd
        static let row: CGFloat = 44
    }
    enum Radius {
        static let small: CGFloat = Kansei.radiusSmall
        static let card: CGFloat = Kansei.radiusMedium
        static let hero: CGFloat = Kansei.radiusLarge
        static let capsule: CGFloat = Kansei.radiusPill
    }
    enum Hair {
        static let line: CGFloat = 0.5
        static let border: CGFloat = 1
        static let inset: CGFloat = Kansei.spacingMd
    }
    enum Motion {
        static let press = Kansei.tap
        static let value = Kansei.count
        static let screen = Kansei.page
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
        static func display(_ size: CGFloat = 72) -> Font {
    .system(size: size, weight: .ultraLight).monospacedDigit() }
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
    enum Status {
        static func color(_ cls: String) -> Color {
            switch cls {
            case "ok", "normal": return .green
            case "warn", "warning": return Kansei.warning
            case "bad", "fault", "abnormal", "danger": return Kansei.error
            case "charge", "charging": return Kansei.info
            case "acc", "accent": return Kansei.ambient
            default: return Kansei.secondary
            }
        }
    }
}
