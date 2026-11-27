import SwiftUI


struct ControlView: View {
    private let store = AppStore.shared


    private let hero: [(key: String, name: String, symbol: String)] = [
        ("LockDoor", "锁车", "lock.fill"),
        ("UnLockDoor", "解锁", "lock.open.fill")
    ]
    private let mainCommands: [(key: String, name: String, symbol: String, note: String?)] = [
        ("OpenAir", "开启空调", "snowflake", "需设置温度"),
        ("CloseAir", "关闭空调", "power", nil)
    ]
    private let moreCommands: [(key: String, name: String, symbol: String, note: String?)] = [
        ("FlashLight", "闪灯", "lightbulb", nil),
        ("Whistle", "鸣笛", "speaker.wave.2", nil),
        ("RemoteSearchCar", "远程寻车", "location", nil),
        ("UpCarCondition", "刷新车况", "arrow.clockwise", "让车端立刻上报一次状态")
    ]
    private struct PresetScene {
        let key: String
        let name: String
        let symbol: String
        let commands: [String]
        let temp: Int?
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

    @ObservedObject private var commands = CommandCenter.shared
    private var busy: Bool { commands.busy }
    private var running: ControlRun? { commands.running }
    private var lastResult: ControlRun? { commands.lastResult }
    private var showResult: Bool { commands.showResult }

    @State private var historyFilter = "all"
    @State var expandedRuns: Set<UUID> = []
    @State var historyFull = false
    @Environment(\.cardViewport) var cardViewport

    @State private var showMoreCommands = true
    @State private var request: ControlRequest?
    @State private var doorPart: CarPart?

    private var bodyDetail: BodyState? {
        BodyState(control: ciVal(store.caches, "control"))
    }
    private func bodyDetailCard(_ bd: BodyState) -> some View {
        DSExpandGroup(title: "车身状态", trailing: bd.summary, trailingCls: bd.cls) {
            if !bd.doorRows.isEmpty {
                DSGroupRow(showsSeparator: true) { sectionLabel("车门") }
                ForEach(Array(bd.doorRows.enumerated()), id: \.offset) { idx, r in
                    DSGroupRow(showsSeparator: idx < bd.doorRows.count - 1) {
                        DSKeyValueRow(key: r.label, value: r.value, valueCls: r.cls)
                    }
                }
            }
            if !bd.windowRows.isEmpty {
                DSGroupRow(showsSeparator: true) { sectionLabel("车窗") }
                ForEach(Array(bd.windowRows.enumerated()), id: \.offset) { idx, r in
                    DSGroupRow(showsSeparator: idx < bd.windowRows.count - 1) {
                        DSKeyValueRow(key: r.label, value: r.value, valueCls: r.cls)
                    }
                }
            }
            if !bd.extraRows.isEmpty {
                DSGroupRow(showsSeparator: true) { sectionLabel("舱盖/天窗") }
                ForEach(Array(bd.extraRows.enumerated()), id: \.offset) { idx, r in
                    DSGroupRow(showsSeparator: idx < bd.extraRows.count - 1) {
                        DSKeyValueRow(key: r.label, value: r.value, valueCls: r.cls)
                    }
                }
            }
            if !bd.lampRows.isEmpty {
                DSGroupRow(showsSeparator: false) {
                    VStack(alignment: .leading, spacing: TokensSpacing.sm) {
                        sectionLabel("灯光")
                        let lit = bd.lampRows.filter { $0.value == "亮" }
                        if !lit.isEmpty {
                            Text(lit.map { $0.label }.joined(separator: " · "))
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
    private func sectionLabel(_ t: String) -> some View {
        DSSectionHeader(title: t)
    }
    @MainActor
    private var cards: [StackCard] {
        var out = HomeMode.control.headCards
        out.append(StackCard(id: "body", title: "车身",
                             at: store.cacheTime("control"),
                             content: AnyView(
            VStack(alignment: .leading, spacing: TokensSpacing.md) {
                controlHeader
                if let bd = bodyDetail { bodyDetailCard(bd) }
            })))
        out.append(StackCard(id: "commands", title: "指令",
                             value: running == nil ? nil : "执行中", cls: "acc",
                             content: AnyView(commandCard)))
        out.append(StackCard(id: "scenes", title: "一键场景",
                             content: AnyView(presetScenesCard)))
        out.append(StackCard(id: "history", title: "执行记录",
                             content: AnyView(historyCard)))
        return out
    }

    var body: some View {
        StackPageView(accent: HomeMode.control.accent, label: "车控", cards: cards)
        .controlCommandFlow($request)
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
            Task {
                await refreshControlCache()
            }
        }
        .dsPageTitle("车控")
            .accessibilityLabel(Text("车控"))
            .accessibilityHint(Text("锁车、解锁、空调、座椅加热"))

        .onAppear {
            commands.clearIfIdle()
            if store.caches["control"] == nil {
                Task { await refreshControlCache() }
            }
        }
        .onDisappear {
            commands.abandon()
        }
        .sheet(isPresented: Binding(get: { commands.showResult },
                                    set: { commands.showResult = $0 })) {
            resultSheet
        }
    }

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

            CarModelView(
                doorCls: doorStates(),
                trunkOpen: trunkIsOpen(),
                windowsOpen: windowsAreOpen(),
                onTapPart: { onCarPartTap($0) }
            )
            .aspectRatio(4.0 / 3.0, contentMode: .fit)
            .frame(maxHeight: carTopMaxHeight)
            .padding(.vertical, TokensSpacing.sm)

            Text(statusLineText())
                .font(TokensTypo.footnote)
                .foregroundStyle(TokensPalette.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }


    private var carTopMaxHeight: CGFloat? {
        cardViewport.height > 0 ? cardViewport.height * 0.58 : nil
    }

    private func doorStates() -> [String] {
        guard let bd = bodyDetail else { return ["ok", "ok", "ok", "ok"] }
        return ["左前门", "右前门", "左后门", "右后门"].map { name in
            bd.doorRows.first { $0.label == name }?.cls ?? "ok"
        }
    }

    private func trunkIsOpen() -> Bool {
        guard let bd = bodyDetail else { return false }
        let all = bd.doorRows + bd.windowRows + bd.extraRows
        return all.first { $0.label.contains("后备箱") }?.cls == "bad"
    }

    private func windowsAreOpen() -> Bool {
        (bodyDetail?.windowRows.contains { $0.cls == "bad" }) ?? false
    }

    private func statusLineText() -> String {
        guard let bd = bodyDetail else { return "等待车辆上报" }
        let bad = bd.doorRows.filter { $0.cls == "bad" }.map { $0.label }
            + bd.windowRows.filter { $0.cls == "bad" }.map { $0.label }
        return bad.isEmpty ? "四门已锁 · 车窗已关" : bad.joined(separator: " · ") + " 未关"
    }

    private var presetScenesCard: some View {
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
        request = ControlRequest(key: cmd, name: scene.name, temp: scene.temp)
    }

    private func onCarPartTap(_ part: CarPart) {
        if let key = part.commandKey {
            onCmd(key)
            return
        }
        doorPart = part
    }

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

    @ViewBuilder
    private var commandCard: some View {
        if let run = running { runningCard(run) }
        commandGroup
    }

    private var commandGroup: some View {
        DSGroup(title: "还能做什么",
                trailing: busy || running != nil ? "执行中" : nil,
                trailingCls: "acc",
                footer: "超时标为「待确认」") {
            ForEach(Array(mainCommands.enumerated()), id: \.offset) { idx, item in
                DSGroupRow(showsSeparator: idx < mainCommands.count - 1 || showMoreCommands) {
                    cmdRow(item)
                }
            }
            if showMoreCommands {
                ForEach(Array(moreCommands.enumerated()), id: \.offset) { idx, item in
                    DSGroupRow(showsSeparator: idx < moreCommands.count - 1) {
                        cmdRow(item)
                    }
                }
            }
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

    private var allRuns: [AppStore.HistoryEntry] { store.commandHistory }

    var filteredRuns: [AppStore.HistoryEntry] {
        switch historyFilter {
        case "ok": return allRuns.filter { $0.success && $0.confirmed }
        case "fail": return allRuns.filter { !$0.success && $0.confirmed }
        case "unknown": return allRuns.filter { !$0.confirmed }
        default: return allRuns
        }
    }

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

    private func onCmd(_ key: String) {
        guard !busy, running == nil else { return }
        guard !store.carId.isEmpty else {
            ToastManager.shared.show("请先选择车辆", icon: "car.fill"); return
        }
        request = ControlRequest(key: key, name: nameOf(key))
    }


    @ViewBuilder
    private var resultSheet: some View {
        if let r = lastResult {
            VStack(alignment: .leading, spacing: TokensSpacing.md) {
                HStack {
                    Text(r.name).font(TokensTypo.title3)
                    Spacer()
                    DSChip(text: r.resultText, cls: r.resultCls)
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

    private func refreshControlCache() async {
        if let ctrl = try? await APIClient.shared.getControl(carId: store.carId) {
            store.saveCache(["control": ctrl])
        }
    }
}
