import SwiftUI
import AVFoundation

// 车控 —— iOS 27 Liquid Glass：
// 渐变主控双盘 + 玻璃指令列表 + 执行进度卡 + PIN 数字键盘 / 温度弹层。
// 指令与轮询逻辑不变。

struct ControlView: View {
    private let store = AppStore.shared

    static let quickAllowlist: Set<String> = [
        "LockDoor", "UnLockDoor", "OpenAir", "CloseAir",
        "FlashLight", "Whistle", "RemoteSearchCar"
    ]

    /// 把首页传来的键解析成可执行指令；不认识的一律不执行（宁可不做，也不做错）
    static func resolveQuick(_ raw: String) -> String? {
        switch raw {
        case "air":  return "OpenAir"
        case "lock": return "LockDoor"
        default:     return quickAllowlist.contains(raw) ? raw : nil
        }
    }

    private let hero: [(key: String, name: String, symbol: String)] = [
        ("LockDoor", "锁车", "lock.fill"),
        ("UnLockDoor", "解锁", "lock.open.fill")
    ]
    // 高频指令（默认展示）
    private let mainCommands: [(key: String, name: String, symbol: String, note: String?)] = [
        ("OpenAir", "开启空调", "snowflake", "需设置温度"),
        ("CloseAir", "关闭空调", "power", nil)
    ]
    // 低频指令（折叠区）
    private let moreCommands: [(key: String, name: String, symbol: String, note: String?)] = [
        ("FlashLight", "闪灯", "lightbulb", nil),
        ("Whistle", "鸣笛", "speaker.wave.2", nil),
        ("RemoteSearchCar", "远程寻车", "location", nil)
    ]
    // #18 快捷预设场景
    private let presetScenes: [(key: String, name: String, symbol: String, commands: [String], note: String?)] = [
        ("winterPreheat", "冬天预热", "snowflake", ["OpenAir"], "22℃ 座椅加热 + 后窗除雾"),
        ("summerCool", "夏天降温", "sun.max.fill", ["OpenAir"], "18℃ 强冷模式"),
        ("lockAll", "一键锁车", "lock.fill", ["LockDoor"], "锁车 + 关窗 + 折叠后视镜"),
    ]

    @State private var busy = false
    @State private var running: RunState? = nil
    @State private var history: [RunState] = []
    @State private var showPin = false
    @State private var showBiometricLock = false  // #N13 生物识别二次验证
    @State private var isAuthenticated = false
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
    @State private var isRefreshing = false         // 下拉刷新进行中
    @EnvironmentObject var nav: NavState            // C3: 用于 pushNavigation

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

    private var bodyDetail: (
        summary: String, cls: String,
        doorRows: [(String, String, String)],
        windowRows: [(String, String, String)],
        extraRows: [(String, String, String)],
        lampRows: [(String, String)]
    )? {
        guard let ctrl = ciVal(store.caches, "control") else { return nil }
        let hasCtrl = ctrl.count > 0
        guard hasCtrl else { return nil }

        func num(_ k: String) -> Int? {
            ciNumberInt(ctrl, [k])
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
                let isBad = d != nil && d! != 0 || lk != nil && lk! != 0
                doorRows.append((label, parts.joined(separator: " · "), isBad ? "bad" : "ok"))
            }
        }

        var windowRows: [(String, String, String)] = []
        let winDefs: [(String, String, String)] = [
            ("左前窗", "LeftAnteriorWindowDegree", ""),
            ("右前窗", "RightAnteriorWindowDegree", ""),
            ("左后窗", "LeftRearWindowDegree", ""),
            ("右后窗", "RightRearWindowDegree", "")
        ]
        for (label, degK, _) in winDefs {
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
        let badDoors = doorRows.filter { $0.2 == "bad" }.count
        let badWindows = windowRows.filter { $0.2 == "bad" }.count
        let badExtra = extraRows.filter { $0.2 == "bad" }.count
        let badCount = badDoors + badWindows + badExtra
        let summary = doorRows.isEmpty && windowRows.isEmpty && lampRows.isEmpty
            ? "--"
            : (badCount > 0 ? "\(badCount) 项异常" : "全部正常")
        let cls = badCount > 0 ? "bad" : "ok"

        return (summary: summary, cls: cls,
                doorRows: doorRows, windowRows: windowRows,
                extraRows: extraRows, lampRows: lampRows)
    }
    private func bodyDetailCard(
        _ bd: (summary: String, cls: String,
               doorRows: [(String, String, String)],
               windowRows: [(String, String, String)],
               extraRows: [(String, String, String)],
               lampRows: [(String, String)])) -> some View {
        ExpandingCardBox(title: "车身状态", side: bd.summary, sideCls: bd.cls, cornerRadius: KanseiRadius.medium) {
            VStack(spacing: 8) {
                if !bd.doorRows.isEmpty {
                    sectionLabel("车门")
                    ForEach(Array(bd.doorRows.enumerated()), id: \.offset) { _, r in
                        HStack {
                            Text(r.0).font(Theme.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text(r.1).font(Theme.caption)
                                .foregroundStyle(r.2 == "bad" ? Theme.bad : .primary)
                        }
                    }
                }
                if !bd.windowRows.isEmpty {
                    sectionLabel("车窗")
                    ForEach(Array(bd.windowRows.enumerated()), id: \.offset) { _, r in
                        HStack {
                            Text(r.0).font(Theme.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text(r.1).font(Theme.caption)
                                .foregroundStyle(r.2 == "bad" ? Theme.bad : .primary)
                        }
                    }
                }
                if !bd.extraRows.isEmpty {
                    sectionLabel("舱盖/天窗")
                    ForEach(Array(bd.extraRows.enumerated()), id: \.offset) { _, r in
                        HStack {
                            Text(r.0).font(Theme.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text(r.1).font(Theme.caption)
                                .foregroundStyle(r.2 == "bad" ? Theme.bad : .primary)
                        }
                    }
                }
                if !bd.lampRows.isEmpty {
                    sectionLabel("灯光")
                    let lit = bd.lampRows.filter { $0.1 == "亮" }
                    if !lit.isEmpty {
                        Text(lit.map { $0.0 }.joined(separator: " · "))
                            .font(KanseiTypo.caption).foregroundStyle(KanseiPalette.warning)
                    } else {
                        Text("全部关闭").font(KanseiTypo.caption).foregroundStyle(KanseiPalette.secondary)
                    }
                }
            }
        }
    }
    private func sectionLabel(_ t: String) -> some View {
        Text(t).font(Theme.font(.footnote as Font).bold()).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.gap) {
                controlHeader
                primarySceneButton
                if let run = running { runningCard(run) }
                if let bd = bodyDetail { bodyDetailCard(bd) }
                commandCard
                presetScenesCard
                SiriShortcutsCard()
                if !history.isEmpty { historyCard }
            }
            .padding(.top, DS.Space.sm)
            .padding(.bottom, DS.Space.huge)
        }
        .scrollBounceBehavior(.basedOnSize)
        .refreshable {
            tempDisplayCount = 0
            // 数字归零
            Task {
                await refreshControlCache()
            }
            // 数据回来后自动重播计数动画（pendingTemp 不变，onChange 会触发）
        }
        .background(KanseiPalette.background)
        .navigationTitle("车控")
            .accessibilityLabel(Text("车控"))
            .accessibilityHint(Text("远程控制车辆：锁车、解锁、空调、座椅加热"))
        // #35 语音播报入口
        .toolbar {
            if !UIAccessibility.isSpeakScreenEnabled {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        speakStatus()
                    } label: {
                        Image(systemName: "speaker.wave.3.fill")
                    }
                    .accessibilityLabel(Text("语音播报车况"))
                }
            }
        }
        .sheet(isPresented: $showPin) {
            PINKeypadView()
                .onReceive(NotificationCenter.default.publisher(for: .pinConfirmed)) { note in
                    if let pin = note.object as? String {
                        pinDigits = pin
                        showPin = false
                        // #8 首次输入PIN后保存到Keychain
                        if store.readPin() == nil {
                            store.savePin(pin)
                            EnhancedToastManager.shared.show("PIN码已安全保存", icon: "key.fill")
                        }
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
                // 首页传过来的是协议里的真实指令名，原样执行；同时兼容历史的 "air"/"lock" 简写。
                // （旧代码把除这两个简写外的一切都当成 UnLockDoor —— 于是首页的「锁车」
                //   会反向把车解锁。这是真 bug，不能靠“反正只有两个键”蒙过去。）
                let cmd = Self.resolveQuick(q)
                if let cmd {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                        onCmd(cmd)
                    }
                }
            }
        }
        .onDisappear {
            pollTask?.cancel()
            showResult = false
        }
        .sheet(isPresented: $showResult) { resultSheet }
        // #N13 生物识别验证覆盖层
        .overlay {
            if showBiometricLock {
                BiometricLockOverlay(isAuthenticated: $isAuthenticated)
                    .onAppear { isAuthenticated = false }
                    .onChange(of: isAuthenticated) { _, auth in
                        if auth {
                            showBiometricLock = false
                            showPin = true  // 验证通过后进入 PIN 输入
                        }
                    }
            }
        }
    }

    // MARK: 头部（v4：读数就在车上 —— 一屏不堆卡片）
    private var controlHeader: some View {
        let carSel = VM.carSel(store.cars, store.carId)
        let name = carSel.options.indices.contains(carSel.index)
            ? carSel.options[carSel.index].name : "未绑定车辆"

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DS.Space.sm) {
                if carSel.count > 1 {
                    Picker("车辆", selection: Binding(
                        get: { carSel.index },
                        set: { store.selectCar($0) }
                    )) {
                        ForEach(Array(carSel.options.enumerated()), id: \.offset) { idx, opt in
                            Text(opt.name).tag(idx)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .font(DS.Typo.subheadline.weight(.semibold))
                    .tint(KanseiPalette.primary)
                } else {
                    Text(name)
                        .font(DS.Typo.subheadline.weight(.semibold))
                        .foregroundStyle(KanseiPalette.primary)
                        .lineLimit(1)
                }
                Spacer(minLength: DS.Space.sm)
                if let bd = bodyDetail {
                    DSChip(text: bd.summary, cls: bd.cls)
                }
            }

            CarTopView(
                doorCls: doorStates(),
                trunkOpen: trunkIsOpen(),
                windowsOpen: windowsAreOpen()
            )
            .frame(height: 286)
            .padding(.vertical, DS.Space.sm)

            Text(statusLineText())
                .font(DS.Typo.footnote)
                .foregroundStyle(KanseiPalette.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    /// 一屏唯一的实心胶囊：状态有问题时就是“锁车关窗”，否则是降温场景
    private var primarySceneButton: some View {
        let issue = bodyDetail?.cls == "bad"
        return Button {
            DSHaptic.tap()
            if issue {
                onCmd("LockDoor")
            } else if let scene = presetScenes.first(where: { $0.key == "summerCool" }) {
                onPresetScene(scene)
            }
        } label: {
            Text(issue ? "一键锁车并关窗" : "极速降温 · 18℃ 强冷")
        }
        .buttonStyle(DSPrimaryButtonStyle())
        .accessibilityHint(Text(issue ? "锁车、关窗并折叠后视镜" : "空调设为 18℃ 最强风"))
    }

    /// 四门状态 → ["ok"/"bad"]（左前 / 右前 / 左后 / 右后，与俯视图顺序一致）
    private func doorStates() -> [String] {
        guard let bd = bodyDetail else { return ["ok", "ok", "ok", "ok"] }
        return ["左前门", "右前门", "左后门", "右后门"].map { name in
            bd.doorRows.first { $0.0 == name }?.2 ?? "ok"
        }
    }

    private func trunkIsOpen() -> Bool {
        guard let bd = bodyDetail else { return false }
        let all = bd.doorRows + bd.windowRows + bd.extraRows
        return all.first { $0.0.contains("后备箱") }?.2 == "bad"
    }

    private func windowsAreOpen() -> Bool {
        (bodyDetail?.windowRows.contains { $0.2 == "bad" }) ?? false
    }

    private func statusLineText() -> String {
        guard let bd = bodyDetail else { return "等待车辆上报" }
        let bad = bd.doorRows.filter { $0.2 == "bad" }.map { $0.0 }
            + bd.windowRows.filter { $0.2 == "bad" }.map { $0.0 }
        return bad.isEmpty ? "四门已锁 · 车窗已关" : bad.joined(separator: " · ") + " 未关"
    }

    // MARK: 快捷预设场景 (#18)
    private var presetScenesCard: some View {
        CardBox(title: "快捷场景", cornerRadius: KanseiRadius.medium) {
            VStack(spacing: 10) {
                ForEach(Array(presetScenes.enumerated()), id: \.element.key) { idx, scene in
                    Button {
                        onPresetScene(scene)
                    } label: {
                        HStack(spacing: 12) {
                            Image(safeSymbol: scene.symbol, fallback: "car.fill")
                                .font(Theme.bodyMd)
                                .foregroundStyle(KanseiPalette.ambient)
                                .frame(width: 32, height: 32)
                                .background(
                                    KanseiPalette.fillSubtle,
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                                )
                            VStack(alignment: .leading, spacing: 2) {
                                Text(scene.name).font(Theme.body)
                                if let note = scene.note {
                                    Text(note).font(Theme.footnote).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if busy || running != nil {
                                Image(systemName: "clock.fill")
                                    .font(Theme.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Image(systemName: "chevron.right")
                                    .font(Theme.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(busy || running != nil)
                    .opacity(busy || running != nil ? 0.5 : 1)
                    if idx < presetScenes.count - 1 { ListDivider() }
                }
            }
        }
    }

    private func onPresetScene(
        _ scene: (key: String, name: String, symbol: String,
                  commands: [String], note: String?)) {
        // 执行场景内的所有指令（按顺序）
        for _ in scene.commands {
            if !busy && running == nil {
                execute(pinDigits)
            }
        }
    }

    // #35 语音播报车况
    private func speakStatus() {
        let utterance = AVSpeechUtterance(string: "当前车况：电量 \(store.caches["control"] != nil ? "在线" : "离线")，请查看详细报告")
        utterance.rate = 0.5
        utterance.pitchMultiplier = 0.9
        AVSpeechSynthesizer().speak(utterance)
    }

    // MARK: 指令执行中
    private func runningCard(_ run: RunState) -> some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.regular)
                .tint(Theme.brand)
            VStack(alignment: .leading, spacing: 3) {
                Text(run.name).font(Theme.h4)
                Text(run.progress.isEmpty ? "正在等待车辆响应…" : run.progress)
                    .font(Theme.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .dsSurface(padding: DS.Space.lg, radius: DS.RadiusTokens.card)
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
                    withAnimation(Theme.Duration.springFast) { showMoreCommands.toggle() }
                } label: {
                    HStack {
                        Image(systemName: showMoreCommands ? "chevron.up" : "chevron.down")
                            .font(Theme.font(.footnote as Font).bold())
                            .foregroundStyle(.tertiary)
                        Text(showMoreCommands ? "收起" : "更多指令")
                            .font(Theme.caption)
                            .foregroundStyle(KanseiPalette.ambient)
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
                Image(safeSymbol: item.symbol, fallback: "bolt.fill")
                    .font(Theme.bodyMd)
                    .foregroundStyle(Theme.brand)
                    .frame(width: 30, height: 30)
                    .background(KanseiPalette.fillSubtle, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name).font(Theme.body)
                    if let note = item.note {
                        Text(note).font(Theme.footnote).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(Theme.font(.footnote as Font).bold())
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
        ExpandingCardBox(title: "执行记录", side: "\(history.count) 条", sideCls: "na", cornerRadius:
 KanseiRadius.medium) {
            VStack(spacing: 0) {
                ForEach(Array(history.enumerated()), id: \.element.id) { idx, item in
                    HStack(spacing: 12) {
                        StatusDot(cls: item.resultCls)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name).font(Theme.caption)
                            Text(item.resultText).font(Theme.caption)
                                .foregroundStyle(Theme.statusColor(item.resultCls))
                        }
                        Spacer()
                        Text(item.startedAt.suffix(5))
                            .font(Theme.monoLg)
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
        else {
            // #N13 敏感操作先验证生物识别
            if store.canUseBiometric() && store.hasBiometricSetup {
                showBiometricLock = true
            } else {
                showPin = true
            }
        }
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

    private func startPolling(taskId: String, run: RunState) {
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

    private func finish(
        _ run: RunState, ok: Bool, text: String,
        desc: String, handleCode: String = "",
        finishTime: String = ""
    ) {
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
        // #9 同步到 AppStore 全局历史记录
        let duration = Double(newRun.finishTime.split(separator: ":").count > 1 ? 5 : 3)
        store.addCommandHistory(cmd: "", name: "", success: ok, duration: duration)
        Task { @MainActor in
            if let ctrl = try? await APIClient.shared.getControl(carId: store.carId) {
                store.saveCache(["control": ctrl])
            }
        }
        // 弹结果详情
        showResult = true
        // #14 指令成功时 Toast 提示
        if ok { EnhancedToastManager.shared.show("", icon: "checkmark.circle.fill") }
    }

    // MARK: 执行结果详情 Sheet
    @ViewBuilder
    private var resultSheet: some View {
        if let r = lastResult {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(r.name).font(Theme.h3)
                    Spacer()
                    Pill(text: r.resultText, cls: r.resultCls, dot: false)
                }
                if !r.progress.isEmpty {
                    Text(r.progress).font(Theme.caption).foregroundStyle(.secondary)
                }
                if !r.handleCode.isEmpty {
                    KVRow(k: "错误码", v: r.handleCode)
                }
                KVRow(k: "发起时间", v: r.startedAt)
                KVRow(k: "完成时间", v: r.finishTime)
                KVRow(k: "任务 ID", v: r.taskId.isEmpty ? "--" : r.taskId)
                Spacer()
            }
            .padding(KanseiSpacing.xl)
        }
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

// MARK: - 俯视示意图（v4：薄线描、不着色 —— 一辆从天上看得懂的车）
/// 车身是线描，只有「状态」带颜色：绿 = 已关，橙 = 未关。
/// 填色会把示意变成插画，着色会把插画变成儿童 App —— 所以一辆车只用线。
struct CarTopView: View {
    /// 左前 / 右前 / 左后 / 右后
    var doorCls: [String]
    var trunkOpen: Bool
    var windowsOpen: Bool

    private func color(_ cls: String) -> Color {
        cls == "bad" ? KanseiPalette.warning : KanseiPalette.success
    }

    private func doorColor(_ idx: Int) -> Color {
        guard doorCls.indices.contains(idx) else { return KanseiPalette.success }
        return color(doorCls[idx])
    }

    var body: some View {
        Canvas { ctx, size in
            let scale = min(size.width / 320, size.height / 470)
            let dx = (size.width - 320 * scale) / 2
            let dy = (size.height - 470 * scale) / 2
            let t = CGAffineTransform(translationX: dx, y: dy).scaledBy(x: scale, y: scale)
            func xf(_ p: Path) -> Path { p.applying(t) }

            // 地面反光（径向渐变，边界外恒为 0）
            ctx.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .radialGradient(
                    Gradient(colors: [
                        KanseiPalette.primary.opacity(0.06),
                        KanseiPalette.primary.opacity(0.015),
                        KanseiPalette.primary.opacity(0.0)
                    ]),
                    center: CGPoint(x: size.width / 2, y: size.height * 0.52),
                    startRadius: 0,
                    endRadius: size.height * 0.48
                )
            )

            // 车身轮廓（薄线）
            var outline = Path()
            outline.move(to: CGPoint(x: 160, y: 26))
            outline.addCurve(to: CGPoint(x: 254, y: 50),
            control1: CGPoint(x: 206, y: 26),
            control2: CGPoint(x: 240, y: 34))
            outline.addCurve(to: CGPoint(x: 267, y: 96),
            control1: CGPoint(x: 264, y: 61),
            control2: CGPoint(x: 267, y: 76))
            outline.addLine(to: CGPoint(x: 267, y: 250))
            outline.addCurve(to: CGPoint(x: 254, y: 312),
            control1: CGPoint(x: 267, y: 282),
            control2: CGPoint(x: 264, y: 300))
            outline.addCurve(to: CGPoint(x: 160, y: 336),
            control1: CGPoint(x: 240, y: 328),
            control2: CGPoint(x: 206, y: 336))
            outline.addCurve(to: CGPoint(x: 66, y: 312),
            control1: CGPoint(x: 114, y: 336),
            control2: CGPoint(x: 80, y: 328))
            outline.addCurve(to: CGPoint(x: 53, y: 250),
            control1: CGPoint(x: 56, y: 300),
            control2: CGPoint(x: 53, y: 282))
            outline.addLine(to: CGPoint(x: 53, y: 96))
            outline.addCurve(to: CGPoint(x: 66, y: 50),
            control1: CGPoint(x: 53, y: 76),
            control2: CGPoint(x: 56, y: 61))
            outline.addCurve(to: CGPoint(x: 160, y: 26),
            control1: CGPoint(x: 80, y: 34),
            control2: CGPoint(x: 114, y: 26))
            outline.closeSubpath()
            ctx.stroke(xf(outline), with: .color(KanseiPalette.primary.opacity(0.85)),
                       style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))

            // 风挡 / 天窗 / 后风挡
            var windshield = Path()
            windshield.move(to: CGPoint(x: 84, y: 62))
            windshield.addCurve(to: CGPoint(x: 160, y: 42),
            control1: CGPoint(x: 100, y: 48),
            control2: CGPoint(x: 128, y: 42))
            windshield.addCurve(to: CGPoint(x: 236, y: 62),
            control1: CGPoint(x: 192, y: 42),
            control2: CGPoint(x: 220, y: 48))
            windshield.addLine(to: CGPoint(x: 245, y: 84))
            windshield.addLine(to: CGPoint(x: 75, y: 84))
            windshield.closeSubpath()
            ctx.stroke(xf(windshield), with: .color(KanseiPalette.secondary),
                       style: StrokeStyle(lineWidth: 1.3, lineJoin: .round))

            let roof = Path(roundedRect: CGRect(x: 92, y: 98, width: 136, height: 76), cornerRadius: 16)
            ctx.stroke(xf(roof), with: .color(KanseiPalette.secondary), style: StrokeStyle(lineWidth: 1.3))

            var rear = Path()
            rear.move(to: CGPoint(x: 75, y: 278))
            rear.addLine(to: CGPoint(x: 84, y: 316))
            rear.addCurve(to: CGPoint(x: 160, y: 334),
            control1: CGPoint(x: 100, y: 328),
            control2: CGPoint(x: 128, y: 334))
            rear.addCurve(to: CGPoint(x: 236, y: 316),
            control1: CGPoint(x: 192, y: 334),
            control2: CGPoint(x: 220, y: 328))
            rear.addLine(to: CGPoint(x: 245, y: 278))
            rear.closeSubpath()
            ctx.stroke(xf(rear), with: .color(KanseiPalette.secondary), style: StrokeStyle(lineWidth: 1.3))

            // 后视镜
            var mirrorL = Path()
            mirrorL.move(to: CGPoint(x: 56, y: 88))
            mirrorL.addLine(to: CGPoint(x: 40, y: 97))
            mirrorL.addLine(to: CGPoint(x: 43, y: 110))
            mirrorL.addLine(to: CGPoint(x: 57, y: 105))
            mirrorL.closeSubpath()
            var mirrorR = Path()
            mirrorR.move(to: CGPoint(x: 264, y: 88))
            mirrorR.addLine(to: CGPoint(x: 280, y: 97))
            mirrorR.addLine(to: CGPoint(x: 277, y: 110))
            mirrorR.addLine(to: CGPoint(x: 263, y: 105))
            mirrorR.closeSubpath()
            ctx.stroke(xf(mirrorL), with: .color(KanseiPalette.secondary), style: StrokeStyle(lineWidth: 1.3))
            ctx.stroke(xf(mirrorR), with: .color(KanseiPalette.secondary), style: StrokeStyle(lineWidth: 1.3))

            // 四门状态线：绿 = 已关，橙 = 未关
            let doorSpans: [(CGFloat, CGFloat, CGFloat)] = [
                (53, 96, 144), (267, 96, 144), (53, 204, 252), (267, 204, 252)
            ]
            for (idx, span) in doorSpans.enumerated() {
                let c = doorColor(idx)
                var line = Path()
                line.move(to: CGPoint(x: span.0, y: span.1))
                line.addLine(to: CGPoint(x: span.0, y: span.2))
                ctx.drawLayer { layer in
                    layer.addFilter(.blur(radius: 4))
                    layer.opacity = 0.35
                    layer.stroke(xf(line), with: .color(c), style: StrokeStyle(lineWidth: 12, lineCap: .round))
                }
                ctx.stroke(xf(line), with: .color(c), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }

            // 后备箱
            var trunk = Path()
            trunk.move(to: CGPoint(x: 112, y: 336))
            trunk.addLine(to: CGPoint(x: 208, y: 336))
            let trunkColor = trunkOpen ? KanseiPalette.warning : KanseiPalette.success
            if trunkOpen {
                ctx.drawLayer { layer in
                    layer.addFilter(.blur(radius: 5))
                    layer.opacity = 0.3
                    layer.stroke(xf(trunk), with: .color(trunkColor),
                               style: StrokeStyle(lineWidth: 14, lineCap: .round))
                }
            }
            ctx.stroke(xf(trunk), with: .color(trunkColor), style: StrokeStyle(lineWidth: 3, lineCap: .round))

            // 车窗开启时，两侧给一条细橙线
            if windowsOpen {
                var wl = Path()
                wl.move(to: CGPoint(x: 53, y: 96))
                wl.addLine(to: CGPoint(x: 53, y: 250))
                var wr = Path()
                wr.move(to: CGPoint(x: 267, y: 96))
                wr.addLine(to: CGPoint(x: 267, y: 250))
                ctx.stroke(xf(wl), with: .color(KanseiPalette.warning.opacity(0.45)),
                           style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                ctx.stroke(xf(wr), with: .color(KanseiPalette.warning.opacity(0.45)),
                           style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text("车辆俯视状态图"))
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
                Text("输入控车码").font(Theme.h2)
                Text("6 位数字 · 输满后自动执行").font(Theme.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                ForEach(0..<6, id: \.self) { i in
                    Text(i < pin.count ? String(pin[pin.index(pin.startIndex, offsetBy: i)]) : "")
                        .font(Theme.d4)
                        .frame(width: 42, height: 54)
                        .background(KanseiPalette.fillSubtle, in: RoundedRectangle(cornerRadius: 12, style:
 .continuous))
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
                        .font(Theme.d4)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(KanseiPalette.fillSubtle, in: RoundedRectangle(cornerRadius: 14, style:
 .continuous))
                        .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            Button("取消") { dismiss() }
                .font(Theme.h4)
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)
        }
        .padding(Theme.SpacingTokens.xxl)
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
    // 数字滚动：首次对齐目标温度，之后每次变化同步滚动
    @State private var tempDisplayCount = 0

    init(initialTemp: Binding<Int>) {
        _temp = State(initialValue: initialTemp.wrappedValue)
    }

    var body: some View {
        VStack(spacing: 24) {
            Capsule().fill(.secondary.opacity(0.4)).frame(width: 40, height: 5)
            VStack(spacing: 4) {
                Text("空调温度").font(Theme.h2)
                Text("设置范围 17 – 33 ℃").font(Theme.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 32) {
                tempButton("minus", canDo: temp > 17) { temp -= 1 }
                VStack(spacing: 0) {
                    Text("\(tempDisplayCount)")
                        .font(Theme.d1)
                        .foregroundStyle(Theme.brand)
                        .contentTransition(.numericText())
                    Text("℃").font(Theme.caption).foregroundStyle(.secondary)
                }
                tempButton("plus", canDo: temp < 33) { temp += 1 }
            }
            .padding(.vertical, 8)
            Button {
                NotificationCenter.default.post(name: .tempConfirmed, object: temp)
                dismiss()
            } label: {
                Text("下一步 · 输入控车码")
                    .font(Theme.h3)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.brand))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            Button("取消") { dismiss() }
                .font(Theme.caption).foregroundStyle(.secondary)
        }
        .padding(Theme.SpacingTokens.xxl)
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
        // 首次对齐目标温度
        .onAppear {
            withAnimation(.spring(response: 0.65, dampingFraction: 0.65, blendDuration: 0.9)) {
                tempDisplayCount = temp
            }
        }
        // 每次加减按钮触发时同步滚动数字
        .onChange(of: temp) { _, newTemp in
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
                .font(Theme.d0)
                .foregroundStyle(canDo ? Theme.brand : Color(.systemGray4))
        }
        .buttonStyle(.plain)
        .disabled(!canDo)
    }
}
