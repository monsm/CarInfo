import SwiftUI
import CoreLocation
import UserNotifications
import UIKit
import MapKit

// =============================================================================
//  车况首页 — Tesla 式信息架构
// =============================================================================
//  结构（自上而下，按「用户在车外最关心什么」排序）：
//    ① 车辆标识（哪辆车 / 在线状态）
//    ② 电量 Hero（一个巨大数字 + 续航环 + 充电状态）
//    ③ 快捷操作（锁车 / 解锁 / 空调 / 寻车）
//    ④ 关键指标（里程 / 车速 / 车内温度 / PM2.5）
//    ⑤ 车身状态（门窗锁等安全项）
//    ⑥ 系统健康（8 个状态域，语义色直读）
//    ⑦~⑨ 电池 / 胎压 / 座舱明细
//    ⑩ 位置（地址 + 地图 + 导航）
//    ⑪ 数据来源（更新时间 + 手动刷新）
//
//  视觉：DS 设计系统。单一画布、不透明卡片、发丝分隔、语义色。
//  没有任何铺底装饰与入场动画 —— 打开即到位。
// =============================================================================

struct HomeView: View {

    private let store = AppStore.shared

    @State private var startTimer: Task<Void, Never>? = nil
    @State private var lastFetch: Date?
    @State private var isRefreshing = false
    @State private var showCheckInReminder = false
    @State private var showSearch = false
    @State private var showMap = true
    @State private var focusEnabled = FocusModeManager.shared.config.enabled

    /// 当前缓存（一次取值，多处复用，避免每个卡片各读一遍）
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
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: DS.Space.gap) {

                if store.isOfflineMode || store.networkStatus != .online {
                    DSNotice(
                        kind: store.isOfflineMode ? .warning : .info,
                        text: store.isOfflineMode
                            ? "离线模式：当前显示最后一次同步的数据"
                            : "网络不稳定，数据可能不是最新"
                    )
                }

                vehicleHeader
                hero
                quickActions
                metricsGrid
                bodyStatusCard
                healthCard
                batteryCard
                tyreCard
                comfortCard
                carbonCard
                locationCard
                footer
            }
            .padding(.top, DS.Space.xs)
            .padding(.bottom, DS.Space.xxl)
        }
        .dsCanvas()
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
        }
    }

    // MARK: - ① 车辆标识

    private var vehicleHeader: some View {
        let sel = VM.carSel(store.cars, store.carId)
        let e = VM.energy(cache, store.car)
        let name = sel.options.indices.contains(sel.index) ? sel.options[sel.index].name : "未绑定车辆"

        return HStack(spacing: DS.Space.md) {
            Image(systemName: "car.fill")
                .font(.system(size: DS.Size.iconLg, weight: .medium))
                .foregroundStyle(DS.Palette.label)
                .frame(width: 46, height: 46)
                .background(RoundedRectangle(cornerRadius: DS.Radius.small, style: .continuous)
                    .fill(DS.Palette.surface))

            VStack(alignment: .leading, spacing: 2) {
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
                    .font(DS.Typo.headline)
                    .tint(DS.Palette.label)
                } else {
                    Text(name)
                        .font(DS.Typo.headline)
                        .foregroundStyle(DS.Palette.label)
                        .lineLimit(1)
                }
                Text(e.updated == "--" ? "暂无上报" : "最近上报 \(e.updated)")
                    .font(DS.Typo.caption)
                    .foregroundStyle(DS.Palette.labelTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: DS.Space.sm)

            DSChip(text: e.online.cls == "ok" ? "在线" : "离线", cls: e.online.cls)
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: - ② 电量 Hero

    private var hero: some View {
        let e = VM.energy(cache, store.car)
        let tint = socTint(e.socPct)
        let progress = Double(e.socPct) / 100.0

        return DSCard(padding: DS.Space.xl, radius: DS.Radius.hero) {
            VStack(spacing: DS.Space.lg) {
                HStack(alignment: .center, spacing: DS.Space.lg) {
                    VStack(alignment: .leading, spacing: DS.Space.sm) {
                        DSMetric(
                            value: e.soc,
                            unit: "%",
                            caption: "剩余电量",
                            size: 58,
                            tint: tint
                        )
                        HStack(spacing: DS.Space.xs) {
                            DSChip(text: e.chargeText, cls: e.chargeCls, icon: chargeIcon(e.chargeCls))
                            if !e.socWarn.isEmpty {
                                DSChip(text: e.socPct < 15 ? "电量偏低" : "建议补电", cls: e.socPct < 15 ? "bad" : "warn")
                            }
                        }
                    }
                    Spacer(minLength: 0)
                    DSGauge(
                        progress: progress,
                        lineWidth: 11,
                        tint: tint,
                        value: e.range,
                        unit: "km",
                        caption: "剩余续航",
                        size: 132
                    )
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(DS.Palette.surfaceSunken)
                        Capsule()
                            .fill(tint)
                            .frame(width: max(8, geo.size.width * CGFloat(min(1, max(0, progress)))))
                            .animation(DS.Motion.value, value: progress)
                    }
                }
                .frame(height: 8)
                .accessibilityElement()
                .accessibilityLabel(Text("剩余电量 \(e.socPct)%"))

                DSDivider()

                HStack(alignment: .top, spacing: DS.Space.md) {
                    DSStatTile(label: "电压 / 电流", value: e.voltAmp, icon: "waveform.path.ecg")
                    DSStatTile(label: "电池温度", value: e.battTemp, icon: "thermometer.medium")
                    if let ttf = e.timeToFull {
                        DSStatTile(label: "预计充满", value: ttf, icon: "hourglass")
                    } else if let tte = e.timeToEmpty, tte != "--" {
                        DSStatTile(label: "预计可行驶", value: tte, icon: "hourglass")
                    } else {
                        DSStatTile(label: "平均能耗", value: e.avgConsumption ?? "--", icon: "leaf.fill")
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func chargeIcon(_ cls: String) -> String? {
        cls == "ok" ? "bolt.fill" : nil
    }

    /// SOC 语义色：只表达健康度，不做渐变
    private func socTint(_ pct: Int) -> Color {
        switch pct {
        case ..<15: return DS.Palette.bad
        case ..<30: return DS.Palette.warn
        default: return DS.Palette.ok
        }
    }

    // MARK: - ③ 快捷操作

    private var quickActions: some View {
        let body = VM.bodyStatus(cache)
        let lockChip = body.first { $0.label == "车锁" }
        let acOn = VM.comfortStatus(cache).acOn

        return HStack(spacing: DS.Space.sm) {
            DSTile(
                icon: "lock.fill",
                title: "锁车",
                subtitle: lockChip?.text ?? "--",
                isActive: lockChip?.text == "已锁",
                cls: "ok"
            ) { quick("LockDoor") }

            DSTile(
                icon: "lock.open.fill",
                title: "解锁",
                subtitle: lockChip?.text == "未锁" ? "当前未锁" : "当前已锁",
                isActive: lockChip?.text == "未锁",
                cls: "warn"
            ) { quick("UnLockDoor") }

            DSTile(
                icon: "snowflake",
                title: "空调",
                subtitle: acOn == nil ? "--" : (acOn! ? "运行中" : "已关闭"),
                isActive: acOn == true,
                cls: "ok"
            ) { quick("OpenAir") }

            DSTile(
                icon: "location.fill",
                title: "寻车",
                subtitle: "鸣笛闪灯",
                isActive: false,
                cls: "acc"
            ) { quick("RemoteSearchCar") }
        }
    }

    /// 快捷操作统一走「车控页执行」路径：写入 pendingQuickCtrl 后切到车控 Tab
    private func quick(_ raw: String) {
        DSHaptic.tap()
        store.pendingQuickCtrl = raw
        NotificationCenter.default.post(name: .navToMessages, object: nil)
    }

    // MARK: - ④ 关键指标

    private var metricsGrid: some View {
        let d = VM.driveStatus(cache)
        let comfort = VM.comfortStatus(cache)
        let columns = [GridItem(.flexible(), spacing: DS.Space.md),
                       GridItem(.flexible(), spacing: DS.Space.md)]

        return DSCard {
            VStack(alignment: .leading, spacing: DS.Space.lg) {
                DSSectionHeader(title: "行驶")
                LazyVGrid(columns: columns, spacing: DS.Space.lg) {
                    DSStatTile(label: "总里程", value: d.mile, unit: "km", icon: "road.lanes")
                    DSStatTile(label: "车速", value: d.speed, unit: "km/h", icon: "speedometer")
                    DSStatTile(label: "档位", value: d.gear,
                               cls: d.gearCls.isEmpty ? "na" : d.gearCls,
                               icon: "gearshape.fill")
                    DSStatTile(label: "电机温度", value: motorTempShort(d.motorTemp), icon: "thermometer.medium")
                }
                if !d.batteryNote.isEmpty {
                    Text(d.batteryNote)
                        .font(DS.Typo.caption)
                        .foregroundStyle(DS.Palette.labelTertiary)
                }
                if comfort.cabinTemp != "--" || comfort.pmIn != "--" {
                    DSDivider()
                    HStack(alignment: .top, spacing: DS.Space.md) {
                        DSStatTile(label: "车内温度", value: comfort.cabinTemp, icon: "thermometer.low")
                        DSStatTile(label: "车内 PM2.5", value: comfort.pmIn, unit: "μg/m³", icon: "aqi.low")
                    }
                }
            }
        }
    }

    /// "45℃ / 38℃" → "45℃"（磁贴里只放主读数，全量在车控页）
    private func motorTempShort(_ raw: String) -> String {
        guard raw != "--" else { return "--" }
        return raw.components(separatedBy: "/").first?.trimmingCharacters(in: .whitespaces) ?? raw
    }

    // MARK: - ⑤ 车身状态

    private var bodyStatusCard: some View {
        let chips = VM.bodyStatus(cache)
        let columns = [GridItem(.adaptive(minimum: 92), spacing: DS.Space.sm)]

        return DSCard {
            VStack(alignment: .leading, spacing: DS.Space.md) {
                DSSectionHeader(title: "车身")
                LazyVGrid(columns: columns, alignment: .leading, spacing: DS.Space.sm) {
                    ForEach(chips) { c in
                        DSChip(text: "\(c.label) \(c.text)", cls: c.cls)
                    }
                }
            }
        }
    }

    // MARK: - ⑥ 系统健康

    private var healthCard: some View {
        let summary = AN.summarize(cache, store.car)
        let rows = summary.domains

        return DSCard {
            VStack(alignment: .leading, spacing: DS.Space.sm) {
                DSSectionHeader(title: "系统状态", trailing: summary.overall.title)
                ForEach(Array(rows.enumerated()), id: \.element.id) { idx, d in
                    DSStatRow(
                        label: d.label,
                        value: d.short,
                        valueCls: d.cls,
                        icon: domainIcon(d.key)
                    )
                    if idx < rows.count - 1 { DSDivider() }
                }
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

    // MARK: - ⑦ 电池

    private var batteryCard: some View {
        let e = VM.energy(cache, store.car)

        return DSCard {
            VStack(alignment: .leading, spacing: DS.Space.sm) {
                DSSectionHeader(title: "电池", trailing: e.chargeText)
                DSStatRow(label: "剩余电量", value: "\(e.soc)%", valueCls: e.socCls, icon: "battery.75")
                DSDivider()
                DSStatRow(label: "剩余续航", value: "\(e.range) km", icon: "road.lanes")
                DSDivider()
                DSStatRow(label: "电压 / 电流", value: e.voltAmp, icon: "waveform.path.ecg")
                DSDivider()
                DSStatRow(label: "电池温度", value: e.battTemp, icon: "thermometer.medium")
                DSDivider()
                DSStatRow(label: "绝缘电阻", value: e.insulate, icon: "shield.lefthalf.filled")
                if let c = e.charging {
                    DSDivider()
                    DSStatRow(label: "充电功率", value: c.power, icon: "bolt.fill")
                    DSDivider()
                    DSStatRow(label: "充电时长", value: "\(c.durMin) 分钟", icon: "clock")
                    if let ttf = c.timeToFull {
                        DSDivider()
                        DSStatRow(label: "预计充满", value: ttf, icon: "hourglass")
                    }
                }
            }
        }
    }

    // MARK: - ⑧ 胎压

    private var tyreCard: some View {
        let tyre = VM.tyreStatus(cache)

        return DSCard {
            VStack(alignment: .leading, spacing: DS.Space.lg) {
                DSSectionHeader(title: "胎压", trailing: tyre.alarmText)
                HStack(alignment: .top, spacing: DS.Space.md) {
                    ForEach(tyre.items.prefix(2)) { item in
                        tyreItem(item)
                    }
                }
                HStack(alignment: .top, spacing: DS.Space.md) {
                    ForEach(Array(tyre.items.dropFirst(2).prefix(2))) { item in
                        tyreItem(item)
                    }
                }
                DSDivider()
                DSStatRow(label: "胎温区间", value: tyre.tempRange, icon: "thermometer.medium")
            }
        }
    }

    private func tyreItem(_ item: TyreItem) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(safeSymbol: "circle.dashed", fallback: "circle")
                    .font(.system(size: 11, weight: .medium))
                Text(item.label)
                    .font(DS.Typo.caption2.weight(.medium))
            }
            .foregroundStyle(DS.Palette.labelTertiary)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(item.kpa)
                    .font(DS.Typo.metric(22))
                    .foregroundStyle(item.cls == "ok" ? DS.Palette.label : DS.Palette.status(item.cls))
                    .contentTransition(.numericText())
                Text("kPa")
                    .font(DS.Typo.caption)
                    .foregroundStyle(DS.Palette.labelSecondary)
            }
            Text("\(item.temp)℃")
                .font(DS.Typo.dataSmall)
                .foregroundStyle(DS.Palette.labelSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: - ⑨ 座舱

    private var comfortCard: some View {
        let c = VM.comfortStatus(cache)

        return DSCard {
            VStack(alignment: .leading, spacing: DS.Space.sm) {
                DSSectionHeader(title: "座舱", trailing: c.acOn == true ? "空调运行" : "空调关闭")
                DSStatRow(label: "空调", value: c.acText, icon: "snowflake")
                DSDivider()
                DSStatRow(label: "车内温度", value: c.cabinTemp, icon: "thermometer.low")
                DSDivider()
                DSStatRow(label: "车外温度", value: c.envTemp, icon: "thermometer.high")
                DSDivider()
                DSStatRow(label: "车内 PM2.5", value: c.pmIn, icon: "aqi.low")
                DSDivider()
                DSStatRow(label: "车外 PM2.5", value: c.pmOut, icon: "aqi.medium")
                DSDivider()
                DSStatRow(label: "空气净化", value: c.purifier, icon: "wind")
                DSDivider()
                DSStatRow(label: "主驾座椅", value: c.seatD, icon: "carseat.left.fill")
                DSDivider()
                DSStatRow(label: "副驾座椅", value: c.seatP, icon: "carseat.right.fill")
            }
        }
    }

    // MARK: - ⑩ 碳减排

    @ViewBuilder
    private var carbonCard: some View {
        let stats = CarbonSavingsTracker.shared.getTodayStats()
        if stats.todaySteps > 0 {
            DSCard {
                VStack(alignment: .leading, spacing: DS.Space.sm) {
                    DSSectionHeader(title: "碳减排", trailing: "\(stats.equivalentTrees) 棵树")
                    DSStatRow(label: "今日步行", value: "\(stats.todaySteps) 步", icon: "figure.walk")
                    DSDivider()
                    DSStatRow(label: "今日减碳", value: String(format: "%.2f kg", stats.todayCarbonKg), icon: "leaf.fill")
                    DSDivider()
                    DSStatRow(label: "累计减碳", value: String(format: "%.2f kg", stats.totalCarbonKg), icon: "leaf.arrow.triangle.circlepath")
                }
            }
        }
    }

    // MARK: - ⑪ 位置

    private var locationCard: some View {
        let loc = VM.locStatus(cache)
        let hasCoord = loc.lat != "--" && loc.lng != "--"

        return DSCard {
            VStack(alignment: .leading, spacing: DS.Space.md) {
                DSSectionHeader(title: "位置", trailing: loc.dir != "--" ? loc.dir : nil)

                Text(loc.addr.isEmpty ? "暂无定位数据" : loc.addr)
                    .font(DS.Typo.headline)
                    .foregroundStyle(loc.addr.isEmpty ? DS.Palette.labelSecondary : DS.Palette.label)
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
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                }

                HStack(spacing: DS.Space.sm) {
                    if hasCoord {
                        Button("导航") { openNav(loc) }
                            .buttonStyle(DSSecondaryButtonStyle())
                    }
                    Button(showMap ? "隐藏地图" : "显示地图") {
                        withAnimation(DS.Motion.fade) { showMap.toggle() }
                    }
                    .buttonStyle(DSSecondaryButtonStyle())

                    Button {
                        saveParking(loc)
                    } label: {
                        Image(systemName: store.parkingLocation != nil ? "parkingsign.circle.fill" : "parkingsign.circle")
                    }
                    .buttonStyle(DSIconButtonStyle(size: DS.Size.button))
                    .accessibilityLabel(Text("保存停车位置"))
                }

                DSDivider()

                DSStatRow(label: "GPS", value: loc.gpsText, valueCls: loc.gpsCls, icon: "location.fill")
                DSDivider()
                DSStatRow(label: "方位", value: "\(loc.dir) \(loc.deg)", icon: "location.north.fill")
                DSDivider()
                DSStatRow(label: "卫星", value: loc.satAlt, icon: "antenna.radiowaves.left.and.right")
                DSDivider()
                DSStatRow(label: "坐标", value: hasCoord ? "\(loc.lat), \(loc.lng)" : "--", icon: "mappin.and.ellipse")

                if let pk = store.parkingLocation, let t = store.lastParkingTime {
                    DSDivider()
                    DSStatRow(
                        label: "停车点",
                        value: String(format: "%.4f, %.4f", pk.coordinate.latitude, pk.coordinate.longitude),
                        icon: "parkingsign.circle.fill"
                    )
                    Text("保存于 \(DateFormatter.relative(t))")
                        .font(DS.Typo.caption)
                        .foregroundStyle(DS.Palette.labelTertiary)
                }
            }
        }
    }

    // MARK: - ⑫ 数据来源

    private var footer: some View {
        let update = lastFetch.map { DateFormatter.relative($0) } ?? "--"
        return HStack(spacing: DS.Space.sm) {
            Image(safeSymbol: "clock.badge.checkmark", fallback: "clock.fill")
                .font(.system(size: DS.Size.iconSm, weight: .medium))
                .foregroundStyle(DS.Palette.labelTertiary)
            Text("更新于 \(update)")
                .font(DS.Typo.caption)
                .foregroundStyle(DS.Palette.labelSecondary)
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
                .buttonStyle(DSIconButtonStyle(size: 36, tint: DS.Palette.tint))
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
        withAnimation(DS.Motion.press) { focusEnabled = next.enabled }
    }

    private func openNav(_ loc: LocModel) {
        guard loc.lat != "--", loc.lng != "--" else { return }
        guard let url = URL(string: "http://uri.amap.com/navigation?to=\(loc.lng),\(loc.lat)&mode=car") else { return }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
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
        let vc = UIActivityViewController(activityItems: [generateShareableStatus(info: info)], applicationActivities: nil)
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
                // 智能通知：低电量 / 充满 / 胎压 / 到期等
                store.checkNotificationsIfNeeded()
                // 上车打卡提醒：每日首次进入提示一次
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
            points: []
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
            DS.Palette.surfaceSunken
            VStack(spacing: DS.Space.sm) {
                Image(systemName: "map")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(DS.Palette.labelTertiary)
                Text(addr.isEmpty ? "暂无定位" : addr)
                    .font(DS.Typo.footnote)
                    .foregroundStyle(DS.Palette.labelSecondary)
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
