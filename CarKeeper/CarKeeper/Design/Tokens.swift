import SwiftUI
import UIKit

enum TokensPalette {
    static let canvas: Color = Color(uiColor: UIColor.systemGroupedBackground)
    static let surface: Color = Color(uiColor: UIColor.secondarySystemGroupedBackground)
    static let hairline: Color = Color(uiColor: UIColor.separator)
    static let track: Color = Color(uiColor: .quaternaryLabel)
    static let labelOnTint: Color = .white
    static let scrim: Color = .black
    static let lightSource: Color = .white
    private static let blue: Color = tokenDynamic(light: (0.000, 0.478, 1.000),
                                                  dark: (0.039, 0.518, 1.000))
    static var lightBar: LinearGradient {
        LinearGradient(colors: [.white,
                                Color(red: 0.612, green: 0.776, blue: 1.000),
                                blue],
                       startPoint: .leading, endPoint: .trailing)
    }
    static let primary: Color = Color(uiColor: .label)
    static let secondary: Color = Color(uiColor: .secondaryLabel)
    static let tertiary: Color = Color(uiColor: .tertiaryLabel)


    static let accent: Color = tokenDynamic(light: (0.000, 0.478, 1.000),
                                            dark: (0.039, 0.518, 1.000))
    static var ambient: Color { accent }

    static let success: Color = tokenDynamic(light: (0.204, 0.780, 0.349),
                                             dark: (0.188, 0.820, 0.345))
    static let warning: Color = tokenDynamic(light: (1.000, 0.584, 0.000),
                                             dark: (1.000, 0.624, 0.039))
    static let error: Color = tokenDynamic(light: (1.000, 0.231, 0.188),
                                           dark: (1.000, 0.271, 0.227))
    static let info: Color = tokenDynamic(light: (0.000, 0.780, 0.745),
                                          dark: (0.400, 0.839, 1.000))

    private static let faceFill: Double = 0.5
    static var fillSubtle: Color { surface.opacity(0.22 * faceFill) }

    static var panel: Color { surface.opacity(0.34 * faceFill) }


    static let barFill: Color = tokenDynamic(light: (1, 1, 1),
                                             dark: (0.11, 0.11, 0.12),
                                             alpha: 0.55)
    static let glassDim: Color = tokenDynamic(light: (1, 1, 1),
                                              dark: (0, 0, 0),
                                              alpha: 0.35)



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

    static let pageAccents: [Color] = [tokenColor(0xAF52DE), tokenColor(0x007AFF),
                                       tokenColor(0x34C759), tokenColor(0x30B0C7),
                                       tokenColor(0x5856D6), tokenColor(0x5AC8FA)]
}

enum TokensInk {
    static var primary: AnyShapeStyle { AnyShapeStyle(HierarchicalShapeStyle.primary) }
    static var secondary: AnyShapeStyle { AnyShapeStyle(HierarchicalShapeStyle.secondary) }
    static var tertiary: AnyShapeStyle { AnyShapeStyle(HierarchicalShapeStyle.tertiary) }
}


enum TokensSpacing {
    static let xxs = CGFloat(2)
    static let xs = CGFloat(4)
    static let sm = CGFloat(8)
    static let snug = CGFloat(12)
    static let md = CGFloat(16)
    static let lg = CGFloat(24)
    static let xl = CGFloat(32)
    static let xxl = CGFloat(48)
    static let xxxl = CGFloat(64)
    static let page = CGFloat(20)
    static let row = CGFloat(44)
}

enum TokensRadius {
    static let small = CGFloat(8)
    static let medium = CGFloat(12)
    static let large = CGFloat(20)
    static let pill = CGFloat(999)
}

enum TokensTypo {
    static let title = Font.title.weight(.semibold)
    static let title2 = Font.title2.weight(.semibold)
    static let title3 = Font.title3.weight(.semibold)
    static let headline = Font.headline
    static let body = Font.body
    static let subheadline = Font.subheadline
    static let footnote = Font.footnote
    static let caption = Font.caption
    static let caption2 = Font.caption2
    static let sectionLabel = Font.footnote

    static var subtitle: Font { Font.system(size: 17, weight: .regular) }
    static var micro: Font { Font.system(size: 11, weight: .regular) }

    static func display(_ size: CGFloat = 72, weight: Font.Weight = .ultraLight) -> Font {
        .system(size: size, weight: weight).monospacedDigit()
    }
    static func metric(_ size: CGFloat = 34) -> Font {
        .system(size: size, weight: .light).monospacedDigit()
    }
    static let data = Font.system(size: 17).monospacedDigit()
    static let dataSmall = Font.system(size: 15).monospacedDigit()
    static func fixed(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
    static func digits(_ size: CGFloat) -> Font {
        .system(size: size).monospacedDigit()
    }
}

enum TokensMotion {
    static let tap = Animation.spring(response: 0.25, dampingFraction: 0.7)
    static let count = Animation.spring(response: 0.4, dampingFraction: 0.6)
    static let settle = Animation.spring(response: 0.34, dampingFraction: 1.0)
    static let press = Animation.spring(response: 0.30, dampingFraction: 0.86)
    static let value = Animation.spring(response: 0.36, dampingFraction: 0.88)
    static let fade = Animation.easeOut(duration: 0.20)
    static let draw = Animation.easeOut(duration: 1.1)
}

enum TokensHaptic {
    static func select() { UISelectionFeedbackGenerator().selectionChanged() }
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func error() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    static func heavy() { UIImpactFeedbackGenerator(style: .heavy).impactOccurred() }
    static func result(_ ok: Bool) {
        if ok { success() } else { error() }
    }
}

enum TokensHair {
    static let line: CGFloat = 0.5
    static let border: CGFloat = 1
    static let inset: CGFloat = 16
}

enum TokensSize {
    static let tap: CGFloat = 44
    static let button: CGFloat = 50
    static let icon: CGFloat = 17
    static let iconColumn: CGFloat = 29
}

enum TokensTracking {
    static let label: CGFloat = 0.6
    static let title: CGFloat = -0.2
}

private func tokenColor(_ hex: UInt32, alpha: Double = 1) -> Color {
    Color(
        .sRGB,
        red: Double((hex >> 16) & 0xFF) / 255,
        green: Double((hex >> 8) & 0xFF) / 255,
        blue: Double(hex & 0xFF) / 255,
        opacity: alpha
    )
}

private func tokenDynamic(
    light: (CGFloat, CGFloat, CGFloat),
    dark: (CGFloat, CGFloat, CGFloat),
    alpha: CGFloat = 1
) -> Color {
    Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
        ? UIColor(red: dark.0, green: dark.1, blue: dark.2, alpha: alpha)
        : UIColor(red: light.0, green: light.1, blue: light.2, alpha: alpha)
    })
}
