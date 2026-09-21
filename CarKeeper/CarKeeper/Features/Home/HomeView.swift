import SwiftUI
import Combine
import CoreLocation
import UserNotifications
import UIKit
import MapKit

// =============================================================================
//  车况 — v4（Apple 原生语言）
// =============================================================================
//  这一屏只有一个主角：车。
//
//  核心机制：车尾那道贯穿光带就是电量表。
//  亮的长度就是 SOC，暗的部分就是还没充的。没有仪表盘、没有续航环 ——
//  同一个数字在下面用一条白色光条再讲一遍，两者永远同步。
//
//  结构（自上而下）：
//    ① 车（道具即界面：剪影 + 车灯 + 地面光池）
//    ② 车辆标识（车牌 / 在线 / 最近上报）
//    ③ 唯一的大数字（Soc）+ 光条 + 续航 / 充电状态
//    ④ 三条事实（发丝线分隔，无容器）
//    ⑤ 快捷操作 / 行驶 / 系统状态 / 电池 / 胎压 / 座舱 / 位置
//
//  排版规则：不堆卡片。单条信息直接落在画布上，用内缩发丝线分隔；
//  需要成组的用 iOS inset-grouped 表面（DSCard）。
//
//  车身本身就是控件：点车门 = 锁 / 解锁（以那扇门的状态取反），
//  点后备箱 = 看状态并说明为什么不能远程开合。车上的门灯与状态行随即同步。
// =============================================================================

/// 车身上可点的区域。侧面视角只看得见近侧的两扇门，所以门只分前后门。
enum CarZone: String, CaseIterable, Identifiable {
    case leftFront, leftRear, trunk

    var id: String { rawValue }

    var label: String {
        switch self {
        case .leftFront: return "左前门"
        case .leftRear:  return "左后门"
        case .trunk:     return "后备箱"
        }
    }
}

/// 车端指令表。
///
/// ⚠️ 本车型的协议只有 7 条指令（证据：小程序 pages/control/control.js 与 App 的车控页完全一致）：
///    LockDoor / UnLockDoor / OpenAir / CloseAir / FlashLight / Whistle / RemoteSearchCar。
/// 也就是说：**没有单独开关某一扇车门、也没有远程开合后备箱的指令**。
/// 车门与后备箱的“开 / 合”是车身上报的状态，App 能远程改变的只有「锁 / 解锁」。
/// 若车端确认支持后备箱指令，把下面两个 key 填上即可 —— 热区文案与行为会自动从
/// “查看状态”变成“开合动作”，无需改其他代码。
enum CarCommand {
    static let lock = "LockDoor"
    static let unlock = "UnLockDoor"
    static let trunkOpen: String? = nil
    static let trunkClose: String? = nil
}

struct HomeView: View {

    private let store = AppStore.shared

    @State private var startTimer: Task<Void, Never>? = nil
    @State private var lastFetch: Date?
    @State private var isRefreshing = false
    @State private var showCheckInReminder = false
    @State private var showSearch = false
    @State private var showMap = false
    @State private var focusEnabled = FocusModeManager.shared.config.enabled

    // 车身交互（点门 / 点后备箱）
    @State private var carBusy = false
    @State private var carLine: (text: String, cls: String)? = nil
    @State private var pendingLock: Bool? = nil          // 乐观锁状态：指令发出后、车辆回报前的界面值
    @State private var showPinPad = false
    @State private var pendingCarCmd: String? = nil
    @State private var pendingCarZone: CarZone? = nil
    @State private var carTask: Task<Void, Never>? = nil

    /// 当前缓存（一次取值，多处复用）
    private var cache: [String: Any?] { store.caches }

    // MARK: - 根

    var body: some View {
        Group {
            if let cfg = TokenStore.read(), !cfg.accessToken.isEmpty {
                content
            } else {
                DSPlaceholder(
                    icon: "lock.fill",
                    title: "请先登录",
                    message: "登录后即可查看车辆状态"
                )
            }
        }
        .sheet(isPresented: $showSearch) {
            NavigationStack {
                GlobalSearchHUD(isPresented: $showSearch)
                    .navigationTitle("搜索")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        .sheet(isPresented: $showPinPad) {
            PINKeypadView()
                .onReceive(NotificationCenter.default.publisher(for: .pinConfirmed)) { note in
                    guard let pin = note.object as? String else { return }
                    showPinPad = false
                    if store.readPin() == nil { store.savePin(pin) }
                    if let cmd = pendingCarCmd, let zone = pendingCarZone {
                        pendingCarCmd = nil
                        pendingCarZone = nil
                        executeCarCommand(cmd, zone: zone, pin: pin)
                    }
                }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                if store.isOfflineMode || store.networkStatus != .online {
                    DSNotice(
                        kind: store.isOfflineMode ? .warning : .info,
                        text: store.isOfflineMode
                            ? "离线模式：当前显示最后一次同步的数据"
                            : "网络不稳定，数据可能不是最新"
                    )
                    .padding(.bottom, DS.Space.lg)
                }

                hero
                    .padding(.bottom, DS.Space.xxl)

                quickActions
                driveSection
                systemSection
                batterySection
                tyreSection
                cabinSection
                carbonSection
                locationSection
                footer
            }
            .padding(.top, DS.Space.sm)
            .padding(.bottom, DS.Space.huge)
        }
        .background(KanseiPalette.background)
        .scrollBounceBehavior(.basedOnSize)
        .refreshable {
            isRefreshing = true
            await fetchCore()
        }
        .navigationTitle("车况")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button { showSearch = true } label: {
                    Image(systemName: "magnifyingglass")
                }
                .accessibilityLabel(Text("搜索"))

                Button {
                    toggleFocusMode()
                } label: {
                    Image(systemName: focusEnabled ? "moon.fill" : "moon.stars")
                }
                .accessibilityLabel(Text(focusEnabled ? "退出专注模式" : "启用专注模式"))

                Button { shareStatus() } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel(Text("分享车况"))
            }
        }
        .alert("上车打卡", isPresented: $showCheckInReminder) {
            Button("已上车，检查车况") { store.checkIn() }
            Button("稍后再说", role: .cancel) { }
        } message: {
            Text("今天还没检查车况，建议上车前确认胎压、电量是否正常。")
        }
        .task { startPolling() }
        .onDisappear {
            startTimer?.cancel()
            startTimer = nil
            carTask?.cancel()
            carTask = nil
        }
    }

    // MARK: - ① 车 + ③ 大数字

    private var hero: some View {
        let sel = VM.carSel(store.cars, store.carId)
        let e = VM.energy(cache, store.car)
        let name = sel.options.indices.contains(sel.index) ? sel.options[sel.index].name : "未绑定车辆"
        let fraction = max(0, min(1, Double(e.socPct) / 100.0))
        let lightColor = heroLightColor(e)
        let facts = bodyFacts()

        return VStack(alignment: .leading, spacing: 0) {

            // 车 —— 只用车灯与剪影成像，车身不填色；车身本身就是控件
            CarStageView(lit: fraction,
                         accent: lightColor,
                         doorLocks: doorLightCls(),
                         trunkCls: trunkState().cls,
                         busy: carBusy,
                         onZone: { onCarZone($0) })
                .frame(height: 196)
                .padding(.horizontal, -DS.Space.page)   // 让车超出画幅（产品照的构图）
                .padding(.bottom, DS.Space.xs)

            carFeedbackLine

            // 车辆标识
            HStack(spacing: DS.Space.sm) {
                Circle()
                    .fill(e.online.cls == "ok" ? KanseiPalette.success : KanseiPalette.tertiary)
                    .frame(width: 7, height: 7)
                if sel.count > 1 {
                    Picker("选择车辆", selection: Binding(
                        get: { sel.index },
                        set: { store.selectCar($0) }
                    )) {
                        ForEach(Array(sel.options.enumerated()), id: \.offset) { idx, opt in
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
                Text(e.updated == "--" ? "暂无上报" : "\(e.updated)")
                    .font(DS.Typo.footnote)
                    .foregroundStyle(KanseiPalette.tertiary)
                    .lineLimit(1)
            }

            // 唯一的大数字
            DSBigNumber(value: e.soc, unit: "%", size: 104)
                .padding(.top, DS.Space.xl)

            // 光条 —— 同一个数字的另一种写法
            VStack(alignment: .leading, spacing: DS.Space.md) {
                DSLightBar(progress: fraction, tint: lightBarGradient(lightColor))
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.sm) {
                    Text("剩余 \(e.range) km")
                        .font(DS.Typo.footnote)
                        .foregroundStyle(KanseiPalette.secondary)
                    Spacer(minLength: DS.Space.sm)
                    if e.chargeCls == "ok" || e.chargeCls == "charge" {
                        Text(e.chargeText)
                            .font(DS.Typo.footnote.weight(.medium))
                            .foregroundStyle(KanseiPalette.info)
                    } else if !e.socWarn.isEmpty {
                        Text(e.socPct < 15 ? "电量偏低" : "建议补电")
                            .font(DS.Typo.footnote.weight(.medium))
                            .foregroundStyle(e.socPct < 15 ? KanseiPalette.error : KanseiPalette.warning)
                    } else if let tte = e.timeToEmpty, tte != "--" {
                        Text("可行驶 \(tte)")
                            .font(DS.Typo.footnote)
                            .foregroundStyle(KanseiPalette.secondary)
                    }
                }
            }
            .padding(.top, DS.Space.xl)

            // 三条事实：只有发丝线，没有容器
            DSStatStrip(items: [
                .init("电池温度", e.battTemp),
                .init("电压 / 电流", e.voltAmp),
                .init("电池健康", healthText(), cls: healthCls())
            ])
            .padding(.top, DS.Space.xl)
            .overlay(alignment: .top) { DSDivider() }
            .overlay(alignment: .bottom) { DSDivider() }

            // 车身状态：发丝线分隔的事实行（车门 / 车窗 / 车锁 / 后备箱）
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(facts.enumerated()), id: \.element.id) { idx, item in
                    DSStatRow(label: item.label, value: item.text, valueCls: item.cls)
                    if idx < facts.count - 1 { DSSeparator(inset: 0) }
                }
                Text("点车门可锁 / 解锁整车 —— 本车型协议未提供单门与后备箱的远程开合指令")
                    .font(DS.Typo.caption)
                    .foregroundStyle(KanseiPalette.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, DS.Space.md)
            }
            .overlay(alignment: .bottom) { DSDivider() }
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: - 车身交互（车身即控件）

    /// 车上操作的一行反馈：正在执行 / 已完成 / 失败；空闲时是一句可操作提示
    private var carFeedbackLine: some View {
        HStack(spacing: DS.Space.sm) {
            if carBusy {
                ProgressView().controlSize(.small)
            }
            Text(carLine?.text ?? "点车门可锁 / 解锁")
                .font(DS.Typo.footnote)
                .foregroundStyle(carLine == nil
                                 ? KanseiPalette.tertiary
                                 : KanseiPalette.statusColor(carLine?.cls ?? "na"))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, DS.Space.lg)
        .accessibilityElement(children: .combine)
    }

    private func onCarZone(_ zone: CarZone) {
        DSHaptic.tap()
        switch zone {
        case .leftFront, .leftRear:
            // 以被点的那扇门的锁状态取反；车端指令作用于整车（协议里唯一的车身指令）
            let idx = (zone == .leftFront) ? 0 : 1
            let lights = doorLightCls()
            let locked = lights.indices.contains(idx) && lights[idx] == "ok"
            sendCarCommand(locked ? CarCommand.unlock : CarCommand.lock, zone: zone)
        case .trunk:
            let t = trunkState()
            if let open = CarCommand.trunkOpen, let close = CarCommand.trunkClose {
                sendCarCommand(t.cls == "bad" ? close : open, zone: zone)
            } else {
                let state = t.text == "--" ? "暂无上报" : t.text
                carLine = ("后备箱 · \(state)（车辆上报）· 本车型不支持远程开合", "warn")
                scheduleCarLineClear()
            }
        }
    }

    /// 需要控车码：没存过就先弹数字键盘，输满 6 位后自动执行（与车控页同一套流程）
    private func sendCarCommand(_ cmd: String, zone: CarZone) {
        guard !carBusy else { return }
        guard let pin = store.readPin(), !pin.isEmpty else {
            pendingCarCmd = cmd
            pendingCarZone = zone
            showPinPad = true
            return
        }
        executeCarCommand(cmd, zone: zone, pin: pin)
    }

    private func executeCarCommand(_ cmd: String, zone: CarZone, pin: String) {
        let locking = (cmd == CarCommand.lock)
        let verb = locking ? "锁车" : "解锁"
        carBusy = true
        pendingLock = locking                       // 乐观：车还没回报，界面先响应
        carLine = ("正在执行 · \(zone.label) \(verb)…", "na")
        carTask?.cancel()
        carTask = Task { @MainActor in
            do {
                let r = try await APIClient.shared.sendControlCommand(cmd: cmd, carId: store.carId, pin: pin)
                store.addCommandHistory(cmd: cmd, name: verb, success: true, duration: 0)
                let taskId = r.flatMap { ciString($0, ["TaskId", "taskId"]) } ?? ""
                if !taskId.isEmpty {
                    let confirmed = await awaitControlTask(taskId)
                    guard confirmed else { throw APIError(message: "60 秒内未收到车辆确认") }
                }
                await refreshControlCache()
                pendingLock = nil
                carLine = ("\(zone.label) · 已\(verb)", "ok")
                DSHaptic.result(true)
            } catch {
                store.addCommandHistory(cmd: cmd, name: verb, success: false, duration: 0)
                pendingLock = nil                   // 失败立刻回到车辆上报的真实值
                carLine = ("\(zone.label) · 执行失败：\(error.localizedDescription)", "bad")
                DSHaptic.result(false)
            }
            carBusy = false
            scheduleCarLineClear()
        }
    }

    /// 车控是异步的：服务端返回 TaskId，轮询到终态才算数（判定与车控页一致）
    private func awaitControlTask(_ taskId: String) async -> Bool {
        for _ in 0..<12 {
            if Task.isCancelled { return false }
            let r = await APIClient.shared.getControlInfo(carId: store.carId, taskId: taskId)
            if let d = r.data {
                let status = ciString(d, ["HandleStatus", "handleStatus", "Status", "status"]) ?? ""
                let finals = ["Success", "Completed", "RunFailure", "Failed", "Timeout",
                              "success", "completed", "runFailure", "failed", "timeout"]
                if finals.contains(status) {
                    return ["Success", "Completed", "success", "completed"].contains(status)
                }
            }
            try? await Task.sleep(for: .seconds(5))
        }
        return false
    }

    private func refreshControlCache() async {
        if let ctrl = try? await APIClient.shared.getControl(carId: store.carId) {
            store.saveCache(["control": ctrl])
        }
    }

    private func scheduleCarLineClear() {
        let snapshot = carLine?.text ?? ""
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            if carLine?.text == snapshot { carLine = nil }
        }
    }

    // MARK: - 车身状态派生

    private struct BodyFact: Identifiable {
        var id: String { label }
        let label: String
        let text: String
        let cls: String
    }

    /// 事实行：车门 / 车窗 / 车锁 / 后备箱（车锁优先用乐观值，让界面与操作同步）
    private func bodyFacts() -> [BodyFact] {
        let chips = VM.bodyStatus(cache)
        var out: [BodyFact] = []
        for label in ["车门", "车窗"] {
            if let c = chips.first(where: { $0.label == label }) {
                out.append(BodyFact(label: label, text: c.text, cls: c.cls))
            }
        }
        let lock = lockSummary()
        out.append(BodyFact(label: "车锁", text: lock.text, cls: lock.cls))
        if let t = chips.first(where: { $0.label == "后备箱" }) {
            out.append(BodyFact(label: "后备箱", text: t.text, cls: t.cls))
        }
        return out
    }

    /// 四门锁：报文里 0 = 已锁。顺序：左前 / 右前 / 左后 / 右后（与车控页、小程序 vm.js 一致）
    private func doorLockStates() -> [Bool?] {
        guard let ctrl = cache["control"] as? [String: Any] else { return [nil, nil, nil, nil] }
        // 总锁：小程序里「车锁」读的就是 DriverDoorLock（0 = 已锁），部分车型只报这一个字段。
        let master = ciNumber(ctrl, ["DriverDoorLock"]).map { $0 == 0 }
        return ["LeftFrontDoorLock", "RightFrontDoorLock", "LeftRearDoorLock", "RightRearDoorLock"].map { key in
            // 没有分门字段的车型拿总锁兵底 —— 否则车门永远是“状态未知”，
            // 点它也无从判断该锁还是该解。
            ciNumber(ctrl, [key]).map { $0 == 0 } ?? master
        }
    }

    private func lockSummary() -> (text: String, cls: String) {
        if let p = pendingLock { return (p ? "已锁" : "未锁", p ? "ok" : "warn") }
        let states = doorLockStates().compactMap { $0 }
        guard !states.isEmpty else { return ("--", "na") }
        let unlocked = states.filter { !$0 }.count
        return unlocked == 0 ? ("已锁", "ok") : ("\(unlocked) 门未锁", "warn")
    }

    /// 侧面车身上两段门灯的色（左前 / 左后）：绿 = 已锁，橙 = 未锁，灰 = 未上报
    private func doorLightCls() -> [String] {
        let states = doorLockStates()
        let near: [Bool?] = [states.first ?? nil, states.count > 2 ? states[2] : nil]
        let effective: [Bool?] = pendingLock == nil ? near : near.map { _ in pendingLock }
        return effective.map { st in
            guard let st else { return "na" }
            return st ? "ok" : "bad"
        }
    }

    private func trunkState() -> (text: String, cls: String) {
        guard let ctrl = cache["control"] as? [String: Any],
              let v = ciNumber(ctrl, ["Trunk", "trunk"]) else { return ("--", "na") }
        return v == 0 ? ("已关", "ok") : ("开启", "bad")
    }

    private func heroLightColor(_ e: EnergyModel) -> Color {
        if e.chargeCls == "ok" || e.chargeCls == "charge" { return KanseiPalette.info }
        if e.socPct < 15 { return KanseiPalette.error }
        if e.socPct < 30 { return KanseiPalette.warning }
        return KanseiPalette.ambient
    }

    private func lightBarGradient(_ accent: Color) -> LinearGradient {
        LinearGradient(
            colors: [Color.white, accent.opacity(0.75), accent],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private func healthText() -> String {
        let s = AN.summarize(cache, store.car)
        return s.overall.title
    }

    private func healthCls() -> String {
        let s = AN.summarize(cache, store.car)
        return s.overall.cls
    }

    // MARK: - ⑤ 分组容器（iOS inset-grouped）

    /// ⚠️ `content` 必须标 `@escaping`：它会被交给 `DSCard`，而 `DSCard` 把闭包
    /// 存成了属性（`init(content: @escaping () -> Content)`）。函数参数默认是
    /// **非逃逸**的，漏掉 `@escaping` 就会编译报错：
    /// `escaping closure captures non-escaping parameter 'content'`。
    @ViewBuilder
    private func group<Content: View>(
        _ title: String,
        trailing: String? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            DSSectionHeader(title: title, trailing: trailing)
            DSCard {
                VStack(alignment: .leading, spacing: 0) { content() }
            }
        }
        .padding(.bottom, DS.Space.gap)
    }

    // MARK: - ④ 快捷操作

    private var quickActions: some View {
        let body = VM.bodyStatus(cache)
        let lockChip = body.first { $0.label == "车锁" }
        let acOn = VM.comfortStatus(cache).acOn

        return group("快捷操作") {
            DSRow(
                icon: lockChip?.text == "未锁" ? "lock.open.fill" : "lock.fill",
                title: lockChip?.text == "未锁" ? "锁车" : "解锁",
                value: lockChip?.text ?? "--",
                valueCls: lockChip?.cls ?? "na"
            ) { quick(lockChip?.text == "未锁" ? "LockDoor" : "UnLockDoor") }
            DSSeparator()
            DSRow(
                icon: "snowflake",
                title: acOn == true ? "关闭空调" : "打开空调",
                value: acOn == nil ? "--" : (acOn! ? "运行中" : "已关闭"),
                valueCls: acOn == true ? "ok" : "na"
            ) { quick("OpenAir") }
            DSSeparator()
            DSRow(
                icon: "location.fill",
                title: "寻车鸣笛",
                subtitle: "闪灯并鸣笛一次"
            ) { quick("RemoteSearchCar") }
            // 这里曾经有一个「后备箱」行，但它发的是一条协议里并不存在的后备箱指令，点了必然失败。
            // 后备箱在车上（点车尾）与车况事实行里已经直读，所以删掉而不是留着。
        }
    }

    /// 快捷操作统一走「车控页执行」路径：写入 pendingQuickCtrl 后切到车控 Tab。
    /// 写的是协议里的真实指令名，由车控页原样执行（它同时兼容历史的 "air"/"lock" 简写）。
    private func quick(_ raw: String) {
        DSHaptic.tap()
        store.pendingQuickCtrl = raw
        NavState.shared.selectedTab = .control
    }

    // MARK: - 行驶

    private var driveSection: some View {
        let d = VM.driveStatus(cache)
        let comfort = VM.comfortStatus(cache)

        return group("行驶", trailing: d.batteryNote.isEmpty ? nil : d.batteryNote) {
            DSStatStrip(items: [
                .init("总里程", d.mile.isEmpty ? "--" : "\(d.mile) km"),
                .init("车速", d.speed.isEmpty ? "--" : "\(d.speed) km/h"),
                .init("档位", d.gear.isEmpty ? "--" : d.gear, cls: d.gearCls)
            ])
            DSSeparator(inset: 0)
            DSStatStrip(items: [
                .init("电机温度", motorTempShort(d.motorTemp)),
                .init("车内温度", comfort.cabinTemp),
                .init("车内 PM2.5", comfort.pmIn)
            ])
        }
    }

    /// "45℃ / 38℃" → "45℃"
    private func motorTempShort(_ raw: String) -> String {
        guard raw != "--" else { return "--" }
        return raw.components(separatedBy: "/").first?.trimmingCharacters(in: .whitespaces) ?? raw
    }

    // MARK: - 系统状态

    private var systemSection: some View {
        let summary = AN.summarize(cache, store.car)
        let rows = summary.domains

        return group("系统状态", trailing: summary.overall.title) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { idx, d in
                DSRow(
                    icon: domainIcon(d.key),
                    title: d.label,
                    value: d.short,
                    valueCls: d.cls
                )
                if idx < rows.count - 1 { DSSeparator() }
            }
        }
    }

    private func domainIcon(_ key: String) -> String {
        switch key {
        case "battery": return "battery.75"
        case "charge": return "bolt.fill"
        case "body": return "car.side.fill"
        case "tyre": return "circle.dashed"
        case "climate": return "snowflake"
        case "power": return "bolt.circle.fill"
        case "safety": return "shield.lefthalf.filled"
        case "network": return "antenna.radiowaves.left.and.right"
        case "service": return "wrench.and.screwdriver.fill"
        default: return "info.circle.fill"
        }
    }

    // MARK: - 电池

    private var batterySection: some View {
        let e = VM.energy(cache, store.car)

        return group("电池", trailing: e.chargeText) {
            DSRow(icon: "battery.75", title: "剩余电量", value: "\(e.soc)%", valueCls: e.socCls)
            DSSeparator()
            DSRow(icon: "road.lanes", title: "剩余续航", value: "\(e.range) km")
            DSSeparator()
            DSRow(icon: "waveform.path.ecg", title: "电压 / 电流", value: e.voltAmp)
            DSSeparator()
            DSRow(icon: "thermometer.medium", title: "电池温度", value: e.battTemp)
            DSSeparator()
            DSRow(icon: "shield.lefthalf.filled", title: "绝缘电阻", value: e.insulate)
            if let c = e.charging {
                DSSeparator()
                DSRow(icon: "bolt.fill", title: "充电功率", value: c.power, valueCls: "charge")
                DSSeparator()
                DSRow(icon: "clock", title: "充电时长", value: "\(c.durMin) 分钟")
                if let ttf = c.timeToFull {
                    DSSeparator()
                    DSRow(icon: "hourglass", title: "预计充满", value: ttf)
                }
            }
        }
    }

    // MARK: - 胎压

    private var tyreSection: some View {
        let tyre = VM.tyreStatus(cache)

        return group("胎压", trailing: tyre.alarmText) {
            HStack(alignment: .top, spacing: DS.Space.md) {
                ForEach(tyre.items.prefix(2)) { item in
                    tyreItem(item)
                }
            }
            DSSeparator(inset: 0)
            HStack(alignment: .top, spacing: DS.Space.md) {
                ForEach(Array(tyre.items.dropFirst(2).prefix(2))) { item in
                    tyreItem(item)
                }
            }
            DSSeparator(inset: 0)
            DSStatRow(label: "胎温区间", value: tyre.tempRange)
            DSSeparator(inset: 0)
            tyreTrend
        }
    }

    /// 胎压趋势 —— 真实采样：每 30 分钟一次，任一胎变化 ≥ 5 kPa 也会立刻留点。
    /// （服务端没有历史接口，曲线只能这样积累，所以攒不够时明确说明原因）
    @ViewBuilder
    private var tyreTrend: some View {
        let points = HistoryStore.shared.tyreSeries(hours: 24 * 7)
        if points.count >= 2 {
            DSTyreTrendChart(points: points)
                .padding(.top, DS.Space.md)
                .padding(.bottom, DS.Space.xs)
        } else {
            DSTrendEmpty(
                icon: "gauge.with.dots.needle.50percent",
                title: "正在积累胎压趋势",
                message: "每 \(Int(HistoryStore.tyreInterval / 60)) 分钟记一次"
                         + "（任一胎变化 ≥ \(Int(HistoryStore.tyreJump)) kPa 也会立刻记）。"
                         + "已记录 \(points.count) 个点。"
            )
            .padding(.top, DS.Space.sm)
        }
    }

    private func tyreItem(_ item: TyreItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.label)
                .font(DS.Typo.caption)
                .foregroundStyle(KanseiPalette.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(item.kpa)
                    .font(DS.Typo.metric(28))
                    .foregroundStyle(item.cls == "ok" ? KanseiPalette.primary : KanseiPalette.statusColor(item.cls))
                    .contentTransition(.numericText())
                Text("kPa")
                    .font(DS.Typo.caption)
                    .foregroundStyle(KanseiPalette.secondary)
            }
            Text("\(item.temp)℃")
                .font(DS.Typo.dataSmall)
                .foregroundStyle(KanseiPalette.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: - 座舱

    private var cabinSection: some View {
        let c = VM.comfortStatus(cache)

        return group("座舱", trailing: c.acOn == true ? "空调运行" : "空调关闭") {
            DSRow(icon: "snowflake", title: "空调", value: c.acText)
            DSSeparator()
            DSRow(icon: "thermometer.low", title: "车内温度", value: c.cabinTemp)
            DSSeparator()
            DSRow(icon: "thermometer.high", title: "车外温度", value: c.envTemp)
            DSSeparator()
            DSRow(icon: "aqi.low", title: "车内 PM2.5", value: c.pmIn)
            DSSeparator()
            DSRow(icon: "wind", title: "空气净化", value: c.purifier)
            DSSeparator()
            DSRow(icon: "carseat.left.fill", title: "主驾座椅", value: c.seatD)
            DSSeparator()
            DSRow(icon: "carseat.right.fill", title: "副驾座椅", value: c.seatP)
        }
    }

    // MARK: - 碳减排（有数据才出现）

    @ViewBuilder
    private var carbonSection: some View {
        let stats = CarbonSavingsTracker.shared.getTodayStats()
        if stats.todaySteps > 0 {
            group("碳减排", trailing: "\(stats.equivalentTrees) 棵树") {
                DSRow(icon: "figure.walk", title: "今日步行", value: "\(stats.todaySteps) 步")
                DSSeparator()
                DSRow(icon: "leaf.fill", title: "今日减碳", value: String(format: "%.2f kg", stats.todayCarbonKg))
                DSSeparator()
                DSRow(icon: "leaf.arrow.triangle.circlepath",
                      title: "累计减碳", value: String(format: "%.2f kg", stats.totalCarbonKg))
            }
        }
    }

    // MARK: - 位置

    private var locationSection: some View {
        let loc = VM.locStatus(cache)
        let hasCoord = loc.lat != "--" && loc.lng != "--"

        return VStack(alignment: .leading, spacing: DS.Space.sm) {
            DSSectionHeader(title: "位置", trailing: loc.dir != "--" ? loc.dir : nil)

            VStack(alignment: .leading, spacing: DS.Space.lg) {
                Text(loc.addr.isEmpty ? "暂无定位数据" : loc.addr)
                    .font(DS.Typo.headline)
                    .foregroundStyle(loc.addr.isEmpty ? KanseiPalette.secondary : KanseiPalette.primary)
                    .fixedSize(horizontal: false, vertical: true)

                if showMap {
                    Group {
                        if hasCoord {
                            LocationMapView(addr: loc.addr, lat: loc.lat, lng: loc.lng)
                        } else {
                            LocationMapViewPlaceholder(addr: loc.addr, lat: loc.lat, lng: loc.lng)
                        }
                    }
                    .frame(height: 180)
                }

                HStack(spacing: DS.Space.md) {
                    if hasCoord {
                        Button("导航") { openNav(loc) }
                            .buttonStyle(DSSecondaryButtonStyle())
                    }
                    Button(showMap ? "隐藏地图" : "显示地图") {
                        withAnimation(DS.MotionTokens.fade) { showMap.toggle() }
                    }
                    .buttonStyle(DSSecondaryButtonStyle())
                }
            }
            .padding(DS.Space.cardPadding)
            .background(RoundedRectangle(cornerRadius: DS.RadiusTokens.card, style: .continuous)
                .fill(KanseiPalette.nightSurface))

            DSCard {
                VStack(alignment: .leading, spacing: 0) {
                    DSRow(icon: "location.fill", title: "GPS", value: loc.gpsText, valueCls: loc.gpsCls)
                    DSSeparator()
                    DSRow(icon: "location.north.fill", title: "方位", value: "\(loc.dir) \(loc.deg)")
                    DSSeparator()
                    DSRow(icon: "antenna.radiowaves.left.and.right", title: "卫星", value: loc.satAlt)
                    DSSeparator()
                    DSRow(icon: "mappin.and.ellipse", title: "坐标",
                          value: hasCoord ? "\(loc.lat), \(loc.lng)" : "--")
                    if let pk = store.parkingLocation, let t = store.lastParkingTime {
                        DSSeparator()
                        DSRow(icon: "parkingsign.circle.fill", title: "停车点",
                              subtitle: "保存于 \(DateFormatter.relative(t))",
                              value: String(format: "%.4f, %.4f", pk.coordinate.latitude, pk.coordinate.longitude))
                    }
                }
            }

            HStack(spacing: DS.Space.md) {
                Button {
                    saveParking(loc)
                } label: {
                    Label(
                        store.parkingLocation != nil ? "更新停车位置" : "保存停车位置",
                        systemImage: "parkingsign.circle"
                    )
                }
                .buttonStyle(DSSecondaryButtonStyle())
            }
        }
        .padding(.bottom, DS.Space.gap)
    }

    // MARK: - 数据来源

    private var footer: some View {
        let update = lastFetch.map { DateFormatter.relative($0) } ?? "--"
        return HStack(spacing: DS.Space.sm) {
            Text("更新于 \(update)")
                .font(DS.Typo.footnote)
                .foregroundStyle(KanseiPalette.tertiary)
            Spacer(minLength: DS.Space.sm)
            if isRefreshing {
                ProgressView().controlSize(.small)
            } else {
                Button {
                    DSHaptic.tap()
                    Task { await fetchCore() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(DSIconButtonStyle(size: 36, tint: KanseiPalette.ambient))
                .accessibilityLabel(Text("刷新"))
            }
        }
        .padding(.vertical, DS.Space.sm)
    }

    // MARK: - 动作

    private func toggleFocusMode() {
        let fm = FocusModeManager.shared
        let next = FocusModeConfig(
            enabled: !fm.config.enabled,
            hideSensitiveData: fm.config.hideSensitiveData,
            showEssentialOnly: fm.config.showEssentialOnly,
            doNotDisturb: fm.config.doNotDisturb,
            autoStartDriving: fm.config.autoStartDriving,
            customMessage: fm.config.customMessage
        )
        fm.saveConfig(next)
        withAnimation(DS.MotionTokens.press) { focusEnabled = next.enabled }
    }

    /// 导航交给系统地图（MKMapItem 驾车模式）。
    /// 此前跳的是网页高德（http://uri.amap.com）—— 先起浏览器再授权，慢且体验断裂；
    /// 系统地图直达导航界面，无需任何授权弹窗。
    private func openNav(_ loc: LocModel) {
        guard let lat = Double(loc.lat), let lng = Double(loc.lng) else { return }
        let item = MKMapItem(location: CLLocation(latitude: lat, longitude: lng), address: nil)
        item.name = loc.addr.isEmpty ? "车辆位置" : loc.addr
        item.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
        ])
    }

    private func saveParking(_ loc: LocModel) {
        guard let lat = Double(loc.lat), let lng = Double(loc.lng) else { return }
        store.saveParkingLocation(CLLocation(latitude: lat, longitude: lng))
        ToastManager.shared.show("停车位置已保存", icon: "parkingsign.circle.fill")
    }

    private func shareStatus() {
        let e = VM.energy(cache, store.car)
        let tyre = VM.tyreStatus(cache)
        let comfort = VM.comfortStatus(cache)
        let summary = AN.summarize(cache, store.car)
        let info = ShareableStatusInfo(
            soc: "\(e.socPct)%",
            range: e.range,
            tireStatus: tyre.warnAny ? "有异常" : "正常",
            healthScore: summary.overall.title,
            cabinTemp: comfort.cabinTemp
        )
        let vc = UIActivityViewController(
            activityItems: [generateShareableStatus(info: info)],
            applicationActivities: nil
        )
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first?.rootViewController else { return }
        root.present(vc, animated: true)
    }

    // MARK: - 轮询

    private func startPolling() {
        startTimer?.cancel()
        startTimer = Task {
            await fetchCore()
            while !Task.isCancelled {
                store.checkNotificationsIfNeeded()
                let cal = Calendar.current
                if let last = store.lastCheckInDate {
                    if !cal.isDateInToday(last) { showCheckInReminder = true }
                } else {
                    showCheckInReminder = true
                }
                try? await Task.sleep(for: .seconds(60))
                await fetchCore()
            }
        }
    }

    private func fetchCore() async {
        await store.fetchCore()
        lastFetch = Date()
        isRefreshing = false
    }
}

// MARK: - 车（道具即界面）

/// 一辆车：近黑剪影 + 车窗反光 + 轮 + 车灯。
/// 车尾那条贯穿光带按 `lit` 比例点亮 —— 它同时就是电量表。
struct CarStageView: View {
    /// 尾灯亮起比例 0...1（= SOC）
    var lit: Double
    var accent: Color
    /// 两扇可见车门的灯光色（左前 / 左后）："ok" 已锁 / "bad" 未锁 / "na" 未上报
    var doorLocks: [String] = ["na", "na"]
    /// 后备箱灯："ok" 已关 / "bad" 开启 / "na" 未上报
    var trunkCls: String = "na"
    /// 指令执行中：门灯走虚线（静态的"进行中"，不用循环动画）
    var busy: Bool = false
    var onZone: (CarZone) -> Void = { _ in }

    private let carW: CGFloat = 470
    private let carH: CGFloat = 250

    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width / carW, geo.size.height / carH)
            let dx = (geo.size.width - carW * scale) / 2
            let dy = (geo.size.height - carH * scale) / 2
            ZStack {
                canvasLayer(scale: scale, dx: dx, dy: dy)
                tapZones(scale: scale, dx: dx, dy: dy)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("车辆"))
        .accessibilityValue(Text("电量 \(Int(max(0, min(1, lit)) * 100))%"))
    }

    // MARK: - 绘制

    private func canvasLayer(scale: CGFloat, dx: CGFloat, dy: CGFloat) -> some View {
        Canvas { ctx, size in
            let t = CGAffineTransform(translationX: dx, y: dy).scaledBy(x: scale, y: scale)
            func xf(_ p: Path) -> Path { p.applying(t) }

            // 地面光池：径向渐变，边界外恒为 0 —— 不可能出现"亮矩形"
            ctx.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .radialGradient(
                    Gradient(colors: [
                        Color.white.opacity(0.10),
                        Color.white.opacity(0.025),
                        Color.white.opacity(0.0)
                    ]),
                    center: CGPoint(x: size.width / 2, y: size.height * 0.60),
                    startRadius: 0,
                    endRadius: size.height * 0.52
                )
            )

            let body = Color(white: 0.045)

            // 车身剪影
            var silhouette = Path()
            silhouette.move(to: CGPoint(x: 24, y: 150))
            silhouette.addCurve(to: CGPoint(x: 50, y: 128),
            control1: CGPoint(x: 24, y: 136),
            control2: CGPoint(x: 34, y: 131))
            silhouette.addCurve(to: CGPoint(x: 178, y: 86),
            control1: CGPoint(x: 76, y: 106),
            control2: CGPoint(x: 122, y: 90))
            silhouette.addCurve(to: CGPoint(x: 322, y: 118),
            control1: CGPoint(x: 238, y: 82),
            control2: CGPoint(x: 292, y: 96))
            silhouette.addCurve(to: CGPoint(x: 380, y: 137),
            control1: CGPoint(x: 350, y: 122),
            control2: CGPoint(x: 372, y: 128))
            silhouette.addCurve(to: CGPoint(x: 387, y: 151),
            control1: CGPoint(x: 385, y: 142),
            control2: CGPoint(x: 387, y: 146))
            silhouette.addLine(to: CGPoint(x: 387, y: 156))
            silhouette.addCurve(to: CGPoint(x: 376, y: 164),
            control1: CGPoint(x: 387, y: 161),
            control2: CGPoint(x: 383, y: 164))
            silhouette.addLine(to: CGPoint(x: 36, y: 164))
            silhouette.addCurve(to: CGPoint(x: 24, y: 156),
            control1: CGPoint(x: 28, y: 164),
            control2: CGPoint(x: 24, y: 161))
            silhouette.closeSubpath()
            ctx.fill(xf(silhouette), with: .color(body))

            // 车顶轮廓光
            var roof = Path()
            roof.move(to: CGPoint(x: 52, y: 142))
            roof.addCurve(to: CGPoint(x: 178, y: 92),
            control1: CGPoint(x: 78, y: 112),
            control2: CGPoint(x: 124, y: 96))
            roof.addCurve(to: CGPoint(x: 320, y: 122),
            control1: CGPoint(x: 234, y: 88),
            control2: CGPoint(x: 288, y: 100))
            ctx.stroke(xf(roof), with: .color(Color.white.opacity(0.55)),
                       style: StrokeStyle(lineWidth: 2.2, lineCap: .round))

            // 腰线
            var waist = Path()
            waist.move(to: CGPoint(x: 30, y: 132))
            waist.addCurve(to: CGPoint(x: 384, y: 140),
            control1: CGPoint(x: 120, y: 124),
            control2: CGPoint(x: 300, y: 124))
            ctx.stroke(xf(waist), with: .color(Color.white.opacity(0.20)), style: StrokeStyle(lineWidth: 1.4))

            // 车窗 + 一道斜反光
            var window = Path()
            window.move(to: CGPoint(x: 112, y: 140))
            window.addCurve(to: CGPoint(x: 214, y: 100),
            control1: CGPoint(x: 136, y: 116),
            control2: CGPoint(x: 168, y: 104))
            window.addCurve(to: CGPoint(x: 302, y: 120),
            control1: CGPoint(x: 252, y: 97),
            control2: CGPoint(x: 280, y: 104))
            window.addLine(to: CGPoint(x: 286, y: 140))
            window.closeSubpath()
            ctx.fill(xf(window), with: .color(Color(white: 0.02)))

            var glass = Path()
            glass.move(to: CGPoint(x: 126, y: 136))
            glass.addCurve(to: CGPoint(x: 214, y: 103),
            control1: CGPoint(x: 148, y: 114),
            control2: CGPoint(x: 178, y: 106))
            glass.addLine(to: CGPoint(x: 200, y: 133))
            glass.closeSubpath()
            ctx.fill(xf(glass), with: .color(Color.white.opacity(0.16)))

            // 车轮
            for cx in [110.0, 316.0] {
                let tyre = Path(ellipseIn: CGRect(x: cx - 30, y: 134, width: 60, height: 60))
                ctx.stroke(xf(tyre), with: .color(Color.white.opacity(0.16)), style: StrokeStyle(lineWidth: 1.4))
                let rim = Path(ellipseIn: CGRect(x: cx - 17, y: 147, width: 34, height: 34))
                ctx.stroke(xf(rim), with: .color(Color.white.opacity(0.24)), style: StrokeStyle(lineWidth: 1.6))
                var arch = Path()
                arch.move(to: CGPoint(x: cx - 17, y: 152))
                arch.addQuadCurve(to: CGPoint(x: cx + 17, y: 152), control: CGPoint(x: cx, y: 128))
                ctx.stroke(xf(arch), with: .color(Color.white.opacity(0.38)),
                           style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }

            // 车门锁状态灯（近侧两扇门，与车门位置对齐）：
            // 绿 = 已锁，橙 = 未锁，灰 = 未上报。车端只有整车锁 / 解锁指令，所以两段灯一起变。
            let seamY = 158.0
            let doorSegments: [(CGFloat, CGFloat, Int)] = [(148, 210, 0), (218, 280, 1)]
            for (x0, x1, idx) in doorSegments {
                let cls = doorLocks.indices.contains(idx) ? doorLocks[idx] : "na"
                let c = lockColor(cls)
                let seg = Path { p in
                    p.move(to: CGPoint(x: x0, y: seamY))
                    p.addLine(to: CGPoint(x: x1, y: seamY))
                }
                if cls != "na" {
                    ctx.drawLayer { layer in
                        layer.addFilter(.blur(radius: 8))
                        layer.opacity = 0.5
                        layer.stroke(xf(seg), with: .color(c), style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    }
                }
                ctx.stroke(xf(seg), with: .color(c),
                           style: busy
                           ? StrokeStyle(lineWidth: 4, lineCap: .round, dash: [5, 4])
                           : StrokeStyle(lineWidth: 4, lineCap: .round))
            }

            // 后备箱：状态灯 + 开启时画出掀起的箱盖
            let tc = lockColor(trunkCls)
            var trunkSeam = Path()
            trunkSeam.move(to: CGPoint(x: 44, y: 150))
            trunkSeam.addLine(to: CGPoint(x: 96, y: 150))
            if trunkCls == "bad" {
                ctx.drawLayer { layer in
                    layer.addFilter(.blur(radius: 8))
                    layer.opacity = 0.5
                    layer.stroke(xf(trunkSeam), with: .color(tc), style: StrokeStyle(lineWidth: 12, lineCap: .round))
                }
            }
            ctx.stroke(xf(trunkSeam), with: .color(tc), style: StrokeStyle(lineWidth: 4, lineCap: .round))

            if trunkCls == "bad" {
                var lid = Path()
                lid.move(to: CGPoint(x: 96, y: 148))
                lid.addLine(to: CGPoint(x: 58, y: 116))
                ctx.stroke(xf(lid), with: .color(tc.opacity(0.85)), style: StrokeStyle(lineWidth: 2.4, lineCap:
 .round))
            }

            // 前灯（冷白）
            var head = Path()
            head.move(to: CGPoint(x: 370, y: 128))
            head.addCurve(to: CGPoint(x: 387, y: 142),
            control1: CGPoint(x: 378, y: 131),
            control2: CGPoint(x: 384, y: 136))
            ctx.drawLayer { layer in
                layer.addFilter(.blur(radius: 8))
                layer.opacity = 0.55
                layer.stroke(xf(head), with: .color(Color(red: 1.0, green: 0.98, blue: 0.94)),
                             style: StrokeStyle(lineWidth: 11, lineCap: .round))
            }
            ctx.stroke(xf(head), with: .color(Color(red: 1.0, green: 0.98, blue: 0.94)),
                       style: StrokeStyle(lineWidth: 3.4, lineCap: .round))

            // 尾灯贯穿光带 = 电量表
            let tailY = 142.0
            let full = Path { p in
                p.move(to: CGPoint(x: 24, y: tailY))
                p.addLine(to: CGPoint(x: 88, y: tailY))
            }
            ctx.stroke(xf(full), with: .color(Color.white.opacity(0.14)),
                       style: StrokeStyle(lineWidth: 4, lineCap: .round))

            let width = 64.0 * max(0, min(1, lit))
            if width > 0.5 {
                let on = Path { p in
                    p.move(to: CGPoint(x: 24, y: tailY))
                    p.addLine(to: CGPoint(x: 24 + width, y: tailY))
                }
                let gradient = Gradient(colors: [Color.white, accent])
                ctx.drawLayer { layer in
                    layer.addFilter(.blur(radius: 9))
                    layer.opacity = 0.6
                    layer.stroke(xf(on), with: .linearGradient(
                        gradient,
                        startPoint: CGPoint(x: 24 * scale + dx, y: 0),
                        endPoint: CGPoint(x: (24 + width) * scale + dx, y: 0)
                    ), style: StrokeStyle(lineWidth: 11, lineCap: .round))
                }
                ctx.stroke(xf(on), with: .linearGradient(
                    gradient,
                    startPoint: CGPoint(x: 24 * scale + dx, y: 0),
                    endPoint: CGPoint(x: (24 + width) * scale + dx, y: 0)
                ), style: StrokeStyle(lineWidth: 4, lineCap: .round))
            }
        }
    }

    private func lockColor(_ cls: String) -> Color {
        switch cls {
        case "ok":  return KanseiPalette.success
        case "bad": return KanseiPalette.warning
        default:    return Color.white.opacity(0.16)
        }
    }

    // MARK: - 可点区域（车身即控件）

    /// 车坐标（470×250）里的热区：两扇近侧车门 + 后备箱，互不重叠
    private func carRect(_ zone: CarZone) -> CGRect {
        switch zone {
        case .leftRear:  return CGRect(x: 140, y: 136, width: 76, height: 46)
        case .leftFront: return CGRect(x: 212, y: 136, width: 76, height: 46)
        case .trunk:     return CGRect(x: 20, y: 104, width: 108, height: 78)
        }
    }

    private func viewRect(_ r: CGRect, scale: CGFloat, dx: CGFloat, dy: CGFloat) -> CGRect {
        let rect = CGRect(x: r.minX * scale + dx, y: r.minY * scale + dy,
                          width: r.width * scale, height: r.height * scale)
        // 触控目标不小于 44pt（HIG）：不够就把热区向外扩
        return rect.insetBy(dx: min(0, (rect.width - 44) / 2), dy: min(0, (rect.height - 44) / 2))
    }

    private func tapZones(scale: CGFloat, dx: CGFloat, dy: CGFloat) -> some View {
        ZStack {
            ForEach(CarZone.allCases) { zone in
                let r = viewRect(carRect(zone), scale: scale, dx: dx, dy: dy)
                Button {
                    onZone(zone)
                } label: {
                    Color.clear.contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(width: r.width, height: r.height)
                .position(x: r.midX, y: r.midY)
                .accessibilityLabel(Text(zoneLabel(zone)))
                .accessibilityHint(Text(zoneHint(zone)))
            }
        }
    }

    private func zoneLockText(_ idx: Int) -> String {
        guard doorLocks.indices.contains(idx) else { return "状态未知" }
        switch doorLocks[idx] {
        case "ok":  return "已锁"
        case "bad": return "未锁"
        default:    return "状态未知"
        }
    }

    private func zoneLabel(_ zone: CarZone) -> String {
        switch zone {
        case .leftFront: return "左前门，\(zoneLockText(0))"
        case .leftRear:  return "左后门，\(zoneLockText(1))"
        case .trunk:
            switch trunkCls {
            case "ok":  return "后备箱，已关"
            case "bad": return "后备箱，开启"
            default:    return "后备箱，状态未知"
            }
        }
    }

    private func zoneHint(_ zone: CarZone) -> String {
        if zone == .trunk {
            return CarCommand.trunkOpen == nil ? "双击查看后备箱状态" : "双击开合后备箱"
        }
        return "双击锁车或解锁整车"
    }
}

// MARK: - 相对时间

extension DateFormatter {
    static func relative(_ date: Date) -> String {
        let diff = Int(Date().timeIntervalSince(date))
        if diff < 60 { return "刚刚" }
        if diff < 3600 { return "\(diff / 60) 分钟前" }
        if diff < 86400 { return "\(diff / 3600) 小时前" }
        return "\(diff / 86400) 天前"
    }
}

// MARK: - 位置地图（#NEW-102 内嵌 MapKit 实时地图）

struct LocationMapView: View {
    let addr: String
    let lat: String
    let lng: String
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 39.9, longitude: 116.4),
        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
    )

    var body: some View {
        MapView(
            coordinate: parseCoordinate() ?? CLLocationCoordinate2D(latitude: 39.9, longitude: 116.4),
            span: region.span,
            points: [],
            title: addr.isEmpty ? "车辆位置" : addr
        )
    }

    private func parseCoordinate() -> CLLocationCoordinate2D? {
        guard let latVal = Double(lat), let lngVal = Double(lng) else { return nil }
        return CLLocationCoordinate2D(latitude: latVal, longitude: lngVal)
    }
}

// MARK: - 位置地图占位（坐标缺失时）

struct LocationMapViewPlaceholder: View {
    let addr: String
    let lat: String
    let lng: String

    var body: some View {
        ZStack {
            KanseiPalette.glassLight
            VStack(spacing: DS.Space.sm) {
                Image(systemName: "map")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(KanseiPalette.tertiary)
                Text(addr.isEmpty ? "暂无定位" : addr)
                    .font(DS.Typo.footnote)
                    .foregroundStyle(KanseiPalette.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, DS.Space.lg)
            }
        }
    }
}

struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack { HomeView() }
    }
}
