import SwiftUI
import Intents
import Foundation

// =============================================================================
// #NEW-6 Siri 快捷指令 — 语音控制核心逻辑
// 支持：锁车、解锁、开空调、寻车（鸣笛+闪灯）
// 使用方法：在 Xcode 中添加 Intent Extension Target，注册以下 Intent
// =============================================================================

// MARK: - Intent 扩展接口（供 Intents Extension 调用）

@MainActor
struct SiriCarController {
    static let shared = SiriCarController()
    
    // 执行语音指令
    func handleIntent(_ intent: INIntent) async -> INInteraction? {
        let store = AppStore.shared
        guard store.isLoggedIn, !store.carId.isEmpty else {
            return nil
        }
        
        let api = APIClient.shared
        let pin = store.readPin() ?? ""
        
        switch intent {
        case let lock as CarLockIntent:
            await executeLock(pin: pin, carId: store.carId, locked: lock.locked == true)
        case let ac as CarSetAirConditioningIntent:
            await executeAc(pin: pin, carId: store.carId, on: ac.airConditioningOn == true)
        case let find as CarFindIntent:
            await executeFindCar(pin: pin, carId: store.carId)
        default:
            break
        }
        return nil
    }
    
    private func executeLock(pin: String, carId: String, locked: Bool) async {
        let store = AppStore.shared
        let api = APIClient.shared
        let cmd = locked ? "CentralLock" : "CentralUnlock"
        let name = locked ? "锁车" : "解锁"
        let start = Date()
        do {
            _ = try await api.sendControlCommand(cmd: cmd, carId: carId, pin: pin)
            store.addCommandHistory(cmd: cmd, name: name, success: true, duration: Date().timeIntervalSince(start))
            store.recordSiriUsage("lock_\(locked ? "on" : "off")")
        } catch {
            store.addCommandHistory(cmd: cmd, name: name, success: false, duration: Date().timeIntervalSince(start))
        }
    }
    
    private func executeAc(pin: String, carId: String, on: Bool) async {
        let store = AppStore.shared
        let api = APIClient.shared
        let cmd = on ? "OpenAir" : "CloseAir"
        let name = on ? "开空调" : "关空调"
        let start = Date()
        do {
            _ = try await api.sendControlCommand(cmd: cmd, carId: carId, pin: pin, temperature: 22)
            store.addCommandHistory(cmd: cmd, name: name, success: true, duration: Date().timeIntervalSince(start))
            store.recordSiriUsage("ac_\(on ? "on" : "off")")
        } catch {
            store.addCommandHistory(cmd: cmd, name: name, success: false, duration: Date().timeIntervalSince(start))
        }
    }
    
    private func executeFindCar(pin: String, carId: String) async {
        let store = AppStore.shared
        let api = APIClient.shared
        let cmd = "HornLight"
        let name = "寻车"
        let start = Date()
        do {
            _ = try await api.sendControlCommand(cmd: cmd, carId: carId, pin: pin)
            store.addCommandHistory(cmd: cmd, name: name, success: true, duration: Date().timeIntervalSince(start))
            store.recordSiriUsage("find_car")
        } catch {
            store.addCommandHistory(cmd: cmd, name: name, success: false, duration: Date().timeIntervalSince(start))
        }
    }
}

// MARK: - Intent 定义（需在 Intents Extension 中实现）

// 锁车/解锁
@available(iOS 12.0, *)
class CarLockIntent: INIntent {
    var locked: Bool?
    override init() { super.init() }
    required init?(coder: NSCoder) { fatalError() }
}

// 空调控制
@available(iOS 12.0, *)
class CarSetAirConditioningIntent: INIntent {
    var airConditioningOn: Bool?
    override init() { super.init() }
    required init?(coder: NSCoder) { fatalError() }
}

// 寻车
@available(iOS 12.0, *)
class CarFindIntent: INIntent {
    override init() { super.init() }
    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - Siri 快捷指令卡片（主 App 内展示）

struct SiriShortcutsCard: View {
    let store = AppStore.shared
    
    var body: some View {
        CardBox(title: "Siri 快捷指令", side: "语音控制", cornerRadius: Theme.Radius.card) {
            VStack(spacing: 12) {
                ShortcutRow(icon: "lock.fill", title: "锁车", subtitle: "语音说「锁车」", usage: store.siriUsageCount["lock_true"] ?? 0)
                ShortcutRow(icon: "lock.open.fill", title: "解锁", subtitle: "语音说「解锁」", usage: store.siriUsageCount["lock_false"] ?? 0)
                ShortcutRow(icon: "fan.fill", title: "开空调", subtitle: "语音说「开空调」", usage: store.siriUsageCount["ac_on"] ?? 0)
                ShortcutRow(icon: "power", title: "关空调", subtitle: "语音说「关空调」", usage: store.siriUsageCount["ac_off"] ?? 0)
                ShortcutRow(icon: "speaker.wave.2.fill", title: "寻车", subtitle: "语音说「寻车」", usage: store.siriUsageCount["find_car"] ?? 0)
            }
            .padding(.vertical, 8)
        }
    }
}

struct ShortcutRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let usage: Int
    
    var body: some View {
        HStack(spacing: 12) {
            Image(safeSymbol: icon, fallback: "car.fill")
                .font(.title3)
                .foregroundStyle(Theme.Colors.accent)
                .frame(width: 36, height: 36)
                .background(DS.Palette.fillSubtle, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.body).foregroundStyle(.primary)
                Text(subtitle).font(Theme.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if usage > 0 {
                Text("\(usage)次")
                    .font(Theme.micro)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}
