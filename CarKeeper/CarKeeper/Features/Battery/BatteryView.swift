import SwiftUI
import Charts

// 电池与充电：SOC 光环 + 一致性柱图 + 充电会话 + 子系统 + 电机 + 故障码 + 告警
struct BatteryView: View {
    private let store = AppStore.shared
    @State private var ready = false
    @State private var loaded = false

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.cardSpacing) {
                let cache = store.caches
                let b = batteryModel(cache)
                let e = VM.energy(cache, store.car)
                    // SOC Hero
                    VStack(spacing: 10) {
                        ZStack {
                            Circle().stroke(Color(.systemGray5), lineWidth: 10).frame(width: 180, height: 180)
                            Circle().trim(from: 0, to: CGFloat(e.socPct) / 100)
                                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                                .frame(width: 180, height: 180)
                            VStack(spacing: 2) {
                                Text(e.soc).font(Theme.d1)
                                Text("%").font(.system(size: 14)).foregroundStyle(.secondary)
                            }
                        }
                        HStack(spacing: 24) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("约可行驶").font(.system(size: 12)).foregroundStyle(.secondary)
                                HStack(alignment: .firstTextBaseline, spacing: 4) {
                                    Text(e.range).font(Theme.d3)
                                    Text("km").font(.system(size: 12)).foregroundStyle(.secondary)
                                }
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text("充电状态").font(.system(size: 12)).foregroundStyle(.secondary)
                                Text(e.chargeText).font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(e.chargeCls == "ok" ? Color.green : .secondary)
                            }
                        }
                        Text("更新 \(e.updated == "--" ? "--" : String(e.updated.suffix(5)))").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)

                    // 分析结论
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

                    // 一致性
                    let cellStats = b.cellStats
                    let probeStats = b.probeStats
                    CardBox(title: "一致性", side: cellStats.map { "\($0.count) 节采样" } ?? "接口未上报",
                            sideCls: "ok") {
                        VStack(spacing: 12) {
                            if let cellStats {
                                Text("单体电压").font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                                Chart(Array(cellStats.bars.enumerated()), id: \.offset) { idx, v in
                                    BarMark(x: .value("序号", idx), y: .value("V", v))
                                        .foregroundStyle(Color.accentColor.opacity(0.7))
                                }
                                .frame(height: 100)
                                HStack(spacing: 16) {
                                    kvChip("最高", String(format: "%.3f", cellStats.max) + " V")
                                    kvChip("最低", String(format: "%.3f", cellStats.min) + " V")
                                    if let dv = b.diffV {
                                        kvChip("压差", String(format: "%.3f", dv) + " V", cls: dv >= 0.05 ? "bad" : "ok")
                                    }
                                }
                            }
                            if let probeStats {
                                Text("温度探针").font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                                Chart(Array(probeStats.bars.enumerated()), id: \.offset) { idx, v in
                                    BarMark(x: .value("序号", idx), y: .value("℃", v))
                                        .foregroundStyle(Color.blue.opacity(0.5))
                                }
                                .frame(height: 80)
                                HStack(spacing: 16) {
                                    kvChip("最高", String(format: "%.1f", probeStats.max) + " ℃")
                                    kvChip("最低", String(format: "%.1f", probeStats.min) + " ℃")
                                    if let dt = b.diffT {
                                        kvChip("温差", String(format: "%.1f", dt) + " ℃", cls: dt >= 5 ? "bad" : "ok")
                                    }
                                }
                            }
                        }
                    }

                    // 充电会话
                    CardBox(title: "充电", side: b.charging.text, sideCls: b.charging.cls.isEmpty ? "na" : b.charging.cls) {
                        let rows = chargeRows(b)
                        VStack(spacing: 0) {
                            ForEach(rows, id: \.k) { r in
                                HStack {
                                    Text(r.k).font(.system(size: 13)).foregroundStyle(.secondary)
                                    Spacer()
                                    Text(r.v).font(.system(size: 13)).foregroundStyle(.primary)
                                }
                                .padding(.vertical, 8)
                            }
                        }
                    }

                    // 子系统
                    if !b.subsystems.isEmpty || !b.tempSubs.isEmpty {
                        CardBox(title: "子系统") {
                            VStack(alignment: .leading, spacing: 10) {
                                if !b.subsystems.isEmpty {
                                    Text("电压采样").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
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
                                    Text("温度采样").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
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

                    // 动力电机
                    if !b.motors.isEmpty {
                        CardBox(title: "动力系统", side: "\(b.motors.count) 台电机") {
                            ForEach(Array(b.motors.enumerated()), id: \.offset) { _, m in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(m.num == "--" ? "驱动电机" : "驱动电机 #\(m.num)")
                                        .font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                                    let rows = motorRows(m)
                                    ForEach(rows, id: \.k) { r in
                                        KVRow(k: r.k, v: r.v)
                                    }
                                }
                                .padding(.bottom, 8)
                            }
                        }
                    }

                    // 故障码
                    CardBox(title: "故障码",
                            side: b.faultTotal > 0 ? "共 \(b.faultTotal) 条" : "无故障",
                            sideCls: b.faultTotal > 0 ? "bad" : "ok") {
                        if b.faults.filter { $0.count > 0 }.isEmpty {
                            Text("驱动电机 / 储能 / 发动机均无故障").font(.system(size: 13)).foregroundStyle(.secondary)
                        } else {
                            ForEach(b.faults.filter { $0.count > 0 }) { f in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(f.name).font(.system(size: 14, weight: .medium))
                                        Spacer()
                                        Text("\(f.count) 条").font(.system(size: 13, weight: .medium)).foregroundStyle(Color.red)
                                    }
                                    if !f.codes.isEmpty {
                                        Text(f.codes).font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                                            .lineLimit(3)
                                    }
                                }
                            }
                        }
                    }

                    // 电池告警
                    if !b.alarms.isEmpty {
                        CardBox(title: "电池告警", side: "共 \(b.alarms.count) 项", sideCls: "bad") {
                            ForEach(b.alarms, id: \.self) { a in
                                HStack {
                                    Text(a).font(.system(size: 14))
                                    Spacer()
                                    Text("触发").font(.system(size: 12, weight: .medium)).foregroundStyle(Color.red)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("电池与充电")
        .onAppear { load() }
        .refreshable { await load() }
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

    private func kvChip(_ k: String, _ v: String, cls: String = "ok") -> some View {
        VStack(spacing: 2) {
            Text(k).font(.system(size: 11)).foregroundStyle(.secondary)
            Text(v).font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundStyle(cls == "bad" ? Color.red : .primary)
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func load() async {
        guard !store.carId.isEmpty else { return }
        let api = APIClient.shared
        if let charge = try? await api.getCharge(carId: store.carId) { store.saveCache(["charge": charge]) }
        if let control = try? await api.getControl(carId: store.carId) { store.saveCache(["control": control]) }
        loaded = true
    }
}
