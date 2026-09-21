import SwiftUI
import Charts

// 电池与充电 —— iOS 27 Liquid Glass：
// SOC 渐变光环 + 一致性图表 + 充电会话 + 子系统 + 电机 + 故障码 + 告警。

struct BatteryView: View {
    private let store = AppStore.shared
    @State private var loaded = false
    @State private var errText: String = ""
    @State private var loadTask: Task<Void, Never>? = nil
    @State private var socProgress: CGFloat = 0      // SOC 环进度 0→socPct
    @State private var socCount: Int = 0             // SOC 数字计数
    @State private var rangeCount: Int = 0           // 续航数字计数
    @State private var isRefreshing = false          // 下拉刷新进行中
    @State private var showDestinationCalc = false
    @State private var destinationDistance: String = ""
    @State private var canReach: Bool?
    // 趋势周期。旧的「实时/本周/本月」是假的：它读的是 energyHistory —— 一个 20 条 /
    // 60 秒的实时缓冲，选"本周"永远只有最近一分钟的数据，图是空的一条线。
    enum TrendPeriod: String, CaseIterable, Identifiable {
        case day = "24 小时"
        case week = "7 天"
        case month = "30 天"
        var id: String { rawValue }
        var hours: Double {
            switch self {
            case .day: return 24
            case .week: return 24 * 7
            case .month: return 24 * 30
            }
        }
    }
    @State private var trendPeriod: TrendPeriod = .day
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollView {
            VStack(spacing: TokensSpacing.lg) {
                sections
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(TokensPalette.background)
        .navigationTitle("充电")
        .navigationBarTitleDisplayMode(.large)
            .accessibilityLabel(Text("充电"))
            .accessibilityHint(Text("电池状态、充电历史与诊断报告"))
        .onAppear { loadIfNeeded(); startSocAnimation() }
        .onDisappear { loadTask?.cancel(); loadTask = nil }
        .refreshable { isRefreshing = true; await load(); isRefreshing = false }
        .toolbar {
            // #20 目的地续航计算器入口
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showDestinationCalc = true
                } label: {
                    Image(systemName: "map.pin")
                }
                .accessibilityLabel(Text("目的地续航计算"))
            }
        }
        .sheet(isPresented: $showDestinationCalc) {
            DestinationCalculatorView(distance: $destinationDistance, canReach: $canReach)
        }
        .onChange(of: store.carId) { _, newId in
            guard !newId.isEmpty else { return }
            // 切车后重新拉一次数据
            Task { await load() }
        }
        .overlay(alignment: .center) {
            if !loaded && errText.isEmpty {
                PageLoadingView("正在同步电池数据…")
            } else if !errText.isEmpty {
                PageErrorView(errText) { Task { await load() } }
            }
        }
    }

    // MARK: 卡片列表（独立 ViewBuilder，避免整个 body 类型检查超时）
    @ViewBuilder
    private var sections: some View {
        let cache = store.caches
        let b = batteryModel(cache)
        let e = VM.energy(cache, store.car)
        socHero(e)
        verdictCard(cache, b)
        consistencyCard(b)
        chargeCard(b)
        // 趋势（SOC 历史 / 充电功率）—— 真实车端采样，见 Services/HistoryStore.swift
        trendSection
        subsystemCard(b)
        motorCard(b)
        faultCard(b)
        alarmCard(b)
    }

    // MARK: 电池头部（v4：一个巨大数字 + 一条光条 + 三条事实，不装容器）
    private func socHero(_ e: EnergyModel) -> some View {
        let tint = socTint(e.socPct)
        let socText = e.soc == "--" ? "--" : "\(socCount)"
        let fraction = max(0, min(1, Double(e.socPct) / 100.0))
        let rangeText = e.range == "--" ? "--" : (rangeCount > 0 ? String(rangeCount) : e.range)

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: TokensSpacing.sm) {
                Text(e.chargeText)
                    .font(TokensTypo.footnote)
                    .foregroundStyle(e.chargeCls == "ok" || e.chargeCls == "charge"
                                     ? TokensPalette.info : TokensPalette.secondary)
                Spacer(minLength: TokensSpacing.sm)
                if !e.socWarn.isEmpty {
                    Text(e.socWarn)
                        .font(TokensTypo.footnote)
                        .foregroundStyle(TokensPalette.statusColor(e.socCls))
                }
            }

            DSBigNumber(value: socText, unit: "%", caption: "电池电量", size: 116, tint: tint)
                .padding(.top, TokensSpacing.md)

            DSLightBar(
                progress: fraction,
                tint: LinearGradient(colors: [Color.white, tint.opacity(0.75), tint],
                                     startPoint: .leading, endPoint: .trailing)
            )
            .padding(.top, TokensSpacing.xl)

            HStack(alignment: .firstTextBaseline, spacing: TokensSpacing.sm) {
                Text("续航 \(rangeText) km")
                    .font(TokensTypo.footnote)
                    .foregroundStyle(TokensPalette.secondary)
                Spacer(minLength: TokensSpacing.sm)
                if let ttf = e.timeToFull, ttf != "--" {
                    Text("预计充满 \(ttf)")
                        .font(TokensTypo.footnote)
                        .foregroundStyle(TokensPalette.secondary)
                } else if let tte = e.timeToEmpty, tte != "--" {
                    Text("可行驶 \(tte)")
                        .font(TokensTypo.footnote)
                        .foregroundStyle(TokensPalette.secondary)
                }
            }
            .padding(.top, TokensSpacing.md)

            DSStatStrip(items: [
                .init("电池温度", e.battTemp),
                .init("电压 / 电流", e.voltAmp),
                .init(e.online.text, e.updated == "--" ? "--" : String(e.updated.suffix(5)))
            ])
            .padding(.top, TokensSpacing.xl)
            .overlay(alignment: .top) { DSDivider() }
            .overlay(alignment: .bottom) { DSDivider() }
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: SOC 语义色（不用渐变，颜色只表达健康度）
    private func socTint(_ pct: Int) -> Color {
        switch pct {
        case ..<20: return TokensPalette.error
        case ..<40: return TokensPalette.warning
        default: return TokensPalette.success
        }
    }

    // MARK: 分析结论
    private func verdictCard(_ cache: [String: Any?], _ b: BatteryModel) -> some View {
        Group {
            if let batt = AN.summarize(cache, store.car).domains.first(where: { $0.key == "battery" }) {
                ExpandingCardBox(title: "分析结论", side: batt.title,
                                 sideCls: batt.cls, cornerRadius: TokensRadius.medium) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(batt.reasons.enumerated()), id: \.offset) { _, r in
                            HStack(alignment: .top, spacing: 8) {
                                StatusDot(cls: r.cls)
                                Text(r.t).font(TokensTypo.caption).foregroundStyle(TokensPalette.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: 一致性
    private func consistencyCard(_ b: BatteryModel) -> some View {
        let cellLabel = b.cellStats.map { cell in "\(cell.count) 节采样" } ?? "接口未上报"
        return ExpandingCardBox(title: "一致性", side: cellLabel, sideCls: "ok",
                         cornerRadius: TokensRadius.medium) {
            VStack(spacing: 12) {
                if let cell = b.cellStats {
                    VStack(spacing: 6) {
                        sectionLabel("单体电压 (V)")
                        Chart(Array(cell.bars.enumerated()), id: \.offset) { (_ idx, v) in
                            BarMark(x: .value("序号", idx), y: .value("V", v))
                                .foregroundStyle(TokensPalette.success.opacity(0.7))
                                .cornerRadius(1.5)
                        }
                        .chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) }
                        .frame(height: 96)
                        HStack(spacing: 8) {
                            miniStat("最高", String(format: "%.3f", cell.max), "V")
                            miniStat("最低", String(format: "%.3f", cell.min), "V")
                            if let dv = b.diffV {
                                miniStat("压差", String(format: "%.3f", dv), "V",
                                         warn: dv >= 0.05)
                            }
                        }
                    }
                }
                if let probe = b.probeStats {
                    VStack(spacing: 6) {
                        sectionLabel("温度探针 (℃)")
                        Chart(Array(probe.bars.enumerated()), id: \.offset) { (_ idx, v) in
                            BarMark(x: .value("序号", idx), y: .value("℃", v))
                                .foregroundStyle(TokensPalette.ambient.opacity(0.55))
                                .cornerRadius(1.5)
                        }
                        .chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) }
                        .frame(height: 80)
                        HStack(spacing: 8) {
                            miniStat("最高", String(format: "%.1f", probe.max), "℃")
                            miniStat("最低", String(format: "%.1f", probe.min), "℃")
                            if let dt = b.diffT {
                                miniStat("温差", String(format: "%.1f", dt), "℃", warn: dt >= 5)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: 能耗历史折线图 (#13)
    private func chargeCard(_ b: BatteryModel) -> some View {
        let chargeSide = b.charging.cls.isEmpty ? "na" : b.charging.cls
        // 显式 return：本函数不是 @ViewBuilder，多语句体必须 return，
        // 否则是「opaque return type 无 return」错误（此前被开头一句多余的
        // `return EmptyView()` 掩盖，那句同时让整张充电卡片渲染成空视图）。
        return ExpandingCardBox(title: "充电", side: b.charging.text, sideCls: chargeSide,
                                cornerRadius: TokensRadius.medium) {
            VStack(spacing: 0) {
                let rows = chargeRows(b)
                ForEach(Array(rows.enumerated()), id: \.offset) { (_ idx, r) in
                    KVRow(k: r.k, v: r.v)
                        .padding(.vertical, 8)
                    if idx < rows.count - 1 { ListDivider() }
                }
            }
        }
    }

    // MARK: 子系统
    private func subsystemCard(_ b: BatteryModel) -> some View {
        Group {
            if !b.subsystems.isEmpty || !b.tempSubs.isEmpty {
                CardBox(title: "子系统") {
                    VStack(alignment: .leading, spacing: 10) {
                        if !b.subsystems.isEmpty {
                            sectionLabel("电压采样")
                            ForEach(b.subsystems, id: \.num) { s in
                                KVRow(k: s.num == "--" ? "子系统" : "子系统 \(s.num)",
                                      v: [s.count != "--" ? "\(s.count) 串" : "",
                                          s.volt != "--" ? "\(s.volt) V" : "",
                                          s.amp != "--" ? "\(s.amp) A" : "",
                                          s.vMin != "--" && s.vMax != "--" ? "\(s.vMin)~\(s.vMax) V" : ""
                                      ].filter { !$0.isEmpty }.joined(separator: " · "))
                            }
                        }
                        if !b.tempSubs.isEmpty {
                            sectionLabel("温度采样")
                            ForEach(b.tempSubs, id: \.num) { s in
                                KVRow(k: s.num == "--" ? "子系统" : "子系统 \(s.num)",
                                      v: [s.count != "--" ? "\(s.count) 探针" : "",
                                          s.tMin != "--" && s.tMax != "--" ? "\(s.tMin)~\(s.tMax) ℃" : ""
                                      ].filter { !$0.isEmpty }.joined(separator: " · "))
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: 动力电机
    private func motorCard(_ b: BatteryModel) -> some View {
        Group {
            if !b.motors.isEmpty {
                ExpandingCardBox(title: "动力系统", side: "\(b.motors.count) 台电机", cornerRadius: TokensRadius.medium) {
                    VStack(spacing: 12) {
                        ForEach(Array(b.motors.enumerated()), id: \.offset) { (_ idx, m) in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(m.num == "--" ? "驱动电机" : "驱动电机 #\(m.num)")
                                    .font(TokensTypo.caption.weight(.bold)).foregroundStyle(TokensPalette.secondary)
                                let rows = motorRows(m)
                                ForEach(Array(rows.enumerated()), id: \.offset) { (_ idx, r) in
                                    KVRow(k: r.k, v: r.v)
                                    if idx < rows.count - 1 { ListDivider().opacity(0.4) }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: 故障码
    private func faultCard(_ b: BatteryModel) -> some View {
        CardBox(title: "故障码",
                side: b.faultTotal > 0 ? "共 \(b.faultTotal) 条" : "无故障",
                sideCls: b.faultTotal > 0 ? "bad" : "ok") {
            if b.faults.filter({ $0.count > 0 }).isEmpty {
                Text("驱动电机 / 储能 / 发动机均无故障")
                    .font(TokensTypo.caption).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 10) {
                    ForEach(b.faults.filter { $0.count > 0 }) { f in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(f.name).font(Theme.font(.caption as Font).bold())
                                Spacer()
                                Text("\(f.count) 条").font(Theme.font(.caption as Font).bold())
                                    .foregroundStyle(TokensPalette.error)
                            }
                            if !f.codes.isEmpty {
                                Text(f.codes)
                                    .font(TokensTypo.dataSmall)
                                    .foregroundStyle(TokensPalette.secondary).lineLimit(3)
                            }
                        }
                        .padding(10)
                        .background(TokensPalette.fillSubtle, in: RoundedRectangle(cornerRadius: 12, style:
 .continuous))
                    }
                }
            }
        }
    }

    // MARK: 电池告警
    private func alarmCard(_ b: BatteryModel) -> some View {
        Group {
            if !b.alarms.isEmpty {
                CardBox(title: "电池告警", side: "共 \(b.alarms.count) 项", sideCls: "bad") {
                    VStack(spacing: 0) {
                        ForEach(Array(b.alarms.enumerated()), id: \.offset) { (_ idx, a) in
                            HStack {
                                StatusDot(cls: "bad")
                                Text(a).font(TokensTypo.caption)
                                Spacer()
                                Text("触发").font(Theme.font(.footnote as Font).bold())
                                    .foregroundStyle(TokensPalette.error)
                            }
                            .padding(.vertical, 6)
                            if idx < b.alarms.count - 1 { ListDivider() }
                        }
                    }
                }
            }
        }
    }

    // MARK: 辅助
    private func sectionLabel(_ t: String) -> some View {
        Text(t).font(Theme.font(.footnote as Font).bold()).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func miniStat(_ k: String, _ v: String, _ unit: String, warn: Bool = false) -> some View {
        HStack(spacing: 4) {
            Text(k).font(TokensTypo.footnote).foregroundStyle(.secondary)
            Text(v).font(Theme.font(.caption as Font).bold()).monospacedDigit()
                .foregroundStyle(warn ? TokensPalette.error : .primary)
            Text(unit).font(TokensTypo.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(TokensPalette.fillSubtle, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private struct R { let k: String; let v: String; var cls: String = "" }

    private func chargeRows(_ b: BatteryModel) -> [R] {
        var rows: [R] = []
        let c = b.charging
            if c.text != "未充电" {
            if c.soc != "--" { rows.append(R(k: "当前电量", v: "\(c.soc)%")) }
            if c.range != "--" { rows.append(R(k: "剩余续航", v: "\(c.range) km")) }
            if c.power != "--" { rows.append(R(k: "充电功率", v: c.power)) }
            if c.durMin != "--" { rows.append(R(k: "已充时长", v: "\(c.durMin) 分钟")) }
            // #1 充电倒计时
            if let ttf = c.timeToFull { rows.append(R(k: "预计充满", v: ttf)) }
            if c.start != "--" { rows.append(R(k: "开始时间", v: c.start)) }
            if c.end != "--" { rows.append(R(k: "结束时间", v: c.end)) }
        }
        if c.powerLine != "--" { rows.append(R(k: "电源线路", v: c.powerLine)) }
        if c.heating != "--" { rows.append(R(k: "电池加热", v: c.heating)) }
        if c.reservation != "--" { rows.append(R(k: "预约充电", v: c.reservation)) }
        if c.reserveTime != "--" { rows.append(R(k: "预约用车", v: c.reserveTime)) }
        if rows.isEmpty { rows.append(R(k: "充电", v: "暂无充电会话数据")) }
        return rows
    }

    private func motorRows(_ m: MotorModel) -> [R] {
        var rows: [R] = []
        if m.state != "--" { rows.append(R(k: "状态", v: m.state)) }
        if m.rpm != "--" { rows.append(R(k: "转速", v: "\(m.rpm) rpm")) }
        if m.torque != "--" { rows.append(R(k: "扭矩", v: "\(m.torque) N·m")) }
        if m.temp != "--" { rows.append(R(k: "电机温度", v: "\(m.temp) ℃")) }
        if m.ctrlTemp != "--" { rows.append(R(k: "控制器温度", v: "\(m.ctrlTemp) ℃")) }
        if m.inputV != "--" { rows.append(R(k: "控制器输入电压", v: "\(m.inputV) V")) }
        if m.dcBus != "--" { rows.append(R(k: "母线电流", v: "\(m.dcBus) A")) }
        return rows
    }

    // MARK: 趋势（SOC 历史 + 充电功率）
    /// 数据全部来自 HistoryStore 的真实采样：服务端只有"当前状态"接口（小程序也一样），
    /// 所以曲线是 App 一点点攒出来的。攒不够时说清原因，不画灰块、不编数字。
    @ViewBuilder
    private var trendSection: some View {
        let socPoints = HistoryStore.shared.socSeries(hours: trendPeriod.hours)
            .map { DSTrendChart.Point(t: $0.t, v: $0.v) }
        let powerPoints = HistoryStore.shared.powerSeries(hours: trendPeriod.hours)
            .map { DSTrendChart.Point(t: $0.t, v: $0.v) }
        let e = VM.energy(store.caches, store.car)
        let socMinutes = Int(HistoryStore.socInterval / 60)
        let powerMinutes = Int(HistoryStore.powerInterval / 60)

        VStack(alignment: .leading, spacing: TokensSpacing.lg) {
            DSSectionHeader(title: "趋势", trailing: "采样自车端实时数据")

            Picker("周期", selection: $trendPeriod) {
                ForEach(TrendPeriod.allCases) { p in
                    Text(p.rawValue).tag(p)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            // ---- SOC 历史 ----
            VStack(alignment: .leading, spacing: TokensSpacing.sm) {
                HStack(alignment: .firstTextBaseline) {
                    Text("SOC 历史")
                        .font(TokensTypo.subheadline.weight(.semibold))
                        .foregroundStyle(TokensPalette.primary)
                    Spacer(minLength: TokensSpacing.sm)
                    Text("当前 \(e.socPct)%")
                        .font(TokensTypo.digits(13))
                        .foregroundStyle(TokensPalette.secondary)
                }
                if socPoints.count >= 2 {
                    DSTrendChart(points: socPoints,
                                 unit: "%",
                                 tint: socTint(e.socPct),
                                 yDomain: 0...100,
                                 valueText: { String(format: "%.0f", $0) })
                } else {
                    DSTrendEmpty(
                        icon: "chart.xyaxis.line",
                        title: "正在积累 SOC 数据",
                        message: "服务端没有历史接口，这条曲线由 App 每 \(socMinutes) " +
                                 "分钟采一次（电量变化 ≥ \(Int(HistoryStore.socJump))% 也会立刻留一个点）。"
                                 + "已记录 \(socPoints.count) 个点。"
                    )
                }
            }

            // ---- 充电功率 ----
            VStack(alignment: .leading, spacing: TokensSpacing.sm) {
                HStack(alignment: .firstTextBaseline) {
                    Text("充电功率")
                        .font(TokensTypo.subheadline.weight(.semibold))
                        .foregroundStyle(TokensPalette.primary)
                    Spacer(minLength: TokensSpacing.sm)
                    if let c = e.charging {
                        Text(c.power)
                            .font(TokensTypo.digits(13))
                            .foregroundStyle(TokensPalette.info)
                    }
                }
                if powerPoints.count >= 2 {
                    DSTrendChart(points: powerPoints,
                                 unit: "kW",
                                 tint: TokensPalette.info,
                                 height: 132,
                                 valueText: { String(format: "%.0f", $0) })
                } else {
                    DSTrendEmpty(
                        icon: "bolt",
                        title: "还没有充电曲线",
                        message: "只在充电中每 \(powerMinutes) 分钟记一个点，所以这条曲线要真正充过一次电才会长出来。已记录 \(powerPoints.count) 个点。"
                    )
                }
            }
        }
    }

    // MARK: SOC 环进度对齐（只做状态变化动画）
    private func startSocAnimation() {
        let e = VM.energy(store.caches, store.car)
        let target = max(0, min(100, e.socPct))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.spring(response: 0.65, dampingFraction: 0.65, blendDuration: 0.9)) {
                socProgress = CGFloat(target)
            }
        }
        // B2: 续航数字滚动计数
        let rangeTarget = Int(e.range) ?? 0
        if rangeTarget > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                withAnimation(.spring(response: 0.65, dampingFraction: 0.65, blendDuration: 0.9)) {
                    rangeCount = rangeTarget
                }
            }
        }
    }

    private func loadIfNeeded() {
        guard !store.carId.isEmpty else { return }
        guard loadTask == nil || loadTask!.isCancelled else { return }
        if store.needsRefresh("charge") || store.needsRefresh("control") {
            loadTask = Task { await load() }
        }
    }

    @MainActor
    private func load() async {
        guard !store.carId.isEmpty else { return }
        let api = APIClient.shared
        do {
            // ⚠️ 这里必须用 try（原来是 try?）：try? 会让 do 体不抛任何错误，
            // 于是两个 catch 都成为死代码 —— errText 永远为空、token 失效也不会自动登出。
            let charge = try await api.getCharge(carId: store.carId)
            store.saveCache(["charge": charge])
            let control = try await api.getControl(carId: store.carId)
            store.saveCache(["control": control])
            loaded = true
            errText = ""
            // 刷新后重新对齐 SOC / 续航读数
            socCount = 0
            rangeCount = 0
            startSocAnimation()
        } catch {
            errText = error.localizedDescription
            let errDesc = error.localizedDescription.lowercased()
            if errDesc.contains("未找到") || errDesc.contains("登录") || errDesc.contains("token") {
                // token 过期，跳回登录页
                AppStore.shared.logout()
            }
        }
    }
}

// MARK: - #20 目的地续航计算器
struct DestinationCalculatorView: View {
    @Binding var distance: String
    @Binding var canReach: Bool?
    @Environment(\.dismiss) private var dismiss
    private let store = AppStore.shared

    var body: some View {
        VStack(spacing: 20) {
            Text("目的地续航计算").font(TokensTypo.title3).foregroundStyle(.primary)
            Text("输入目的地距离，估算当前电量是否足够到达")
                .font(TokensTypo.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            TextField("目的地距离 (km)", text: $distance)
                .keyboardType(.decimalPad)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(TokensPalette.fillSubtle, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1))

            if let reach = canReach {
                HStack {
                    Image(systemName: reach ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(reach ? .green : .red)
                    Text(reach ? "电量足够到达" : "电量不足，建议充电")
                        .font(TokensTypo.body.weight(.semibold))
                        .foregroundStyle(reach ? .green : .red)
                }
                .padding()
                .background(reach ? .green.opacity(0.1) : .red.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            }

            Button("计算") {
                calculateReach()
            }
            .buttonStyle(.borderedProminent)
            .tint(TokensPalette.ambient)

            Button("取消") { dismiss() }
                .font(TokensTypo.body)
                .foregroundStyle(.secondary)
        }
        .padding(TokensSpacing.xxl)
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
    }

    private func calculateReach() {
        guard let dist = Double(distance), dist > 0 else { return }
        let e = VM.energy(store.caches, store.car)
        // 保守估算：续航 * 0.85（考虑空调、路况等损耗）
        let effectiveRange = e.socPct > 0 ? Int(Double(e.socPct) / 100.0 * Double(Int(e.range) ?? 0) * 0.85) : 0
        canReach = effectiveRange >= Int(dist)
    }
}

