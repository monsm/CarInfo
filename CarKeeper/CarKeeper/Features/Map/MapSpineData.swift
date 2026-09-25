// =============================================================================
// MapSpineData.swift — 地图主屏的数据层
// =============================================================================
//
// 这一层只做一件事：**把 AppStore 里已有的真实数据，翻译成地图上画得出来的东西。**
//
// 为什么单独一层（而不是在 View 里到处读 store）：
//   ① 地图主屏要同时用到 5 个数据源（energy / location / control / tripHistory /
//      parkingHistory），散在 View 里会变成一坨 `store.xxx`；
//   ② **它让"哪些是真数据、哪些没有"变成代码里看得见的事实** ——
//      每个字段的注释都写着它来自哪个接口。没有数据时就是 nil / 空数组，
//      绝不用默认值把空的地方填满（第 7 版我就是用假数据把"洞察"糊过去的）。
//
// 数据来源（全部是项目里已经存在的真实字段，没有新接口）
//   • 电量 / 续航 / 充电      ← VM.energy(store.caches, store.car)  ← charge + control 接口
//   • 位置 / 地址 / 车头朝向  ← VM.locStatus(store.caches)          ← location 接口（Lat/Lng/Heading）
//   • 门/窗/后备箱/锁          ← VM.bodyStatus(store.caches)        ← control 接口
//   • 行程的起终点与电量       ← store.tripHistory                  ← 本地记录的 TripRecord
//   • 停车点                  ← store.parkingLocation / parkingHistory
//   • 保养里程                ← store.maintenancePlan（服务端 plan 优先，本机记录兜底）
//
// 已知缺口（**故意不做假**）：
//   • 行程**没有 GPS 轨迹点**。TripRecord 只有 start/end 两个坐标，
//     所以画出来的是"起终点连线"，不是"你实际开过的那条路"。界面上照实写。
//   • 异常（后备箱未关等）**没有发现地点**。只能挂在车当前所在位置，
//     文案写成"发现时车在这儿"，而不是暗示它发生在那里。
// =============================================================================
import SwiftUI
import CoreLocation
import MapKit

// MARK: - 图层
/// 地图主屏的四个图层。每一个都是**一个真实问题**，不是一个分类。
/// 名字带 `Spine` 前缀是刻意的：`MapLayer` 这类名字离系统类型太近，
/// 一旦某个 SDK 版本真的定义了它，就是全项目编译失败（shadowguard 拦这类形状）。
enum MapSpineLayer: String, CaseIterable, Identifiable {
    /// 车现在在哪、什么状态 → 默认层
    case now
    /// 今天/最近它被开去哪儿了 → tripHistory
    case trips
    /// 它都在哪儿停过 → parkingHistory
    case holds
    /// 该去哪儿充电、现在充得怎么样 → MKLocalSearch + 充电会话
    case charge

    var id: String { rawValue }

    var title: String {
        switch self {
        case .now: return "现在"
        case .trips: return "行程"
        case .holds: return "停车"
        case .charge: return "充电"
        }
    }

    // 这里曾经有一个 `icon`（每层一个 SF Symbol）。模式条改成相机语法之后
    // 每一项**只有文字**（没有图标、没有底、没有描边），所以它没有调用点了。
    // 留一个没人用的图标表，下一个人就会以为模式条是该带图标的。

    /// 这一层没有数据时**照实说**（空不是缺陷，是真实读数）
    var emptyNote: String {
        switch self {
        case .now: return "还没收到位置上报"
        case .trips: return "还没有行程记录"
        case .holds: return "还没有停车记录"
        case .charge: return "正在搜索附近充电站"
        }
    }
}

extension MapSpineLayer {
    /// 主屏当前显示哪一层。存在 UserDefaults 里（MapSpineView 用 @AppStorage 读），
    /// 所以"从别处把地图开到某一层"有正式入口 —— 不需要每个页面再各写一份充电站列表。
    static let storageKey = "carkeeper_map_layer"

    /// 把地图主屏切到这一层（只改意图，不负责跳转）
    func makeCurrent() { UserDefaults.standard.set(rawValue, forKey: Self.storageKey) }
}

// MARK: - 图上元素
/// 一条行程。**注意：这是起终点连线，不是行驶轨迹** —— TripRecord 里没有轨迹点。
struct MapTripLine: Identifiable {
    let id: String
    let from: CLLocationCoordinate2D
    let to: CLLocationCoordinate2D
    let startedAt: Date
    let endedAt: Date?
    let distanceKm: Double
    let startSoc: Int
    let endSoc: Int
    /// kWh/100km（需要电池容量，报文里 `capacity` 是 null → 目前恒为 nil）
    let efficiency: Double?
    /// 每 1% SOC 多少 km（不需要容量，是目前唯一算得出的能效口径）
    let kmPerPercent: Double?

    /// 这一段用了几个百分点
    var socUsed: Int { max(0, startSoc - endSoc) }

    /// 起点时刻（`HH:mm`）。
    ///
    /// 它是这一层里最烫的一个字符串：`MapSpineLayers` 为**每一段行程**读它一次，
    /// 而地图页在车动起来时每 2 秒求值一次（节律见 `RefreshLoop`）—— 原来每读一次
    /// 就现造一个 `DateFormatter`，30 段就是 30 个。现在构造器在 `DateText` 的池子里。
    var timeText: String {
        DateText.shared.string(startedAt, "HH:mm")
    }
}

/// 一个停过的地方
struct MapHoldPoint: Identifiable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let address: String
    let time: Date
    /// 是否就是"现在停在这儿"（parkingLocation 那条）
    let isLatest: Bool

    var agoText: String { MapSpineData.agoText(time) }
}

/// 一个异常点
struct MapIssue: Identifiable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let title: String
    /// 必须写清这个点是"发现时车在哪"，不是"故障发生地"
    let detail: String
    let cls: String
}

/// 一个轮胎。**只有真的读到压力时才存在** —— 没有读数就不占位（不摆 `--`）。
struct MapTyre: Identifiable {
    /// 左前 / 右前 / 左后 / 右后（屏幕方位，与车头朝向无关）
    let label: String
    /// kPa 读数。来自 control 接口的 LfTyrePressure 等字段。
    let kpa: String
    /// 车端自己置的报警位（LfPressureWarning > 0），不是我们拿阈值猜的
    let warn: Bool
    var id: String { label }
}

/// 热区：一段真实生活里的"常来之地"。完全由停车史聚类得出 ——
/// 半径是几何的产物（组内最大间距加 60m 缓冲），次数是数据本身。
/// 没有停车史就没有热区，一个都不编。
struct MapHotspot: Identifiable {
    let id: String
    let center: CLLocationCoordinate2D
    let radiusMeters: Double
    let visits: Int
    let lastVisit: Date
}

/// 附近充电站（MKLocalSearch 的真实结果）
struct MapCharger: Identifiable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let name: String
    let distanceMeters: Double
    let isEVCharger: Bool

    var distanceText: String {
        distanceMeters < 1000
            ? "\(Int(distanceMeters.rounded())) m"
            : String(format: "%.1f km", distanceMeters / 1000)
    }
}

/// 一句"为什么"。**每一句都必须由真实字段推出** —— 这是这一屏的立身之本。
/// 如果推不出来，就不显示；宁可少一行，也不写一句台词。
struct MapReason: Identifiable {
    let id: String
    let text: String
    let cls: String
}

// MARK: - 视图数据
struct MapSpineData {
    // 车
    var carCoordinate: CLLocationCoordinate2D?
    var headingDeg: Double
    var headingText: String
    var address: String
    var gpsText: String
    var gpsCls: String
    var satAlt: String

    // 电量与充电
    var socPct: Int
    var socCls: String
    var rangeText: String
    var chargeText: String
    var chargeCls: String
    var charging: ChargingSession?
    var timeToFull: String?
    var avgConsumption: String?

    // 车辆本身
    var carName: String
    var online: OnlineState
    var updated: String

    // 图上元素
    var trips: [MapTripLine]
    var holds: [MapHoldPoint]
    var issues: [MapIssue]
    var reasons: [MapReason]
    /// 四轮胎压。空数组 = 这一刻没有真实读数（整行不出现）
    var tyres: [MapTyre]
    /// 常停热区。空数组 = 停车史还不够聚出一个圈（一个都不编）
    var hotspots: [MapHotspot]

    /// 有没有位置：没有位置时所有"地方类"内容都必须退场，不能画在(0,0)
    var hasLocation: Bool { carCoordinate != nil }

    /// 最近一次上报到现在（用于"数据有多新"）
    var updatedText: String { updated.isEmpty ? "--" : updated }

    /// 剩余续航（**米**，地图画圈用）。
    ///
    /// ⚠️ 车端那个字段的单位是**公里**，不是米 —— 这不是猜的：
    ///   · `API-FIELD-MAP.md` 里写着（`remainedPowerMile` 样例 `204`，「剩余续航 km」，
    ///     charge 与 control 两个接口一致）；
    ///   · 卡里那一格一直按 km 显示（同一个数「续航 243 km」）。
    ///
    /// 原先这里直接把它当米用 —— 于是「续航圈」在地图上只有两百多米：
    /// 一个 243 km 的圈在当前缩放下**根本看不见**，而那个小圈看起来正好像
    /// 「定位误差圈」（2026-09-25 第十一轮，对着用户那张截图核出来的）。
    /// 单位也是「同一件事实」：换算只在这一处，别处不许再乘一次。
    ///
    /// 车没报就是 nil —— 续航圈不画。（AppStore 是 @MainActor，这里也必须标）
    @MainActor
    var rangeMeters: Double? {
        let cache = AppStore.shared.caches
        for key in ["charge", "control"] {   // 与 VM.energy 取 range 的顺序一致
            if let n = ciNumber(ciVal(cache, key), ["RemainedPowerMile"]), n > 0 {
                return n * 1_000        // km → m（唯一一处换算）
            }
        }
        return nil
    }

    /// 此刻的光：由**车所在的经纬度 + 真实时刻**算出（太阳位置是纯数学，不联网）。
    /// 没有车的位置就没有光 —— 不拿设备自己的位置冒充车的位置。
    /// @MainActor：天气快照住在 `WeatherService`（@MainActor）里。
    @MainActor
    var sky: SkyLight? { sky(at: Date()) }

    /// 指定时刻的光（「拖着看一整天的光」用；不带参数就是此刻）。
    @MainActor
    func sky(at date: Date) -> SkyLight? {
        guard let c = carCoordinate else { return nil }
        // 只有「看此刻」才让天气参与：那份实况是**现在**的云量，
        // 把它挂到滑块拖出的早上 6 点就是造假 —— 回放时刻一律用晴空模型。
        let isNow = abs(date.timeIntervalSinceNow) < 60
        return SkyLight.now(at: date,
                            coordinate: c,
                            weather: isNow ? WeatherService.shared.current : nil)
    }

    // 【已删】`placeLabel`（2026-09-25）。它原本是**地图上那句大字地名**：
    // 把车端上报的地址截到 7 个字（「听涛观海龙台」之类），长了带省略号。
    //
    // 删它的原因不是它写错了，是**它唯一的读者没了**：那个读者是
    // `MapSpineView.mapPlaceLabel`（左上角、安全区下 108pt 的那行衬线大字），
    // 用户 2026-09-25 第 2 条点名把它删掉（「地图页最上面的位置没删」）。
    // 地图本身就在画地名，卡里的地址说的是同一个地方 —— 第三种说法。
    //
    // 留着它的后果与 `DS.swift` 里删「纸页外壳」时记的那条一样：
    // **一件已经没有读者的东西，下一个写这一页的人会拿它当模板。**
    // 地址那个字段（`address`）还在，且仍有读者（抽屉正文的第一行）；被删的只是
    // 「把它截成 7 个字」这一个转写。

    // -------------------------------------------------------------------------
    // MARK: 组装
    // -------------------------------------------------------------------------
    /// 从真实状态组装。**@MainActor**：AppStore 是 @MainActor @Observable，
    /// 在别处读它的属性会直接编译不过（不是风格问题）。
    @MainActor
    static func build() -> MapSpineData {
        let store = AppStore.shared
        let cache = store.caches
        let e = VM.energy(cache, store.car)
        let loc = VM.locStatus(cache)
        let chips = VM.bodyStatus(cache)
        let car = store.currentLocation

        // ---- 行程（起终点连线）----
        let trips: [MapTripLine] = store.tripHistory.compactMap { t in
            guard let a = t.startLocation?.coordinate, let b = t.endLocation?.coordinate else {
                return nil   // 缺任一端的行程画不出来 —— 不猜、不补、不画在(0,0)
            }
            return MapTripLine(
                id: t.id.uuidString,
                from: a, to: b,
                startedAt: t.startTime,
                endedAt: t.endTime,
                distanceKm: t.distanceKm,
                startSoc: t.startSoc,
                endSoc: t.endSoc,
                efficiency: t.avgEfficiency,
                kmPerPercent: t.kmPerPercent
            )
        }

        // ---- 停车点 ----
        var holds: [MapHoldPoint] = []
        if let p = store.parkingLocation {
            holds.append(MapHoldPoint(
                id: "latest",
                coordinate: p.coordinate,
                address: store.parkingHistory.first?.address ?? "上次停车位置",
                time: store.lastParkingTime ?? Date(),
                isLatest: true
            ))
        }
        holds += store.parkingHistory.enumerated().compactMap { idx, rec in
            // 与"最近一次"重合的跳过，避免同一个点画两个钉
            if let p = store.parkingLocation,
               p.distance(from: rec.location) < 25 { return nil }
            return MapHoldPoint(
                id: "h\(idx)",
                coordinate: rec.location.coordinate,
                address: rec.address,
                time: rec.time,
                isLatest: false
            )
        }

        // ---- 异常点（挂在车的位置，文案写清是"发现时车在这儿"）----
        var issues: [MapIssue] = []
        if let c = car {
            for chip in chips where chip.ok == false {
                issues.append(MapIssue(
                    id: chip.id,
                    coordinate: c.coordinate,
                    title: "\(chip.label)\(chip.text.isEmpty ? "" : " · \(chip.text)")",
                    detail: "最后一次上报时车在这儿",
                    cls: chip.cls
                ))
            }
        }

        // 胎压：一次算好，既喂「为什么」也喂面板上那一行
        let tyreList = tyres(cache)

        // ---- 常停热区：停车史聚出来的"生活圈"，没有史就一个不画 ----
        let hotspots = clusterHotspots(from: store.parkingHistory,
                                       excluding: store.parkingLocation)

        return MapSpineData(
            carCoordinate: car?.coordinate,
            headingDeg: Double(loc.degNum),
            headingText: loc.dir,
            address: loc.addr.isEmpty ? "--" : loc.addr,
            gpsText: loc.gpsText,
            gpsCls: loc.gpsCls,
            satAlt: loc.satAlt,
            socPct: e.socPct,
            socCls: e.socCls,
            rangeText: e.range,
            chargeText: e.chargeText,
            chargeCls: e.chargeCls,
            charging: e.charging,
            timeToFull: e.timeToFull,
            avgConsumption: e.avgConsumption,
            carName: e.carName.isEmpty ? "我的车" : e.carName,
            online: e.online,
            updated: e.updated,
            trips: trips,
            holds: holds,
            issues: issues,
            reasons: reasons(e: e, loc: loc, chips: chips, trips: trips, tyres: tyreList,
                             hotspots: hotspots, store: store),
            tyres: tyreList,
            hotspots: hotspots
        )
    }

    // -------------------------------------------------------------------------
    // MARK: 为什么
    // -------------------------------------------------------------------------
    /// 「为什么」不写在别处，就从这几个真实字段推。
    /// 推不出来的情形一律**不输出**（例如没有 GPS 就不谈位置；没有行程就不谈最近一段）。
    @MainActor
    private static func reasons(
        e: EnergyModel,
        loc: LocModel,
        chips: [StatusChip],
        trips: [MapTripLine],
        tyres: [MapTyre],
        hotspots: [MapHotspot],
        store: AppStore
    ) -> [MapReason] {
        var out: [MapReason] = []

        // ① 位置：GPS 有效性 + 车头朝向
        if !loc.addr.isEmpty {
            out.append(MapReason(
                id: "loc",
                text: "车停在 \(loc.addr)；\(loc.gpsText)，车头朝\(loc.dir)（\(loc.deg)）",
                cls: loc.gpsCls
            ))
        } else if loc.gpsCls != "na" {
            out.append(MapReason(id: "loc", text: "收到了坐标但没解析出地址；\(loc.gpsText)", cls: loc.gpsCls))
        }

        // ② 电量：低于 20% 时才解释"还能去哪"
        if e.socPct < 20, e.range != "--" {
            out.append(MapReason(
                id: "soc",
                text: "电量 \(e.socPct)%，只剩 \(e.range)",
                cls: "warn"
            ))
        }

        // ③ 充电：为什么这么慢 / 还要多久
        if let s = e.charging {
            if let full = e.timeToFull {
                out.append(MapReason(
                    id: "charge",
                    text: "正在充电：\(s.power)，充满还要 \(full)",
                    cls: "ok"
                ))
            } else {
                out.append(MapReason(id: "charge", text: "正在充电：\(s.power)", cls: "ok"))
            }
        }

        // ④ 车身：几个没关好的部件
        let bad = chips.filter { $0.ok == false }
        if !bad.isEmpty {
            let names = bad.map { "\($0.label)\($0.text)" }.joined(separator: "、")
            out.append(MapReason(
                id: "body",
                text: "\(names) —— 这一条是此刻的读数，不是历史",
                cls: "bad"
            ))
        }

        // ⑤ 最近一段行程：花了几个百分点走了多远
        if let t = trips.first {
            // 能效只用**算得出来**的那个口径：kWh/100km 需要电池容量（null），
            // 所以实际显示的是「每 1% SOC 跑多少 km」。
            let eff = t.efficiency.map { String(format: "，%.1f kWh/100km", $0) }
                ?? t.kmPerPercent.map { String(format: " · %.1f km / 1%% SOC", $0) }
                ?? ""
            let km = String(format: "%.1f", t.distanceKm)
            out.append(MapReason(
                id: "trip",
                text: "最近一段 \(t.timeText)：\(km) km，电量 \(t.startSoc)% → \(t.endSoc)%\(eff)",
                cls: t.distanceKm > 0 ? "na" : "warn"
            ))
        }

        // ⑥ 保养：距下一次还有多少公里。
        // 唯一来源是 store.maintenancePlan —— 服务端已经给了这套计划
        // （maintainSpaceMileage 20000 + lastMaintainMileage 20100），
        // 不再用硬编码的 10000 km 与只在本机记过才存在的里程。
        if let plan = store.maintenancePlan {
            let src = plan.fromServer ? "" : "（本机记录）"
            out.append(MapReason(
                id: "service",
                text: plan.remaining > 0
                    ? "距下次保养还有 \(plan.remaining) km（上次 \(plan.last) km，间隔 \(plan.interval) km）\(src)"
                    : "已超过保养里程 \(abs(plan.remaining)) km\(src)",
                cls: plan.remaining > 0 ? "na" : "warn"
            ))
        }

        // ⑦ 停放时长：只有真存过停车时间才说
        if let t = store.lastParkingTime {
            out.append(MapReason(id: "hold", text: "上次标记停车：\(agoText(t))", cls: "na"))
        }

        // ⑦.5 数据龄期：车端最后一次上报是什么时候。
        // 这一条不是「锦上添花」：服务端只回放车端最后一次上报的快照，车端停报时
        // 页面上每个数字都还是那一刻的，而它们看上去都像「现在」。
        // 本次抓包就是活例：刷新发生在 09:56，而车端最后一次上报是 07:19:28。
        if let age = VM.reportAge(ciVal(store.caches, "control")) {
            out.append(MapReason(
                id: "freshness",
                text: age.stale
                    ? "车端已 \(age.text)没上报：下面的数字是那一刻的，不是现在"
                    : "车端 \(age.text)上报过一次，这些数字是新的",
                cls: age.stale ? "warn" : "na"
            ))
        }

        // ⑦.7 告警总灯：车端自己置的报警位 + 服务端给的最高等级。
        // 只在**真的亮着**的时候才出现 —— 一条「无报警」每次刷新都重复一遍，
        // 只会训练人忽略这一栏。
        let alarms = VM.activeAlarms(store.caches)
        let alarmLevel = VM.maxAlarmLevel(store.caches)
        if !alarms.isEmpty || alarmLevel != nil {
            var parts: [String] = []
            if !alarms.isEmpty { parts.append("\(alarms.count) 个报警位亮着：" + alarms.joined(separator: "、")) }
            if let lv = alarmLevel { parts.append("服务端最高等级 \(Int(lv))") }
            out.append(MapReason(
                id: "alarm",
                text: parts.joined(separator: "；") + "（车端自报）",
                cls: alarms.isEmpty ? "warn" : "bad"
            ))
        }

        // ⑧ 胎压：有真实读数才谈；报警的轮位单独列出来，没报警就只报四条读数
        let warned = tyres.filter { $0.warn }
        if !warned.isEmpty {
            let names = warned.map { "\($0.label) \($0.kpa) kPa" }.joined(separator: "、")
            out.append(MapReason(
                id: "tyre",
                text: "\(names) —— 这是车端自己置的报警位，不是我们拿阈值猜的",
                cls: "bad"
            ))
        } else if !tyres.isEmpty {
            let all = tyres.map { "\($0.label) \($0.kpa)" }.joined(separator: " / ")
            out.append(MapReason(id: "tyre", text: "四轮胎压 \(all) kPa", cls: "na"))
        }

        // ⑨ 常来之地：≥3 次才值得说（“来过两次”不构成习惯）
        if let top = hotspots.first(where: { $0.visits >= 3 }) {
            out.append(MapReason(
                id: "hot",
                text: "来过 \(top.visits) 次，最近 \(agoText(top.lastVisit))",
                cls: "na"
            ))
        }

        return out
    }

    // -------------------------------------------------------------------------
    // MARK: 常停热区聚类
    // -------------------------------------------------------------------------
    /// 逐点贪心：以每个停车点为核，把 80 米内的同伴收进同一组（间距是停车记录之间
    /// 的真实距离，够近的记录本来就该是同一个目的地）。组内≥2 次才算热区；
    /// 半径取组内各点到质心的最大距离再放宽 60 米 —— 是几何的产物，不是美术。
    static func clusterHotspots(
        from records: [AppStore.ParkingRecord],
        excluding latest: CLLocation?
    ) -> [MapHotspot] {
        var used = Array(repeating: false, count: records.count)
        var out: [MapHotspot] = []

        for i in records.indices where !used[i] {
            used[i] = true
            var group: [Int] = [i]
            for j in records.indices where j != i && !used[j] {
                // 与"最近一次"重合的点本来就没画钉，也不进热区
                if let p = latest, p.distance(from: records[j].location) < 25 { continue }
                if records[j].location.distance(from: records[i].location) <= 80 {
                    used[j] = true
                    group.append(j)
                }
            }
            guard group.count >= 2 else { continue }

            var lat = 0.0, lng = 0.0
            for j in group {
                lat += records[j].location.coordinate.latitude
                lng += records[j].location.coordinate.longitude
            }
            let center = CLLocationCoordinate2D(latitude: lat / Double(group.count),
                                                longitude: lng / Double(group.count))
            // 质心只造一次（2026-09-25 性能轮）：原来它在 `for j in group` 的**每一轮**里
            // 造一个 —— 同一个坐标造了 group.count 次。几何与结果一字未改。
            let centerLoc = CLLocation(latitude: center.latitude, longitude: center.longitude)
            var maxMeters = 0.0
            for j in group {
                maxMeters = max(maxMeters, records[j].location.distance(from: centerLoc))
            }
            let newest = group.map { records[$0].time }.max() ?? records[i].time
            out.append(MapHotspot(
                id: "hot-\(Int(center.latitude * 10000))-\(Int(center.longitude * 10000))",
                center: center,
                radiusMeters: maxMeters + 60,
                visits: group.count,
                lastVisit: newest
            ))
        }
        return out.sorted { $0.visits > $1.visits }
    }

    /// 胎压：复用 `VM.tyreStatus`（与 Analysis / 旧页面同一份读数，不另写一套解析）。
    /// 凡是没真读到的轮位直接不出现 —— 四个轮位全空时返回空数组。
    private static func tyres(_ cache: [String: Any?]) -> [MapTyre] {
        let model = VM.tyreStatus(cache)
        return model.items.compactMap { item in
            let kpa = item.kpa.trimmingCharacters(in: .whitespaces)
            guard !kpa.isEmpty, kpa != "--" else { return nil }
            return MapTyre(label: item.label, kpa: kpa, warn: item.warn)
        }
    }

    // MARK: - 小工具
    /// "3 小时前" 这种相对时间。写成静态是为了让 MapHoldPoint 也能用。
    static func agoText(_ date: Date) -> String {
        let s = Date().timeIntervalSince(date)
        if s < 60 { return "刚刚" }
        if s < 3600 { return "\(Int(s / 60)) 分钟前" }
        if s < 86400 { return "\(Int(s / 3600)) 小时前" }
        return "\(Int(s / 86400)) 天前"
    }
}

// =============================================================================
// MARK: - 充电站聚合（地图上的标注聚合）
// =============================================================================
//
// 为什么必须做：搜索半径 8km 内搜出来的站可能有几十个，**全画出来就是一片钉子**。
// 改之前是 `prefix(12)` 的权宜 —— 既画不全，也说不清为什么是 12 个。
//
// 判据是地理的，不是美术的：两站地面距离 ≤ 400m 归为一组（贪心，先近后远），
// 组的坐标取组内成员的重心（成员越多自然越落在中间），计数是这一组**真实的站数**。
// 组内离车最近的那一个单独留着 —— 点开时必须说得出名字。
struct MapChargerCluster: Identifiable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let count: Int
    let nearest: MapCharger
}

extension MapSpineData {
    /// 400m 内两两合并。距离用 `CLLocation.distance(from:)`（与停车热区同一套算法）。
    static func clusterChargers(_ chargers: [MapCharger],
                                radiusMeters: Double = 400) -> [MapChargerCluster] {
        var out: [MapChargerCluster] = []
        // 与 `out` 一一平行的 CLLocation（2026-09-25 性能轮）。
        //
        // 原来那句判据是 `out.firstIndex(where: { CLLocation(...).distance(from: here) ... })`
        // —— 也就是**每一次比较**都现造一个 CLLocation：一枚钉子 × 已有的每一组。
        // 几十个站时就是几百次分配，而它跑在每次求值的地图图层里。
        // 现在每个站/每个组各造一次（O(n) 而不是 O(n × 组数)），比较用的还是
        // `CLLocation.distance(from:)` 本尊 —— **判据与分组结果一字未改**。
        var outLoc: [CLLocation] = []
        for c in chargers.sorted(by: { $0.distanceMeters < $1.distanceMeters }) {
            let here = CLLocation(latitude: c.coordinate.latitude, longitude: c.coordinate.longitude)
            if let i = outLoc.firstIndex(where: { $0.distance(from: here) <= radiusMeters }) {
                let old = out[i]
                let n = Double(old.count)
                // 重心与原式逐位相同（同一串运算、同一个顺序）。
                let center = CLLocationCoordinate2D(
                    latitude: (old.coordinate.latitude * n + c.coordinate.latitude) / (n + 1),
                    longitude: (old.coordinate.longitude * n + c.coordinate.longitude) / (n + 1)
                )
                out[i] = MapChargerCluster(
                    id: old.id,
                    coordinate: center,
                    count: old.count + 1,
                    nearest: old.nearest
                )
                // 比较用的坐标必须跟着走：下一枚钉子比的是**重心**，
                // 与原来（`where: { $0.coordinate ... }` 读 `out[i]`）一模一样。
                outLoc[i] = CLLocation(latitude: center.latitude, longitude: center.longitude)
            } else {
                out.append(MapChargerCluster(id: c.id, coordinate: c.coordinate, count: 1, nearest: c))
                outLoc.append(here)
            }
        }
        return out
    }
}
