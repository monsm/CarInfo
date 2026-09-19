import SwiftUI
import UIKit

// 车况首页 —— iOS 27 Liquid Glass：
// SOC Hero + 车速里程 + 快控按钮 + 状态域 + 电池 + 胎压 + 座舱 + 位置
// 轮询 60s（fetchCore）+ 位置 8s

struct HomeView: View {
    private let store = AppStore.shared
    @State private var showLoginAlert = false
    @State private var startTimer: Task<Void, Never>? = nil
    @State private var lastFetch: Date?
    @State private var showMap = true
    @State private var carVersion: Int = 0          // 切换车辆时 +1，驱动过渡动画
    @State private var socProgress: CGFloat = 0      // SOC圆环进度 0→socPct
    @State private var socCardOpacity: CGFloat = 0   // SOC卡片入场淡入
    @State private var socCount: Int = 0             // SOC数字滚动计数
    @State private var mileCount: Int = 0            // 里程数字滚动计数
    @State private var isRefreshing = false          // 下拉刷新标志（仅刷新时重播动画）
    @State private var pulseTrigger: String = ""      // 触发数值脉冲高亮（SOC / 里程变化时更新）
    @State private var expandedDrive = false          // 车速里程行展开状态
    @State private var expandedTyre = false           // 胎压卡展开状态
    @State private var tyreWatchValue: String = ""    // B7: 胎压数值变化脉冲触发器
    @State private var switchingCar = false           // 切换车辆涟漪标志
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize = ContentSizeCategory.med

    var body: some View {
        Group {
            if let cfg = TokenStore.read(), !cfg.accessToken.isEmpty {
                content
            } else {
                ContentUnavailableView("请先登录", systemImage: "lock.rectangle", description: Text("点击下方登录"))
                    .padding(.top, 100)
            }
        }
        .sheet(isPresented: $showLoginAlert) { LoginView() }
    }

    private var content: some View {
        let cache = store.caches
        let car = store.car
        let energy = VM.energy(cache, car)
        let summary = AN.summarize(cache, car)
        let tyre = VM.tyreStatus(cache)
        let comfort = VM.comfortStatus(cache)
        let loc = VM.locStatus(cache)
        let hasData = cache["control"] != nil
        let drive = VM.driveStatus(cache)

        return ScrollView {
            VStack(spacing: DynamicTypeScale.spacing(Theme.cardSpacing, dynamicTypeSize)) {
                greetingRow(energy)
                socHero(energy).staggeredEntrance(index: 0)
                driveMetricsExpanded(drive).staggeredEntrance(index: 1)
                carSelector.staggeredEntrance(index: 2)
                quickControl.staggeredEntrance(index: 3)
                domainCard(summary).staggeredEntrance(index: 4)
                if hasData { batterySection(cache).staggeredEntrance(index: 5) }
                tyreCardExpanded(tyre).staggeredEntrance(index: 6)
                comfortCard(comfort).staggeredEntrance(index: 7)
                locationCard(loc).staggeredEntrance(index: 8)
                footerNote(energy).staggeredEntrance(index: 9)
            }
            .adaptivePagePadding(dynamicTypeSize)
            .adaptiveSafeAreaBottom(12, dynamicTypeSize)
        }
        .id(carVersion)
        .transition(
            .asymmetric(
                insertion: .move(edge: .trailing)
                    .combined(with: .opacity)
                    .combined(with: .scale(scale: 0.96, anchor: .center)),
                removal: .move(edge: .leading)
                    .combined(with: .opacity)
                    .combined(with: .scale(scale: 0.96, anchor: .center))
            )
        )
        .animation(.spring(response: 0.45, dampingFraction: 0.7, blendDuration: 0.4), value: carVersion)
        .scrollBounceBehavior(.basedOnSize)
        .milestoneCelebration(mileage: mileCount)
        .pageBackground(.accentColor)
        .overlay(alignment: .top) {
            // #41 天气联动主题 - 雨天粒子效果
            if WeatherTheme.currentCondition == .rainy {
                WeatherEffectView(particles: WeatherTheme.weatherParticles)
                    .opacity(0.3)
            }
        }
        .navigationTitle("车况").navBarStyle()
        .toolbar {
            // #19 分享按钮
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    shareStatus()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel(Text("分享车况"))
            }
        }
        .onChange(of: store.carId) { newId in
            guard !newId.isEmpty else { return }
            withAnimation(.easeInOut(duration: 0.08)) {
                carVersion += 1
            }
            // 切换车辆时触发全屏玻璃涟漪扩散动效
            switchingCar = true
            // B7: 胎压数值变化脉冲
            tyreWatchValue = UUID().uuidString
        }
        .onChange(of: switchingCar) { switching in
            guard switching else { return }
            // 涟漪扩散后自动消散
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.easeOut(duration: 0.3)) {
                    switchingCar = false
                }
            }
        }
        .onAppear { startPolling(); startSocAnimation(); startMileAnimation(); tyreWatchValue = UUID().uuidString }
        .onDisappear {
            startTimer?.cancel()
            startTimer = nil
        }
        .refreshable { isRefreshing = true; await fetchCore(); isRefreshing = false }
        .glassRefreshRipple(isRefreshing: $isRefreshing)
        .glassRefreshHalo(isRefreshing: $isRefreshing)
        .refreshProgressRing(progress: $isRefreshing)
        .glassSwitchRipple(isSwitching: $switchingCar)
    }

    // MARK: 问候行
    private func greetingRow(_ e: EnergyModel) -> some View {
        let hour = Calendar.current.component(.hour, from: Date())
        let greeting = localizedGreeting
        let dateStr = DateFormatter.relative(Date())
        return HStack {
            Text(greeting)
                .font(Theme.h4)))
            Spacer()
            Text(dateStr)
                .font(Theme.caption)).foregroundStyle(.secondary)
        }
        .adaptivePagePadding(dynamicTypeSize)
        .padding(.vertical, 8)
    }

    // MARK: SOC Hero — 渐变圆环 + 入场动画 + 浮动粒子
    private func socHero(_ e: EnergyModel) -> some View {
        VStack(spacing: 18) {
            // 大尺寸 SOC 光环 Hero（带脉冲发光 + 浮动粒子）
            ZStack {
                // 第 0 层：外扩散光晕（呼吸脉冲）
                Circle()
                    .fill(AngularGradient(colors: socGlowColors(e.socPct),
                                          center: .center, startAngle: .degrees(-90), endAngle: .degrees(270)))
                    .frame(width: 232, height: 232)
                    .opacity(0.15)
                    .blur(radius: 12)

                // 第 0.5 层：EKG 心电图描边流动环（颜色随 SOC 动态变化：低电量红→高电量绿）
                EKGFloRingDynamic(size: 224, lineWidth: 1.5, speed: 3.5, percentage: e.socPct)

                // 第 1 层：脉冲光环（持续呼吸）
                Circle()
                    .strokeBorder(AngularGradient(colors: [.green, .teal], center: .center, startAngle: .degrees(-90), endAngle: .degrees(270)), lineWidth: 2)
                    .frame(width: 218, height: 218)
                    .opacity(0.10)
                    .blur(radius: 5)
                    .heartbeatPulse()

                // 第 2 层：底色轨道
                Circle()
                    .stroke(Color(.systemGray5).opacity(0.55), lineWidth: 16)
                    .frame(width: 196, height: 196)

                // 第 3 层：彩色进度弧（动画展开）
                Circle()
                    .trim(from: 0, to: max(0.02, socProgress / 100))
                    .stroke(
                        AngularGradient(colors: [.green, .green, .accentColor, .orange, .red],
                                        center: .center, startAngle: .degrees(-90), endAngle: .degrees(270)),
                        style: StrokeStyle(lineWidth: 16, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 196, height: 196)
                    .shadow(color: socShadowColor(e.socPct).opacity(0.35), radius: 12, y: 4)

                // 第 4 层：浮动装饰粒子
                FloatingParticles(size: 196)

                // 第 5 层：中心数字（流体字体，随容器宽度自适应）
                VStack(spacing: 2) {
                    FluidPercentHero(e.soc == "--" ? "--" : String(socCount))
                        .dynamicTypeLineLimit(1)
                    Text("剩余电量")
                        .font(Theme.caption)))
                        .foregroundStyle(.secondary)
                        .dynamicTypeTextCompress(isTitle: true)
                        .accessibilityLabel(Text("剩余电量"))
                }
            }
            // 续航 + 充电状态
            HStack(spacing: 16) {
                MetricPill(icon: "point.topleft.down.curvedto.point.bottomright.up",
                           value: e.range == "--" ? "--" : e.range,
                           unit: "km", tint: .green, fluidValue: true)
                MetricPill(icon: "bolt.fill", value: e.chargeText, unit: "", tint: .accentColor, fluidValue: true)
            }
            // #1 充电倒计时
            if let ttf = e.timeToFull {
                Text("预计充满：\(ttf)").font(Theme.footnote).foregroundStyle(.secondary)
            }
            // #2 #23 能耗统计 + SOC耗尽预测
            if let cons = e.avgConsumption, cons != "--" {
                HStack {
                    Text("平均能耗").font(Theme.footnote).foregroundStyle(.secondary)
                    Spacer()
                    Text(cons).font(Theme.caption.weight(.semibold)).foregroundStyle(.accentColor)
                }
            }
            if let tte = e.timeToEmpty, tte != "--" {
                Text("预计剩余行驶：\(tte)").font(Theme.footnote).foregroundStyle(.secondary)
            }
            // 在线状态
            Text(e.online.text)
                .font(Theme.footnote)))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .dynamicTypeCompress()
        .glassHeroCard()
        .glassLongPressDeform()
        .runningGlow(color: .green)
        .opacity(socCardOpacity)
        .valuePulse(tint: .green)
    }

    // MARK: SOC颜色辅助函数
    private func socGlowColors(_ pct: Int) -> [Color] {
        switch pct {
        case 0...39: return [.red.opacity(0.5), .clear]
        case 40...69: return [.orange.opacity(0.45), .clear]
        case 70...89: return [.yellow.opacity(0.45), .green.opacity(0.25)]
        default: return [.green.opacity(0.45), .teal.opacity(0.25)]
        }
    }

    private func socShadowColor(_ pct: Int) -> Color {
        switch pct {
        case 0...39: return .red
        case 40...69: return .orange
        case 70...89: return .yellow
        default: return .green
        }
    }

    // MARK: 快控按钮动作
    private func onQuickCtrl(_ q: QuickCtrl) {
        store.pendingQuickCtrl = q.rawValue
        NotificationCenter.default.post(name: .navToMessages, object: nil)
        // 穿透到车控页自动执行（见 ControlView.onAppear）
    }

    // MARK: 车辆切换
    private var carSelector: some View {
        let carSel = VM.carSel(store.cars, store.carId)
        return HStack(spacing: 12) {
            Image(systemName: "car.2.fill")
                .font(Theme.bodyMd))
                .foregroundStyle(Color.accentColor)
                .frame(width: 40, height: 40)
                .background(.thin, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Picker("车辆", selection: Binding(
                get: { carSel.index },
                set: { store.selectCar($0) }
            )) {
                ForEach(Array(carSel.options.enumerated()), id: \.offset) { idx, opt in
                    Text(opt.name).tag(idx)
                }
            }
            .pickerStyle(.menu)
            .padding(.horizontal, 4)
            .font(Theme.h4)))
            Spacer()
            if carSel.count > 1 {
                Text("\(carSel.count) 辆")
                    .font(Theme.footnote.bold())))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(.thin, in: Capsule())
            }
        }
        .padding(16)
        .dynamicTypeCompress()
        .glassCard(corner: 22)
        .glassLongPressDeform()
    }

    // MARK: 电池摘要行（来自 AN.summarize）
    private var battSummary: (headLines: [HeadLine], cls: String, title: String) {
        guard let battDomain = AN.summarize(store.caches, store.car).domains.first(where: { $0.key == "battery" }) else {
            return ([], "na", "--")
        }
        let lines: [HeadLine] = [
            HeadLine(id: "soc", label: "SOC", value: battDomain.metrics.first { $0.k == "SOC" }?.v ?? "--", cls: battDomain.cls, reason: ""),
            HeadLine(id: "range", label: "续航", value: VM.energy(store.caches, store.car).range + " km", cls: battDomain.cls, reason: ""),
            HeadLine(id: "alarm", label: "告警", value: battDomain.alarms.isEmpty ? "无" : "\(battDomain.alarms.count) 项", cls: battDomain.cls, reason: battDomain.alarms.isEmpty ? "" : battDomain.alarms.joined(separator: " · "))
        ].filter { !$0.value.contains("--") }
        return (lines, battDomain.cls, battDomain.title)
    }

    private struct HeadLine: Identifiable {
        let id: String
        let label: String
        let value: String
        let cls: String
        let reason: String
    }

    // MARK: 车速里程行（带 EKG 波形背景）
    private func driveMetricsRow(_ d: DriveModel) -> some View {
        ZStack(alignment: .leading) {
            // EKG 波形背景（微透明流动描边，模拟速度波动）
            EKGFloRingDynamic(size: 200, lineWidth: 1.0, speed: 4.0, percentage: min(1.0, max(0.0, Double(d.speed) / 200)))
                .opacity(0.18)
                .allowsHitTesting(false)
            HStack(spacing: 12) {
            if !d.fireStatus.isEmpty {
                let fCls = d.fireStatus == "启动" ? "bad" : "ok"
                VStack(spacing: 2) {
                    Image(systemName: d.fireStatus == "启动" ? "fire.fill" : "battery.100")
                        .font(Theme.footnote)).foregroundStyle(Theme.statusColor(fCls))
                    Text(d.fireStatus).font(Theme.micro))).foregroundStyle(Theme.statusColor(fCls))
                }
                .frame(width: 52, height: 40)
                .background(Theme.statusColor(fCls).opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            // 速度 + 里程：流体数字字体，随容器宽度自动缩放
            MetricPill(icon: "speedometer", value: d.speed, unit: "km/h", tint: Theme.brand, fluidValue: true)
            MetricPill(icon: "gauge.full", value: mileCount > 0 ? String(mileCount) : d.mile, unit: "km", tint: .accentColor, fluidValue: true)
                .valuePulse(tint: .accentColor, watchValue: pulseTrigger)
        }            .padding(Theme.Spacing.xl)
            .dynamicTypeCompress()
            .glassCard(corner: 20)
            .glassLongPressDeform()
        }
    }

    // MARK: 车速里程展开卡（弹簧高度动画 + 玻璃压缩形变）
    private func driveMetricsExpanded(_ d: DriveModel) -> some View {
        let chevronAngle: Angle = expandedDrive ? .degrees(90) : .degrees(0)
        return Button {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.65, blendDuration: 0.35)) {
                expandedDrive.toggle()
            }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                driveMetricsRow(d)
                if expandedDrive {
                    Divider().padding(.horizontal, Theme.Spacing.xl)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            MetricPill(icon: "gearshape.fill", value: d.gear, unit: d.gearSub, tint: .purple)
                            MetricPill(icon: "thermometer.super", value: d.motorTemp, unit: "℃", tint: .orange)
                        }
                        if !d.batteryNote.isEmpty {
                            Text(d.batteryNote).font(Theme.footnote)).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.xl)
                    .padding(.bottom, Theme.Spacing.lg)
                }
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(expandedDrive ? 0.98 : 1.0)
        .animation(.spring(response: 0.5, dampingFraction: 0.65, blendDuration: 0.4), value: expandedDrive)
        .liquidGlassRipple(cornerRadius: 20)
        .accessibilityLabel(Text("车速里程详情"))
        .accessibilityHint(Text(expandedDrive ? "点击收起详细数据" : "点击展开车速、档位、电机温度等行驶详情"))
        .overlay(alignment: .trailing) {
            Image(systemName: "chevron.right")
                .font(Theme.footnote.bold())
                .foregroundStyle(.tertiary)
                .rotationEffect(chevronAngle)
                .animation(.spring(response: 0.35, dampingFraction: 0.6), value: expandedDrive)
                .padding(.trailing, 14)
        }
    }

    // MARK: 快控 - 2x2 网格大圆钮
    private var quickControl: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                ForEach(Array(QuickCtrl.allCases.enumerated()), id: \.element) { idx, q in
                    QuickControlButton(icon: q.symbol, label: q.title, tint: q.accent) {
                        onQuickCtrl(q)
                    }
                }
            }
        }
        .padding(Theme.Spacing.xl)
        .dynamicTypeCompress()
        .glassHeroCard()
        .glassLongPressDeform()
    }

    // MARK: 快捷控制枚举
    private enum QuickCtrl: String, CaseIterable {
        case lock = "LockDoor"
        case unlock = "UnLockDoor"
        case air = "OpenAir"
        case search = "RemoteSearchCar"
        var symbol: String {
            switch self {
            case .lock: return "lock.fill"
            case .unlock: return "lock.open.fill"
            case .air: return "snowflake"
            case .search: return "location"
            }
        }
        var title: String {
            switch self {
            case .lock: return "锁车"
            case .unlock: return "解锁"
            case .air: return "开空调"
            case .search: return "寻车"
            }
        }
        var accent: Color {
            switch self {
            case .lock, .unlock: return .blue
            case .air: return .teal
            case .search: return .orange
            }
        }
    }

    // MARK: 状态域（可展开）
    private func domainCard(_ summary: Summary) -> some View {
        ExpandingCardBox(title: "车辆状态", side: summary.overall.title, sideCls: summary.overall.cls, cornerRadius: 20) {
            VStack(spacing: 2) {
                let rows = summary.domains.filter { $0.key != "service" }
                ForEach(Array(rows.enumerated()), id: \.element.id) { idx, d in
                    domainRow(d)
                    if idx < rows.count - 1 { ListDivider() }
                }
            }
        }
    }

    private func domainRow(_ d: DomainVerdict) -> some View {
        let icon = domainIcon(d.key)
        HStack(spacing: 10) {
            Text(icon)
                .font(Theme.caption))
                .foregroundStyle(Theme.statusColor(d.cls))
                .frame(width: 20)
            Text(d.label)
                .font(Theme.caption)))
                .foregroundStyle(.primary)
            Spacer()
            Text(d.short)
                .font(Theme.caption.bold())))
                .foregroundStyle(Theme.statusColor(d.cls))
        }
        .padding(.vertical, 6)
    }

    private func domainIcon(_ key: String) -> String {
        switch key {
        case "battery": return "battery.3quarter.fill"
        case "charge": return "lightning.bolt.fill"
        case "body": return "car.door"
        case "tyre": return "tire.flattraction"
        case "climate": return "snowflake.fill"
        case "power": return "bolt.circle.fill"
        case "safety": return "shield.lefthalf.fill"
        case "network": return "antenna.radiowaves.left.and.right"
        case "service": return "wrench.and.screwdriver.fill"
        default: return "circle.fill"
        }
    }

    // MARK: 电池区
    private func batterySection(_ cache: [String: Any?]) -> some View {
        let batt = VM.batteryModel(cache)
        return VStack(spacing: DynamicTypeScale.spacing(Theme.cardSpacing, dynamicTypeSize)) {
            // 电池摘要行（SOC / 续航 / 告警 来自分析域，不重复 SOC Hero）
            VStack(alignment: .leading, spacing: 8) {
                Text("电池状态").font(Theme.footnote.bold()))).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 12) {
                    ForEach(battSummary.headLines, id: \.id) { h in
                        VStack(spacing: 4) {
                            Text(h.label).font(Theme.footnote)).foregroundStyle(.secondary)
                            Text(h.value).font(Theme.h3)))
                                .foregroundStyle(h.cls == "ok" ? Theme.ok : (h.cls == "bad" ? Theme.bad : .primary))
                            if !h.reason.isEmpty {
                                Text(h.reason).font(Theme.micro)).foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                    }
                }
            }
            .padding(Theme.Spacing.xl)
            .dynamicTypeCompress()
            .glassCard(corner: 20)
            .glassLongPressDeform()

            // 分析结论详情
            for line in battSummary.headLines {
                HStack(spacing: 6) {
                    Text(line.label).font(Theme.caption)).foregroundStyle(.secondary)
                    Text(line.value).font(Theme.caption.bold()))).foregroundStyle(line.cls == "ok" ? Theme.ok : (line.cls == "bad" ? Theme.bad : .primary))
                    if !line.reason.isEmpty {
                        Text(line.reason).font(Theme.footnote)).foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            }

            // 电池一致性（可展开）
            ExpandingCardBox(title: "一致性", side: batt.cellStats.map { "\($0.count) 节采样" } ?? "接口未上报", sideCls: "ok", cornerRadius: 20) {
                if let cells = batt.cellStats {
                    let maxV = cells.max { a, b -> Bool in (a.maxV ?? 0) < (b.maxV ?? 0) }?.maxV ?? 0
                    let minV = cells.min { a, b -> Bool in (a.minV ?? 999) > (b.minV ?? 999) }?.minV ?? 999
                    let diff = maxV - minV
                    HStack(spacing: 8) {
                        ForEach(cells.enumerated(), id: \.offset) { _, s in
                            VStack(spacing: 2) {
                                Text(s.num == "--" ? "子" : "S\(s.num!)")
                                    .font(Theme.micro)).foregroundStyle(.secondary)
                                Text(s.maxV.map { String(format: "%.3f", $0) } ?? "--")
                                    .font(Theme.footnote.bold()), design: .monospaced))
                                    .foregroundStyle(.primary)
                            }
                            .frame(width: 52)
                        }
                    }
                    HStack(spacing: 8) {
                        Text("压差 \(String(format: "%.3f", diff))V")
                            .font(Theme.caption)).foregroundStyle(.secondary)
                        Spacer()
                        Text("最低 \(String(format: "%.3f", minV))V / 最高 \(String(format: "%.3f", maxV))V")
                            .font(Theme.caption)).foregroundStyle(.secondary)
                    }
                } else {
                    Text("接口未上报单体电压").font(Theme.caption)).foregroundStyle(.secondary)
                }
            }

            // 充电（可展开）
            ExpandingCardBox(title: "充电", side: batt.charging.text, sideCls: batt.charging.cls.isEmpty ? "na" : batt.charging.cls, cornerRadius: 20) {
                let rows: [(String, String)] = [
                    ("开始", batt.charging.start),
                    ("结束", batt.charging.end),
                    ("时长", batt.charging.durMin),
                    ("功率", batt.charging.power),
                    ("状态", batt.charging.text)
                ]
                ForEach(Array(rows.enumerated()), id: \.offset) { idx, r in
                    KVRow(k: r.0, v: r.1)
                    if idx < rows.count - 1 { ListDivider() }
                }
            }
        }
    }

    // MARK: 胎压四宫格
    private func tyreCard(_ tyre: TyreModel) -> some View {
        CardBox(title: "胎压", side: tyre.alarmText, sideCls: tyre.alarmCls) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()),
                                GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(tyre.items) { item in
                    TyreCell(label: item.label, kpa: item.kpa, temp: item.temp,
                             cls: item.cls, minSafePressure: 200,
                             watchValue: tyreWatchValue)
                }
            }
            Text("温度 \(tyre.tempRange)")
                .font(Theme.footnote)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    // MARK: 胎压展开卡（弹簧高度动画 + 玻璃压缩形变）
    private func tyreCardExpanded(_ tyre: TyreModel) -> some View {
        let chevronAngle: Angle = expandedTyre ? .degrees(90) : .degrees(0)
        return Button {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.65, blendDuration: 0.35)) {
                expandedTyre.toggle()
            }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                tyreCard(tyre)
                if expandedTyre {
                    Divider().padding(.horizontal, Theme.Spacing.xl)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("胎压详情")
                            .font(Theme.caption.bold())).foregroundStyle(.secondary)
                        ForEach(Array(tyre.items.enumerated()), id: \.element.id) { idx, item in
                            HStack {
                                Text(item.label).font(Theme.footnote)).foregroundStyle(.primary)
                                Spacer()
                                HStack(spacing: 12) {
                                    Label(item.kpa + " kPa", systemImage: "tire")
                                        .font(Theme.caption)
                                        .foregroundStyle(item.cls == "bad" ? .red : .primary)
                                    Label(item.temp + " °C", systemImage: "thermometer")
                                        .font(Theme.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            // 行级交错滑入
                            .offset(y: idx > 0 ? (expandedTyre ? 0 : 8) : 0)
                            .opacity(idx > 0 ? (expandedTyre ? 1 : 0) : 1)
                            .scaleEffect(idx > 0 ? (expandedTyre ? 1.0 : 0.96) : 1.0)
                            .animation(.spring(response: 0.45, dampingFraction: 0.65, blendDuration: 0.25).delay(Double(idx) * 0.05), value: expandedTyre)
                            if item != tyre.items.last { ListDivider().padding(.leading, 4) }
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.xl)
                    .padding(.bottom, Theme.Spacing.lg)
                }
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(expandedTyre ? 0.98 : 1.0)
        .animation(.spring(response: 0.5, dampingFraction: 0.65, blendDuration: 0.4), value: expandedTyre)
        .liquidGlassRipple(cornerRadius: 20)
        .accessibilityLabel(Text("胎压详情"))
        .accessibilityHint(Text(expandedTyre ? "点击收起胎压详情" : "点击展开四个轮胎的胎压和温度详情"))
        .overlay(alignment: .trailing) {
            Image(systemName: "chevron.right")
                .font(Theme.footnote.bold())
                .foregroundStyle(.tertiary)
                .rotationEffect(chevronAngle)
                .animation(.spring(response: 0.35, dampingFraction: 0.6), value: expandedTyre)
                .padding(.trailing, 14)
        }
    }

    // MARK: 座舱（可展开，含空调/净化器/PM2.5 详情）
    private func comfortCard(_ comfort: ComfortModel) -> some View {
        ExpandingCardBox(title: "座舱", side: comfort.acText.isEmpty ? "--" : (comfort.acCls == "ok" ? "空调运行中" : "空调关闭"),
                sideCls: comfort.acCls == "ok" ? "ok" : "na", cornerRadius: 20) {
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    StatTile(icon: "thermometer.medium", label: "车内温度", value: comfort.cabinTemp == "--" ? "--" : String(comfort.cabinTemp.dropLast()), unit: "℃", tint: .orange)
                    StatTile(icon: "wind", label: "车内 PM2.5", value: comfort.pmIn, unit: "", tint: .teal)
                }
                HStack(spacing: 10) {
                    StatTile(icon: "air.purifier", label: "净化器", value: comfort.purifier, tint: .purple)
                    StatTile(icon: "cloud.sun", label: "车外温度", value: comfort.envTemp == "--" ? "--" : String(comfort.envTemp.dropLast()), unit: "℃", tint: Theme.brand)
                }
                Text(comfort.acText)
                    .font(Theme.caption)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: 位置（可展开，含地图 + 导航按钮）
    private func locationCard(_ loc: LocModel) -> some View {
        ExpandingCardBox(title: "位置", side: loc.deg != "--" ? loc.dir : nil, cornerRadius: 20) {
            VStack(alignment: .leading, spacing: 10) {
                if showMap {
                    LocationMapViewPlaceholder(addr: loc.addr, lat: loc.lat, lng: loc.lng)
                        .frame(height: 190)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .transition(.opacity)
                }
                Text(loc.addr.isEmpty ? "暂无定位数据" : loc.addr)
                    .font(Theme.caption)))
                    .lineLimit(1)
                Text(loc.satAlt).font(Theme.footnote)).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    mapToggleButton
                    if loc.lat != "--" && loc.lng != "--" { navButton(loc) }
                    Spacer()
                    Pill(text: loc.gpsText, cls: loc.gpsCls)
                }
            }
        }
    }

    private var mapToggleButton: some View {
        Button { withAnimation(.spring(Theme.Duration.springFast)) { showMap.toggle() } }
        label: {
            HStack(spacing: 4) {
                Image(systemName: showMap ? "map.fill" : "map")
                Text(showMap ? "隐藏地图" : "显示地图")
                    .font(Theme.caption)))
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(.thin, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func navButton(_ loc: LocModel) -> some View {
        Button { openNav(loc) }
        label: {
            Image(systemName: "arrow.up.right")
                .font(Theme.caption))
                .foregroundStyle(.accentColor)
                .padding(8)
                .background(.thin, in: Circle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Footer
    private var footerNote: some View {
        let update = lastFetch.map { DateFormatter.relative($0) } ?? "刚刚"
        return HStack(spacing: 8) {
            Image(systemName: "clock.badge.checkmark")
                .font(Theme.footnote)).foregroundStyle(.tertiary)
            Text("更新于 \(update)")
                .font(Theme.caption)).foregroundStyle(.secondary)
            Spacer()
            // #3 数据新鲜度徽章
            DataFreshnessBadge(timestamp: lastFetch)
            Button { fetchCore() } label: {
                Image(systemName: "arrow.clockwise.circle.fill")
                    .font(Theme.caption))
                    .foregroundStyle(.accentColor)
                    .padding(6)
                    .background(.thin, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .adaptivePagePadding(dynamicTypeSize)
        .padding(.vertical, 8)
    }

    // #3 数据新鲜度徽章 — 返回缓存时间戳
    private func freshnessTimestamp(for key: String) -> Date? {
        lastFetch
    }

    // #36 多语言国际化
    private var localizedGreeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let lang = Locale.current.languageCode ?? "zh"
        switch lang {
        case "en":
            return hour < 6 ? "🌙 Good Night" : hour < 12 ? "☀️ Good Morning" : hour < 18 ? "☀️ Good Afternoon" : "🌙 Good Evening"
        default:
            return hour < 6 ? "🌙 深夜了" : hour < 12 ? "☀️ 上午好" : hour < 18 ? "☀️ 下午好" : "🌙 晚上好"
        }
    }

    // #19 车况快照分享
    private func shareStatus() {
        let e = VM.energy(store.caches, store.car)
        let tyre = VM.tyreStatus(store.caches)
        let comfort = VM.comfortStatus(store.caches)
        let summary = AN.summarize(store.caches, store.car)
        let scoreText = summary.overall.title
        let tireStatus = tyre.warnAny ? "⚠ 有异常" : "✓ 正常"
        let cabinTemp = comfort.cabinTemp == "--" ? "--" : comfort.cabinTemp + "℃"
        let info = ShareableStatusInfo(
            soc: "\(e.socPct)%",
            range: e.range,
            tireStatus: tireStatus,
            healthScore: scoreText,
            cabinTemp: cabinTemp
        )
        let text = generateShareableStatus(info: info)
        let vc = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            let rc = UIUserInterfaceStyle(rawValue: UserDefaults.standard.integer(forKey: "ui_interface_style")) ?? .unspecified
            vc.preferredContentSize = CGSize(width: 375, height: 200)
            let rootVC = windowScene.windows.first?.rootViewController
            rootVC?.present(vc, animated: true)
        }
    }

    private func openNav(_ loc: LocModel) {
        guard loc.lat != "--", loc.lng != "--" else { return }
        let url = "http://uri.amap.com/navigation?to=\(loc.lng),\(loc.lat)&mode=car"
        if let u = URL(string: url) {
            UIApplication.shared.open(u, options: [:], completionHandler: nil)
        }
    }

    // MARK: SOC入场动画
    private func startSocAnimation() {
        withAnimation(.spring(Theme.Duration.springNormal)) { socCardOpacity = 1 }
        let target = max(0, min(100, VM.energy(store.caches, store.car).socPct))
        // 数字滚动：从 0 弹性计数到目标值（与圆环动画同步）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.spring(response: 0.65, dampingFraction: 0.65, blendDuration: 0.9)) {
                socProgress = CGFloat(target)
                socCount = target
                pulseTrigger = String(target)
            }
        }
    }

    // MARK: 里程入场动画
    private func startMileAnimation() {
        let drive = VM.driveStatus(store.caches)
        let target = Int(drive.mile) ?? 0
        // 延迟 0.2s 后开始计数，与 SOC 错开避免冲突
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.spring(response: 0.65, dampingFraction: 0.65, blendDuration: 0.9)) {
                mileCount = target
                pulseTrigger = String(target)
            }
        }
    }

    // MARK: 轮询
    private func startPolling() {
        startTimer?.cancel()
        startTimer = Task {
            while !Task.isCancelled {
                await fetchCore()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    private func fetchCore() async {
        let startTime = Date()
        await withTaskGroup(of: Void.self) { g in
            g.addTask { await store.fetchCore() }
        }
        lastFetch = Date()
        // #22 页面加载耗时埋点（写入 UserDefaults，DevView 可读取）
        let elapsed = Date().timeIntervalSince(startTime)
        UserDefaults.standard.set(elapsed, forKey: "carkeeper_home_load_time")
        if isRefreshing {
            // 下拉刷新：重置并重播 SOC + 里程入场动画
            isRefreshing = false
            withAnimation(.spring(Theme.Duration.springFast)) { socCardOpacity = 0; socProgress = 0; socCount = 0; mileCount = 0; pulseTrigger = ""; tyreWatchValue = "" }
            startSocAnimation()
            startMileAnimation()
            tyreWatchValue = UUID().uuidString
        }
    }
}

// MARK: - 辅助
extension DateFormatter {
    static func relative(_ date: Date) -> String {
        let now = Date()
        let diff = Int(now.timeIntervalSince(date))
        if diff < 60 { return "刚刚" }
        if diff < 3600 { return "\(diff / 60) 分钟前" }
        if diff < 86400 { return "\(diff / 3600) 小时前" }
        return "\(diff / 86400) 天前"
    }
}

// MARK: - 位置地图占位（iOS 27 液态玻璃风格）
struct LocationMapViewPlaceholder: View {
    let addr: String
    let lat: String
    let lng: String
    var body: some View {
        ZStack {
            LinearGradient(colors: [.blue.opacity(0.12), .teal.opacity(0.06)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .opacity(0.9)
            VStack(spacing: 6) {
                Image(systemName: "map.fill")
                    .font(Theme.d0b))
                    .foregroundStyle(.accentColor.opacity(0.6))
                Text(addr.isEmpty ? "点击导航查看位置" : addr)
                    .font(Theme.caption))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if lat != "--" && lng != "--" {
                    Text("\(lat) · \(lng)")
                        .font(Theme.micro))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}

struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            HomeView()
        }
    }
}
