import SwiftUI
import Foundation


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

    @Published private(set) var busy = false
    @Published private(set) var running: ControlRun?
    @Published private(set) var lastResult: ControlRun?


    private var runStartedAt = Date()

    @Published var showResult = false

    private var pollTask: Task<Void, Never>?

    private static let seq: () -> Int = {
        var n = 0
        let lock = NSLock()
        return { lock.lock(); n += 1; lock.unlock(); return n }
    }()

    private init() {}


    func send(cmd: String, temperature: Int, pin: String, displayName: String) {
        guard !cmd.isEmpty, !busy, running == nil, !store.carId.isEmpty else { return }
        busy = true
        runStartedAt = Date()
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
                        finish(run, ok: false, text: "结果待确认", desc: "60 秒无终态",
                               neutral: true)
                        return
                    }
                    try? await Task.sleep(for: .seconds(5)); continue
                }
                let status = ciString(d, ["HandleStatus", "handleStatus", "Status", "status"]) ?? ""
                let desc = ciString(d, ["HandleStatusDesc", "handleStatusDesc", "Desc"]) ?? ""
                let handleCode = ciString(d, ["HandleCode", "handleCode"]) ?? ""
                let finishTime = ciString(d, ["CmdFinishTime", "cmdFinishTime"]) ?? ""

                let outcome = VM.controlOutcome(status: status, handleCode: handleCode)
                if !finishTime.isEmpty || outcome != nil {
                    finish(run,
                           ok: outcome == true,
                           text: VM.controlOutcomeText(outcome),
                           desc: desc.isEmpty ? (status.isEmpty ? "车端已回执" : status) : desc,
                           handleCode: handleCode, finishTime: finishTime,
                           neutral: outcome == nil)
                    return
                }
                running?.progress = "第 \(i) 次查询 · 车辆处理中"
                if i >= 12 {
                    finish(run, ok: false, text: "结果待确认", desc: "60 秒无终态",
                           neutral: true)
                    return
                }
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }


    private func finish(
        _ run: ControlRun, ok: Bool, text: String,
        desc: String, handleCode: String = "",
        finishTime: String = "", neutral: Bool = false
    ) {
        pollTask?.cancel()
        pollTask = nil
        let cls = neutral ? "na" : (ok ? "ok" : "bad")
        var newRun = run
        newRun.status = cls
        newRun.resultText = text
        newRun.resultCls = cls
        newRun.progress = desc
        newRun.handleCode = handleCode
        newRun.finishTime = finishTime.isEmpty ? VM.nowText() : finishTime
        lastResult = newRun
        running = nil
        busy = false
        store.addCommandHistory(cmd: run.cmd, name: run.name, success: ok,
                                duration: Date().timeIntervalSince(runStartedAt),
                                confirmed: !neutral)

        Task { @MainActor in
            if let ctrl = try? await APIClient.shared.getControl(carId: store.carId) {
                store.saveCache(["control": ctrl])
            }
        }

        TokensHaptic.result(ok)
        ToastManager.shared.show(ok ? "\(run.name)已完成" : "\(run.name)失败",
                                        icon: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
        showResult = true
    }


    func clearIfIdle() {
        if running != nil && pollTask == nil {
            running = nil
            busy = false
        }
    }

    func abandon() {
        pollTask?.cancel()
        pollTask = nil
        running = nil
        busy = false
        showResult = false
    }
}
