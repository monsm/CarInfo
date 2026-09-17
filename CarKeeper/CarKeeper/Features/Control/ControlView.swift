import SwiftUI

// 车控：锁车/解锁 + 指令列表 + PIN 数字键盘弹层 + 温度 Stepper + 指令轮询
struct ControlView: View {
    private let store = AppStore.shared

    private let hero: [(key: String, name: String, symbol: String)] = [
        ("LockDoor", "锁车", "lock.fill"),
        ("UnLockDoor", "解锁", "lock.open.fill")
    ]
    private let list: [(key: String, name: String, symbol: String, note: String?)] = [
        ("OpenAir", "开启空调", "snowflake", "需设置温度"),
        ("CloseAir", "关闭空调", "snowflake.slash", nil),
        ("FlashLight", "闪灯", "lightbulb", nil),
        ("Whistle", "鸣笛", "speaker.wave.2", nil),
        ("RemoteSearchCar", "远程寻车", "location", nil)
    ]

    @State private var busy = false
    @State private var running: RunState? = nil
    @State private var history: [RunState] = []
    @State private var showPin = false
    @State private var showTemp = false
    @State private var pendingCmd = ""
    @State private var pendingTemp = 25
    @State private var pinDigits = ""
    @State private var pollTask: Task<Void, Never>? = nil

    struct RunState: Identifiable {
        let id: Int
        var cmd: String
        var name: String
        var startedAt: String
        var taskId: String
        var status: String
        var progress: String
        var resultText: String
        var resultCls: String
    }

    private static let seq: () -> Int = {
        var n = 0
        let lock = NSLock()
        return { lock.lock(); n += 1; lock.unlock(); return n }
    }()

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.cardSpacing) {
                // 车辆选择
                let carSel = VM.carSel(store.cars, store.carId)
                Picker("车辆", selection: Binding(
                    get: { carSel.index },
                    set: { store.selectCar($0) }
                )) {
                    ForEach(Array(carSel.options.enumerated()), id: \.offset) { idx, opt in
                        Text(opt.name).tag(idx)
                    }
                }
                .pickerStyle(.menu)

                // 主控双盘
                HStack(spacing: 24) {
                    ForEach(hero, id: \.key) { item in
                        VStack(spacing: 8) {
                            Button {
                                onCmd(item.key)
                            } label: {
                                ZStack {
                                    Circle().fill(Color(.systemGray6)).frame(width: 72, height: 72)
                                    Image(systemName: item.symbol).font(.system(size: 28)).foregroundStyle(.primary)
                                }
                                .opacity(busy || running != nil ? 0.4 : 1)
                            }
                            .disabled(busy || running != nil)
                            Text(item.name).font(.system(size: 14, weight: .medium))
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)

                // 执行中进度条
                if let run = running {
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text(run.name).font(.system(size: 15, weight: .medium))
                        Text(run.progress.isEmpty ? "正在等待车辆响应…" : run.progress)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                // 远程指令
                CardBox(title: "远程控制") {
                    VStack(spacing: 0) {
                        ForEach(Array(list.enumerated()), id: \.offset) { idx, item in
                            HStack {
                                Image(systemName: item.symbol).frame(width: 24).foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name).font(.system(size: 15))
                                    if let note = item.note {
                                        Text(note).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                            }
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                            .onTapGesture { onCmd(item.key) }
                            if idx < list.count - 1 { Divider() }
                        }
                    }
                    .disabled(busy || running != nil)
                    .opacity(busy || running != nil ? 0.5 : 1)
                }

                // 记录
                if !history.isEmpty {
                    CardBox(title: "记录") {
                        ForEach(history) { item in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name).font(.system(size: 14, weight: .medium))
                                    Text(item.resultText).font(.caption).foregroundStyle(Theme.statusColor(item.resultCls))
                                }
                                Spacer()
                                Text(item.startedAt.suffix(5)).font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 90)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("车控")
        .sheet(isPresented: $showPin) {
            PINKeypadView()
                .onReceive(NotificationCenter.default.publisher(for: .pinConfirmed)) { note in
                    if let pin = note.object as? String {
                        pinDigits = pin
                        showPin = false
                        execute(pin)
                    }
                }
        }
        .sheet(isPresented: $showTemp) {
            ACStepperView(initialTemp: $pendingTemp)
                .onReceive(NotificationCenter.default.publisher(for: .tempConfirmed)) { note in
                    if let t = note.object as? Int {
                        pendingTemp = t
                        showTemp = false
                        showPin = true
                    }
                }
        }
        .onDisappear {
            pollTask?.cancel()
        }
    }

    private func onCmd(_ key: String) {
        guard !busy, running == nil else { return }
        guard !store.carId.isEmpty else {
            print("请先选择车辆"); return
        }
        pendingCmd = key
        if key == "OpenAir" { showTemp = true }
        else { showPin = true }
    }

    private func execute(_ pin: String) {
        let cmd = pendingCmd
        guard !cmd.isEmpty else { return }
        let temperature = cmd == "OpenAir" ? pendingTemp : 17
        busy = true
        let startedAt = VM.nowText()
        let run = RunState(id: Self.seq(), cmd: cmd, name: nameOf(cmd), startedAt: startedAt,
                            taskId: "", status: "run", progress: "", resultText: "", resultCls: "")
        running = run

        Task { @MainActor in
            do {
                let data = try await APIClient.shared.sendControlCommand(cmd: cmd, carId: store.carId, pin: pin, temperature: temperature)
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

    private func startPolling(taskId: String, run: RunState) {
        pollTask?.cancel()
        pollTask = Task { @MainActor in
            var i = 0
            while !Task.isCancelled {
                i += 1
                let r = await APIClient.shared.getControlInfo(carId: store.carId, taskId: taskId)
                guard let d = r.data else {
                    running?.progress = "查询异常，重试中…"
                    if i >= 12 { finish(run, ok: false, text: "结果待确认", desc: "60秒未收到车辆终态") }
                    try? await Task.sleep(for: .seconds(5)); continue
                }
                let status = ciString(d, ["HandleStatus"]) ?? ""
                let finals = ["Success", "Completed", "RunFailure", "Failed", "Timeout"]
                if finals.contains(status) {
                    let ok = ["Success", "Completed"].contains(status)
                    let desc = ciString(d, ["HandleStatusDesc"]) ?? ""
                    finish(run, ok: ok, text: ok ? "执行成功" : "执行失败", desc: desc)
                    return
                }
                running?.progress = "第 \(i) 次查询"
                if i >= 12 { finish(run, ok: false, text: "结果待确认", desc: "60秒未收到车辆终态"); return }
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private func finish(_ run: RunState, ok: Bool, text: String, desc: String) {
        pollTask?.cancel()
        let cls = ok ? "ok" : "bad"
        var newRun = run
        newRun.status = ok ? "ok" : "bad"
        newRun.resultText = text
        newRun.resultCls = cls
        newRun.progress = desc
        running = nil
        busy = false
        history.insert(newRun, at: 0)
        if history.count > 6 { history.removeLast() }
        // 静默回刷车辆状态
        Task { @MainActor in
            if let ctrl = try? await APIClient.shared.getControl(carId: store.carId) {
                store.saveCache(["control": ctrl])
            }
        }
    }

    private func nameOf(_ key: String) -> String {
        hero.first { $0.key == key }?.name ?? list.first { $0.key == key }?.name ?? key
    }
}

// MARK: - PIN 数字键盘弹层（输满自动执行）

extension Notification.Name {
    static let pinConfirmed = Notification.Name("car_pin_confirmed")
    static let tempConfirmed = Notification.Name("car_temp_confirmed")
}

struct PINKeypadView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var pin = ""
    private let keys = ["1","2","3","4","5","6","7","8","9","","0","del"]

    var body: some View {
        VStack(spacing: 20) {
            Capsule().fill(.secondary.opacity(0.4)).frame(width: 40, height: 5)
            Text("输入控车码").font(.headline)
            Text("6 位数字 · 输满后自动执行").font(.caption).foregroundStyle(.secondary)

            HStack(spacing: 10) {
                ForEach(0..<6, id: \.self) { i in
                    Text(i < pin.count ? String(pin[pin.index(pin.startIndex, offsetBy: i)]) : "·")
                        .font(.system(size: 28, weight: .medium, design: .rounded))
                        .frame(width: 40, height: 52)
                        .background(RoundedRectangle(cornerRadius: 8).fill(.background))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(i == pin.count ? Color.accentColor : Color(.systemGray4), lineWidth: 2))
                }
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(keys, id: \.self) { k in
                    Button {
                        onKey(k)
                    } label: {
                        Group {
                            if k == "del" { Image(systemName: "delete.left") }
                            else if k == "" { Color.clear }
                            else { Text(k) }
                        }
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.systemGray6)))
                        .font(.system(size: 24, weight: .medium))
                    }
                }
            }

            HStack(spacing: 16) {
                Button("取消") { dismiss() }
                    .buttonStyle(.bordered)
                Button("确认") { confirm() }
                    .buttonStyle(.borderedProminent)
                    .disabled(pin.count != 6)
            }
        }
        .padding(24)
        .presentationDetents([.large])
    }

    private func onKey(_ k: String) {
        if k == "del" { if !pin.isEmpty { pin.removeLast() } }
        else if !k.isEmpty { pin = String((pin + k).prefix(6)) }
        if pin.count == 6 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { confirm() }
        }
    }

    private func confirm() {
        guard pin.count == 6 else { return }
        NotificationCenter.default.post(name: .pinConfirmed, object: pin)
        dismiss()
    }
}

// MARK: - 空调温度弹层（Stepper 17–33℃）

struct ACStepperView: View {
    @Environment(\.dismiss) private var dismiss
    @State var temp: Int
    @State private var useSystem: Bool = true

    init(initialTemp: Binding<Int>) {
        _temp = State(initialValue: initialTemp.wrappedValue)
    }

    var body: some View {
        VStack(spacing: 24) {
            Capsule().fill(.secondary.opacity(0.4)).frame(width: 40, height: 5)
            Text("空调温度").font(.headline)
            Text("设置范围 17 – 33 ℃").font(.caption).foregroundStyle(.secondary)

            HStack(spacing: 28) {
                Button { if temp > 17 { temp -= 1 } } label: {
                    Image(systemName: "minus.circle.fill").font(.system(size: 40)).foregroundStyle(.secondary)
                }
                VStack(spacing: 2) {
                    Text("\(temp)").font(Theme.d1)
                    Text("℃").font(.caption).foregroundStyle(.secondary)
                }
                Button { if temp < 33 { temp += 1 } } label: {
                    Image(systemName: "plus.circle.fill").font(.system(size: 40)).foregroundStyle(.secondary)
                }
            }

            Text("设置后立即开启空调制冷").font(.caption).foregroundStyle(.secondary)

            HStack(spacing: 16) {
                Button("取消") { dismiss() }
                    .buttonStyle(.bordered)
                Button("确认") {
                    NotificationCenter.default.post(name: .tempConfirmed, object: temp)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .presentationDetents([.medium])
    }
}
