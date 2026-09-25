// =============================================================================
// #NEW-115 夜间模式独立开关 — App 内单独切换，不跟随系统
// =============================================================================

import SwiftUI

class NightModeManager: ObservableObject {
    static let shared = NightModeManager()

    @Published var isDarkMode: Bool {
        didSet {
            // ⚠️ 只在**明确选了深浅色**时才落盘。`setMode(.auto)` 不再给 `isDarkMode` 赋值
            //（它改为不覆盖），所以这个 didSet 不会把「自动」误写成「强制深色」。
            if !isAutoMode {
                UserDefaults.standard.set(isDarkMode, forKey: "carkeeper_force_dark_mode")
            }
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

    /// 这个开关对界面的**实际作用**。
    ///
    /// 2026-09-25 地毯式审核查到的事：这一页的「自动 / 浅色 / 深色」从前**只改它自己那一行**
    /// —— 全 App 的外观来自艺术方向自带的明暗，`isDarkMode` 除本行以外没有任何读者，
    /// 而 `nightModeChanged` 那条通知一个观察者都没有。也就是说：拨它不会有任何变化
    ///（一个会在说谎的控件）。
    ///
    /// 现在它真的上屏：`CarKeeperApp` 两个窗口都读这个值。返回 nil = 「不覆盖」。
    /// 那时「不覆盖」是「交给艺术方向决定」（纸上=亮、夜光/巨字=暗）；
    /// 2026-09-25 艺术主题整份删除后，nil 就是**跟随系统** —— 也就是这个开关的
    /// 「自动」那一档现在名副其实。
    ///
    /// 「自动」**不是**按钟点切换：原先那一套 21:00–07:00 按小时算的逻辑与它读的两个键
    ///（`carkeeper_night_start_hour` / `_end_hour`）全仓没有任何地方写，永远只能得到
    /// 默认值，而且它会把「夜光」这类故意做成暗的主题在白天强行翻成亮色。已删。
    var schemeOverride: ColorScheme? {
        if isAutoMode { return nil }
        return isDarkMode ? .dark : .light
    }

    /// 切换到指定模式（纯 UserDefaults 计算，无需主线程隔离）
    func setMode(_ mode: NightModeMode) {
        switch mode {
        case .auto:
            isAutoMode = true
            // 回到「自动」要把两个强制标记**都**清掉，否则下一次启动读到的还是上一次的
            // 强制值（`init` 正是靠这两个键判断该不该自动）。
            UserDefaults.standard.set(false, forKey: "carkeeper_force_light_mode")
            UserDefaults.standard.set(false, forKey: "carkeeper_force_dark_mode")
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

    /// 更新 UI 主题。
    ///
    /// 不需要通知任何人：`isDarkMode` / `isAutoMode` 都是 `@Published`，而读它的
    /// `CarKeeperApp` 与这一行都用 `@StateObject` 订阅了 —— SwiftUI 自己会重绘。
    /// （原先这里 post 的 `nightModeChanged` 一个观察者都没有，那条通知与它的
    ///  `Notification.Name` 已删：一条没人听的通知看起来像「已经通知了」。）
    func updateUserInterface() {
        objectWillChange.send()
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
