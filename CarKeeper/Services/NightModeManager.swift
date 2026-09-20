// =============================================================================
// #NEW-115 夜间模式独立开关 — App 内单独切换，不跟随系统
// =============================================================================

import SwiftUI

class NightModeManager: ObservableObject {
    static let shared = NightModeManager()

    @Published var isDarkMode: Bool {
        didSet {
            UserDefaults.standard.set(isDarkMode, forKey: "carkeeper_force_dark_mode")
            updateUserInterface()
        }
    }

    @Published var isAutoMode: Bool = true

    private init() {
        // 从 UserDefaults 恢复设置
        self.isDarkMode = UserDefaults.standard.bool(forKey: "carkeeper_force_dark_mode")
        self.isAutoMode = !UserDefaults.standard.bool(forKey: "carkeeper_force_light_mode") &&
                         !UserDefaults.standard.bool(forKey: "carkeeper_force_dark_mode")
    }

    /// 是否处于夜间时段（默认 21:00-07:00，可用 UserDefaults 覆盖）
    private static var autoDarkMode: Bool {
        if UserDefaults.standard.bool(forKey: "carkeeper_force_dark_mode") { return true }
        if UserDefaults.standard.bool(forKey: "carkeeper_force_light_mode") { return false }
        let hour = Calendar.current.component(.hour, from: Date())
        let rawStart = UserDefaults.standard.integer(forKey: "carkeeper_night_start_hour")
        let rawEnd = UserDefaults.standard.integer(forKey: "carkeeper_night_end_hour")
        let start = rawStart > 0 ? rawStart : 21
        let end = rawEnd > 0 ? rawEnd : 7
        return start > end ? (hour >= start || hour < end) : (hour >= start && hour < end)
    }

    /// 切换到指定模式（纯 UserDefaults 计算，无需主线程隔离）
    func setMode(_ mode: NightModeMode) {
        switch mode {
        case .auto:
            isAutoMode = true
            isDarkMode = Self.autoDarkMode
        case .light:
            isAutoMode = false
            isDarkMode = false
            UserDefaults.standard.set(true, forKey: "carkeeper_force_light_mode")
            UserDefaults.standard.set(false, forKey: "carkeeper_force_dark_mode")
        case .dark:
            isAutoMode = false
            isDarkMode = true
            UserDefaults.standard.set(true, forKey: "carkeeper_force_dark_mode")
            UserDefaults.standard.set(false, forKey: "carkeeper_force_light_mode")
        }
        updateUserInterface()
    }

    /// 更新 UI 主题
    func updateUserInterface() {
        // iOS 17+ 可以直接修改 scenePhase 来触发主题变更
        // 这里通过 post notification 通知各 View 刷新
        NotificationCenter.default.post(name: .nightModeChanged, object: isDarkMode)
    }

    /// 获取当前模式
    var currentMode: NightModeMode {
        if isAutoMode { return .auto }
        return isDarkMode ? .dark : .light
    }
}

enum NightModeMode {
    case auto, light, dark
}

extension Notification.Name {
    static let nightModeChanged = Notification.Name("nightModeChanged")
}
