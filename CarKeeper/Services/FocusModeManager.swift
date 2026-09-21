// =============================================================================
// #NEW-130 锁屏专注模式 — 专注驾驶时隐藏敏感数据，仅显示关键信息
// =============================================================================

import SwiftUI

/// 专注模式配置
struct FocusModeConfig: Codable, Identifiable {
    var id = UUID()
    var enabled: Bool
    var hideSensitiveData: Bool  // 隐藏车牌/ VIN/ 联系人
    var showEssentialOnly: Bool  // 只显示 SOC/锁车/空调
    var doNotDisturb: Bool       // 勿扰模式
    var autoStartDriving: Bool   // 驾驶时自动启动
    var customMessage: String    // 自定义锁屏文字
}

class FocusModeManager: ObservableObject {
    static let shared = FocusModeManager()

    var config: FocusModeConfig {
        if let data = UserDefaults.standard.data(forKey: "carkeeper_focus_mode"),
           let decoded = try? JSONDecoder().decode(FocusModeConfig.self, from: data) {
            return decoded
        }
        return defaultConfig
    }

    func saveConfig(_ config: FocusModeConfig) {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: "carkeeper_focus_mode")
        }
    }

    /// 检测是否正在驾驶（基于速度）
    var isDriving: Bool {
        // 简化：检查最近一次上报的车速
        UserDefaults.standard.double(forKey: "carkeeper_current_speed") > 5
    }

    var defaultConfig: FocusModeConfig {
        FocusModeConfig(
            enabled: false,
            hideSensitiveData: true,
            showEssentialOnly: true,
            doNotDisturb: true,
            autoStartDriving: true,
            customMessage: ""
        )
    }
}


