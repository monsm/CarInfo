import SwiftUI
import Foundation

// =============================================================================
// 车控指令的**唯一**执行路径（2026-09-22，批 1）
//
// 执行一条指令其实是五件事：验身份 → 发指令 → 按 TaskId 轮询到车辆终态 →
// 写指令历史 → 刷新车况缓存。这五件事原先只写在 `ControlView` 里。
//
// 地图上的常驻操作条也要发同一条指令。两边各写一遍的话，迟早会出现
// 「地图上锁车显示成功、车控页里同一辆车显示失败」—— 而这种分歧没有任何检查
// 能发现，因为两边都「自己是对的」。所以整条路径搬到这里，两边共用：
// 界面只负责「在哪里发起」和「怎么显示进度」。
// =============================================================================

/// 一次车控执行的全过程（原 `ControlView.RunState`，抽出来给地图操作条复用）
struct ControlRun: Identifiable {
    let id: Int
    var cmd: String
    var name: String
    var startedAt: String
    var taskId: String
    var status: String
    var progress: String
    var resultText: String
    var resultCls: String
    var handleCode: String = ""
    var finishTime: String = ""
}

@MainActor
final class CommandCenter: ObservableObject {
    static let shared = CommandCenter()

    private let store = AppStore.shared

    /// 同一时刻只允许一条指令在跑。并发发指令会让「这条回执对应哪条指令」
    /// 无法解释 —— 车辆回执里只有 TaskId，没有「第几条」。
    @Published private(set) var busy = false
    @Published private(set) var running: ControlRun?
    @Published private(set) var history: [ControlRun] = []
    @Published private(set) var lastResult: ControlRun?

    /// 结果详情的 sheet 该不该出现：车控页用它。
    /// 地图**不用**它 —— 一条锁车指令不该把用户推到另一个页面，那里只看状态条与 toast。
    @Published var showResult = false

    private var pollTask: Task<Void, Never>?

    private static let seq: () -> Int = {
        var n = 0
        let lock = NSLock()
        return { lock.lock(); n += 1; lock.unlock(); return n }
    }()

    private init() {}

    // MARK: - 发起

    /// 发起一条指令。
    ///
    /// `displayName` 由调用方给（车控页用自己的命令表，地图操作条用按钮上的字）——
    /// 名字只有一处定义，不会出现同一个指令有两个名字。
    ///
    /// 温度只对空调有意义，所以由调用方决定带不带（不发空调时传 17，与 API 默认值一致）。
    func send(cmd: String, temperature: Int, pin: String, displayName: String) {
        guard !cmd.isEmpty, !busy, running == nil, !store.carId.isEmpty else { return }
        busy = true
        let run = ControlRun(id: Self.seq(), cmd: cmd, name: displayName,
                             startedAt: VM.nowText(), taskId: "",
                             status: "run", progress: "", resultText: "", resultCls: "")
        running = run

        Task { @MainActor in
            do {
                let data = try await APIClient.shared.sendControlCommand(
                    cmd: cmd, carId: store.carId,
                    pin: pin, temperature: temperature)
                let taskId = data.flatMap { ciString($0, ["TaskId", "taskId"]) } ?? ""
                if !taskId.isEmpty {
                    running?.taskId = taskId
                    startPolling(taskId: taskId, run: run)
                } else {
                    finish(run, ok: true, text: "执行成功", desc: "服务端已受理")
                }
            } catch {
                finish(run, ok: false, text: "执行失败", desc: error.localizedDescription)
            }
        }
    }

    // MARK: - 轮询到车辆终态

    private func startPolling(taskId: String, run: ControlRun) {
        pollTask?.cancel()
        pollTask = Task { @MainActor in
            var i = 0
            while !Task.isCancelled {
                i += 1
                let r = await APIClient.shared.getControlInfo(carId: store.carId, taskId: taskId)
                guard let d = r.data else {
                    running?.progress = "查询异常，重试中…（\(i)/12"
                    if i >= 12 {
                        finish(run, ok: false, text: "结果待确认", desc: "60秒未收到车辆终态")
                        return
                    }
                    try? await Task.sleep(for: .seconds(5)); continue
                }
                let status = ciString(d, ["HandleStatus", "handleStatus", "Status", "status"]) ?? ""
                let finals = ["Success", "Completed", "RunFailure", "Failed", "Timeout",
                              "success", "completed", "runFailure", "failed", "timeout"]
                if finals.contains(status) {
                    let ok = ["Success", "Completed", "success", "completed"].contains(status)
                    let desc = ciString(d, ["HandleStatusDesc", "handleStatusDesc", "Desc"]) ?? ""
                    let handleCode = ciString(d, ["HandleCode", "handleCode"]) ?? ""
                    let finishTime = ciString(d, ["CmdFinishTime", "cmdFinishTime"]) ?? ""
                    finish(run, ok: ok, text: ok ? "执行成功" : "执行失败",
                           desc: desc.isEmpty ? status : desc,
                           handleCode: handleCode, finishTime: finishTime)
                    return
                }
                running?.progress = "第 \(i) 次查询 · 车辆处理中"
                if i >= 12 {
                    finish(run, ok: false, text: "结果待确认", desc: "60秒未收到车辆终态")
                    return
                }
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    // MARK: - 收尾

    private func finish(
        _ run: ControlRun, ok: Bool, text: String,
        desc: String, handleCode: String = "",
        finishTime: String = ""
    ) {
        pollTask?.cancel()
        pollTask = nil
        let cls = ok ? "ok" : "bad"
        var newRun = run
        newRun.status = ok ? "ok" : "bad"
        newRun.resultText = text
        newRun.resultCls = cls
        newRun.progress = desc
        newRun.handleCode = handleCode
        newRun.finishTime = finishTime.isEmpty ? VM.nowText() : finishTime
        lastResult = newRun
        running = nil
        busy = false
        history.insert(newRun, at: 0)
        if history.count > 10 { history.removeLast() }

        // 同步到 AppStore 全局历史记录
        store.addCommandHistory(cmd: run.cmd, name: run.name, success: ok, duration: 5)

        // 车况缓存重拉：刚下发的指令会改变门锁/空调状态，
        // 不重拉的话「车现在什么样」还停在指令之前的样子
        Task { @MainActor in
            if let ctrl = try? await APIClient.shared.getControl(carId: store.carId) {
                store.saveCache(["control": ctrl])
            }
        }

        // 提示带**指令名**：地图上的操作条发完就回到原样，用户需要一个「刚才那条怎么了」
        // 的落点；原先这里是空字符串（只有图标），在地图上读不出是哪条指令的结果。
        TokensHaptic.result(ok)
        EnhancedToastManager.shared.show(ok ? "\(run.name)已完成" : "\(run.name)失败",
                                        icon: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
        showResult = true
    }

    // MARK: - 宿主视图的生命周期

    /// 上一次执行的结果还在、但没有任何东西在等它 —— 多半是在别的屏发起后被打断的。
    /// 清掉，免得刚进入的页面显示一个陈旧的「正在执行」。
    func clearIfIdle() {
        if running != nil && pollTask == nil {
            running = nil
            busy = false
        }
    }

    /// 离开发起它的那一屏：停止轮询，并**把状态收干净**。
    ///
    /// 只 `cancel()` 不清理会留下两个后果：状态条永远停在「正在执行」，
    /// 而下一次 `send` 会被 `running == nil` 这道闸静默挡回去 —— 车控看起来就「没反应」。
    func abandon() {
        pollTask?.cancel()
        pollTask = nil
        running = nil
        busy = false
        showResult = false
    }
}
