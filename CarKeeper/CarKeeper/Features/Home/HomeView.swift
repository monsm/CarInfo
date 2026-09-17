import SwiftUI
import Charts
import MapKit

// 车况首页 —— iOS 27 Liquid Glass：
// SOC 渐变 Hero 环 + 车辆切换玻璃条 + 快控圆钮 + 状态域 / 胎压 / 座舱 / 位置。
// 数据逻辑与轮询节奏不变（30s 全量 / 8s 位置，地图懒加载）。

struct HomeView: View {
    private let store = AppStore.shared
    @StateObject private var nav = NavState.shared
    @State private var refreshTask: Task<Void, Never>? = nil
    @State private var locTask: Task<Void, Never>? = nil
    @State private var showMap = false

    enum QuickCtrl: String, CaseIterable {
        case lock, unlock, air, charge
        var symbol: String {
            switch self {
            case .lock: "lock.fill"; case .unlock: "lock.open.fill"
            case .air: "fan.blades"; case .charge: "bolt.fill"
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
            case .lock, .unlock: return Color.primary
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
                socHero(energy)
                carSelector
                quickControl
                domainCard(summary)
                if hasData { batterySection(cache) }
                tyreCard(tyre)
                comfortCard(comfort)
                locationCard(loc)
                footerNote(energy)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 96)
        }
        .scrollBounceBehavior(.basedOnSize)
        .pageBackground(.accentColor)
        .navigationTitle("车况")
        .onAppear { startPolling() }
        .onDisappear {
            refreshTask?.cancel()
            locTask?.cancel()
        }
        .refreshable { await store.fetchCore() }
    }

    // MARK: SOC Hero
    private func socHero(_ e: EnergyModel) -> some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(Color(.systemGray4).opacity(0.5), lineWidth: 14)
                    .frame(width: 172, height: 172)
                Circle()
                    .trim(from: 0, to: max(0.02, CGFloat(e.socPct) / 100))
                    .stroke(
                        AngularGradient(colors: [.green, .green, Color.accentColor, .orange, .red],
                                        center: .center, startAngle: .degrees(-90), endAngle: .degrees(270)),
                        style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 172, height: 172)
                    .shadow(color: Color.accentColor.opacity(0.35), radius: 10)
                VStack(spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(e.soc == "--" ? "--" : e.soc)
                            .font(Theme.d1)
                        Text("%").font(.system(size: 20, weight: .semibold, design: .rounded)).foregroundStyle(.secondary)
                    }
                    Text("电量")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 22) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    Text(e.range == "--" ? "续航暂不可用" : "约 \(e.range) km")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                }
                Pill(text: e.chargeText, cls: e.chargeCls == "idle" ? "na" : e.chargeCls)
            }
            Text(e.online.text)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .glassCard()
    }

    // MARK: 车辆切换
    private var carSelector: some View {
        let carSel = VM.carSel(store.cars, store.carId)
        return HStack(spacing: 10) {
            Image(systemName: "car.2.fill")
                .font(.system(size: 14))
                .foregroundStyle(Color.accentColor)
            Picker("车辆", selection: Binding(
                get: { carSel.index },
                set: { store.selectCar($0) }
            )) {
                ForEach(Array(carSel.options.enumerated()), id: \.offset) { idx, opt in
                    Text(opt.name).tag(idx)
                }
            }
            .font(.system(size: 15, weight: .semibold))
            Spacer()
            if carSel.count > 1 {
                Text("\(carSel.count) 辆")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .glassCard(corner: 20)
    }

    // MARK: 快控
    private var quickControl: some View {
        HStack(spacing: 12) {
            ForEach(QuickCtrl.allCases, id: \.self) { q in
                QuickCtrlButton(q: q) { onQuickCtrl(q) }
            }
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .glassCard()
    }

    // MARK: 状态域
    private func domainCard(_ summary: Summary) -> some View {
        CardBox(title: "车辆状态", side: summary.overall.title, sideCls: summary.overall.cls) {
            VStack(spacing: 0) {
                let rows = summary.domains.filter { $0.key != "service" }
                ForEach(Array(rows.enumerated()), id: \.element.id) { idx, d in
                    domainRow(d)
                    if idx < rows.count - 1 { ListDivider().padding(.vertical, 2) }
                }
            }
        }
    }

    private func domainRow(_ d: DomainVerdict) -> some View {
        HStack(spacing: 12) {
            StatusDot(cls: d.cls)
            Text(d.label).font(.system(size: 15, weight: .medium))
            Spacer()
            Text(d.short).font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.statusColor(d.cls))
        }
        .padding(.vertical, 7)
    }

    // MARK: 电池一致性
    private func batterySection(_ cache: [String: Any?]) -> some View {
        let b = batteryModel(cache)
        return CardBox(title: "电池与动力", side: b.alarms.isEmpty ? "无告警" : "\(b.alarms.count) 项告警",
                       sideCls: b.alarms.isEmpty ? "ok" : "bad") {
            VStack(spacing: 10) {
                if let cell = b.cellStats {
                    VStack(spacing: 6) {
                        HStack {
                            Text("单体电压 \(cell.count) 节").font(.system(size: 12)).foregroundStyle(.secondary)
                            Spacer()
                            Text("压差 \(b.diffV.map { String(format: "%.3f", $0) } ?? "--")V")
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundStyle((b.diffV ?? 0) >= 0.05 ? Color.red : Color.green)
                        }
                        Chart(Array(cell.bars.enumerated()), id: \.offset) { idx, v in
                            BarMark(x: .value("序号", idx), y: .value("V", v))
                                .foregroundStyle(Color.accentColor.opacity(0.75))
                                .cornerRadius(1.5)
                        }
                        .chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) }
                        .frame(height: 84)
                    }
                } else {
                    Text("接口未上报单体电压").font(.system(size: 13)).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: 胎压（四宫格）
    private func tyreCard(_ tyre: TyreModel) -> some View {
        CardBox(title: "胎压", side: tyre.alarmText, sideCls: tyre.alarmCls) {
            VStack(spacing: 10) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()),
                                    GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(tyre.items) { item in
                        VStack(spacing: 3) {
                            Text(item.label).font(.system(size: 11)).foregroundStyle(.secondary)
                            HStack(alignment: .firstTextBaseline, spacing: 1) {
                                Text(item.kpa).font(.system(size: 20, weight: .semibold, design: .rounded))
                                    .foregroundStyle(item.cls == "bad" ? Color.red : .primary)
                                Text("kPa").font(.system(size: 9)).foregroundStyle(.secondary)
                            }
                            Text("\(item.temp)℃").font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
                Text("温度 \(tyre.tempRange)")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    // MARK: 座舱
    private func comfortCard(_ comfort: ComfortModel) -> some View {
        CardBox(title: "座舱", side: comfort.acText.isEmpty ? "--" : (comfort.acCls == "ok" ? "空调运行中" : "空调关闭"),
                sideCls: comfort.acCls == "ok" ? "ok" : "na") {
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    StatTile(icon: "thermometer.medium", label: "车内温度", value: comfort.cabinTemp == "--" ? "--" : String(comfort.cabinTemp.dropLast()), unit: "℃", tint: .orange)
                    StatTile(icon: "wind", label: "车内 PM2.5", value: comfort.pmIn, unit: "", tint: .teal)
                }
                HStack(spacing: 10) {
                    StatTile(icon: "air.purifier", label: "净化器", value: comfort.purifier, tint: .purple)
                    StatTile(icon: "cloud.sun", label: "车外温度", value: comfort.envTemp == "--" ? "--" : String(comfort.envTemp.dropLast()), unit: "℃", tint: .blue)
                }
                Text(comfort.acText)
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: 位置
    private func locationCard(_ loc: LocModel) -> some View {
        CardBox(title: "位置", side: loc.deg != "--" ? loc.dir : nil) {
            VStack(alignment: .leading, spacing: 10) {
                if showMap {
                    LocationMapView(latStr: loc.lat, lngStr: loc.lng, addr: loc.addr)
                        .frame(height: 190)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .transition(.opacity)
                }
                Text(loc.addr.isEmpty ? "暂无定位数据" : loc.addr)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                Text(loc.satAlt).font(.system(size: 11)).foregroundStyle(.secondary)
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
        Button {
            withAnimation(.easeInOut(duration: 0.25)) { showMap.toggle() }
        } label: {
            Label(showMap ? "收起地图" : "展开地图", systemImage: showMap ? "chevron.up" : "map.fill")
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }

    private func navButton(_ loc: LocModel) -> some View {
        Button {
            openMaps(lat: loc.lat, lng: loc.lng, addr: loc.addr)
        } label: {
            Label("导航", systemImage: "location.north.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color.accentColor, in: Capsule())
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }

    private func footerNote(_ e: EnergyModel) -> some View {
        Text("更新 \(e.updated == "--" ? "--" : String(e.updated.suffix(5))) · 每 30 秒自动刷新")
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity)
    }

    // MARK: 快控 / 导航 / 轮询（逻辑不变）
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

    private func openMaps(lat: String, lng: String, addr: String) {
        guard let la = Double(lat), let lo = Double(lng) else { return }
        UIApplication.shared.open(mapsURL(lat: la, lng: lo, dest: addr.isEmpty ? "车辆位置" : addr))
    }

    private func mapsURL(lat: Double, lng: Double, dest: String) -> URL {
        let escaped = dest.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? dest
        return URL(string: "http://maps.apple.com/?dirflg=d&saddr=&daddr=\(lat),\(lng)&q=\(escaped)")!
    }

    private func startPolling() {
        refreshTask?.cancel()
        locTask?.cancel()
        refreshTask = Task { @MainActor in
            while !Task.isCancelled {
                await store.fetchCore()
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
                    if !newLat.isEmpty, !newLng.isEmpty {
                        NotificationCenter.default.post(name: .locationUpdated, object: nil)
                    }
                }
            }
        }
    }
}

// 快控玻璃圆钮
struct QuickCtrlButton: View {
    let q: HomeView.QuickCtrl
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                ZStack {
                    Circle()
                        .fill(q.accent.opacity(0.14))
                        .frame(width: 58, height: 58)
                    Circle()
                        .strokeBorder(q.accent.opacity(0.35), lineWidth: 1)
                        .frame(width: 58, height: 58)
                    Image(systemName: q.symbol)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(q.accent)
                }
                Text(q.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// 内置车辆位置地图（懒加载 + 随 8s 轮询平移）
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
                    Marker(addr.isEmpty ? "车辆" : addr, systemImage: "car.fill", coordinate: coord)
                        .tint(.red)
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .onReceive(NotificationCenter.default.publisher(for: .locationUpdated)) { _ in
                    withAnimation(.easeInOut(duration: 0.4)) {
                        camera = .camera(MapCamera(centerCoordinate: coord, distance: 600))
                    }
                }
                .onAppear {
                    withAnimation {
                        camera = .camera(MapCamera(centerCoordinate: coord, distance: 600))
                    }
                }
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(.systemGray5))
                    VStack(spacing: 6) {
                        Image(systemName: "location.slash").font(.title2).foregroundStyle(.secondary)
                        Text("暂无定位坐标").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(height: 190)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
