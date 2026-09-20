// =============================================================================
// #NEW-114 多语言完善 - Localizable.strings 辅助工具
// =============================================================================

import Foundation

// 语言枚举
enum AppLanguage: String, CaseIterable {
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
}

// 本地化助手
struct L10n {
    static func localize(_ key: String, _ comments: String? = nil) -> String {
        return NSLocalizedString(key, comment: comments ?? "")
    }

    // 常用键
    static let appName = localize("App.Name")
    static let login = localize("Login.Title")
    static let logout = localize("Logout.Button")
    static let car = localize("Car.Title")
    static let control = localize("Control.Title")
    static let messages = localize("Messages.Title")
    static let profile = localize("Profile.Title")

    // 登录相关
    static let phonePlaceholder = localize("Phone.Placeholder")
    static let smsCodePlaceholder = localize("SMS.Code.Placeholder")
    static let captchaPlaceholder = localize("Captcha.Placeholder")
    static let sendCode = localize("Send.Code")
    static let loginButton = localize("Login.Button")

    // 车况相关
    static let soc = localize("SOC.Title")
    static let range = localize("Range.Title")
    static let temperature = localize("Temperature.Title")
    static let locked = localize("Locked.Title")
    static let charging = localize("Charging.Title")

    // 设置相关
    static let darkMode = localize("Dark.Mode")
    static let powerSaving = localize("Power.Saving")
    static let language = localize("Language.Title")
    static let about = localize("About.Title")

    // 错误信息
    static let networkError = localize("Error.Network")
    static let loginFailed = localize("Error.Login")
    static let tokenExpired = localize("Error.TokenExpired")
}
