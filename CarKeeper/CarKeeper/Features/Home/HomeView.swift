import SwiftUI
import Charts

// 车况首页：SOC hero + 状态域 + 快控 + 30s 轮询 / 8s 位置
struct HomeView: View {
    private let store = AppStore.shared
    @State private var refreshTask: Task<Void, Never>? = nil
    @State private var locTask: Task<Void, Never>? = nil
    @State private var entered = false

    var body: some View {
        Group {
            if let cfg = TokenStore.read(), !cfg.accessToken.isEmpty {
                content
            } else {
                ContentUnavailableView("请先登录", systemImage: "lock.rectangle", description: Text("点击下方登录"))
                    .task {
                        let _ = store // 触发刷新
                        // 未登录时由 RootView 自动切到 LoginView
                    }
            }
        }
    }

    private var content: some View {
        let cache = store.caches
        let car = store.car
        let energy = VM.energy(cache, car)
        let summary = AN.summarize(cache, car)
        let tyre = VM.tyreStatus(cache)
        let comfort = VM.comfortStatus(cache)
        let loc = VM.locStatus(cache)
        let drive = VM.driveStatus(cache)
        let hasData = cache["control"] != nil

        return ScrollView {
            VStack(spacing: Theme.cardSpacing) {
                // SOC Hero
                VStack(spacing: 12) {
                    Text(energy.soc)
                        .font(Theme.d1)
                        .foregroundStyle(.primary)
                    Text(energy.range.isEmpty ? "续航暂不可用" : "约可行驶 \(energy.range) km")
                        .font(Theme.small)
                        .foregroundStyle(.secondary)
                    if let charging = energy.charging {
                        Pill(text: "充电中 \(charging.power)", cls: "acc")
                    } else {
                        Pill(text: energy.chargeText, cls: energy.chargeCls)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)

                // 车辆选择
                Picker("车辆", selection: .constant(0)) {
                    ForEach(Array(VM.carSel(store.cars, store.carId).options.enumerated()), id: \.offset) { idx, opt in
                        Text(opt.name).tag(idx)
                    }
                }
                .pickerStyle(.menu)

                // 状态域
                CardBox(title: "车辆状态", side: summary.overall.title, sideCls: summary.overall.cls) {
                    ForEach(summary.domains.filter { $0.key != "service" }) { d in
                        domainRow(d)
                    }
                }

                // 电池一致性（有全车数据时展示单体电压柱图）
                if hasData { batterySection(cache) }

                // 胎压
                CardBox(title: "胎压", side: tyre.alarmText, sideCls: tyre.alarmCls) {
                    HStack(spacing: 20) {
                        ForEach(tyre.items) { item in
                            VStack(spacing: 4) {
                                Text(item.label).font(.caption2).foregroundStyle(.secondary)
                                Text(item.kpa).font(Theme.d3).foregroundStyle(item.cls == "bad" ? Color.red : .primary)
                                Text(item.temp).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }

                // 座舱
                CardBox(title: "座舱", side: comfort.acText.isEmpty ? "--" : comfort.acText, sideCls: comfort.acCls) {
                    VStack(spacing: 8) {
                        if comfort.cabinTemp != "--" {
                            KVRow(k: "车内温度", v: comfort.cabinTemp)
                        }
                        if comfort.pmIn != "--" {
                            KVRow(k: "车内PM2.5", v: comfort.pmIn)
                        }
                    }
                }

                // 位置
                CardBox(title: "位置", side: loc.deg != "--" ? loc.dir : nil) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(loc.addr.isEmpty ? "暂无定位数据" : loc.addr)
                            .font(.system(size: 15))
                        Text(loc.satAlt)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                // 页脚
                HStack {
                    Text("更新 \(energy.updated == "--" ? "--" : String(energy.updated.suffix(5))) · 30 秒自动")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer()
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 90)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("车况")
        .onAppear {
            withAnimation(.easeOut(duration: 0.25)) { entered = true }
            startPolling()
        }
        .onDisappear {
            refreshTask?.cancel()
            locTask?.cancel()
        }
        .refreshable {
            await store.fetchCore()
        }
    }

    private func domainRow(_ d: DomainVerdict) -> some View {
        HStack(spacing: 12) {
            StatusDot(cls: d.cls)
            Text(d.label).font(.system(size: 15, weight: .medium))
            Spacer()
            Text(d.short).font(.system(size: 14)).foregroundStyle(Theme.statusColor(d.cls))
        }
    }

    private func batterySection(_ cache: [String: Any?]) -> some View {
        let b = batteryModel(cache)
        return CardBox(title: "电池与动力", side: b.alarms.isEmpty ? "无告警" : "\(b.alarms.count) 项告警",
                      sideCls: b.alarms.isEmpty ? "ok" : "bad") {
            VStack(spacing: 10) {
                if let cell = b.cellStats {
                    VStack(spacing: 4) {
                        HStack {
                            Text("单体电压 \(cell.count) 节").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text("压差 \(b.diffV.map { String(format: "%.3f", $0) } ?? "--")V")
                                .font(.system(size: 13, design: .monospaced))
                        }
                        Chart(Array(cell.bars.enumerated()), id: \.offset) { idx, v in
                            BarMark(x: .value("序号", idx), y: .value("V", v))
                                .foregroundStyle(Color.accentColor.opacity(0.7))
                        }
                        .frame(height: 80)
                    }
                } else {
                    Text("接口未上报单体电压").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func startPolling() {
        refreshTask?.cancel()
        locTask?.cancel()
        refreshTask = Task {
            while !Task.isCancelled {
                await store.fetchCore()
                try? await Task.sleep(for: .seconds(30))
            }
        }
        locTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(8))
                let api = APIClient.shared
                guard !store.carId.isEmpty else { continue }
                if let loc = try? await api.getLocation(carId: store.carId) {
                    store.saveCache(["location": loc])
                }
            }
        }
    }
}
