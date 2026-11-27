import SwiftUI
import Charts


struct ChargeView: View {
    private let store = AppStore.shared

    @State private var loading = true
    @State private var errText = ""
    @State private var loadTask: Task<Void, Never>? = nil
    @State private var trendPeriod: TrendPeriod = .day

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

    @MainActor
    private var cards: [StackCard] {
        let e = VM.energy(store.caches, store.car)
        let b = batteryModel(store.caches)
        let chargeAt = store.cacheTime("charge")
        return HomeMode.charge.headCards + [
            StackCard(id: "state", title: "此刻",
                      value: e.chargeText, cls: e.chargeCls,
                      at: chargeAt,
                      content: AnyView(chargeHero(e))),
            StackCard(id: "detail", title: "明细",
                      at: chargeAt,
                      content: AnyView(chargeDetail(b))),
            StackCard(id: "battery", title: "电池",
                      value: "\(e.socPct)%", cls: "ok",
                      at: chargeAt,
                      content: AnyView(batterySection(b, e))),
            StackCard(id: "trend", title: "趋势", value: "车端采样",
                      at: chargeAt,
                      content: AnyView(trendSection(e))),
            StackCard(id: "plan", title: "长途",
                      content: AnyView(DestinationCalculatorSection()))
        ]
    }


    private func hasEnergyLine(_ e: EnergyModel) -> Bool {
        if e.range != "--" { return true }
        if let ttf = e.timeToFull, ttf != "--" { return true }
        if let tte = e.timeToEmpty, tte != "--" { return true }
        return false
    }

    private func chargeHero(_ e: EnergyModel) -> some View {
        let tint = socTint(e.socPct)
        let fraction = max(0, min(1, Double(e.socPct) / 100.0))
        let power = chargePowerText

        return VStack(alignment: .leading, spacing: 0) {
            if !e.socWarn.isEmpty {
                Text(e.socWarn)
                    .font(TokensTypo.footnote)
                    .foregroundStyle(TokensPalette.statusColor(e.socCls))
            }

            DSLightBar(
                progress: fraction,
                tint: LinearGradient(colors: [TokensPalette.lightSource, tint.opacity(0.75), tint],
                                     startPoint: .leading, endPoint: .trailing)
            )
            .padding(.top, e.socWarn.isEmpty ? 0 : TokensSpacing.lg)

            if hasEnergyLine(e) {
                HStack(alignment: .firstTextBaseline, spacing: TokensSpacing.sm) {
                    if e.range != "--" {
                        Text("续航 \(e.range) km")
                            .font(TokensTypo.footnote)
                            .foregroundStyle(TokensPalette.secondary)
                    }
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
            }

            DSStatStrip(items: [
                .init("充电功率", power),
                .init("电池温度", e.battTemp),
                .init("电压 / 电流", e.volt, second: e.amp == "--" ? nil : e.amp)
            ])
            .padding(.top, TokensSpacing.xl)
            .overlay(alignment: .top) { DSDivider() }
            .overlay(alignment: .bottom) { DSDivider() }
        }
        .accessibilityElement(children: .contain)
    }

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


    @ViewBuilder
    private func batterySection(_ b: BatteryModel, _ e: EnergyModel) -> some View {
        verdict()
        consistency(b)
        insulation(e)
        voltageSampling(b)
        motors(b)
        alarms(b)
    }

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

    private func joined(_ parts: [String]) -> String {
        parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func miniStat(_ k: String, _ v: String, _ unit: String, warn: Bool = false) -> some View {
        HStack(spacing: TokensSpacing.xs) {
            Text(k).font(TokensTypo.footnote).foregroundStyle(TokensPalette.secondary)
                .lineLimit(1).minimumScaleFactor(0.75)
            Text(v).font(TokensTypo.caption.weight(.bold)).monospacedDigit()
                .foregroundStyle(warn ? TokensPalette.error : TokensPalette.primary)
                .lineLimit(1).minimumScaleFactor(0.85)
            Text(unit).font(TokensTypo.caption2).foregroundStyle(TokensPalette.secondary)
                .lineLimit(1).minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, TokensSpacing.sm)
        .background(TokensPalette.fillSubtle, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }


    @ViewBuilder
    private func trendSection(_ e: EnergyModel) -> some View {
        let socPoints = HistoryStore.shared.socSeries(hours: trendPeriod.hours)
            .map { DSTrendChart.Point(t: $0.t, v: $0.v) }
        let powerPoints = HistoryStore.shared.powerSeries(hours: trendPeriod.hours)
            .map { DSTrendChart.Point(t: $0.t, v: $0.v) }
        let socMinutes = Int(HistoryStore.socInterval / 60)
        let powerMinutes = Int(HistoryStore.powerInterval / 60)

        VStack(alignment: .leading, spacing: TokensSpacing.lg) {
            DSSegmentPicker(options: TrendPeriod.allCases.map { (value: $0, title: $0.rawValue) },
                            selection: $trendPeriod,
                            label: "趋势周期")

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
