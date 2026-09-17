import SwiftUI
import Charts
import MapKit

// 车况首页：SOC hero + 状态域 + 快控 + 内置地图 + 30s 轮询 / 8s 位置
struct HomeView: View {
    private let store = AppStore.shared
    @StateObject private var nav = NavState.shared
    @State private var refreshTask: Task<Void, Never>? = nil
    @State private var locTask: Task<Void, Never>? = nil
    @State private var entered = false
    @State private var showMap = false  // 地图懒加载：点「展开地图」才创建 Map，省首屏内存

    enum QuickCtrl: String, CaseIterable {
        case lock, unlock, air, charge
        var symbol: String {
            switch self {
            case .lock: "lock.fill"; case .unlock: "lock.open.fill"
            case .air: "snowflake"; case .charge: "bolt.fill"
            }
        }
        var title: String {
            switch self {
            case .lock: "锁车"; case .unlock: "解锁"
            case .air: "空调"; case .charge: "充电"
            }
        }
        var accent: Color {
            switch self {
            case .lock, .unlock: return .primary
            case .air: return .blue
            case .charge: return .accentColor
            }
        }
    }

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
                let carSel = VM.carSel(store.cars, store.carId)
                Picker("车辆", selection: Binding(
                    get: { carSel.index },
                    set: { store.selectCar($0) }
                )) {
                    ForEach(Array(carSel.options.enumerated()), id: \.offset) { idx, opt in
                        Text(opt.name).tag(idx)
                    }
                }
                .pickerStyle(.menu)

                // 快控圆钮（对应小程序 home 的 qctrl：锁车/解锁/空调/充电直达）
                CardBox(title: "快控") {
                    HStack(spacing: 12) {
                        ForEach(QuickCtrl.allCases, id: \.self) { q in
                            QuickCtrlButton(q: q) { onQuickCtrl(q) }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }

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

                // 位置（地图懒加载：默认收起，点「展开地图」才创建 Map，省首屏内存）
                CardBox(title: "位置", side: loc.deg != "--" ? loc.dir : nil) {
                    VStack(alignment: .leading, spacing: 10) {
                        // 已展开：才真正渲染 Map/Marker（否则首屏不创建，省内存/启动更快）。
                        if showMap {
                            LocationMapView(latStr: loc.lat, lngStr: loc.lng, addr: loc.addr)
                                .frame(height: 180)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .transition(.opacity)
                        }
                        HStack(spacing: 8) {
                            Text(loc.addr.isEmpty ? "暂无定位数据" : loc.addr)
                                .font(.system(size: 14))
                                .lineLimit(1)
                            Spacer()
                            HStack(spacing: 8) {
                                Button {
                                    withAnimation(.easeInOut(duration: 0.25)) { showMap.toggle() }
                                } label: {
                                    Label(showMap ? "收起地图" : "展开地图", systemImage: showMap ? "chevron.up" : "map.fill")
                                        .font(.system(size: 13, weight: .medium))
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                if loc.lat != "--" && loc.lng != "--" {
                                    Button {
                                        openMaps(lat: loc.lat, lng: loc.lng, addr: loc.addr)
                                    } label: {
                                        Label("导航", systemImage: "location.north.fill")
                                            .font(.system(size: 13, weight: .medium))
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                }
                            }
                        }
                        Text(loc.satAlt).font(.caption).foregroundStyle(.secondary)
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

    // 快控圆钮：充电直达电池页；其余切到车控 tab 并透传指令（PIN/温度由车控页接住）。
    private func onQuickCtrl(_ q: QuickCtrl) {
        switch q {
        case .charge:
            nav.path = [.battery]
            nav.selectedTab = 0
        default:
            store.pendingQuickCtrl = q.rawValue
            nav.selectedTab = 1
        }
    }

    // 调起 Apple Maps 导航到车辆定位（iOS 通过 URL 打开地图，无需定位权限）。
    private func openMaps(lat: String, lng: String, addr: String) {
        guard let la = Double(lat), let lo = Double(lng) else { return }
        UIApplication.shared.open(mapsURL(lat: la, lng: lo, dest: addr.isEmpty ? "车辆位置" : addr))
    }

    private func mapsURL(lat: Double, lng: Double, dest: String) -> URL {
        let escaped = dest.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? dest
        // dirflg=d 驾车导航；saddr 留空 = 以我当前位置为起点。
        return URL(string: "http://maps.apple.com/?dirflg=d&saddr=&daddr=\(lat),\(lng)&q=\(escaped)")!
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
        // 全量轮询任务：后台线程跑，完成后回到主线程写 store，避免主线程被 URLSession/Task.sleep 卡住。
        refreshTask = Task { @MainActor in
            while !Task.isCancelled {
                await store.fetchCore()  // 只拉 6 个轻接口，不拉 7 天消息
                do { try await Task.sleep(for: .seconds(30)) } catch { break }
            }
        }
        locTask = Task { @MainActor in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(8)) } catch { break }
                let api = APIClient.shared
                guard !store.carId.isEmpty else { continue }
                if let loc = try? await api.getLocation(carId: store.carId) {
                    let newLat = ciString(loc, ["Lat", "lat"]) ?? ""
                    let newLng = ciString(loc, ["Lng", "lng"]) ?? ""
                    store.saveCache(["location": loc])
                    // 坐标变化时通知内置地图平移。
                    if !newLat.isEmpty, !newLng.isEmpty {
                        NotificationCenter.default.post(name: .locationUpdated, object: nil)
                    }
                }
            }
        }
    }
}

// 快控圆钮（4 个：锁车/解锁/空调/充电）
struct QuickCtrlButton: View {
    let q: HomeView.QuickCtrl
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(q.accent.opacity(0.12))
                        .frame(width: 56, height: 56)
                    Circle()
                        .strokeBorder(q.accent.opacity(0.35), lineWidth: 1)
                        .frame(width: 56, height: 56)
                    Image(systemName: q.symbol)
                        .font(.system(size: 22))
                        .foregroundStyle(q.accent)
                }
                Text(q.title)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

// 内置车辆位置地图（随 8s 轮询的新坐标自动平移）。
struct LocationMapView: View {
    let latStr: String
    let lngStr: String
    let addr: String
    @State private var camera: MapCameraPosition = .automatic

    private var coordinate: CLLocationCoordinate2D? {
        Double(latStr).flatMap { la in Double(lngStr).map { lo in
            CLLocationCoordinate2D(latitude: la, longitude: lo)
        }}
    }

    var body: some View {
        Group {
            if let coord = coordinate {
                Map(position: $camera, interactionModes: .all) {
                    Marker(addr.isEmpty ? "车辆" : addr, systemImage: "car.fill",
                           coordinate: coord)
                        .tint(.red)
                }
                .onReceive(NotificationCenter.default.publisher(for: .locationUpdated)) { _ in
                    // 8s 轮询拉到新坐标后，AppStore 发通知；地图平移到新车。
                    withAnimation(.easeInOut(duration: 0.4)) { camera = .camera(MapCamera(centerCoordinate: coord, distance: 600)) }
                }
                .onAppear {
                    // 首次进入：定位到当前坐标。
                    withAnimation { camera = .camera(MapCamera(centerCoordinate: coord, distance: 600)) }
                }
            } else {
                ZStack {
                    Rectangle().fill(Color(.systemGray5))
                    VStack(spacing: 6) {
                        Image(systemName: "location.slash").font(.title2).foregroundStyle(.secondary)
                        Text("暂无定位坐标").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .background(Color(.systemGray6))
    }
}
