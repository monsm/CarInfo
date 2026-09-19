// =============================================================================
// #NEW-119 App Intents — 深度 Siri 集成，支持动态参数和 Siri Suggestions
// =============================================================================

import AppIntents
import SwiftUI

// MARK: - App Intent 定义

struct CheckCarStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "查看车辆状态"
    static let description = IntentDescription("通过 Siri 查看车辆电量、续航里程、胎压等信息")
    
    static let openInForeground = true
    
    func perform() async throws -> some IntentResult {
        // 获取车况数据
        let status = AppStore.shared.quickStatus()
        
        // 构建语音回复
        let reply = "当前车辆 SOC \(status.soc)%，续航 \(status.range) km，车内温度 \(status.cabinTemp)，\(status.locked ? "已锁车" : "已解锁")"
        
        // 触发通知
        let notification = UNMutableNotificationContent()
        notification.title = "🚗 车辆状态"
        notification.body = reply
        notification.sound = .default
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: notification, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
        
        return .result()
    }
}

struct ControlCarIntent: AppIntent {
    static let title: LocalizedStringResource = "控制车辆"
    static let description = IntentDescription("通过 Siri 控制车辆：锁车、解锁、开空调")
    
    @Parameter(title: "操作", description: "选择要执行的操作")
    var action: CarAction
    
    static let openInForeground = true
    
    enum CarAction: String, AppEnum {
        case lock = "锁车"
        case unlock = "解锁"
        case acOn = "开空调"
        case acOff = "关空调"
        case find = "寻车"
        
        static let typeDisplay = TypeDisplay(name: "车辆操作")
        static let caseDisplay: [Self : String] = [
            .lock: "锁车",
            .unlock: "解锁",
            .acOn: "开空调",
            .acOff: "关空调",
            .find: "寻车"
        ]
    }
    
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = AppStore.shared
        guard store.isLoggedIn, !store.carId.isEmpty else {
            return .result(dialog: "请先登录并绑定车辆")
        }
        
        let api = APIClient.shared
        let pin = store.readPin() ?? ""
        var command = ""
        
        switch action {
        case .lock: command = "CentralLock"
        case .unlock: command = "CentralUnlock"
        case .acOn: command = "OpenAir"
        case .acOff: command = "CloseAir"
        case .find: command = "HornLight"
        }
        
        do {
            _ = try await api.sendControlCommand(cmd: command, carId: store.carId, pin: pin)
            store.addCommandHistory(cmd: command, name: action.rawValue, success: true, duration: 0)
            return .result(dialog: "\(action.rawValue)指令已发送")
        } catch {
            return .result(dialog: "\(action.rawValue)失败: \(error.localizedDescription)")
        }
    }
}

struct FindCarLocationIntent: AppIntent {
    static let title: LocalizedStringResource = "查找车辆位置"
    static let description = IntentDescription("查看车辆当前停在哪里")
    
    static let openInForeground = true
    
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let location = AppStore.shared.caches["location"] as? [String: Any],
              let addr = location["Address"] as? String,
              let lat = location["Lat"] as? String,
              let lng = location["Lng"] as? String else {
            return .result(dialog: "未获取到车辆位置信息")
        }
        
        let reply = "车辆停在：\(addr)，坐标：\(lat)，\(lng)"
        return .result(dialog: reply)
    }
}

// MARK: - Siri Suggestions

struct CarKeeperIntentSuggestions: AppShortcutsProvider {
    static var shortcutDescriptors: [ShortcutDescriptor] {
        [
            ShortcutDescriptor<CheckCarStatusIntent>(
                .checkCarStatus,
                title: "查看车辆状态",
                shortTitle: "车况查询",
                description: "快速了解车辆电量、续航和温度"
            ),
            ShortcutDescriptor<ControlCarIntent>(
                .controlCar,
                title: "控制车辆",
                shortTitle: "车辆控制",
                description: "远程锁车、解锁或开关空调"
            ),
            ShortcutDescriptor<FindCarLocationIntent>(
                .findCarLocation,
                title: "查找车辆",
                shortTitle: "找车",
                description: "查看车辆当前位置"
            )
        ]
    }
}

// MARK: - Intent 快捷方式定义

extension IntentName {
    static let checkCarStatus = Self("CheckCarStatus")
    static let controlCar = Self("ControlCar")
    static let findCarLocation = Self("FindCarLocation")
}
