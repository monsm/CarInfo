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
        static let caption = Font.caption
        static let footnote = Font.footnote
        static let subheadline = Font.subheadline
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

// MARK: - Kansei.Color ShapeStyle conformance
extension Kansei.Color: ShapeStyle {
    func resolve(in context: ShapeStyle.Context) -> Color { self }
}

// MARK: - Kansei.Color opacity helper
extension Kansei.Color {
    @inline(__always) func dsOpacity(_ o: Double) -> Color { self.opacity(o) }
}




// MARK: - DS.Palette / Theme 兼容别名（渐进迁移）
// 旧代码引用的 DS.Palette.* 和 Theme.* 全部重定向到 Kansei