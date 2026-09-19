import SwiftUI

// 车控 —— iOS 27 Liquid Glass：
// 渐变主控双盘 + 玻璃指令列表 + 执行进度卡 + PIN 数字键盘 / 温度弹层。
// 指令与轮询逻辑不变。

struct ControlView: View {
    private let store = AppStore.shared

    private let hero: [(key: String, name: String, symbol: String)] = [
        ("LockDoor", "锁车", "lock.fill"),
        ("UnLockDoor", "解锁", "lock.open.fill")
    ]
    // 高频指令（默认展示）
    private let mainCommands: [(key: String, name: String, symbol: String, note: String?)] = [
        ("OpenAir", "开启空调", "snowflake", "需设置温度"),
        ("CloseAir", "关闭空调", "snowflake.slash", nil)
    ]
    // 低频指令（折叠区）
    private let moreCommands: [(key: String, name: String, symbol: String, note: String?)] = [
        ("FlashLight", "闪灯", "lightbulb", nil),
        ("Whistle", "鸣笛", "speaker.wave.2", nil),
        ("RemoteSearchCar", "远程寻车", "location", nil)
    ]

    @State private var busy = false
    @State private var running: RunState? = nil
    @State private var history: [RunState] = []
    @State private var showPin = false
    @State private var showTemp = false
    @State private var showResult = false
    @State private var showMoreCommands = false
    @State private var pendingCmd = ""
    @State private var pendingTemp = 25
    @State private var pinDigits = ""
    @State private var pollTask: Task<Void, Never>? = nil
    @State private var lastResult: RunState? = nil
    // lastResult 由 resultSheet 直接使用，保留
    @State private var tempDisplayCount: Int = 0   // HeroDisc 温度数字滚动计数（0→pendingTemp）

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
        var handleCode: String = ""
        var finishTime: String = ""
    }

    private static let seq: () -> Int = {
        var n = 0
        let lock = NSLock()
        return { lock.lock(); n += 1; lock.unlock(); return n }
    }()

    var body: some View {
        ScrollView {
            VStack(spacing: DynamicTypeScale.spacing(Theme.cardSpacing, dynamicTypeSize)) {
                carSelector
                heroDiscs
                if let run = running { runningCard(run) }
                commandCard
                if let bd = bodyDetail { bodyDetailCard(bd) }
                if !history.isEmpty { historyCard }
            }
            .adaptivePagePadding(dynamicTypeSize)
            .adaptiveSafeAreaBottom(12, dynamicTypeSize)
        }
        .scrollBounceBehavior(.basedOnSize)
        .refreshable {
            tempDisplayCount = 0            // 数字归零
            withAnimation(.spring(Theme.Duration.springFast)) {
                try? await refreshControlCache()
            }
            // 数据回来后自动重播计数动画（pendingTemp 不变，onChange 会触发）
        }
        .pageBackground(Theme.pageBlue)
        .navigationTitle("车控").navBarStyle()
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
        // MARK: 车身明细（车门/窗/灯状态）
    private var bodyDetail: (summary: String, cls: String, doorRows: [(String, String, String)], windowRows: [(String, String, String)], extraRows: [(String, String, String)], lampRows: [(String, String)])? {
        guard let ctrl = ciVal(store.caches, "control") else { return nil }
        let hasCtrl = ctrl.count > 0
        guard hasCtrl else { return nil }
        
        func num(_ k: String) -> Int? {
            ciNumber(ctrl, [k])
        }
        func s(_ k: String) -> String? {
            ciString(ctrl, [k])
        }
        
        var doorRows: [(String, String, String)] = []
        let doorDefs: [(String, String, String)] = [
            ("左前门", "LeftFrontDoor", "LeftFrontDoorLock"),
            ("右前门", "RightFrontDoor", "RightFrontDoorLock"),
            ("左后门", "LeftRearDoor", "LeftRearDoorLock"),
            ("右后门", "RightRearDoor", "RightRearDoorLock")
        ]
        for (label, doorK, lockK) in doorDefs {
            let d = num(doorK), lk = num(lockK)
            if d == nil && lk == nil { continue }
            let parts: [String] = [
                d.map { $0 == 0 ? "已关" : "开启" },
                lk.map { $0 == 0 ? "已锁" : "未锁" }
            ].compactMap { $0 }
            if !parts.isEmpty {
                doorRows.append((label, parts.joined(separator: " · "), d != nil && d! != 0 || lk != nil && lk! != 0 ? "bad" : "ok"))
            }
        }
        
        var windowRows: [(String, String, String)] = []
        let winDefs: [(String, String, String)] = [
            ("左前窗", "LeftAnteriorWindowDegree"),
            ("右前窗", "RightAnteriorWindowDegree"),
            ("左后窗", "LeftRearWindowDegree"),
            ("右后窗", "RightRearWindowDegree")
        ]
        for (label, degK) in winDefs {
            let deg = num(degK)
            if deg == nil { continue }
            let v = deg == 0 ? "关闭" : "开启 \(deg!)°"
            windowRows.append((label, v, deg != 0 ? "bad" : "ok"))
        }
        
        var lampRows: [(String, String)] = []
        let lampDefs: [(String, String, String?)] = [
            ("近光灯", "LowBeam", nil),
            ("远光灯", "HighBeam", nil),
            ("前雾灯", "FrontFoglamp", "FrontFogLight"),
            ("后雾灯", "RearFoglamp", "RearFogLight"),
            ("示廓灯", "PositionLamp", "PositionLight"),
            ("左转向灯", "LeftTurnSignal", "TurnLndicatorLeft"),
            ("右转向灯", "RightTurnSignal", "TurnLndicatorRight")
        ]
        for (label, k1, k2) in lampDefs {
            let x1 = num(k1), x2 = k2.map { num($0) }
            if x1 == nil && x2 == nil { continue }
            let isOn = (x1 != nil && x1! != 0) || (x2 != nil && x2! != 0)
            lampRows.append((label, isOn ? "亮" : "灭"))
        }
        
        // 舱盖/天窗（引擎盖/天窗）
        var extraRows: [(String, String, String)] = []
        if let hood = ciNumber(ctrl, ["Hood", "hood"]) {
            let v = hood == 0 ? "关闭" : "开启"
            extraRows.append(("引擎盖", v, hood != 0 ? "bad" : "ok"))
        }
        if let sunroof = ciNumber(ctrl, ["Sunroof", "sunroof"]) {
            let v = sunroof == 0 ? "关闭" : "开启"
            extraRows.append(("天窗", v, sunroof != 0 ? "bad" : "ok"))
        }
        let badCount = doorRows.filter { $0.2 == "bad" }.count + windowRows.filter { $0.2 == "bad" }.count + extraRows.filter { $0.2 == "bad" }.count
        let summary = doorRows.isEmpty && windowRows.isEmpty && lampRows.isEmpty
            ? "--"
            : (badCount > 0 ? "\(badCount) 项异常" : "全部正常")
        let cls = badCount > 0 ? "bad" : "ok"
        
        return (summary: summary, cls: cls, doorRows: doorRows, windowRows: windowRows, extraRows: extraRows, lampRows: lampRows)
    }
    
    private func bodyDetailCard(_ bd: (summary: String, cls: String, doorRows: [(String, String, String)], windowRows: [(String, String, String)], extraRows: [(String, String, String)], lampRows: [(String, String)])) -> some View {
        ExpandingCardBox(title: "车身状态", side: bd.summary, sideCls: bd.cls, cornerRadius: Theme.Radius.card) {
            VStack(spacing: 8) {
                if !bd.doorRows.isEmpty {
                    sectionLabel("车门")
                    ForEach(Array(bd.doorRows.enumerated()), id: \.offset) { _, r in
                        HStack {
                            Text(r.0).font(Theme.caption)).foregroundStyle(.secondary)
                            Spacer()
                            Text(r.1).font(Theme.caption)))
                                .foregroundStyle(r.2 == "bad" ? Theme.bad : .primary)
                        }
                    }
                }
                if !bd.windowRows.isEmpty {
                    sectionLabel("车窗")
                    ForEach(Array(bd.windowRows.enumerated()), id: \.offset) { _, r in
                        HStack {
                            Text(r.0).font(Theme.caption)).foregroundStyle(.secondary)
                            Spacer()
                            Text(r.1).font(Theme.caption)))
                                .foregroundStyle(r.2 == "bad" ? Theme.bad : .primary)
                        }
                    }
                }
                if !bd.extraRows.isEmpty {
                    sectionLabel("舱盖/天窗")
                    ForEach(Array(bd.extraRows.enumerated()), id: \.offset) { _, r in
                        HStack {
                            Text(r.0).font(Theme.caption)).foregroundStyle(.secondary)
                            Spacer()
                            Text(r.1).font(Theme.caption)))
                                .foregroundStyle(r.2 == "bad" ? Theme.bad : .primary)
                        }
                    }
                }
                if !bd.lampRows.isEmpty {
                    sectionLabel("灯光")
                    let lit = bd.lampRows.filter { $0.1 == "亮" }
                    if !lit.isEmpty {
                        Text(lit.map { $0.0 }.joined(separator: " · "))
                            .font(Theme.caption)).foregroundStyle(Theme.warn)
                    } else {
                        Text("全部关闭").font(Theme.caption)).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
    
    private func sectionLabel(_ t: String) -> some View {
        Text(t).font(Theme.footnote.bold()))).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

        .onAppear {
            if running != nil && pollTask == nil {
                running = nil
                busy = false
            }
            // 首次进入时若缓存为空，主动拉一次数据
            if store.caches["control"] == nil {
                Task { await refreshControlCache() }
            }
            if let q = store.pendingQuickCtrl {
                store.pendingQuickCtrl = nil
                let cmd = q == "air" ? "OpenAir" : (q == "lock" ? "LockDoor" : "UnLockDoor")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    onCmd(cmd)
                }
            }
        }
        .onDisappear {
            pollTask?.cancel()
            showResult = false
        }
        .sheet(isPresented: $showResult) { resultSheet }
    }

    // MARK: 车辆切换
    private var carSelector: some View {
        let carSel = VM.carSel(store.cars, store.carId)
        return HStack(spacing: 10) {
            Image(systemName: "car.2.fill")
                .font(Theme.caption))
                .foregroundStyle(Theme.brand)
            Picker("车辆", selection: Binding(
                get: { carSel.index },
                set: { store.selectCar($0) }
            )) {
                ForEach(Array(carSel.options.enumerated()), id: \.offset) { idx, opt in
                    Text(opt.name).tag(idx)
                }
            }
            .font(Theme.h4)))
            Spacer()
        }
        .adaptivePagePadding(dynamicTypeSize).padding(.vertical, 12)
        .dynamicTypeCompress()
        .glassCard(corner: 20)
        .glassLongPressDeform()
    }

    // MARK: 主控双盘
    private var heroDiscs: some View {
        HStack(spacing: 20) {
            ForEach(Array(hero.enumerated()), id: \.element.key) { idx, item in
                heroDisc(item, idx: idx)
            }
            ACHeroDisc(pendingTemp: $pendingTemp, displayCount: $tempDisplayCount)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .dynamicTypeCompress()
        .glassCard()
        .glassLongPressDeform()
    }

    private func heroDisc(_ item: (key: String, name: String, symbol: String), idx: Int) -> some View {
        HeroDiscButton(key: item.key, name: item.name, symbol: item.symbol, disabled: busy || running != nil, appearDelay: Double(idx) * 0.08) { onCmd(item.key) }
    }

    // MARK: 执行中（带呼吸光晕）
    private func runningCard(_ run: RunState) -> some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.regular)
                .tint(Theme.brand)
            VStack(alignment: .leading, spacing: 3) {
                Text(run.name).font(Theme.h4)))
                Text(run.progress.isEmpty ? "正在等待车辆响应…" : run.progress)
                    .font(Theme.caption)).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .dynamicTypeCompress()
        .glassCard(corner: 20)
        .glassLongPressDeform()
        // 液态玻璃呼吸光晕：品牌色从中心向外扩散脉冲，营造"执行中"活跃感
        .runningGlow(color: Theme.brand)
    }

    // MARK: 指令列表
    private var commandCard: some View {
        CardBox(title: "远程控制", side: busy || running != nil ? "执行中" : nil, sideCls: "acc") {
            VStack(spacing: 0) {
                // 高频指令（默认展示）
                ForEach(Array(mainCommands.enumerated()), id: \.offset) { idx, item in
                    cmdRow(item)
                    if idx < mainCommands.count - 1 || showMoreCommands { ListDivider() }
                }
                // 低频指令（可折叠）
                if showMoreCommands {
                    ForEach(Array(moreCommands.enumerated()), id: \.offset) { idx, item in
                        cmdRow(item)
                        if idx < moreCommands.count - 1 { ListDivider() }
                    }
                }
                // 展开/收起按钮
                Button {
                    withAnimation(.spring(Theme.Duration.springFast)) { showMoreCommands.toggle() }
                } label: {
                    HStack {
                        Image(systemName: showMoreCommands ? "chevron.up" : "chevron.down")
                            .font(Theme.footnote.bold())))
                            .foregroundStyle(.tertiary)
                        Text(showMoreCommands ? "收起" : "更多指令")
                            .font(Theme.caption)))
                            .foregroundStyle(.accentColor)
                        Spacer()
                    }
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func cmdRow(_ item: (key: String, name: String, symbol: String, note: String?)) -> some View {
        Button {
            onCmd(item.key)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: item.symbol)
                    .font(Theme.bodyMd)))
                    .foregroundStyle(Theme.brand)
                    .frame(width: 30, height: 30)
                    .background(.thin, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name).font(Theme.body)))
                    if let note = item.note {
                        Text(note).font(Theme.footnote)).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(Theme.footnote.bold())))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(busy || running != nil)
        .opacity(busy || running != nil ? 0.45 : 1)
    }

    // MARK: 记录
    private var historyCard: some View {
        ExpandingCardBox(title: "执行记录", side: "\(history.count) 条", sideCls: "na", cornerRadius: Theme.Radius.card) {
            VStack(spacing: 0) {
                ForEach(Array(history.enumerated()), id: \.element.id) { idx, item in
                    HStack(spacing: 12) {
                        StatusDot(cls: item.resultCls)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name).font(Theme.caption)))
                            Text(item.resultText).font(Theme.caption))
                                .foregroundStyle(Theme.statusColor(item.resultCls))
                        }
                        Spacer()
                        Text(item.startedAt.suffix(5))
                            .font(Theme.monoLg))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                    if idx < history.count - 1 { ListDivider() }
                }
            }
        }
    }

    // MARK: 指令执行逻辑（不变）
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
                    running?.progress = "查询异常，重试中…（\(i)/12)"
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
                    finish(run, ok: ok, text: ok ? "执行成功" : "执行失败", desc: desc.isEmpty ? status : desc,
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

    private func finish(_ run: RunState, ok: Bool, text: String, desc: String, handleCode: String = "", finishTime: String = "") {
        pollTask?.cancel()
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
        Task { @MainActor in
            if let ctrl = try? await APIClient.shared.getControl(carId: store.carId) {
                store.saveCache(["control": ctrl])
            }
        }
        // 弹结果详情
        showResult = true
    }

    // MARK: 执行结果详情 Sheet
    private var resultSheet: some View {
        guard let r = lastResult else { return EmptyView().frame(width: 0, height: 0) }
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(r.name).font(Theme.h3) weight: .bold))
                Spacer()
                Pill(text: r.resultText, cls: r.resultCls, dot: false)
            }
            if !r.progress.isEmpty {
                Text(r.progress).font(Theme.caption)).foregroundStyle(.secondary)
            }
            if !r.handleCode.isEmpty {
                KVRow(k: "错误码", v: r.handleCode)
            }
            KVRow(k: "发起时间", v: r.startedAt)
            KVRow(k: "完成时间", v: r.finishTime)
            KVRow(k: "任务 ID", v: r.taskId.isEmpty ? "--" : r.taskId)
            Spacer()
        }
        .padding(Theme.Spacing.xl)
        .presentationDetents([.medium])
    }

    private func nameOf(_ key: String) -> String {
        hero.first { $0.key == key }?.name
        ?? mainCommands.first { $0.key == key }?.name
        ?? moreCommands.first { $0.key == key }?.name
        ?? key
    }

    // MARK: 缓存刷新
    private func refreshControlCache() async {
        if let ctrl = try? await APIClient.shared.getControl(carId: store.carId) {
            store.saveCache(["control": ctrl])
        }
    }
}

// MARK: - 主控双盘按钮（液态玻璃按压回弹）
struct HeroDiscButton: View {
    let key: String
    let name: String
    let symbol: String
    let disabled: Bool
    let appearDelay: CGFloat
    let action: () -> Void
    @State private var isEntered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                ZStack {
                    // 第 0.5 层：EKG 心电图描边流动环（首尾相连，沿圆环持续行进）
                    EKGFloRing(size: 102, color: Theme.brand.opacity(0.45), lineWidth: 1.5, speed: 3.5)

                    // 第 1 层：脉冲光环（持续呼吸，模拟 Liquid Glass 生命感）
                    Circle()
                        .strokeBorder(Theme.brand.opacity(0.25), lineWidth: 1.5)
                        .frame(width: 96, height: 96)
                        .blur(radius: 3)
                        .heartbeatPulse()
                    // 第 2 层：底色填充
                    Circle()
                        .fill(Theme.brand.opacity(0.08))
                        .frame(width: 92, height: 92)
                    // 第 3 层：中层填充
                    Circle()
                        .fill(Theme.brand.opacity(0.12))
                        .frame(width: 80, height: 80)
                    // 第 4 层：清晰边框
                    Circle()
                        .strokeBorder(Theme.brand.opacity(0.30), lineWidth: 1.5)
                        .frame(width: 80, height: 80)
                    // 第 5 层：图标
                    Image(systemName: symbol)
                        .font(Theme.d3))
                        .foregroundStyle(Theme.brand)
                }
                .opacity(disabled ? 0.45 : 1)
                .animation(.easeInOut(duration: 0.2), value: disabled)
                Text(name)
                    .font(Theme.h4)))
                    .foregroundStyle(disabled ? .secondary : .primary)
            }
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        // 入场动画：交错淡入 + 缩放回弹
        .opacity(isEntered ? 1 : 0)
        .scaleEffect(isEntered ? 1.0 : 0.85)
        .animation(.spring(response: 0.55, dampingFraction: 0.7, blendDuration: 0.35).delay(appearDelay), value: isEntered)
        .onAppear { isEntered = true }
        // 液态玻璃按压反馈（统一 PressFeedback）
        .modifier(PressFeedback(pressScale: 0.88, glowColor: Theme.brand, glowIntensity: 1.0,
                                springResponse: 0.4, springDamping: 0.65))
    }
}

// MARK: - 空调温度 HeroDisc（带心跳脉冲 + EKG 流动环 + 数字滚动）
struct ACHeroDisc: View {
    @Binding var pendingTemp: Int
    @Binding var displayCount: Int
    @State private var isEntered = false
    @State private var pulseTrigger: String = ""

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                // 第 0.5 层：EKG 心电图描边流动环
                EKGFloRing(size: 102, color: Theme.brand.opacity(0.45), lineWidth: 1.5, speed: 3.5)

                // 第 1 层：脉冲光环（持续呼吸）
                Circle()
                    .strokeBorder(Theme.brand.opacity(0.25), lineWidth: 1.5)
                    .frame(width: 96, height: 96)
                    .blur(radius: 3)
                    .heartbeatPulse()

                // 第 2 层：底色填充
                Circle()
                    .fill(Theme.brand.opacity(0.08))
                    .frame(width: 92, height: 92)

                // 第 3 层：中层填充
                Circle()
                    .fill(Theme.brand.opacity(0.12))
                    .frame(width: 80, height: 80)

                // 第 4 层：清晰边框
                Circle()
                    .strokeBorder(Theme.brand.opacity(0.30), lineWidth: 1.5)
                    .frame(width: 80, height: 80)

                // 第 5 层：温度数字（流体字体，随容器宽度自动缩放）
                FluidTempHero(String(displayCount))
                    .valuePulse(tint: Theme.brand, watchValue: pulseTrigger)
            }
            .scaleEffect(isEntered ? 1.0 : 0.82)
            .opacity(isEntered ? 1.0 : 0.0)
            .animation(.spring(response: 0.55, dampingFraction: 0.7, blendDuration: 0.35), value: isEntered)
            Text("空调")
                .font(Theme.h4))
                .foregroundStyle(.primary)
        }
        .onAppear {
            isEntered = true
            pulseTrigger = UUID()
            // 从 0 弹性计数到目标温度（入场动画）
            withAnimation(.spring(response: 0.65, dampingFraction: 0.65, blendDuration: 0.9)) {
                displayCount = pendingTemp
            }
        }
        // 温度变化时同步滚动 + 触发脉冲
        .onChange(of: pendingTemp) { newTemp in
            pulseTrigger = UUID()
            withAnimation(.spring(response: 0.5, dampingFraction: 0.65, blendDuration: 0.6)) {
                displayCount = newTemp
            }
        }
    }
}

// MARK: - PIN 数字键盘弹层（玻璃化）

struct PINKeypadView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var pin = ""
    private let keys = ["1","2","3","4","5","6","7","8","9","","0","del"]

    var body: some View {
        VStack(spacing: 22) {
            Capsule().fill(.secondary.opacity(0.4)).frame(width: 40, height: 5)
            VStack(spacing: 4) {
                Text("输入控车码").font(Theme.h2) weight: .bold))
                Text("6 位数字 · 输满后自动执行").font(Theme.caption)).foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                ForEach(0..<6, id: \.self) { i in
                    Text(i < pin.count ? String(pin[pin.index(pin.startIndex, offsetBy: i)]) : "")
                        .font(Theme.d4) weight: .semibold, design: .rounded))
                        .frame(width: 42, height: 54)
                        .background(.thin, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(i == pin.count ? Theme.brand : Color(.systemGray4),
                                          lineWidth: i == pin.count ? 2 : 1))
                }
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(keys, id: \.self) { k in
                    Button {
                        onKey(k)
                    } label: {
                        Group {
                            if k == "del" { Image(systemName: "delete.left") }
                            else if k == "" { Color.clear }
                            else { Text(k) }
                        }
                        .font(Theme.d4) weight: .medium, design: .rounded))
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(.thin, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            Button("取消") { dismiss() }
                .font(Theme.h4)))
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)
        }
        .padding(Theme.Spacing.xxl)
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
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

// MARK: - 空调温度弹层（玻璃化）

struct ACStepperView: View {
    @Environment(\.dismiss) private var dismiss
    @State var temp: Int
    // 数字滚动：从 0 弹性计数到目标温度（入场动画 + 每次变化同步滚动）
    @State private var tempDisplayCount = 0

    init(initialTemp: Binding<Int>) {
        _temp = State(initialValue: initialTemp.wrappedValue)
    }

    var body: some View {
        VStack(spacing: 24) {
            Capsule().fill(.secondary.opacity(0.4)).frame(width: 40, height: 5)
            VStack(spacing: 4) {
                Text("空调温度").font(Theme.h2) weight: .bold))
                Text("设置范围 17 – 33 ℃").font(Theme.caption)).foregroundStyle(.secondary)
            }
            HStack(spacing: 32) {
                tempButton("minus", canDo: temp > 17) { temp -= 1 }
                VStack(spacing: 0) {
                    Text("\(tempDisplayCount)")
                        .font(Theme.d1) weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.brand)
                        .contentTransition(.numericText())
                    Text("℃").font(Theme.caption)).foregroundStyle(.secondary)
                }
                tempButton("plus", canDo: temp < 33) { temp += 1 }
            }
            .padding(.vertical, 8)
            Button {
                NotificationCenter.default.post(name: .tempConfirmed, object: temp)
                dismiss()
            } label: {
                Text("下一步 · 输入控车码")
                    .font(Theme.h3)))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.brand))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            Button("取消") { dismiss() }
                .font(Theme.caption)).foregroundStyle(.secondary)
        }
        .padding(Theme.Spacing.xxl)
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
        // 入场动画：从 0 弹性计数到目标温度
        .onAppear {
            pulseTrigger = UUID()
            withAnimation(.spring(response: 0.65, dampingFraction: 0.65, blendDuration: 0.9)) {
                tempDisplayCount = temp
            }
        }
        // 每次加减按钮触发时同步滚动数字 + 触发脉冲
        .onChange(of: temp) { newTemp in
            pulseTrigger = UUID()
            withAnimation(.spring(response: 0.5, dampingFraction: 0.65, blendDuration: 0.6)) {
                tempDisplayCount = newTemp
            }
        }
    }

    private func tempButton(_ sym: String, canDo: Bool, _ action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            Image(systemName: "\(sym).circle.fill")
                .font(Theme.d0))
                .foregroundStyle(canDo ? Theme.brand : Color(.systemGray4))
        }
        .buttonStyle(.plain)
        .disabled(!canDo)
    }
}
