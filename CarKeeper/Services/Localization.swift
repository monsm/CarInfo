// =============================================================================
// N42 国际化字符串提取
// N9 夜间呼吸灯增强（SOC 绑定频率）
// =============================================================================

import Foundation
import SwiftUI

// MARK: - N42 国际化辅助
enum AppLocale: String, CaseIterable {
    case zhHans = "zh-Hans"
    case en = "en"
    case ja = "ja"

    var displayName: String {
        switch self {
        case .zhHans: return "简体中文"
        case .en: return "English"
        case .ja: return "日本語"
        }
    }

    static var current: Locale {
        get {
            Locale(identifier: UserDefaults.standard.string(forKey: "carkeeper_locale") ?? "zh_Hans_CN")
        }
        set {
            UserDefaults.standard.set(newValue.identifier, forKey: "carkeeper_locale")
        }
    }
}

struct I18n {
    static func t(_ key: String, _ args: CVarArg...) -> String {
        let format = NSLocalizedString(key, bundle: .main, comment: "")
        return String(format: format, locale: AppLocale.current, arguments: args)
    }

    // 常用字符串键
    static let appName       = t("App.Name")
    static let login         = t("Login.Title")
    static let home          = t("Tab.Home")
    static let control       = t("Tab.Control")
    static let messages      = t("Tab.Messages")
    static let profile       = t("Tab.Profile")
    static let vehicle       = t("Tab.Vehicle")
    static let health        = t("Tab.Health")
    static let battery       = t("Tab.Battery")
    static let data          = t("Tab.Data")
    static let dev           = t("Tab.Dev")
    static let soc           = t("SOC")
    static let range         = t("Range")
    static let temperature   = t("Temperature")
    static let lock          = t("Lock")
    static let unlock        = t("Unlock")
    static let charge        = t("Charge")
    static let charging      = t("Charging")
    static let airConditioning = t("AirConditioning")
    static let tirePressure  = t("TirePressure")
    static let brake         = t("Brake")
    static let light         = t("Light")
    static let door          = t("Door")
    static let window        = t("Window")
    static let trunk         = t("Trunk")
    static let findCar       = t("FindCar")
    static let share         = t("Share")
    static let settings      = t("Settings")
    static let logout        = t("Logout")
    static let yes           = t("Yes")
    static let no            = t("No")
    static let cancel        = t("Cancel")
    static let confirm       = t("Confirm")
    static let save          = t("Save")
    static let delete        = t("Delete")
    static let edit          = t("Edit")
    static let back          = t("Back")
    static let next          = t("Next")
    static let done          = t("Done")
    static let ok            = t("OK")
    static let empty         = t("Empty")
    static let loading       = t("Loading")
    static let error         = t("Error")
    static let retry         = t("Retry")
    static let refresh       = t("Refresh")
    static let search        = t("Search")
    static let filter        = t("Filter")
    static let sort          = t("Sort")
    static let all           = t("All")
    static let recent        = t("Recent")
    static let today         = t("Today")
    static let tomorrow      = t("Tomorrow")
    static let week          = t("Week")
    static let month         = t("Month")
    static let year          = t("Year")
}

// MARK: - N9 夜间呼吸灯增强
struct BreathingGlowView: View {
    let soc: Int
    let size: CGFloat
    let color: Color

    private var pulsePeriod: Double {
        guard soc > 0 else { return 0.6 }
        return max(0.4, Double(soc) / 100.0)
    }

    var body: some View {
        Circle()
            .fill(color.opacity(0.12))
            .frame(width: size, height: size)
            .scaleEffect(1 + sin(Date().timeIntervalSince1970 * .pi * 2 / pulsePeriod) * 0.08)
            .opacity(0.5 + sin(Date().timeIntervalSince1970 * .pi * 2 / pulsePeriod) * 0.5)
            .animation(.linear(duration: pulsePeriod).repeatForever(autoreverses: false), value: soc)
    }
}

struct NightBreathingContainer: ViewModifier {
    let soc: Int
    let color: Color
    let size: CGFloat

    func body(content: Content) -> some View {
        ZStack {
            BreathingGlowView(soc: soc, size: size, color: color)
                .position(x: size / 2, y: size / 2)
            content
        }
    }
}

extension View {
    func nightBreathing(soc: Int, color: Color = .accentColor, size: CGFloat = 200) -> some View {
        modifier(NightBreathingContainer(soc: soc, color: color, size: size))
    }
}
