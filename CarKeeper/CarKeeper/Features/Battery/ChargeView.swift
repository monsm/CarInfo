import SwiftUI
import Charts

// =============================================================================
//  充电 —— 从零重写的一页（旧 BatteryView 已删，不在它的基础上改）
// =============================================================================
//
//  旧页的问题不是排版，是**它同时是五个页面**：充电、电池健康、故障码、账本、
//  目的地续航计算器挤在同一张纸上，谁都没有说清「这一页是干什么的」。
//
//  这一页只装三件事，顺序就是看的顺序：
//    ① 充电 —— 此刻在不在充、功率多少、还要多久
//    ② 电池 —— 车端报的电池读数：一致性（单体电压 / 温度探针）、绝缘电阻、
//              电压采样子系统、动力电机、电池告警
//    ③ 趋势 —— SOC 与充电功率两条曲线（本机按 5 / 1 分钟采样，服务端不提供历史）
//
//  不在这里的东西与它们的去处：
//    · 故障码 → 体检（「这辆车有没有毛病」归健康报告）
//    · 分析结论（综合评分）→ 体检
//    · **充电账本（花了多少钱）→ 整条链路已删**（2026-09-23，用户要求）：
//      它算的是本机积分出的度数 × 手填电价，没有任何账单接口，
//      它带来的那条 PDF 导出、地图上的账块、搜索里的充电记录也一并去掉。
//
//  数据口径：所有读数都来自**刚刚那一次网络请求**（`store.caches`），
//  没有 TTL、不落盘、失败不保留旧值 —— 取不到就显示取不到。
// =============================================================================

struct ChargeView: View {
    private let store = AppStore.shared

    @State private var loading = true
    @State private var errText = ""
    @State private var loadTask: Task<Void, Never>? = nil
    @State private var trendPeriod: TrendPeriod = .day

    /// 趋势周期。读的是 HistoryStore 的真实采样（服务端只有「当前状态」接口），
    /// 所以「7 天 / 30 天」看到的是**攒下来的**点，不是它去查了历史。
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

    var body: some View {
        StackPageView(accent: HomeMode.charge.accent, label: "充电", cards: cards)
            .pageBackground()
            .dsPageTitle("充电")
        .accessibilityLabel(Text("充电"))
        .onAppear { loadIfNeeded() }
        .onDisappear { loadTask?.cancel(); loadTask = nil }
        .refreshable { await load() }
        .onChange(of: store.carId) { _, newId in
            guard !newId.isEmpty else { return }
            Task { await load() }
        }
        .overlay(alignment: .center) {
            if loading && errText.isEmpty {
                ProgressView().controlSize(.small)
            } else if !errText.isEmpty {
                DSPlaceholder(icon: "exclamationmark.triangle",
                              title: "充电数据读取失败",
                              message: errText,
                              actionTitle: "重新加载",
                              cls: "warn") { Task { await load() } }
            }
        }
    }

    // =====================================================================
    // MARK: - 叠叠乐：这一档的卡
    // =====================================================================
    //
    //  顺序就是读的顺序：**此刻 → 明细 → 电池 → 趋势 → 长途**。
    //  此前这五项是同一张纸里的五节 —— 换档时整屏一起闪；现在它们是五张卡，
    //  上下滑是一张一张过。
    //
    //  三态的责任在这里落：
    //    · 有数据 → 卡头右侧带读数
    //    · 无数据 → 卡片正文自己说一句真话（`GlassCardEmpty`），**不摆 `--`**
    //    · 过期   → 卡头右侧带时间（`at`）
    @MainActor
    private var cards: [StackCard] {
        let e = VM.energy(store.caches, store.car)
        let b = batteryModel(store.caches)
        // 「此刻 / 明细 / 电池 / 趋势」是**同一份读数**的四种读法，所以时间戳同源：
        // 四个不同时间只会让读者以为它们不是一回事。
        let chargeAt = store.cacheTime("charge")
        return HomeMode.charge.headCards + [
            StackCard(id: "state", title: "此刻",
                      value: e.chargeText, cls: e.chargeCls,
                      at: chargeAt,
                      content: AnyView(chargeHero(e))),
            StackCard(id: "detail", title: "明细",
                      at: chargeAt,
                      content: AnyView(chargeDetail(b))),
            // `at` 不是装饰：它回答「这个 68% 是什么时候的」。
            // 没拿到过就是 nil（那会走空态），所以这里不会摆一个假时间。
            StackCard(id: "battery", title: "电池",
                      value: "\(e.socPct)%", cls: "ok",
                      at: chargeAt,
                      content: AnyView(batterySection(b, e))),
            StackCard(id: "trend", title: "趋势",
                      at: chargeAt,
                      content: AnyView(trendSection(e))),
            StackCard(id: "plan", title: "长途",
                      content: AnyView(DestinationCalculatorSection()))
        ]
    }

    // MARK: - ① 充电（此刻的状态）

    private func chargeHero(_ e: EnergyModel) -> some View {
        let tint = socTint(e.socPct)
        let fraction = max(0, min(1, Double(e.socPct) / 100.0))
        let power = chargePowerText

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

            DSBigNumber(value: e.soc == "--" ? "--" : "\(e.socPct)", unit: "%",
                        caption: "电池电量", size: 116, tint: tint)
                .padding(.top, TokensSpacing.md)

            DSLightBar(
                progress: fraction,
                tint: LinearGradient(colors: [TokensPalette.lightSource, tint.opacity(0.75), tint],
                                     startPoint: .leading, endPoint: .trailing)
            )
            .padding(.top, TokensSpacing.xl)

            HStack(alignment: .firstTextBaseline, spacing: TokensSpacing.sm) {
                Text(e.range == "--" ? "续航 --" : "续航 \(e.range) km")
                    .font(TokensTypo.footnote)
                    .foregroundStyle(TokensPalette.secondary)
                Spacer(minLength: TokensSpacing.sm)
                // 充电中报「还要多久」，没充时报「还能跑多久」——两者不会同时出现。
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
                .init("充电功率", power),
                .init("电池温度", e.battTemp),
                .init("电压 / 电流", e.voltAmp)
            ])
            .padding(.top, TokensSpacing.xl)
            .overlay(alignment: .top) { DSDivider() }
            .overlay(alignment: .bottom) { DSDivider() }
        }
        .accessibilityElement(children: .contain)
    }

    /// 充电功率：唯一算法在 `VM.chargePowerKW`（`totalVoltage × totalCurrent`）。
    /// 报文里**没有** `ChargPower` / `ChargingPower` 这两个键 —— 旧代码在「预计充满」
    /// 那里读的就是它们，所以那个数字永远是空的。
    private var chargePowerText: String {
        guard let p = VM.chargePowerKW(ciVal(store.caches, "charge"), ciVal(store.caches, "control")),
              p > 0.1 else { return "--" }
        return String(format: "%.1f kW", p)
    }

    private func socTint(_ pct: Int) -> Color {
        switch pct {
        case ..<20: return TokensPalette.error
        case ..<40: return TokensPalette.warning
        default: return TokensPalette.success
        }
    }

    // MARK: - ①' 充电明细（车端报的充电字段）

    private func chargeDetail(_ b: BatteryModel) -> some View {
        let c = b.charging
        let cls = c.cls.isEmpty ? "na" : c.cls
        var rows: [Row] = []
        if c.power != "--" { rows.append(Row("充电功率", c.power)) }
        if c.durMin != "--" { rows.append(Row("已充时长", "\(c.durMin) 分钟")) }
        if c.start != "--" { rows.append(Row("开始", c.start)) }
        if c.end != "--" { rows.append(Row("结束", c.end)) }
        if c.powerLine != "--" { rows.append(Row("电源线路", c.powerLine)) }
        if c.heating != "--" { rows.append(Row("电池加热", c.heating)) }
        if c.reservation != "--" { rows.append(Row("预约充电", c.reservation)) }
        if c.reserveTime != "--" { rows.append(Row("预约用车", c.reserveTime)) }

        return DSSection(title: "充电", trailing: c.text, trailingCls: cls) {
            if rows.isEmpty {
                DSGroupRow(showsSeparator: false) {
                    Text("充电状态未上报")
                        .font(TokensTypo.footnote)
                        .foregroundStyle(TokensPalette.secondary)
                }
            } else {
                ForEach(Array(rows.enumerated()), id: \.offset) { idx, r in
                    DSGroupRow(showsSeparator: idx < rows.count - 1) {
                        DSKeyValueRow(key: r.k, value: r.v)
                    }
                }
            }
        }
    }

    private struct Row { let k: String; let v: String
        init(_ k: String, _ v: String) { self.k = k; self.v = v }
    }

    // MARK: - ② 电池（车端读数）

    @ViewBuilder
    private func batterySection(_ b: BatteryModel, _ e: EnergyModel) -> some View {
        verdict()
        consistency(b)
        insulation(e)
        voltageSampling(b)
        motors(b)
        alarms(b)
    }

    /// 电池域的结论：只取 `AN.summarize` 里电池那一域的理由。
    /// （其余五域的结论归体检报告，避免同一句话在两页各说一遍。）
    @ViewBuilder
    private func verdict() -> some View {
        if let batt = AN.summarize(store.caches, store.car).domains.first(where: { $0.key == "battery" }),
           !batt.reasons.isEmpty {
            DSSection(title: "电池结论", trailing: batt.title, trailingCls: batt.cls) {
                ForEach(Array(batt.reasons.enumerated()), id: \.offset) { idx, r in
                    DSGroupRow(showsSeparator: idx < batt.reasons.count - 1) {
                        HStack(alignment: .top, spacing: TokensSpacing.sm) {
                            StatusDot(cls: r.cls)
                            Text(r.t)
                                .font(TokensTypo.footnote)
                                .foregroundStyle(TokensPalette.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    /// 一致性：单体电压与温度探针的逐点柱图 + 三个统计。
    /// 没有采样数组时只写「接口未上报」，不画空图。
    @ViewBuilder
    private func consistency(_ b: BatteryModel) -> some View {
        let cellLabel = b.cellStats.map { "\($0.count) 节采样" } ?? "未上报"
        DSSection(title: "一致性", trailing: cellLabel,
                  trailingCls: b.cellStats == nil ? "na" : "ok") {
            if let cell = b.cellStats {
                DSGroupRow(showsSeparator: b.probeStats != nil) {
                    VStack(spacing: TokensSpacing.sm) {
                        DSSectionHeader(title: "单体电压 (V)")
                        Chart(Array(cell.bars.enumerated()), id: \.offset) { (idx, v) in
                            BarMark(x: .value("序号", idx), y: .value("V", v))
                                .foregroundStyle(TokensPalette.success.opacity(0.7))
                                .cornerRadius(1.5)
                        }
                        .chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) }
                        .frame(height: 96)
                        HStack(spacing: TokensSpacing.sm) {
                            miniStat(cellNumLabel("最高", b.cellMaxNum), String(format: "%.3f", cell.max), "V")
                            miniStat(cellNumLabel("最低", b.cellMinNum), String(format: "%.3f", cell.min), "V")
                            if let dv = b.diffV {
                                miniStat("压差", String(format: "%.3f", dv), "V", warn: dv >= 0.05)
                            }
                        }
                    }
                    .padding(.vertical, TokensSpacing.sm)
                }
            }
            if let probe = b.probeStats {
                DSGroupRow(showsSeparator: false) {
                    VStack(spacing: TokensSpacing.sm) {
                        DSSectionHeader(title: "温度探针 (℃)")
                        Chart(Array(probe.bars.enumerated()), id: \.offset) { (idx, v) in
                            BarMark(x: .value("序号", idx), y: .value("℃", v))
                                .foregroundStyle(TokensPalette.ambient.opacity(0.55))
                                .cornerRadius(1.5)
                        }
                        .chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) }
                        .frame(height: 80)
                        HStack(spacing: TokensSpacing.sm) {
                            miniStat("最高", String(format: "%.1f", probe.max), "℃")
                            miniStat("最低", String(format: "%.1f", probe.min), "℃")
                            if let dt = b.diffT {
                                miniStat("温差", String(format: "%.1f", dt), "℃", warn: dt >= 5)
                            }
                        }
                    }
                    .padding(.vertical, TokensSpacing.sm)
                }
            }
        }
    }

    /// 有节号就写成「最低·第56节」，没有就只写「最低」—— 不拿序号猜。
    private func cellNumLabel(_ base: String, _ num: String?) -> String {
        guard let num, !num.isEmpty, num != "0", num != "--" else { return base }
        return "\(base)·第\(num)节"
    }

    private func insulation(_ e: EnergyModel) -> some View {
        DSSection(title: "高压安全",
                  footer: "越限时车端会置位绝缘告警，出现在下面的「电池告警」里。") {
            DSGroupRow(showsSeparator: false) {
                DSKeyValueRow(key: "绝缘电阻", value: e.insulate,
                              valueCls: e.insulate == "--" ? "na" : "ok")
            }
        }
    }

    @ViewBuilder
    private func voltageSampling(_ b: BatteryModel) -> some View {
        if !b.subsystems.isEmpty || !b.tempSubs.isEmpty {
            VStack(spacing: TokensSpacing.xl) {
                if !b.subsystems.isEmpty {
                    DSSection(title: "电压采样") {
                        ForEach(Array(b.subsystems.enumerated()), id: \.element.num) { idx, s in
                            DSGroupRow(showsSeparator: idx < b.subsystems.count - 1) {
                                DSKeyValueRow(key: s.num == "--" ? "子系统" : "子系统 \(s.num)",
                                              value: joined([
                                                  s.count != "--" ? "\(s.count) 串" : "",
                                                  s.volt != "--" ? "\(s.volt) V" : "",
                                                  s.amp != "--" ? "\(s.amp) A" : "",
                                                  s.vMin != "--" && s.vMax != "--" ? "\(s.vMin)~\(s.vMax) V" : ""
                                              ]))
                            }
                        }
                    }
                }
                if !b.tempSubs.isEmpty {
                    DSSection(title: "温度采样") {
                        ForEach(Array(b.tempSubs.enumerated()), id: \.element.num) { idx, t in
                            DSGroupRow(showsSeparator: idx < b.tempSubs.count - 1) {
                                DSKeyValueRow(key: t.num == "--" ? "子系统" : "子系统 \(t.num)",
                                              value: joined([
                                                  t.count != "--" ? "\(t.count) 路" : "",
                                                  t.tMin != "--" && t.tMax != "--" ? "\(t.tMin)~\(t.tMax) ℃" : ""
                                              ]))
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func motors(_ b: BatteryModel) -> some View {
        if !b.motors.isEmpty {
            DSSection(title: "动力电机") {
                ForEach(Array(b.motors.enumerated()), id: \.element.num) { idx, m in
                    DSGroupRow(showsSeparator: idx < b.motors.count - 1) {
                        DSKeyValueRow(key: m.num == "--" ? "电机" : "电机 \(m.num)",
                                      value: joined([
                                          m.state != "--" ? m.state : "",
                                          m.rpm != "--" ? "\(m.rpm) rpm" : "",
                                          m.torque != "--" ? "\(m.torque) N·m" : "",
                                          m.temp != "--" ? "\(m.temp) ℃" : "",
                                          m.inputV != "--" ? "\(m.inputV) V" : "",
                                          m.dcBus != "--" ? "\(m.dcBus) A" : ""
                                      ]))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func alarms(_ b: BatteryModel) -> some View {
        if !b.alarms.isEmpty {
            DSSection(title: "电池告警", trailing: "共 \(b.alarms.count) 项", trailingCls: "bad") {
                ForEach(Array(b.alarms.enumerated()), id: \.offset) { idx, a in
                    DSGroupRow(showsSeparator: idx < b.alarms.count - 1) {
                        HStack(spacing: TokensSpacing.sm) {
                            StatusDot(cls: "bad")
                            Text(a)
                                .font(TokensTypo.footnote)
                                .foregroundStyle(TokensPalette.primary)
                            Spacer(minLength: TokensSpacing.sm)
                            Text("触发")
                                .font(TokensTypo.footnote.weight(.bold))
                                .foregroundStyle(TokensPalette.error)
                        }
                    }
                }
            }
        }
    }

    /// 把「串数 · 电压 · 电流」里真正有值的部分接成一句（空项丢掉，不留多余分隔点）。
    private func joined(_ parts: [String]) -> String {
        parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func miniStat(_ k: String, _ v: String, _ unit: String, warn: Bool = false) -> some View {
        HStack(spacing: 4) {
            Text(k).font(TokensTypo.footnote).foregroundStyle(TokensPalette.secondary)
            Text(v).font(TokensTypo.caption.weight(.bold)).monospacedDigit()
                .foregroundStyle(warn ? TokensPalette.error : TokensPalette.primary)
            Text(unit).font(TokensTypo.caption2).foregroundStyle(TokensPalette.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(TokensPalette.fillSubtle, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - ③ 趋势（本机采样攒出来的两条曲线）

    @ViewBuilder
    private func trendSection(_ e: EnergyModel) -> some View {
        let socPoints = HistoryStore.shared.socSeries(hours: trendPeriod.hours)
            .map { DSTrendChart.Point(t: $0.t, v: $0.v) }
        let powerPoints = HistoryStore.shared.powerSeries(hours: trendPeriod.hours)
            .map { DSTrendChart.Point(t: $0.t, v: $0.v) }
        let socMinutes = Int(HistoryStore.socInterval / 60)
        let powerMinutes = Int(HistoryStore.powerInterval / 60)

        VStack(alignment: .leading, spacing: TokensSpacing.lg) {
            DSSectionHeader(title: "趋势", trailing: "车端采样")

            Picker("周期", selection: $trendPeriod) {
                ForEach(TrendPeriod.allCases) { p in
                    Text(p.rawValue).tag(p)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            VStack(alignment: .leading, spacing: TokensSpacing.sm) {
                HStack(alignment: .firstTextBaseline) {
                    Text("SOC")
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
                    DSTrendEmpty(icon: "chart.xyaxis.line",
                                 title: "正在积累数据",
                                 message: "每 \(socMinutes) 分钟记一个点，已 \(socPoints.count) 个点。")
                }
            }

            VStack(alignment: .leading, spacing: TokensSpacing.sm) {
                HStack(alignment: .firstTextBaseline) {
                    Text("充电功率")
                        .font(TokensTypo.subheadline.weight(.semibold))
                        .foregroundStyle(TokensPalette.primary)
                    Spacer(minLength: TokensSpacing.sm)
                    Text(chargePowerText)
                        .font(TokensTypo.digits(13))
                        .foregroundStyle(TokensPalette.info)
                }
                if powerPoints.count >= 2 {
                    DSTrendChart(points: powerPoints,
                                 unit: "kW",
                                 tint: TokensPalette.info,
                                 height: 132,
                                 valueText: { String(format: "%.0f", $0) })
                } else {
                    DSTrendEmpty(icon: "bolt",
                                 title: "还没有充电曲线",
                                 message: "只在充电中记点，每 \(powerMinutes) 分钟一个。已 \(powerPoints.count) 个点。")
                }
            }
        }
    }

    // MARK: - 数据

    private func loadIfNeeded() {
        guard !store.carId.isEmpty else { loading = false; return }
        guard loadTask == nil || loadTask!.isCancelled else { return }
        loadTask = Task { await load() }
    }

    @MainActor
    private func load() async {
        guard !store.carId.isEmpty else { loading = false; return }
        let api = APIClient.shared
        do {
            // 必须用 try：try? 会让 do 体永远不抛错，两个 catch 就成了死代码。
            let charge = try await api.getCharge(carId: store.carId)
            store.saveCache(["charge": charge])
            let control = try await api.getControl(carId: store.carId)
            store.saveCache(["control": control])
            errText = ""
        } catch {
            errText = error.localizedDescription
            let desc = error.localizedDescription.lowercased()
            if desc.contains("未找到") || desc.contains("登录") || desc.contains("token") {
                AppStore.shared.logout()
            }
        }
        loading = false
    }
}
