import SwiftUI
import Charts

// 电池与充电 —— iOS 27 Liquid Glass：
// SOC 渐变光环 + 一致性图表 + 充电会话 + 子系统 + 电机 + 故障码 + 告警。

struct BatteryView: View {
    private let store = AppStore.shared
    @State private var loaded = false
    @State private var errText: String = ""
    @State private var loadTask: Task<Void, Never>? = nil
    @State private var socProgress: CGFloat = 0      // SOC圆环进度 0→socPct
    @State private var socCardOpacity: CGFloat = 0   // SOC卡片入场淡入

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.cardSpacing) {
                let cache = store.caches
                let b = batteryModel(cache)
                let e = VM.energy(cache, store.car)
                socHero(e)
                verdictCard(cache, b)
                consistencyCard(b)
                chargeCard(b)
                subsystemCard(b)
                motorCard(b)
                faultCard(b)
                alarmCard(b)
            }
            .padding(.horizontal, 16)
            .safeAreaPadding(.bottom, 8)
        }
        .scrollBounceBehavior(.basedOnSize)
        .pageBackground(.green)
        .navigationTitle("电池与充电").navBarStyle()
        .onAppear { loadIfNeeded(); startSocAnimation() }
        .onDisappear { loadTask?.cancel(); loadTask = nil }
        .refreshable { await load() }
        .overlay {
            if !loaded && errText.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !errText.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle").font(.title).foregroundStyle(.orange)
                    Text(errText).font(.system(size: 14)).foregroundStyle(.secondary)
                    Button("重试") { Task { await load() } }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    // MARK: SOC Hero — Apple Watch 风格大圆环 + 入场动画 + 浮动粒子
    private func socHero(_ e: EnergyModel) -> some View {
        VStack(spacing: 18) {
            ZStack {
                // 第 0 层：外扩散光晕（呼吸脉冲）
                Circle()
                    .fill(AngularGradient(colors: socGlowColors(e.socPct),
                                          center: .center, startAngle: .degrees(-90), endAngle: .degrees(270)))
                    .frame(width: 248, height: 248)
                    .opacity(0.15)
                    .blur(radius: 12)

                // 第 1 层：脉冲光环（持续呼吸）
                Circle()
                    .strokeBorder(AngularGradient(colors: [.green, .teal], center: .center, startAngle: .degrees(-90), endAngle: .degrees(270)), lineWidth: 2)
                    .frame(width: 232, height: 232)
                    .opacity(0.10)
                    .blur(radius: 5)
                    .animation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true), value: socProgress)

                // 第 2 层：底色轨道
                Circle()
                    .stroke(Color(.systemGray5).opacity(0.5), lineWidth: 18)
                    .frame(width: 208, height: 208)

                // 第 3 层：彩色进度弧（动画展开）
                Circle()
                    .trim(from: 0, to: max(0.02, socProgress / 100))
                    .stroke(
                        AngularGradient(colors: [.green, .green, .accentColor, .orange, .red],
                                        center: .center, startAngle: .degrees(-90), endAngle: .degrees(270)),
                        style: StrokeStyle(lineWidth: 18, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 208, height: 208)
                    .shadow(color: socShadowColor(e.socPct).opacity(0.35), radius: 14, y: 5)

                // 第 4 层：浮动装饰粒子
                FloatingParticles(size: 208)

                // 第 5 层：中心数字
                VStack(spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(e.soc == "--" ? "--" : e.soc)
                            .font(Theme.d1)
                        Text("%").font(.system(size: 22, weight: .semibold, design: .rounded)).foregroundStyle(.secondary)
                    }
                    Text("电池电量")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            // 续航 + 充电状态
            HStack(spacing: 14) {
                MetricPill(icon: "point.topleft.down.curvedto.point.bottomright.up",
                           value: e.range == "--" ? "--" : e.range, unit: "km", tint: .green)
                MetricPill(icon: "bolt.fill", value: e.chargeText, unit: "", tint: .accentColor)
            }
            Text("更新 \(e.updated == "--" ? "--" : String(e.updated.suffix(5)))")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .glassHeroCard()
        .opacity(socCardOpacity)
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

    // MARK: 分析结论
    private func verdictCard(_ cache: [String: Any?], _ b: BatteryModel) -> some View {
        Group {
            if let batt = AN.summarize(cache, store.car).domains.first(where: { $0.key == "battery" }) {
                CardBox(title: "分析结论", side: batt.title, sideCls: batt.cls) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(batt.reasons) { r in
                            HStack(alignment: .top, spacing: 8) {
                                StatusDot(cls: r.cls)
                                Text(r.t).font(.system(size: 13)).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: 一致性
    private func consistencyCard(_ b: BatteryModel) -> some View {
        CardBox(title: "一致性", side: b.cellStats.map { "\($0.count) 节采样" } ?? "接口未上报", sideCls: "ok") {
            VStack(spacing: 12) {
                if let cell = b.cellStats {
                    VStack(spacing: 6) {
                        sectionLabel("单体电压 (V)")
                        Chart(Array(cell.bars.enumerated()), id: \.offset) { idx, v in
                            BarMark(x: .value("序号", idx), y: .value("V", v))
                                .foregroundStyle(Color.green.opacity(0.7))
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
                        Chart(Array(probe.bars.enumerated()), id: \.offset) { idx, v in
                            BarMark(x: .value("序号", idx), y: .value("℃", v))
                                .foregroundStyle(Color.blue.opacity(0.55))
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

    // MARK: 充电
    private func chargeCard(_ b: BatteryModel) -> some View {
        CardBox(title: "充电", side: b.charging.text, sideCls: b.charging.cls.isEmpty ? "na" : b.charging.cls) {
            VStack(spacing: 0) {
                let rows = chargeRows(b)
                ForEach(Array(rows.enumerated()), id: \.offset) { idx, r in
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
                CardBox(title: "动力系统", side: "\(b.motors.count) 台电机") {
                    VStack(spacing: 12) {
                        ForEach(Array(b.motors.enumerated()), id: \.offset) { _, m in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(m.num == "--" ? "驱动电机" : "驱动电机 #\(m.num)")
                                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                                let rows = motorRows(m)
                                ForEach(Array(rows.enumerated()), id: \.offset) { idx, r in
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
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 10) {
                    ForEach(b.faults.filter { $0.count > 0 }) { f in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(f.name).font(.system(size: 14, weight: .semibold))
                                Spacer()
                                Text("\(f.count) 条").font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Color.red)
                            }
                            if !f.codes.isEmpty {
                                Text(f.codes)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary).lineLimit(3)
                            }
                        }
                        .padding(10)
                        .background(.thin, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                        ForEach(Array(b.alarms.enumerated()), id: \.offset) { idx, a in
                            HStack {
                                StatusDot(cls: "bad")
                                Text(a).font(.system(size: 14))
                                Spacer()
                                Text("触发").font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Color.red)
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
        Text(t).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func miniStat(_ k: String, _ v: String, _ unit: String, warn: Bool = false) -> some View {
        HStack(spacing: 4) {
            Text(k).font(.system(size: 11)).foregroundStyle(.secondary)
            Text(v).font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(warn ? Color.red : .primary)
            Text(unit).font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(.thin, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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

    // MARK: SOC入场动画
    private func startSocAnimation() {
        withAnimation(.spring(Theme.Duration.springNormal)) { socCardOpacity = 1 }
        let e = VM.energy(store.caches, store.car)
        let target = max(0, min(100, e.socPct))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.spring(response: 0.65, dampingFraction: 0.65, blendDuration: 0.9)) {
                socProgress = CGFloat(target)
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
            if let charge = try? await api.getCharge(carId: store.carId) { store.saveCache(["charge": charge]) }
            if let control = try? await api.getControl(carId: store.carId) { store.saveCache(["control": control]) }
            loaded = true
            errText = ""
            // 刷新后重新播放 SOC 液态玻璃入场动画
            withAnimation(.spring(Theme.Duration.springFast)) { socCardOpacity = 0; socProgress = 0 }
            startSocAnimation()
        } catch {
        } catch {
            errText = error.localizedDescription
            let errDesc = error.localizedDescription.lowercased()
            if errDesc.contains("未找到") || errDesc.contains("登录") || errDesc.contains("token") {
                // token 过期，跳回登录页
                await MainActor.run { AppStore.shared.logout() }
            }
        }
    }
}


