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

    // 【已删】`isDriving`（基于速度判断是否在驾驶）——2026-09-25 地毯式审核。
    //
    // 它读的是 `carkeeper_current_speed`，而**全仓没有一处写这个键**：于是它永远
    // 读回 0，`> 5` 永远不成立 —— 无论怎么写都是 false。它本身也没有调用方。
    // 车速的真实来源只有一个：`VM.driveStatus(store.caches).speed`（车端报文）。

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


