import SwiftUI

// 车控 —— iOS 27 Liquid Glass：
// 渐变主控双盘 + 玻璃指令列表 + 执行进度卡 + PIN 数字键盘 / 温度弹层。
//
// 指令的下发与轮询**不在这个文件里**，已整体搬到 `CommandCenter`（同目录）：
// 地图上的常驻操作条也要发同一条指令，两边各写一遍迟早会给出不同结果。
// 这一屏只负责「在哪里发起」与「怎么显示状态」。

struct ControlView: View {
    private let store = AppStore.shared

    // 这里原有 `quickAllowlist` + `resolveQuick`（把首页穿透过来的 "air" / "lock"
    // 简写解析成真指令）。批 1 之后地图上的操作条**直接发真实指令名**、并在原地执行,
    // 不再需要「穿过一层简写再解析」这条路 —— 也就少了一个「简写表与指令表不一致」的坑。

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
        ("RemoteSearchCar", "远程寻车", "location", nil),
        // UpCarCondition 来自参考实现（D:/xm/ChangAnCarInfo）的指令枚举，注释写着
        // 「刷新车辆状态TBOX」。它不发任何物理动作，而是**让车端立刻上报一次** ——
        // 车端停报时刷页面没有用：服务端只会回放同一份快照（本次抓包：07:19:28 之后
        // 十几次轮询拿到的数值一字不差）。想让数字变新，只能先把车端叫醒。
        ("UpCarCondition", "刷新车况", "arrow.clockwise", "让车端立刻上报一次状态")
    ]
    // #18 快捷预设场景
    /// 一个场景 = **一条真指令 + 它自己带的温度**。
    /// `note` 里只许写这个场景真的会发出去的东西 —— 旧版三条说明分别写着
    /// 「22℃ 座椅加热 + 后窗除雾」「18℃ 强冷模式」「锁车 + 关窗 + 折叠后视镜」，
    /// 而实际发出去的只有一条 OpenAir、温度还是上一次残留的值。
    /// 遥控制最不能忍的就是这种：按了锁车，界面说还捎带关了窗。
    private struct PresetScene {
        let key: String
        let name: String
        let symbol: String
        let commands: [String]
        /// 空调温度（包含 OpenAir 的场景才有）：这个值真的会被发给车
        let temp: Int?
        /// 一行说明：只写真的会发的东西
        let note: String
    }

    private let presetScenes: [PresetScene] = [
        PresetScene(key: "winterPreheat", name: "冬天预热", symbol: "snowflake",
                    commands: ["OpenAir"], temp: 26,
                    note: "开启空调 26℃"),
        PresetScene(key: "summerCool", name: "夏天降温", symbol: "sun.max.fill",
                    commands: ["OpenAir"], temp: 18,
                    note: "开启空调 18℃"),
        PresetScene(key: "lockAll", name: "一键锁车", symbol: "lock.fill",
                    commands: ["LockDoor"], temp: nil,
                    note: "发一条「锁车」")
    ]

    // 执行状态（busy / running / lastResult / showResult）全部搬到了
    // `CommandCenter` —— 地图上的常驻操作条与这一屏共用同一条执行路径。
    // 下面这些是**只读转发**：一千多行视图代码只读它们，所以一行都不用改；
    // 写入都发生在中心里（也是唯一能写的地方）。
    @ObservedObject private var commands = CommandCenter.shared
    private var busy: Bool { commands.busy }
    private var running: ControlRun? { commands.running }
    private var lastResult: ControlRun? { commands.lastResult }
    private var showResult: Bool { commands.showResult }

    // MARK: 指令历史的状态
    //
    // 历史**不再**读 `CommandCenter.history` —— 那个列表只活在本机内存里、只留 10 条，
    // 而且摇一摇锁车与 Siri 指令（它们直接写 AppStore）在里面根本不出现。
    // 现在唯一的来源是 `store.commandHistory`：持久、含所有发起路径、最多 50 条。
    @State private var historyFilter = "all"
    // 下面三个都不是 `private`：`ControlFit.swift`（同目录）要读它们，
    // 而 `private` 的作用域是**文件**，跨文件看不见（它的头注里有这一条）。
    @State var expandedRuns: Set<UUID> = []
    /// 历史列表被“摊开全部”了吗（见 `ControlFit` 里的 `historyPlan`）
    @State var historyFull = false
    /// 卡片量到的可用区域（`ArcStack` 写进来的真数；量不到时是 `.zero`）
    @Environment(\.cardViewport) var cardViewport

    @State private var showMoreCommands = false
    /// 一条车控请求。验证、温度、下发都在 `controlCommandFlow` 那道门里 ——
    /// 这一页只负责把请求交出去。用户 2026-09-24 指出的两套强度就出在这里：
    /// 地图右臂直接调 `AppStore.sendControlCommand`（拿 Keychain 里的旧码就发），
    /// 而本页要走温度 → 生物识别 → 控车码。现在两边挂的是同一个 modifier。
    @State private var request: ControlRequest?
    /// 车身上点了某一扇门：等用户选「锁车 / 解锁」（见 `onCarPartTap`）。
    @State private var doorPart: CarPart?
    @State private var isRefreshing = false         // 下拉刷新进行中
    // 原先这里还有个 `@EnvironmentObject var nav` —— 全文件一次都没用过
    // （本页从不 push 别的页面），已删。留着的代价是：一旦这一屏改用 sheet 呈现，
    // 环境里缺这个对象会直接崩。`RunState` 与 id 序列也一并搬到了 CommandCenter。

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
        // 折叠分组 + 键值行：与电池页、全量数据页同一套装法。
        // 「未关」真的是状态，所以值走 valueCls（状态色），不再自己写一个三元表达式的颜色。
        DSExpandGroup(title: "车身状态", trailing: bd.summary, trailingCls: bd.cls) {
            if !bd.doorRows.isEmpty {
                DSGroupRow(showsSeparator: true) { sectionLabel("车门") }
                ForEach(Array(bd.doorRows.enumerated()), id: \.offset) { idx, r in
                    DSGroupRow(showsSeparator: idx < bd.doorRows.count - 1) {
                        DSKeyValueRow(key: r.0, value: r.1, valueCls: r.2)
                    }
                }
            }
            if !bd.windowRows.isEmpty {
                DSGroupRow(showsSeparator: true) { sectionLabel("车窗") }
                ForEach(Array(bd.windowRows.enumerated()), id: \.offset) { idx, r in
                    DSGroupRow(showsSeparator: idx < bd.windowRows.count - 1) {
                        DSKeyValueRow(key: r.0, value: r.1, valueCls: r.2)
                    }
                }
            }
            if !bd.extraRows.isEmpty {
                DSGroupRow(showsSeparator: true) { sectionLabel("舱盖/天窗") }
                ForEach(Array(bd.extraRows.enumerated()), id: \.offset) { idx, r in
                    DSGroupRow(showsSeparator: idx < bd.extraRows.count - 1) {
                        DSKeyValueRow(key: r.0, value: r.1, valueCls: r.2)
                    }
                }
            }
            if !bd.lampRows.isEmpty {
                DSGroupRow(showsSeparator: false) {
                    VStack(alignment: .leading, spacing: TokensSpacing.sm) {
                        sectionLabel("灯光")
                        let lit = bd.lampRows.filter { $0.1 == "亮" }
                        if !lit.isEmpty {
                            Text(lit.map { $0.0 }.joined(separator: " · "))
                                .font(TokensTypo.footnote)
                                .foregroundStyle(TokensPalette.warning)
                        } else {
                            Text("全部关闭")
                                .font(TokensTypo.footnote)
                                .foregroundStyle(TokensPalette.secondary)
                        }
                    }
                    .padding(.vertical, TokensSpacing.sm)
                }
            }
        }
    }
    /// 卡片内的子标题：走全 App 的同一行字（衬线 + 疏排），不再自造一个加粗灰字。
    private func sectionLabel(_ t: String) -> some View {
        DSSectionHeader(title: t)
    }
    /// 这一档的叠叠乐。顺序就是它的信息架构：
    /// **车身 → 现在该做的 → 指令 → 场景 → 记录 → 快捷指令**。
    /// 旧版是一条平铺的卡片堆，上下滑到底；现在它们是六张独立的卡散文，
    /// 滑过去的是一张一张，而不是一整屏。
    @MainActor
    private var cards: [StackCard] {
        var out = HomeMode.control.headCards
        // ① 车现在是什么样：姿态图 + 一句话状态 + 逐字段明细（同一张卡，不拆开）
        out.append(StackCard(id: "body", title: "车身",
                             at: store.cacheTime("control"),
                             content: AnyView(
            VStack(alignment: .leading, spacing: TokensSpacing.md) {
                controlHeader
                if let bd = bodyDetail { bodyDetailCard(bd) }
            })))
        // ② 现在该做的一件事：实心胶囊（状态有问题时它就是「锁车关窗」）
        out.append(StackCard(id: "todo", title: "现在该做的", content: AnyView(
            VStack(alignment: .leading, spacing: TokensSpacing.md) {
                primarySceneButton
                if let run = running { runningCard(run) }
            })))
        // ③ 还能做什么 → ④ 一键场景 → ⑤ 做过什么（按用到它们的频率从高到低）
        out.append(StackCard(id: "commands", title: "指令",
                             value: running == nil ? nil : "执行中", cls: "acc",
                             content: AnyView(commandCard)))
        out.append(StackCard(id: "scenes", title: "一键场景",
                             content: AnyView(presetScenesCard)))
        out.append(StackCard(id: "history", title: "执行记录",
                             content: AnyView(historyCard)))
        // 「快捷指令」从卡表里拿掉（用户 2026-09-23：控制页不要快捷指令卡）：
        // Siri 快捷方式仍由 `SiriShortcuts.swift` 注册，界面只是不再摆这张卡。
        // 若以后要恢复：重新把 `siri` 卡加回这里即可（`SiriShortcutsCard` 还留着）。
        return out
    }

    var body: some View {
        StackPageView(accent: HomeMode.control.accent, label: "车控", cards: cards)
        // 车控指令的**唯一**那道门：温度 → 生物识别 → 控车码 → 下发。
        // 它原先长在这一页里（三个 sheet + 一个遮罩共 60 行），地图右臂就绕过去了；
        // 现在它是一处 modifier，两处发起处挂同一个（见 `ControlCommandFlow`）。
        .controlCommandFlow($request)
        // 点车门不是「一条指令」：报文里没有单开一扇门的动作，所以给一个二选一。
        // 选完仍然走**同一道门**（`controlCommandFlow`）—— 三维视图没有第二条执行路径。
        .confirmationDialog(doorPart?.title ?? "车门",
                            isPresented: Binding(get: { doorPart != nil },
                                                 set: { if !$0 { doorPart = nil } }),
                            titleVisibility: .visible) {
            Button("锁车") { onCmd("LockDoor") }
            Button("解锁") { onCmd("UnLockDoor") }
            Button("取消", role: .cancel) { }
        } message: {
            Text("没有单独开一扇门的指令，只有整车上锁与解锁。")
        }
        .refreshable {
            // 数字归零
            Task {
                await refreshControlCache()
            }
        }
        .dsPageTitle("车控")
            .accessibilityLabel(Text("车控"))
            .accessibilityHint(Text("锁车、解锁、空调、座椅加热"))
        // 这里原本有一个 `.toolbar { … speakStatus() … }`（#35 语音播报车况）。
        // 用户 2026-09-25 第 7 条要求删掉语音播报 → 按钮、`speakStatus()`、
        // `VoiceBroadcastManager`、以及「我的」里那个开关一起走。
        // 顺带记一条：这一页的导航栏是隐藏的（`MapSpineView` 里 `.toolbar(.hidden)`），
        // 所以那枚钮**从来没有显示过** —— 一个到不了的入口。
        // MARK: 生命周期（车身明细、缓存）

        .onAppear {
            // 上一次执行若是在别的屏发起、又没人等它，这里的陈旧状态要清掉
            commands.clearIfIdle()
            // 首次进入时若缓存为空，主动拉一次数据
            if store.caches["control"] == nil {
                Task { await refreshControlCache() }
            }
        }
        .onDisappear {
            // 离开发起它的那一屏：停止轮询并**把状态收干净**（只 cancel 不清理，
            // 状态条会永远停在「正在执行」，而且下一次指令会被静默挡回去）
            commands.abandon()
        }
        .sheet(isPresented: Binding(get: { commands.showResult },
                                    set: { commands.showResult = $0 })) {
            resultSheet
        }
        // #N13 生物识别验证覆盖层已随那道门一起搬到 `ControlCommandFlow`：
        // 它在那边是「四步里的第②步」，而不是本页的一个开关。
    }

    // MARK: 头部（v4：读数就在车上 —— 一屏不堆卡片）
    private var controlHeader: some View {
        let carSel = VM.carSel(store.cars, store.carId)
        let name = carSel.options.indices.contains(carSel.index)
            ? carSel.options[carSel.index].name : "未绑定车辆"

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: TokensSpacing.sm) {
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
                    .font(TokensTypo.subheadline.weight(.semibold))
                    .tint(TokensPalette.primary)
                } else {
                    Text(name)
                        .font(TokensTypo.subheadline.weight(.semibold))
                        .foregroundStyle(TokensPalette.primary)
                        .lineLimit(1)
                }
                Spacer(minLength: TokensSpacing.sm)
                if let bd = bodyDetail {
                    DSChip(text: bd.summary, cls: bd.cls)
                }
            }

            // 车 = 一辆**真的三维模型**（用户 2026-09-25 第 8 条：
            // 「车太丑了，能不能搞个真车或立体车，可以滑动的，像特斯拉屏幕那样的
            //  也可以点击控车」）。它取代的是那张线描俯视图（`CarTopView`，已删）。
            CarModelView(
                doorCls: doorStates(),
                trunkOpen: trunkIsOpen(),
                windowsOpen: windowsAreOpen(),
                onTapPart: { onCarPartTap($0) }
            )
            // 三维视图没有「原始画布比例」—— 比例得由我们自己定：4:3 是一辆车
            // 从四分之三视角看过去最自然的取景（宽大于高；竖着会像一张海报）。
            // 高度上限仍是卡片量到的可用高度 ×0.58（`carTopMaxHeight`）：量不到就不封顶，
            // 宁可高一点，也不拿一个想象的屏高去砍。
            .aspectRatio(4.0 / 3.0, contentMode: .fit)
            .frame(maxHeight: carTopMaxHeight)
            .padding(.vertical, TokensSpacing.sm)

            Text(statusLineText())
                .font(TokensTypo.footnote)
                .foregroundStyle(TokensPalette.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    /// 一屏唯一的实心胶囊：状态有问题时就是“锁车关窗”，否则是降温场景
    private var primarySceneButton: some View {
        let issue = bodyDetail?.cls == "bad"
        return Button {
            TokensHaptic.tap()
            if issue {
                onCmd("LockDoor")
            } else if let scene = presetScenes.first(where: { $0.key == "summerCool" }) {
                onPresetScene(scene)
            }
        } label: {
            Text(issue ? "锁车关窗" : "极速降温 18℃")
        }
        .buttonStyle(DSPrimaryButtonStyle())
        .accessibilityHint(Text(issue ? "锁车、关窗并折叠后视镜" : "空调设为 18℃ 最强风"))
    }

    /// 车形图的高度上限：卡片量到的可用高度 × 0.58。
    ///
    /// 0.58 是一条**取舍**（车形图不该独占这一屏 —— 下面还有读数与按钮），
    /// 不是量出来的；量出来的是那个乘数左边的视口。量不到视口时返回 nil =
    /// 不封顶，让形状自己定高（宁可高一点，也不拿一个想象的屏高去砍）。
    private var carTopMaxHeight: CGFloat? {
        cardViewport.height > 0 ? cardViewport.height * 0.58 : nil
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
        // 一行一个场景：DSRow 把「图标列 + 标题 + 副标题 + 箭头」全部包好，
        // 旧写法是自己搭一遍 HStack，于是它与车控页其它行差一个内缩。
        DSGroup(title: "一键场景",
                trailing: busy || running != nil ? "执行中" : nil,
                trailingCls: "acc",
                footer: "每个场景一条指令，先验身份再发") {
            ForEach(Array(presetScenes.enumerated()), id: \.element.key) { idx, scene in
                DSGroupRow(showsSeparator: idx < presetScenes.count - 1) {
                    DSRow(icon: scene.symbol, title: scene.name, subtitle: scene.note,
                          value: busy || running != nil ? "执行中" : nil,
                          showsChevron: !(busy || running != nil)) {
                        onPresetScene(scene)
                    }
                }
                .disabled(busy || running != nil)
                .opacity(busy || running != nil ? 0.5 : 1)
            }
        }
    }

    private func onPresetScene(_ scene: PresetScene) {
        guard !busy, running == nil else { return }
        guard let cmd = scene.commands.first else { return }
        // 旧版这里直接 `execute(pinDigits)`，而 **pendingCmd 与 pendingTemp 两样都没设** ——
        // pendingCmd 默认是空串（execute 开头就 return），温度用的是上一次残留值。
        // 也就是说「一键锁车」很可能什么都没发。现在场景自己带上要发的指令与温度。
        //
        // 与单个指令走**同一道门**（`controlCommandFlow`）：敏感操作先验身份、再进控车码。
        // （省掉这道门的话，场景会拿着一个可能为空的 PIN 直接发指令。）
        request = ControlRequest(key: cmd, name: scene.name, temp: scene.temp)
    }

    /// 三维车身上点了一下（`CarModelView.onTapPart` 的唯一去处）。
    ///
    /// 分两种，**没有第三种**（`CarModelView` 头注那条硬规则：界面上每个动作都要
    /// 对应一条真的会发出去的指令）：有指令的部位直接发；四门没有「开门」这种指令，
    /// 所以给一个二选一 —— 而不是替用户猜「现在该锁还是该解」。
    ///
    /// ⚠️ 为什么不去读车锁的读数再取反：`VM.bodyStatus` 的判据是 `num(...) == 0`，
    /// 而同一个字段拿不到时它返回 0 —— 于是那一行**永远**显示「车锁 已锁」
    /// （`API-FIELD-MAP.md` 里那条「最会骗人的一处」）。照它取反 = 永远只发解锁。
    private func onCarPartTap(_ part: CarPart) {
        if let key = part.commandKey {
            onCmd(key)
            return
        }
        doorPart = part
    }

    // MARK: 指令执行中
    private func runningCard(_ run: ControlRun) -> some View {
        HStack(spacing: TokensSpacing.snug) {
            ProgressView()
                .controlSize(.regular)
                .tint(TokensPalette.ambient)
            VStack(alignment: .leading, spacing: TokensSpacing.xs) {
                Text(run.name).font(TokensTypo.headline)
                Text(run.progress.isEmpty ? "等待车辆响应…" : run.progress)
                    .font(TokensTypo.caption).foregroundStyle(TokensPalette.secondary)
            }
            Spacer()
        }
        .dsSurface(padding: TokensSpacing.lg, radius: TokensRadius.medium)
    }

    // MARK: 指令列表
    private var commandCard: some View {
        DSGroup(title: "还能做什么",
                trailing: busy || running != nil ? "执行中" : nil,
                trailingCls: "acc",
                footer: "超时标为「待确认」") {
            // 高频指令（默认展示）
            ForEach(Array(mainCommands.enumerated()), id: \.offset) { idx, item in
                DSGroupRow(showsSeparator: idx < mainCommands.count - 1 || showMoreCommands) {
                    cmdRow(item)
                }
            }
            // 低频指令（可折叠）
            if showMoreCommands {
                ForEach(Array(moreCommands.enumerated()), id: \.offset) { idx, item in
                    DSGroupRow(showsSeparator: idx < moreCommands.count - 1) {
                        cmdRow(item)
                    }
                }
            }
            // 展开/收起：它也是分组里的一行（内缩与分隔线由 DSGroupRow 给）
            DSGroupRow(showsSeparator: false) {
                Button {
                    withAnimation(TokensMotion.press) { showMoreCommands.toggle() }
                } label: {
                    HStack(spacing: TokensSpacing.sm) {
                        Image(safeSymbol: showMoreCommands ? "chevron.up" : "chevron.down",
                              fallback: showMoreCommands ? "chevron.up" : "chevron.down")
                            .font(TokensTypo.footnote.weight(.bold))
                            .foregroundStyle(TokensPalette.tertiary)
                        Text(showMoreCommands ? "收起" : "更多指令")
                            .font(TokensTypo.footnote)
                            .foregroundStyle(TokensPalette.ambient)
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: TokensSpacing.row)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func cmdRow(_ item: (key: String, name: String, symbol: String, note: String?)) -> some View {
        DSRow(icon: item.symbol, title: item.name, subtitle: item.note, showsChevron: true) {
            onCmd(item.key)
        }
        .disabled(busy || running != nil)
        .opacity(busy || running != nil ? 0.45 : 1)
    }

    // MARK: 记录
    //
    // 这一节现在是**唯一**的指令历史界面。原来还有一个独立的「指令历史」页，
    // 两处讲同一件事、数据源却不同（那页读持久历史，这节读本次运行的内存列表）——
    // 同一件事有两个界面、两套数据，正是「缝合」的典型。融合时取了更全的那个数据源。
    private var allRuns: [AppStore.HistoryEntry] { store.commandHistory }

    /// 不是 `private`：`ControlFit.swift`（同目录）要用它算「摊开之后占几屏」——
    /// `private` 的作用域是**文件**，跨文件就是「名字在项目里、但调用点不在作用域」。
    /// 2026-09-25 的 CI 红在这上面（同一个错在 `MapSpineBottomBar.swift` 里还犯了三条）。
    var filteredRuns: [AppStore.HistoryEntry] {
        switch historyFilter {
        // 「成功」只算**已确认**的成功：一条「结果待确认」的指令不该出现在成功列表里，
        // 也不该被算成失败 —— 那两件事都是我们不知道的事。
        case "ok": return allRuns.filter { $0.success && $0.confirmed }
        case "fail": return allRuns.filter { !$0.success && $0.confirmed }
        case "unknown": return allRuns.filter { !$0.confirmed }
        default: return allRuns
        }
    }

    /// 两个统计：总数与成功率。
    /// 刻意**没有**「进行中」：`addCommandHistory` 只在一次执行结束时被调用，
    /// 所以持久历史里不可能有未完成的条目 —— 做一个永远为 0 的筛选项就是界面在说谎。
    /// 真正在跑的那条在上面的 `runningCard` 里。
    /// 筛选项。第四个「未确认」只在真的出现过这种记录时才出现 ——
    /// 常态下不占位置，但一旦发生过（60 秒没等到车端终态），它必须能找到：
    /// 否则那条记录既不在「成功」也不在「失败」里，用户看着「总指令 3、成功 2」
    /// 却怎么都找不出第三条。
    private var historyFilterOptions: [(value: String, title: String)] {
        var o: [(value: String, title: String)] = [("all", "全部"), ("ok", "成功"), ("fail", "失败")]
        if allRuns.contains(where: { !$0.confirmed }) { o.append(("unknown", "未确认")) }
        return o
    }

    private var emptyFilterText: String {
        switch historyFilter {
        case "ok": return "没有成功的指令"
        case "fail": return "没有失败的指令"
        case "unknown": return "没有待确认的指令"
        default: return "没有记录"
        }
    }

    private var successRateText: String {
        guard !allRuns.isEmpty else { return "—" }
        let ok = allRuns.filter { $0.success && $0.confirmed }.count
        return String(format: "%.0f%%", Double(ok) / Double(allRuns.count) * 100)
    }

    private var historyCard: some View {
        DSExpandGroup(title: "做过什么",
                      trailing: allRuns.isEmpty ? "还没有" : "\(allRuns.count) 条",
                      footer: "本机最近 50 条") {
            if allRuns.isEmpty {
                DSGroupRow(showsSeparator: false) {
                    DSPlaceholder(icon: "list.bullet.clipboard",
                                  title: "还没有指令记录",
                                  message: "还没有指令记录")
                }
            } else {
                // 筛选用系统的分段控件语法，不自造一排药丸
                DSGroupRow {
                    DSSegmentPicker(options: historyFilterOptions, selection: $historyFilter,
                                    label: "指令筛选")
                }
                DSGroupRow(showsSeparator: false) {
                    HStack(spacing: 0) {
                        historyStat(label: "总指令", value: "\(allRuns.count)", tint: TokensPalette.primary)
                        historyStat(label: "成功率", value: successRateText, tint: TokensPalette.primary)
                    }
                    .padding(.vertical, TokensSpacing.xs)
                }

                if filteredRuns.isEmpty {
                    DSGroupRow(showsSeparator: false) {
                        Text(emptyFilterText)
                            .font(TokensTypo.footnote)
                            .foregroundStyle(TokensPalette.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(minHeight: TokensSpacing.row)
                    }
                } else {
                    // 显示几条**是算出来的**（`CardFit`）：一条摊开后要多四行键值，
                    // 于是「能放几条」随摊开状态一起变。从前这里是全列（历史最长 50 条，
                    // 摊开四五条就是三屏多），而卡片没有内层滚动 —— 见 `historyPlan`。
                    let plan = historyPlan
                    let shown = plan.keep.map { Array(filteredRuns.prefix($0)) } ?? filteredRuns
                    ForEach(Array(shown.enumerated()), id: \.element.id) { idx, item in
                        DSGroupRow(showsSeparator: idx < shown.count - 1 || plan.hidden > 0) {
                            historyRow(item)
                        }
                    }
                    if plan.hidden > 0 {
                        DSGroupRow(showsSeparator: false) {
                            DSCardMoreRow(rest: plan.hidden, screens: historyScreens, open: false) {
                                withAnimation(TokensMotion.count) { historyFull = true }
                            }
                        }
                    } else if historyFull, filteredRuns.count > 1 {
                        DSGroupRow(showsSeparator: false) {
                            DSCardMoreRow.collapse {
                                withAnimation(TokensMotion.count) { historyFull = false }
                            }
                        }
                    }
                }
            }
        }
    }

    private func historyStat(label: String, value: String, tint: Color) -> some View {
        VStack(spacing: TokensSpacing.xs) {
            Text(value)
                .font(TokensTypo.metric(28))
                .foregroundStyle(tint)
            Text(label)
                .font(TokensTypo.caption2)
                .foregroundStyle(TokensPalette.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    /// 一条历史：整行可点，点开就是四条键值行（与「全量数据」同一种写法）。
    /// 开始 / 结束 / 耗时 / 结果 都是真的记下来了的东西 —— 失败原因没有记，所以不编。
    private func historyRow(_ item: AppStore.HistoryEntry) -> some View {
        let isOpen = expandedRuns.contains(item.id)
        return Button {
            withAnimation(TokensMotion.value) {
                if isOpen { expandedRuns.remove(item.id) } else { expandedRuns.insert(item.id) }
            }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: TokensSpacing.md) {
                    StatusDot(cls: item.statusCls)
                    VStack(alignment: .leading, spacing: TokensSpacing.xxs) {
                        Text(item.name)
                            .font(TokensTypo.footnote)
                            .foregroundStyle(TokensPalette.primary)
                        Text(item.startedAt.formatted(date: .omitted, time: .shortened))
                            .font(TokensTypo.caption2)
                            .foregroundStyle(TokensPalette.secondary)
                    }
                    Spacer(minLength: TokensSpacing.sm)
                    Image(safeSymbol: item.iconName, fallback: item.iconName)
                        .font(TokensTypo.caption)
                        .foregroundStyle(item.statusColor)
                }
                if isOpen {
                    VStack(alignment: .leading, spacing: 0) {
                        DSKeyValueRow(key: "开始",
                                      value: item.startedAt.formatted(date: .omitted, time: .standard))
                        DSKeyValueRow(key: "结束",
                                      value: item.finishedAt?.formatted(date: .omitted, time: .standard) ?? "—")
                        DSKeyValueRow(key: "耗时", value: item.durationText)
                        DSKeyValueRow(key: "结果", value: item.resultText,
                                      valueCls: item.statusCls)
                    }
                    .padding(.top, TokensSpacing.sm)
                }
            }
            .frame(minHeight: TokensSpacing.row)
        }
        .buttonStyle(DSRowButtonStyle())
    }

    // MARK: 指令执行逻辑（不在本文件）
    /// 指令的**下发与轮询**在 `CommandCenter`（同目录）—— 那是唯一执行路径。
    /// 而「发之前要先过哪几道门」在 `ControlCommandFlow`（同目录）——
    /// 那是唯一验证路径。本页只做一件事：把请求交给那道门。
    private func onCmd(_ key: String) {
        guard !busy, running == nil else { return }
        guard !store.carId.isEmpty else {
            ToastManager.shared.show("请先选择车辆", icon: "car.fill"); return
        }
        request = ControlRequest(key: key, name: nameOf(key))
    }

    // `execute` / `startPolling` / `finish` 三个函数整体搬到了 `CommandCenter`
    // （地图上的常驻操作条要发同一条指令，两边各写一遍迟早会给出不同结果）。
    //
    // 搬过去时顺手修了两处：
    //   · `store.addCommandHistory(cmd: "", name: "")` 原先写的是空串 —— 指令历史里
    //     每一条都没有名字，看不出这条到底做了什么。现在传真实指令名。
    //   · 成功时的 toast 是 `show("")`（只有图标、没有字）。在地图上发指令不会跳页，
    //     用户需要一个「刚才那条怎么了」的落点，所以改成带指令名的文案。

    // MARK: 执行结果详情 Sheet
    @ViewBuilder
    private var resultSheet: some View {
        if let r = lastResult {
            VStack(alignment: .leading, spacing: TokensSpacing.md) {
                HStack {
                    Text(r.name).font(TokensTypo.title3)
                    Spacer()
                    Pill(text: r.resultText, cls: r.resultCls, dot: false)
                }
                if !r.progress.isEmpty {
                    Text(r.progress).font(TokensTypo.caption).foregroundStyle(TokensPalette.secondary)
                }
                DSGroup(title: "执行详情") {
                    if !r.handleCode.isEmpty {
                        DSGroupRow {
                            DSKeyValueRow(key: "错误码", value: r.handleCode, valueCls: "bad")
                        }
                    }
                    DSGroupRow { DSKeyValueRow(key: "发起时间", value: r.startedAt) }
                    DSGroupRow { DSKeyValueRow(key: "完成时间", value: r.finishTime) }
                    DSGroupRow(showsSeparator: false) {
                        DSKeyValueRow(key: "任务 ID", value: r.taskId.isEmpty ? "--" : r.taskId)
                    }
                }
                Spacer()
            }
            .padding(TokensSpacing.xl)
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

// MARK: - 已删除：俯视示意图 `CarTopView`（2026-09-25）
//
// 它是一条条线画出来的俯视图（`Canvas` + 手写路径）：线描、不着色、没有体积。
// 用户第 8 条要的是「真车或立体车、可以滑动、可以点击控车」——
// 线描俯视图这三件事一件都做不到（它转不了、点不到、也没有「立体」这回事）。
// 现在是 `CarModelView`（RealityKit 的真实三维实体，同目录）。
// 删掉之后 `CarTopView.artSize` / `artAspect` 两个派生量也一起消失 ——
// 三维视图没有「原始画布比例」，比例由调用点自己定（4:3）。
//
// 它读状态的那几处（`doorStates()` / `trunkIsOpen()` / `windowsAreOpen()`）留着，
// 现在喂给三维视图 —— 状态从哪儿来这件事与车长什么样无关。
/// 车身是线描，只有「状态」带颜色：绿 = 已关，橙 = 未关。
/// 填色会把示意变成插画，着色会把插画变成儿童 App —— 所以一辆车只用线。
// MARK: - PIN 数字键盘弹层（玻璃化）

struct PINKeypadView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var pin = ""
    private let keys = ["1","2","3","4","5","6","7","8","9","","0","del"]

    var body: some View {
        VStack(spacing: TokensSpacing.lg) {
            Capsule().fill(TokensPalette.secondary.opacity(0.4)).frame(width: 40, height: 5)
            VStack(spacing: TokensSpacing.xs) {
                Text("输入控车码").font(TokensTypo.title)
                Text("6 位数字，输满自动执行").font(TokensTypo.caption).foregroundStyle(TokensPalette.secondary)
            }
            HStack(spacing: TokensSpacing.snug) {
                ForEach(0..<6, id: \.self) { i in
                    Text(i < pin.count ? String(pin[pin.index(pin.startIndex, offsetBy: i)]) : "")
                        .font(TokensTypo.metric(26))
                        .frame(width: 42, height: 54)
                        .background(TokensPalette.fillSubtle, in: RoundedRectangle(cornerRadius: 12, style:
 .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(i == pin.count ? TokensPalette.ambient : Color(.systemGray4),
                                          lineWidth: i == pin.count ? 2 : 1))
                }
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()),
                                GridItem(.flexible())],
                      spacing: TokensSpacing.snug) {
                ForEach(keys, id: \.self) { k in
                    Button {
                        onKey(k)
                    } label: {
                        Group {
                            if k == "del" { Image(safeSymbol: "delete.left", fallback: "delete.left") }
                            else if k == "" { Color.clear }
                            else { Text(k) }
                        }
                        .font(TokensTypo.metric(26))
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(TokensPalette.fillSubtle, in: RoundedRectangle(cornerRadius: 14, style:
 .continuous))
                        .foregroundStyle(TokensPalette.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            Button("取消") { dismiss() }
                .font(TokensTypo.headline)
                .foregroundStyle(TokensPalette.secondary)
                .padding(.bottom, TokensSpacing.sm)
        }
        .padding(TokensSpacing.xxl)
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
        VStack(spacing: TokensSpacing.lg) {
            Capsule().fill(TokensPalette.secondary.opacity(0.4)).frame(width: 40, height: 5)
            VStack(spacing: TokensSpacing.xs) {
                Text("空调温度").font(TokensTypo.title)
                Text("17 – 33 ℃").font(TokensTypo.caption).foregroundStyle(TokensPalette.secondary)
            }
            HStack(spacing: TokensSpacing.xl) {
                tempButton("minus", canDo: temp > 17) { temp -= 1 }
                VStack(spacing: 0) {
                    Text("\(tempDisplayCount)")
                        .font(TokensTypo.display(72))
                        .foregroundStyle(TokensPalette.ambient)
                        .contentTransition(.numericText())
                    Text("℃").font(TokensTypo.caption).foregroundStyle(TokensPalette.secondary)
                }
                tempButton("plus", canDo: temp < 33) { temp += 1 }
            }
            .padding(.vertical, TokensSpacing.sm)
            Button {
                NotificationCenter.default.post(name: .tempConfirmed, object: temp)
                dismiss()
            } label: {
                Text("输入控车码")
                    .font(TokensTypo.title3)
                    .foregroundStyle(TokensPalette.labelOnTint)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, TokensSpacing.md)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(TokensPalette.ambient))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, TokensSpacing.sm)
            Button("取消") { dismiss() }
                .font(TokensTypo.caption).foregroundStyle(TokensPalette.secondary)
        }
        .padding(TokensSpacing.xxl)
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
            Image(safeSymbol: sym + ".circle.fill", fallback: sym + ".circle.fill")
                .font(TokensTypo.display(42))
                .foregroundStyle(canDo ? TokensPalette.ambient : Color(.systemGray4))
        }
        .buttonStyle(.plain)
        .disabled(!canDo)
    }
}
