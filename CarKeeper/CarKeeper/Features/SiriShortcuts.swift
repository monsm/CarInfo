import SwiftUI
import AppIntents
import Foundation



@MainActor
struct SiriCarController {
    static let shared = SiriCarController()

    enum Outcome: Sendable {
        case notLoggedIn
        case noPin
        case sent
        case failed(String)
    }

    func lock(locked: Bool) async -> Outcome {
        await send(cmd: locked ? "CentralLock" : "CentralUnlock",
                   name: locked ? "锁车" : "解锁")
    }

    func air(on: Bool, temperature: Int = 22) async -> Outcome {
        if on {
            return await send(cmd: "OpenAir", name: "开空调", temperature: temperature)
        } else {
            return await send(cmd: "CloseAir", name: "关空调")
        }
    }

    func findCar() async -> Outcome {
        await send(cmd: "HornLight", name: "寻车")
    }

    private func send(cmd: String, name: String, temperature: Int = 17) async -> Outcome {
        let store = AppStore.shared
        guard store.isLoggedIn, !store.carId.isEmpty else { return .notLoggedIn }
        guard let pin = store.readPin(), !pin.isEmpty else { return .noPin }

        let start = Date()
        do {
            _ = try await APIClient.shared.sendControlCommand(cmd: cmd,
                                                             carId: store.carId,
                                                             pin: pin,
                                                             temperature: temperature)
            store.addCommandHistory(cmd: cmd, name: name, success: true,
                                    duration: Date().timeIntervalSince(start))
            return .sent
        } catch {
            store.addCommandHistory(cmd: cmd, name: name, success: false,
                                    duration: Date().timeIntervalSince(start))
            return .failed(error.localizedDescription)
        }
    }

    nonisolated static func dialog(_ outcome: Outcome, action: String) -> String {
        switch outcome {
        case .sent: return "已\(action)"
        case .notLoggedIn: return "请先登录并绑定车辆。"
        case .noPin: return "请先在 App 里设置 PIN。"
        case .failed(let message): return "\(action)失败：\(message)"
        }
    }
}



private func siriResult(_ outcome: SiriCarController.Outcome, action: String) -> some IntentResult & ProvidesDialog {
    let text = SiriCarController.dialog(outcome, action: action)
    return .result(dialog: IntentDialog(LocalizedStringResource(stringLiteral: text)))
}

struct LockCarIntent: AppIntent {
    static var title: LocalizedStringResource = "锁车"
    static var description = IntentDescription("锁定车辆中控锁")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        siriResult(await SiriCarController.shared.lock(locked: true), action: "锁车")
    }
}

struct UnlockCarIntent: AppIntent {
    static var title: LocalizedStringResource = "解锁"
    static var description = IntentDescription("解开车辆中控锁")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        siriResult(await SiriCarController.shared.lock(locked: false), action: "解锁")
    }
}

struct OpenAirIntent: AppIntent {
    static var title: LocalizedStringResource = "开空调"
    static var description = IntentDescription("打开车内空调（22℃）")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        siriResult(await SiriCarController.shared.air(on: true), action: "开空调")
    }
}

struct CloseAirIntent: AppIntent {
    static var title: LocalizedStringResource = "关空调"
    static var description = IntentDescription("关闭车内空调")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        siriResult(await SiriCarController.shared.air(on: false), action: "关空调")
    }
}

struct FindCarIntent: AppIntent {
    static var title: LocalizedStringResource = "寻车"
    static var description = IntentDescription("鸣笛并闪灯，帮你找到车")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        siriResult(await SiriCarController.shared.findCar(), action: "寻车")
    }
}

struct CarKeeperShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: LockCarIntent(),
                    phrases: ["用\(.applicationName)锁车", "\(.applicationName)锁车"],
                    shortTitle: "锁车",
                    systemImageName: "lock.fill")
        AppShortcut(intent: UnlockCarIntent(),
                    phrases: ["用\(.applicationName)解锁", "\(.applicationName)解锁"],
                    shortTitle: "解锁",
                    systemImageName: "lock.open.fill")
        AppShortcut(intent: OpenAirIntent(),
                    phrases: ["用\(.applicationName)开空调", "\(.applicationName)开空调"],
                    shortTitle: "开空调",
                    systemImageName: "fan.fill")
        AppShortcut(intent: CloseAirIntent(),
                    phrases: ["用\(.applicationName)关空调", "\(.applicationName)关空调"],
                    shortTitle: "关空调",
                    systemImageName: "wind")
        AppShortcut(intent: FindCarIntent(),
                    phrases: ["用\(.applicationName)寻车", "\(.applicationName)寻车"],
                    shortTitle: "寻车",
                    systemImageName: "speaker.wave.2.fill")
    }
}

