import SwiftUI
import AppIntents
import Foundation

// =============================================================================
// #NEW-6 Siri 快捷指令 — 语音控制
// 支持：锁车、解锁、开空调、寻车（鸣笛+闪灯）
//
// 为什么整段重写：
// 旧版用的是三个老的 Intent 子类（基于 `INIntent`），文件头注释写着「需在 Xcode 中添加
// Intent Extension Target」—— 而 project.yml 里**没有那个 target**。在 App 进程内
// 这类子类不会自动成为 Siri 的入口，所以那三个类永远不会被系统构造；
// 相应那个意图分发函数也没有任何调用点。等于「Siri 车控」从来没通。
//
// 现在改用 App Intents：不需要额外 target，`AppShortcutsProvider` 抛出的短语
// 会直接出现在系统「快捷指令」里，Siri 可以直接唤起。
// =============================================================================

// MARK: - 指令执行（Siri intent 与卡片共用同一条路径）

@MainActor
struct SiriCarController {
    static let shared = SiriCarController()

    /// 一次车控语音指令的结果，供 intent 拼对话文案
    enum Outcome {
        case notLoggedIn
        case noPin
        case sent
        case failed(String)
    }

    func lock(locked: Bool) async -> Outcome {
        await send(cmd: locked ? "CentralLock" : "CentralUnlock",
                   name: locked ? "锁车" : "解锁",
                   usageKey: locked ? "lock_true" : "lock_false")
    }

    func air(on: Bool, temperature: Int = 22) async -> Outcome {
        await send(cmd: on ? "OpenAir" : "CloseAir",
                   name: on ? "开空调" : "关空调",
                   usageKey: on ? "ac_on" : "ac_off",
                   temperature: on ? temperature : nil)
    }

    func findCar() async -> Outcome {
        await send(cmd: "HornLight", name: "寻车", usageKey: "find_car")
    }

    /// 唯一的一条发送路径：验登录 → 验 PIN → 发指令 → 记历史 + 记使用次数。
    ///
    /// 使用次数的 key 必须与 `SiriShortcutsCard` 里那张表一致：旧代码记的是
    /// `lock_on` / `lock_off`，而卡片读的是 `lock_true` / `lock_false` ——
    /// 所以卡片永远显示「还没有用过语音指令」，哪怕你用了一百次。
    private func send(cmd: String, name: String, usageKey: String, temperature: Int? = nil) async -> Outcome {
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
            store.recordSiriUsage(usageKey)
            return .sent
        } catch {
            store.addCommandHistory(cmd: cmd, name: name, success: false,
                                    duration: Date().timeIntervalSince(start))
            return .failed(error.localizedDescription)
        }
    }

    /// 把 Outcome 变成 Siri 说的话 / 卡片上的说明（只有这一份文案）
    static func dialog(_ outcome: Outcome, action: String) -> String {
        switch outcome {
        case .sent: return "已\(action)"
        case .notLoggedIn: return "请先在长安车管家里登录并绑定车辆。"
        case .noPin: return "车控需要 PIN，请先在 App 里设置。"
        case .failed(let message): return "\(action)失败：\(message)"
        }
    }
}

// MARK: - App Intents（Siri / 快捷指令 / 聚焦搜索共用入口）

// 一句话说完一个动作 —— 每条指令一个类型，**不带参数**。
// 不用 `@Parameter` 是故意的：“锁车/解锁”本来就是两句不同的话，
// 做成一个带布尔的参数不会让用户少说什么，只会让代码多一层参数包装。

/// 每个 AppIntent 共用的「把结果说成一句话」
private func siriResult(_ outcome: SiriCarController.Outcome, action: String) -> some IntentResult & ProvidesDialog {
    let text = SiriCarController.dialog(outcome, action: action)
    return .result(dialog: IntentDialog(LocalizedStringResource(stringLiteral: text)))
}

struct LockCarIntent: AppIntent {
    static var title: LocalizedStringResource = "锁车"
    static var description = IntentDescription("锁定车辆中控锁")
    /// 车控是后台动作，不必把 App 拉到前台
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

/// 注册进系统「快捷指令」。这个结构存在本身就是在注册，不需要额外 target。
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

// MARK: - Siri 快捷指令卡片（主 App 内展示）

struct SiriShortcutsCard: View {
    let store = AppStore.shared

    /// 五条指令、它们的真实计数键（与 `SiriCarController.send` 的 usageKey 一一对应）。
    /// 「语音说 X」是提示语，不是数据。
    private static let shortcuts: [(icon: String, title: String, phrase: String, key: String)] = [
        ("lock.fill", "锁车", "语音说「锁车」", "lock_true"),
        ("lock.open.fill", "解锁", "语音说「解锁」", "lock_false"),
        ("fan.fill", "开空调", "语音说「开空调」", "ac_on"),
        ("wind", "关空调", "语音说「关空调」", "ac_off"),
        ("speaker.wave.2.fill", "寻车", "语音说「寻车」", "find_car")
    ]

    var body: some View {
        DSGroup(title: "Siri 快捷指令", footer: footer) {
            ForEach(Self.shortcuts, id: \.key) { s in
                DSGroupRow {
                    ShortcutRow(icon: s.icon,
                                title: s.title,
                                subtitle: s.phrase,
                                usage: store.siriUsageCount[s.key] ?? 0)
                }
            }
        }
    }

    /// 计数只说真话：一次都没用过就照实说，不摆一排「0 次」。
    private var footer: String {
        let total = Self.shortcuts.reduce(0) { $0 + (store.siriUsageCount[$1.key] ?? 0) }
        return total == 0
            ? "还没有用过语音指令 —— 这条短语已注册进系统「快捷指令」，直接对 Siri 说即可。"
            : "共 \(total) 次语音指令。"
    }
}

struct ShortcutRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let usage: Int

    var body: some View {
        HStack(spacing: TokensSpacing.md) {
            Image(safeSymbol: icon, fallback: "car.fill")
                .font(TokensTypo.title3)
                .foregroundStyle(TokensPalette.ambient)
                .frame(width: TokensSize.iconColumn, alignment: .center)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(TokensTypo.body).foregroundStyle(TokensPalette.primary)
                Text(subtitle).font(TokensTypo.footnote).foregroundStyle(TokensPalette.secondary)
            }
            Spacer(minLength: TokensSpacing.sm)
            // 次数是真实计数；没出现过就不显示（「0 次」是一个假读数）
            if usage > 0 {
                Text("\(usage) 次")
                    .font(TokensTypo.dataSmall)
                    .foregroundStyle(TokensPalette.tertiary)
            }
        }
    }
}
