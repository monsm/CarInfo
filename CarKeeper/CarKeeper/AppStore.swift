import SwiftUI
import Observation
import Foundation
import CoreLocation
import Intents
import UserNotifications
import LocalAuthentication
import CoreHaptics
import AVFoundation
import Photos

// 全局应用状态（对应小程序 app.js 的 globalData）。
// 使用 @Observable 宏（iOS 17+）做细粒度响应式更新。

@MainActor
@Observable
final class AppStore: @unchecked Sendable {
    static let shared = AppStore()

    // 登录态
    var isLoggedIn: Bool = false
    var phone: String = ""
    var cars: [[String: Any]] = []
    var carId: String = ""
    var car: [String: Any]? = nil
    var user: [String: Any]? = nil

    // 最近一次 API 响应（charge / pm25 / location / control / check / messages）。
    //
    // **这里不是缓存**：不做 TTL、不跨启动落盘、失败不保留旧值。
    // 它只装「刚刚从接口拿到的那一份」，所以界面上的每个数字都能追溯到一次真实响应；
    // 某个源这次没取到，就把它清掉，让界面显示自己的空/失败态 ——
    // 而不是继续端着上一次的读数（那才是缓存，也是「看着是数据其实早过期」的来源）。
    var caches: [String: Any?] = [
        "charge": nil, "pm25": nil, "location": nil,
        "control": nil, "check": nil, "messages": nil
    ]

    /// 每个数据源**最后那次真的拿到了**的时刻。键与 `caches` 相同。
    ///
    /// 它回答的是界面上一句很容易说错的话：「这个 68% 是什么时候的？」
    /// 不记这个时刻，卡片就只能显示“有读数”，读者无法判断它是不是几分钟前那一份。
    /// （它**不是 TTL**：不过期、不落盘、不拦请求 —— 只用来在卡头上标一个时间。）
    /// 唯一的写入点是 `saveCache`，它也是 `caches` 唯一的写入点。
    private var cacheTimes: [String: Date] = [:]

    /// 某个数据源最后一次真拿到值的时刻。没拿到过就是 nil。
    func cacheTime(_ key: String) -> Date? { cacheTimes[key] }

    /// 最近一次取数里**没取到**的那几个源（键名，已排序）。
    ///
    /// 它只服务一件事：手动「全局刷新」之后那一句反馈（见 `RefreshLoop.refreshAll`）。
    /// 「刷新完了」与「刷新完了但有 3 项没取到」对用户是两件完全不同的事 ——
    /// 而自动那趟不该弹任何东西（每 2 秒弹一次，那就是噪音）。
    private(set) var lastMissedSources: [String] = []

    // 上一次已经喊过「位置变了」的坐标（`.locationUpdated` 的去重门槛）。
    // 初始是 NaN，所以第一条定位报文一定会被判为「动了」—— 第一次总要喊。
    private var lastPostedLat = Double.nan
    private var lastPostedLng = Double.nan

    // #9 控制命令历史记录
    var commandHistory: [HistoryEntry] = []
    struct HistoryEntry: Identifiable {
        let id = UUID()
        let cmd: String
        let name: String
        let startedAt: Date
        let finishedAt: Date?
        let success: Bool
        /// 车端是否给出了**可识别**的回执结果。
        /// `false` = 指令发出去了、但结果未知（60 秒没等到终态，或服务端的状态值我们还不认识）——
        /// 这种情况既不是成功也不是失败，界面要显示成「未确认」，不能沿用「失败」。
        let confirmed: Bool
        let duration: TimeInterval  // 执行耗时（秒）

        // 颜色只能从令牌来：`.green` / `.red` 在四套艺术主题里都不会跟着变。
        var statusColor: Color {
            if !confirmed { return TokensPalette.warning }
            return success ? TokensPalette.success : TokensPalette.error
        }
        var iconName: String {
            if !confirmed { return "questionmark.circle.fill" }
            return success ? "checkmark.circle.fill" : "xmark.circle.fill"
        }
        var resultText: String {
            if !confirmed { return "未确认" }
            return success ? "成功" : "失败"
        }
        var statusCls: String {
            if !confirmed { return "na" }
            return success ? "ok" : "bad"
        }
        // 一条车控指令通常是几秒到几十秒。原来这里一律按分钟显示，
        // 于是每一次都是「0min」—— 看起来像数据，其实是把秒数除没了。
        var durationText: String {
            guard duration > 0 else { return "--" }
            if duration < 60 { return String(format: "%.1fs", duration) }
            return "\(Int(duration / 60))min"
        }
    }

    func addCommandHistory(cmd: String, name: String, success: Bool,
                           duration: TimeInterval, confirmed: Bool = true) {
        commandHistory.insert(HistoryEntry(cmd: cmd, name: name,
                                          startedAt: Date().advanced(by: -duration),
                                          finishedAt: Date(), success: success,
                                          confirmed: confirmed, duration: duration), at: 0)
        // 只保留最近 50 条
        if commandHistory.count > 50 { commandHistory = Array(commandHistory.prefix(50)) }
    }

    // #16 维保里程记录（UserDefaults 持久化）
    nonisolated static let lastServiceMileageKey = "carkeeper_last_service_mileage"

    /// 车端当前里程。唯一写入点是 `recordHistory()`（读 `control.totalOdometer`），
    /// 读取点有 DevView 与保养提醒。写成常量是因为「同一个键名字符串散在三处」
    /// 早晚会有一处拼错 —— 拼错不会报错，只会安静地读回 0。
    nonisolated static let currentMileageKey = "carkeeper_current_mileage"

    /// 上次选中的车辆 id（重启后恢复，否则每次都跳回第一辆）
    nonisolated static let selectedCarIdKey = "carkeeper_selected_car_id"

    // 这里曾有 `appGroupId = "group.com.you.CarKeeper"`：小组件 / 表盘 / 灵动岛读快照用的
    // 共享容器。App Group 是免费账号拿不到的能力，而读它的那三个扩展已全部删除 ——
    // 保留一个没有任何读者的容器 id 只会误导下一处改动。
    var lastServiceMileage: Int {
        get { UserDefaults.standard.integer(forKey: Self.lastServiceMileageKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.lastServiceMileageKey) }
    }
    nonisolated static let defaultServiceInterval: Int = 10000  // 默认保养间隔 10000 km

    // #40 维保价格估算
    nonisolated static let servicePriceEstimate: Int = 800  // 默认保养价格 800 元
    static let majorServicePriceEstimate: Int = 2500  // 大保养价格 2500 元

    // #13 能耗历史（每次刷新记录 SOC + range）
    struct EnergyRecord: Identifiable {
        let id = UUID()
        let timestamp: Date
        let soc: Int
        let range: Int
    }
    var energyHistory: [EnergyRecord] = []

    // E7 充电功率历史记录
    struct ChargingPowerRecord: Identifiable {
        let id = UUID()
        let time: Date
        let power: Double // kW
    }
    var chargingPowerHistory: [ChargingPowerRecord] = []

    // #NEW-2 驾驶行程记录
    struct TripRecord: Identifiable {
        let id = UUID()
        let startTime: Date
        let endTime: Date?
        let startLocation: CLLocation?
        let endLocation: CLLocation?
        let distanceKm: Double
        var durationText: String {
            let dur = (endTime?.timeIntervalSince(startTime) ?? 0) / 60
            return dur > 0 ? "\(Int(dur))min" : "--"
        }
        let startSoc: Int
        let endSoc: Int
        /// kWh/100km。**需要电池容量**才算得出，而报文里的 `capacity` 是 `null` ——
        /// 所以这个字段目前为 nil（以前硬编码 15 kWh 算出一个假数字）。
        let avgEfficiency: Double?
        /// 每 1% SOC 跑了多少 km —— **不需要容量**的口径，因此是目前唯一真算得出的能效指标。
        let kmPerPercent: Double?
    }
    var tripHistory: [TripRecord] = []
    /// 正在进行的行程。`startMileage` 来自点火那一刻的 `control.totalOdometer`，
    /// 它和熄火时的里程相减就是这一段真跑了多远（没有它就只能猜）。
    private var currentTrip: (startTime: Date, startSoc: Int,
                              startLocation: CLLocation?, startMileage: Int?)? = nil

    // #NEW-1 停车位置
    var parkingLocation: CLLocation? {
        get { if let data = UserDefaults.standard.data(forKey: "carkeeper_parking_loc"), let loc = try? NSKeyedUnarchiver.unarchivedObject(ofClass: CLLocation.self, from: data) { return loc } else { return nil } }
        set {
            guard let loc = newValue else {
                // ⚠️ 传 nil 必须真的清掉，否则停车位置永远删不掉
                UserDefaults.standard.removeObject(forKey: "carkeeper_parking_loc")
                return
            }
            if let data = try? NSKeyedArchiver.archivedData(withRootObject: loc, requiringSecureCoding: true) {
                UserDefaults.standard.set(data, forKey: "carkeeper_parking_loc")
            }
        }
    }
    var lastParkingTime: Date? {
        get { UserDefaults.standard.object(forKey: "carkeeper_parking_time") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "carkeeper_parking_time") }
    }

    // #NEW-4「上车打卡」已删（2026-09-23）：它的两个键 `carkeeper_last_checkin` /
    // `carkeeper_checkin_count` 与 `checkIn()` **全库零个调用点** —— 写进去之后
    // 没有任何界面读它。一个没有人看的计数就是这一轮要清的东西。

    // #NEW-3 离线模式标记
    var isOfflineMode: Bool = false
    var offlineMessage: String = ""

    /// 跨面交接：出行面点「在图上看看」→ 地图把镜头移到这里（地图消费后清空）。
    /// 用结构体而不是元组：`.onChange(of:)` 需要 `Equatable`。
    /// 注意：本类是 `@Observable` —— 这里**不能**再加 `@Published`，
    /// 两个宏都会合成 `_mapFocus`，重声明直接编译失败（CI 上踩过一次）。
    struct MapFocus: Equatable, Identifiable {
        let lat: Double
        let lng: Double
        let label: String
        var id: String { "\(lat),\(lng)" }
    }
    var mapFocus: MapFocus? = nil

    // #驾驶安全评分 — 只由**行程里真有的事实**推出来（0-100）。没有事实就是 nil。
    // 返回类型是 Int? 是刻意的：早先这里在"没有任何行程"时返回 75，
    // 于是"不知道"和"中等水平"在界面上长得一模一样。不知道就得是不知道。
    var drivingScore: Int? {
        let recent = Array(tripHistory.prefix(10))
        let efforts = recent.compactMap { $0.avgEfficiency }
        let kmPerPct = recent.compactMap { $0.kmPerPercent }
        // 能效分有两套口径，能用哪套取决于我们**真的知道**什么：
        //   ① kWh/100km（优先）：只有知道电池容量时才算得出 —— 目前算不出。
        //   ② 每 1% SOC 跑多少 km：不需要容量。但它只能**与自己比**：
        //      基线取自己最近行程的中位数（车、人、路况、季节都不同，跨车主比没有意义）。
        let efficiencyScore: Int?
        if !efforts.isEmpty {
            // 分母必须是**真有读数的条数**：原来除以 recent.count，
            // 缺读数的行程会把平均值拉低成一个谁也不认识的数。
            let avg = efforts.reduce(0.0, +) / Double(efforts.count)
            efficiencyScore = max(0, min(100, Int(100 - (avg - 15) * 4)))
        } else if kmPerPct.count >= 2, let latest = kmPerPct.first {
            let sorted = kmPerPct.sorted()
            let median = sorted[sorted.count / 2]
            guard median > 0 else { return nil }
            // 比自己的中位数跑得更远＝省；±30% 视为满分/零分。
            let ratio = latest / median
            efficiencyScore = max(0, min(100, Int((ratio - 0.7) / 0.6 * 100)))
        } else {
            // 还没有任何可比的东西 → **不给分**（"不知道"不能长得像"中等水平"）。
            return nil
        }
        guard let efficiencyScore else { return nil }
        guard !recent.isEmpty else { return nil }
        // 短途占比：短途多说明这段时期跑得都不远，不完全是"稳"，所以只占一半权重
        let shortTripRatio = Double(recent.filter { $0.distanceKm < 5 }.count) / Double(recent.count)
        let stabilityScore = Int(shortTripRatio * 50 + 50)
        return max(0, min(100, (efficiencyScore + stabilityScore) / 2))
    }

    // #NEW-6「Siri 快捷指令使用次数」已删（2026-09-23）：它把每个短语被用过几次
    // 写进 UserDefaults（`carkeeper_siri_usage`），唯一用途是在快捷指令页上
    // 多显示一行「已用过 N 次」。那是「本机攒出来的数」里最不重要的一类。
    // 删掉之后快捷指令页只剩两件真事：这个短语是什么、当前用不用得了。

    func recordEnergySnapshot(soc: Int, rangeKm: Int) {
        // 防止重复记录（同一分钟内只记一次）
        let recent = energyHistory.filter { Date().timeIntervalSince($0.timestamp) < 60 }
        guard recent.isEmpty else { return }
        energyHistory.append(EnergyRecord(timestamp: Date(), soc: soc, range: rangeKm))
        // 只保留最近 20 条
        if energyHistory.count > 20 { energyHistory = Array(energyHistory.suffix(20)) }
    }

    // MARK: - 停车点（唯一的写入点是事件流里的「熄火」）
    struct ParkingPoint: Codable {
        let lat: Double
        let lng: Double
        let time: Date
        let address: String
    }
    nonisolated static let parkingPointsKey = "carkeeper_parking_points"

    /// 停车点序列（持久化）。服务端**没有**「停车历史」接口，这些点只能从事件流里攒；
    /// 而以前 `parkingHistory` 是个进程内数组、全库只有读没有写 —— 所以「常停热区」永远是空的。
    var parkingPoints: [ParkingPoint] {
        get {
            guard let data = UserDefaults.standard.data(forKey: Self.parkingPointsKey),
                  let list = try? JSONDecoder().decode([ParkingPoint].self, from: data) else { return [] }
            return list
        }
        set {
            let capped = Array(newValue.suffix(200))
            if let data = try? JSONEncoder().encode(capped) {
                UserDefaults.standard.set(data, forKey: Self.parkingPointsKey)
            }
        }
    }

    // #NEW-1 记录停车位置（`address` 来自事件的 `jumpParam.addrName`）
    func saveParkingLocation(_ location: CLLocation?, at time: Date? = nil, address: String = "") {
        parkingLocation = location
        lastParkingTime = time ?? Date()
        guard let c = location?.coordinate else { return }
        // 同一个地方反复熄火只算一次：与上一个点相距 < 120 m 就当同一次停放
        // （GPS 抖动几十米是常态，逐条追加会把热区淹掉）。
        var points = parkingPoints
        if let last = points.last {
            let d = CLLocation(latitude: last.lat, longitude: last.lng)
                .distance(from: CLLocation(latitude: c.latitude, longitude: c.longitude))
            if d < 120 { return }
        }
        points.append(ParkingPoint(lat: c.latitude, lng: c.longitude,
                                   time: time ?? Date(), address: address))
        parkingPoints = points
    }

    // #NEW-2 开始新行程（唯一的调用方是 `ingestEvents` 里的点火事件）
    /// 为什么带 `at:` / `mileage:`：事件自带**那一刻**的时刻与里程。
    /// 我们是在事后（用户打开 App）才读到这些事件的，用「现在」当起点会把行程算歪。
    func startTrip(_ location: CLLocation? = nil, soc: Int? = nil,
                   at time: Date? = nil, mileage: Int? = nil) {
        let currentSoc = soc ?? (energyHistory.last?.soc ?? 0)
        currentTrip = (startTime: time ?? Date(), startSoc: currentSoc,
                       startLocation: location, startMileage: mileage)
    }

    // #NEW-2 结束行程
    func endTrip(distanceKm: Double, endSoc: Int? = nil,
                 endLocation: CLLocation? = nil, at time: Date? = nil) -> TripRecord? {
        guard let trip = currentTrip else { return nil }
        let endSoc = endSoc ?? (energyHistory.last?.soc ?? 0)
        let socUsed = trip.startSoc - endSoc
        // 每 1% SOC 多少 km：不需要电池容量。原来用硬编码的 15 kWh 算 kWh/100km，
        // 算出来的是「假设」而不是读数，所以那个字段现在老实返回 nil。
        let kmPerPercent: Double? = (socUsed > 0 && distanceKm > 0)
            ? distanceKm / Double(socUsed) : nil
        let record = TripRecord(
            startTime: trip.startTime,
            endTime: time ?? Date(),
            startLocation: trip.startLocation,
            endLocation: endLocation,
            distanceKm: distanceKm,
            startSoc: trip.startSoc,
            endSoc: endSoc,
            avgEfficiency: nil,
            kmPerPercent: kmPerPercent
        )
        tripHistory.insert(record, at: 0)
        if tripHistory.count > 50 { tripHistory = Array(tripHistory.prefix(50)) }
        currentTrip = nil
        return record
    }

    // MARK: - 事件 → 行程（这是**唯一**的行程生成器）
    //
    // 消息事件流里已经有：点火/熄火、那一刻的坐标、地址、毫秒时刻。
    // 把它们配成对就是一段行程的骨架；行程里程用点火与熄火两次的
    // `control.totalOdometer` 相减。
    //
    // ⚠️ 没有轨迹点。`isPrivacyDrvingHistory: 1` 说明车端根本不上传行驶轨迹，
    // 所以只能给「起点 + 终点 + 停留」，**绝不能画一条连线当成走过的路**。

    /// 已处理事件（`stubId`）。服务端每次都把同一个 7 天窗口整段返回，
    /// 同一条点火事件会被反复读到 —— 不去重就会每次刷新都多出几段重复行程。
    /// `stubId`（`1:<uuid>:<时间戳>:<序号>`）正是服务端给的幂等键。
    private var processedEventIds: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "carkeeper_processed_event_ids") ?? []) }
        set { UserDefaults.standard.set(Array(newValue.suffix(2000)),
                                        forKey: "carkeeper_processed_event_ids") }
    }

    /// `jumpParam` 是一段**被包在字符串里的 JSON**，事件的机器可读字段在这里：
    /// `gpsTime` / `lat` / `lng` / `addrName` / `eventActionTime` / `flameoutReason`。
    /// 消息正文（`content`）是给人读的中文句子，不能当数据源用。
    nonisolated static func jumpParams(_ m: [String: Any]) -> [String: Any] {
        guard let raw = ciString(m, ["JumpParam", "jumpParam"]), !raw.isEmpty,
              let obj = jsonToAny(raw) else { return [:] }
        return (obj["uriParams"] as? [String: Any]) ?? obj
    }

    /// 把消息事件流喂给行程生成器（幂等：已处理过的 `stubId` 直接跳过）。
    func ingestEvents(_ messages: [[String: Any]]) {
        guard !carId.isEmpty else { return }
        var seen = processedEventIds
        let events = messages.compactMap { m -> (id: String, ignition: Bool, at: Date,
                                                  loc: CLLocation?, addr: String)? in
            guard let kind = ciString(m, ["InfoTypeId", "infoTypeId"])?.uppercased(),
                  kind == "IGNITION" || kind == "FLAMEOUT" else { return nil }
            let id = ciString(m, ["StubId", "stubId"]) ?? ciString(m, ["Id", "id"]) ?? ""
            guard !id.isEmpty, !seen.contains(id) else { return nil }
            let p = Self.jumpParams(m)
            guard let at = VM.serverDate(p["gpsTime"])
                    ?? VM.serverDate(ciPick(m, ["CreatedAt", "createdAt"])) else { return nil }
            var loc: CLLocation?
            if let lat = VM.vnum(p["lat"]), let lng = VM.vnum(p["lng"]) {
                loc = CLLocation(latitude: lat, longitude: lng)
            }
            return (id, kind == "IGNITION", at, loc, (p["addrName"] as? String) ?? "")
        }
        // 报文里消息是**倒序**（最新在前）：顺序弄反就会把熄火当成点火。先按时刻升序。
        let ordered = events.sorted { $0.at < $1.at }
        guard !ordered.isEmpty else { return }

        let soc = ciNumberInt(ciVal(caches, "charge"), ["RemainPower"])
        let mileage = ciNumber(ciVal(caches, "control"), ["TotalOdometer"]).map { Int($0.rounded()) }
        for e in ordered {
            seen.insert(e.id)
            if e.ignition {
                startTrip(e.loc, soc: soc, at: e.at, mileage: mileage)
            } else {
                // 里程差只在「点火与熄火发生在同一次会话内」时才真实：
                // 如果是几天前的历史事件，两端的 currentMileage 都是今天的值，
                // 差值会是 0 —— 那就写 0，不编一个「估算里程」。
                let km: Double
                if let start = currentTrip?.startMileage, let end = mileage, end >= start {
                    km = Double(end - start)
                } else {
                    km = 0
                }
                _ = endTrip(distanceKm: km, endSoc: soc, endLocation: e.loc, at: e.at)
                saveParkingLocation(e.loc, at: e.at, address: e.addr)
            }
        }
        processedEventIds = seen
    }

    // `unreadMessageCount` 已删：它**永远返回 0**，而且全仓零个读取点 ——
    // 未读数由消息那一节自己按本地已读状态算（`MessagesSection`）。

    // #NEW-7 控制中心快速车况数据（供 ControlCenter 扩展使用）
    struct CCQuickStatus {
        var soc: Int = 0
        var range: String = "--"
        var locked: Bool = true
        var cabinTemp: String = "--"
        var charging: Bool = false
        var online: String = "--"
    }
    func quickStatus() -> CCQuickStatus {
        guard let charge = caches["charge"] as? [String: Any],
              let soc = ciNumberInt(charge, ["RemainPower"]) else { return CCQuickStatus() }
        let rangeStr = ciString(charge, ["RemainedPowerMile"]) ?? "--"
        let ctrl = caches["control"] as? [String: Any]
        // ⚠️ 官方报文里没有 DoorLocked / InteriorTemperature（小程序 0 处引用）：
        // 锁止状态是 DriverDoorLock（0 = 已锁），车内温度在 pm25 报文的 VehicleTemperature 里。
        // 原来读不存在的键 → 恒显示「已锁」+ 温度 "--"。
        let locked = ciNumber(ctrl, ["DriverDoorLock"]).map { $0 == 0 } ?? true
        let temp = VM.n0(ciPick(caches["pm25"] as? [String: Any], ["VehicleTemperature"])) ?? "--"
        let charging = isCharging
        return CCQuickStatus(soc: soc, range: rangeStr, locked: locked, cabinTemp: "\(temp)℃", charging: charging, online: "在线")
    }

    // #4 网络状态追踪
    var networkStatus: NetworkStatus = .online
    enum NetworkStatus: String {
        case online = "在线"
        case weak = "弱网"
        case offline = "离线"
    }
    func updateNetworkStatus(_ status: NetworkStatus) {
        networkStatus = status
    }

    // 【已删】#7 夜间模式自动切换的四个静态量（`nightModeStartHour` / `nightModeEndHour` /
    // `forceDarkMode` / `forceLightMode`，2026-09-25 地毯式审核）。
    // 四个都只有「声明 + 一套没人调用的算法」，而且 `static let` 在这里意味着
    // **进程内只读一次**：用户改了设置也不会变 —— 看起来在算，其实早就算死了。
    // 夜间模式的唯一实现现在在 `NightModeManager`（它自己读那两个 force 键）。

    // #31 省电模式
    static let powerSavingKey = "carkeeper_power_saving"
    var isPowerSaving: Bool {
        get { UserDefaults.standard.bool(forKey: Self.powerSavingKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.powerSavingKey) }
    }

    // #8 PIN码Keychain安全存储
    private static let pinKeychainService = "com.carkeeper.pin"
    private static let pinKeychainAccount = "car_pin"
    // #NEW-101 FaceID/TouchID 生物识别
    private static let biometricSetupKey = "carkeeper_biometric_setup"

    func savePin(_ pin: String) {
        // 编码不出来就**不存**，而不是存一段空数据（那会让「已设置控车码」变成谎话）。
        guard let pinData = pin.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.pinKeychainService,
            kSecAttrAccount as String: Self.pinKeychainAccount,
            kSecValueData as String: pinData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    func readPin() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.pinKeychainService,
            kSecAttrAccount as String: Self.pinKeychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: 1
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func deletePin() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.pinKeychainService,
            kSecAttrAccount as String: Self.pinKeychainAccount
        ]
        SecItemDelete(query as CFDictionary)
    }

    // #NEW-101 生物识别状态
    var hasBiometricSetup: Bool {
        get { UserDefaults.standard.bool(forKey: Self.biometricSetupKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.biometricSetupKey) }
    }

    /// 检查设备是否支持生物识别
    func canUseBiometric() -> Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    /// 使用生物识别验证（FaceID/TouchID）
    func authenticateWithBiometrics(reason: String) async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return false
        }
        do {
            try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )
            return true
        } catch {
            return false
        }
    }

    /// 启用生物识别（首次设置时调用）
    func enableBiometric() {
        hasBiometricSetup = true
    }

    /// 禁用生物识别
    func disableBiometric() {
        hasBiometricSetup = false
    }

    // 【已删】`shouldUseDarkMode()` / `isNightMode` / `forceDarkMode` / `forceLightMode` /
    // `nightModeStartHour` / `nightModeEndHour`（2026-09-25 地毯式审核）。
    //
    // 它们是「现在是不是夜间」的**第二套实现**，而它与 `NightModeManager` 那套的差别还有两处
    // 实错：① 它把 UserDefaults 读进 `static let`（进程内只读一次，改了也不会变 ——
    // 这正是 `delguard` 盯的那种「看起来在算其实早就算死了」）；② 它在全仓**没有任何调用方**
    //（`isNightMode` 也没人读）。明暗的唯一出处是 `NightModeManager.schemeOverride`，
    // `CarKeeperApp` 两个窗口都从那里取 —— 它一度还要与「艺术方向自带的明暗」取一个或，
    // 那套主题 2026-09-25 已整份删除。

    // `#17 请求去重`（`inFlightRequests` + `markRequestStarted` / `markRequestFinished`）
    // 已于 2026-09-25 删除：**全仓零调用**（它当年是给「同一时刻两处点着同一个请求」用的，
    // 而真出这件事的地方后来各自改成了别的写法）。留着它只有一种效果 —— 下一个人读到
    // 「这里有一套去重」，于是以为去重已经有人管了。
    //
    // 现在「同一件事不并发」只有一处机制，就在 `RefreshLoop` 里：一次取数 `await` 完了
    // 才睡下一次（见那个文件的 ①）。两套机制管一件事，等于两套都不可信。

    /// 车在不在**动** —— 最近一次取到的报文里 `VehicleSpeed > 0`。
    ///
    /// 它是刷新节律的输入（地图页 2s / 60s 就是照它分的，见 `RefreshLoop`）。
    /// 解析复用 `VM.driveStatus`：那份模型里的 `isMoving` 原来**没有任何读者**，
    /// 于是「车在不在动」这件事在界面上一次都没被用过（车速是另一条路取的）。
    var isCarMoving: Bool { VM.driveStatus(caches).isMoving }

    // 这里原有 `pendingQuickCtrl`（首页把指令「穿透」给车控页，由车控页执行）。
    // 已删：**全库没有任何地方写入过它** —— 读它的只有车控页的 onAppear，
    // 而首页从来没设过。批 1 之后地图上的操作条直接执行指令，这条路已无必要。

    private init() {
        if let cfg = TokenStore.read(), !cfg.accessToken.isEmpty {
            isLoggedIn = true
            phone = cfg.mobile
        }
    }

    // MARK: 车辆 / 用户

    // #21 冷启动预加载：App 启动时异步预取核心数据
    private var preloadTask: Task<Void, Never>? = nil

    /// 正在飞的那一趟 `bootstrap()`（合并并发调用用，见下）。
    private var bootstrapTask: Task<Void, Never>? = nil

    // #28 Dynamic Island / Live Activity 状态
    var isCharging: Bool {
        guard let charge = caches["charge"] as? [String: Any] else { return false }
        // ciString 同时兼容字符串 "1" 与数字 1 两种返回，避免服务端改类型后状态恒为 false
        let status = ciString(charge, ["ChrgStatus"]) ?? ""
        return status == "1" || status == "2"
    }
    var chargingProgress: Double {
        guard let charge = caches["charge"] as? [String: Any] else { return 0 }
        let soc = ciNumber(charge, ["RemainPower"]) ?? 0
        return min(1.0, max(0.0, soc / 100.0))
    }

    /// 启动取数（车辆列表 + 用户）。**同时飞的那几趟合并成一趟**。
    ///
    /// 启动时有三个地方会调它：根视图 `onAppear` 里两处（一处主取、一处兑底提示）
    /// 加上地图外壳的 `.task`。它们问的是**同一件事**，而在合并之前那是三份真实的
    /// `getCars` + `getUser`，外加三次 `cancel`/重启预加载（每次预加载都是 6 个请求）——
    /// 冷启动头几秒本来就在抢 CPU 与网络，这一下是白白多出来的。
    ///
    /// 合并的边界：只合并**同时**在飞的那几趟。串行的重复调用照旧各取一次 ——
    /// 退出登录后重新登录、以及用户下拉刷新，都应当真的重新问一次服务端。
    func bootstrap() async {
        if let running = bootstrapTask {
            await running.value
            return
        }
        let task = Task { await runBootstrap() }
        bootstrapTask = task
        await task.value
        bootstrapTask = nil
    }

    /// 一趟真正的启动取数（`bootstrap` 只负责让并发调用共用它）。
    private func runBootstrap() async {
        let api = APIClient.shared
        do {
            let carsRes = try await api.getCars()
            let userRes = try await api.getUser()
            self.cars = carsRes
            if let u = userRes { user = u }
            // 优先恢复上次选中的车辆，否则每次重启都会跳回第一辆
            let savedCarId = UserDefaults.standard.string(forKey: Self.selectedCarIdKey) ?? ""
            let picked = self.cars.first { (ciString($0, ["CarId", "carId"]) ?? "") == savedCarId } ?? self.cars.first
            if let first = picked {
                let id = ciString(first, ["CarId", "carId"]) ?? ""
                self.car = first
                self.carId = id
                if !savedCarId.isEmpty { UserDefaults.standard.set(id, forKey: Self.selectedCarIdKey) }
                // #21 冷启动预加载：后台异步拉取所有数据，不阻塞 UI
                preloadTask?.cancel()
                preloadTask = Task {
                    await fetchVehicleData()
                }
            }
        } catch {
            // token 过期 / 刷新失败：静默吞掉会让用户看到空白地图且永远没有消息。
            // 识别这类错误，主动清掉登录态，让用户回到登录页重新走一遍完整流程。
            // 其他错误（弱网、断网）保留现有登录态，下次启动再重试。
            let apiErr = error as? APIError
            if apiErr?.expired == true || error.localizedDescription.contains("token expired") {
                NSLog("bootstrap: token expired — forcing logout")
                logout()
                // logout() 已经清空 isLoggedIn，UI 会自动切到登录页；
                // 这里再发一条 Toast 明确告知原因，避免用户以为 App 坏了。
                Task { @MainActor in
                    ToastManager.shared.show("登录已过期，请重新登录", icon: "exclamationmark.triangle.fill")
                }
            } else {
                NSLog("bootstrap: \(error.localizedDescription)")
            }
        }
    }

    /// 取消预加载任务（用于退出登录等场景）
    func cancelPreload() {
        preloadTask?.cancel()
        preloadTask = nil
    }

    func fetchCore() async {
        guard !carId.isEmpty else { return }
        let results = await gather(carId: carId, includeMessages: false, includeCheck: false)
        saveCache(results)
    }

    func fetchVehicleData() async {
        guard !carId.isEmpty else { return }
        let results = await gather(carId: carId, includeMessages: true, includeCheck: true)
        saveCache(results)
    }

    /// 并行拉取多个数据源。使用 withTaskGroup，子任务失败单独吞掉，
    /// 返回成功的那些键值对（统一装进 [String: Any?]）。`includeMessages`/`includeCheck` 控制是否拉全部。
    private func gather(carId: String, includeMessages: Bool, includeCheck: Bool) async -> [String: Any?] {
        await withTaskGroup(of: (String, Any?).self) { group in
            let api = APIClient.shared
            group.addTask { () -> (String, Any?) in
                return ("charge", try? await api.getCharge(carId: carId))
            }
            group.addTask { () -> (String, Any?) in
                return ("pm25", try? await api.getCarPm25(carId: carId))
            }
            group.addTask { () -> (String, Any?) in
                return ("location", try? await api.getLocation(carId: carId))
            }
            group.addTask { () -> (String, Any?) in
                return ("control", try? await api.getControl(carId: carId))
            }
            if includeMessages {
                group.addTask { () -> (String, Any?) in
                    let r = try? await api.getMessages()
                    return ("messages", r)
                }
            }
            if includeCheck {
                group.addTask { () -> (String, Any?) in
                    return ("check", try? await api.getCarCheck(carId: carId))
                }
            }
            var out: [String: Any?] = [:]
            for await (key, value) in group {
                // 成功的收值，失败的收 nil —— 失败的也必须落进来：
                // 由 saveCache 把那个源清空，界面如实显示「这次没取到」。
                // （早先是「失败就跳过」，于是弱网下界面继续显示上一次的读数 ——
                //  那就是缓存，也正是这一轮要去掉的东西。）
                out[key] = value
            }
            return out
        }
    }

    func saveCache(_ patch: [String: Any?]) {
        lastMissedSources = patch.compactMap { $0.value == nil ? $0.key : nil }.sorted()
        for (k, v) in patch {
            // nil = 这个源本次没取到：清空它。界面自己会说「没取到」，
            // 而不是继续显示上一次的读数（不保留旧值是刻意的 —— 见 caches 上的说明）。
            caches[k] = v
            // 同一时刻记下「这份读数是什么时候拿到的」。清空时也清掉时刻 ——
            // 留着一个时间戳而值是空的，会让卡片显示“有数据但很久没更新”，
            // 而真实情况是「这次没取到」，那是两种不同的状态。
            if v == nil { cacheTimes[k] = nil } else { cacheTimes[k] = Date() }
        }
        // 事件 → 行程：消息缓存是**唯一**的入口（网络与缓存共用同一条路径，
        // 所以「上次打开时拿到的那些事件」也会被补上，不会只算新来的）。
        if let msgs = patch["messages"] as? [[String: Any]] {
            ingestEvents(msgs)
        }
        // #13 记录能耗快照（ciNumberInt 同时兼容字符串与数字两种返回）
        if let charge = patch["charge"] as? [String: Any] {
            let soc = ciNumberInt(charge, ["RemainPower"])
            let range = ciNumberInt(charge, ["RemainedPowerMile"])
            if let soc, let range {
                recordEnergySnapshot(soc: soc, rangeKm: range)
            }
        }
        // #NEW-3 离线判定：真正断网（本次一个数据源都没拿到）且已登录时才提示
        let anySuccess = patch.values.contains { $0 != nil }
        if anySuccess {
            isOfflineMode = false
            offlineMessage = ""
        } else if !patch.isEmpty && isLoggedIn {
            isOfflineMode = true
            offlineMessage = "网络异常"
        }
        // 「车的位置变了」必须真有人喊出来。
        //
        // 此前 `.locationUpdated` 有 **3 个观察者**（地图镜头跟着车走、重取天气、
        // 低电量提示）却**一个 post 都没有** —— 那三条行为从未生效过。
        // 发射点放在这里：location 缓存只从 `saveCache` 进来（`currentLocation`
        // 是计算属性，没有别的写入点）。
        // 带「动了才喊」的门槛（≈5.5 米）：车停着不动时每次刷新都重定位，
        // 会把用户手动拖开的镜头一次次拉回去。
        if let loc = patch["location"] as? [String: Any],
           let lat = ciNumber(loc, ["Lat"]), let lng = ciNumber(loc, ["Lng"]) {
            let moved = !(abs(lat - lastPostedLat) < 0.00005 && abs(lng - lastPostedLng) < 0.00005)
            if moved {
                lastPostedLat = lat
                lastPostedLng = lng
                NotificationCenter.default.post(name: .locationUpdated, object: nil)
            }
        }
        // 把最新车况同步给小组件 / 表盘 / 灵动岛的那一步已删除（见下面 syncSharedDefaults 的说明）
        // 车端时间序列采样（SOC / 充电功率 / 胎压三条趋势曲线的唯一来源）
        recordHistory()
    }

    // MARK: - 车端时间序列采样
    /// 每次拿到车端数据后采样一次。
    /// ⚠️ 服务端只有"当前状态"接口（小程序也一样），曲线只能由 App 自己一点点积累；
    /// 采样间隔与保留上限见 Services/HistoryStore.swift 顶部说明。
    private func recordHistory() {
        guard !carId.isEmpty else { return }
        let e = VM.energy(caches, car)
        let control = ciVal(caches, "control")

        // 充电功率：EnergyModel 里的 power 是给人看的字符串（"7 kW"），曲线要的是数值。
        // 算法只有一份（VM.chargePowerKW）：报文里的 ChargPower / ChargingPower **并不存在**，
        // 真实功率 = totalVoltage × totalCurrent。
        let pow = VM.chargePowerKW(ciVal(caches, "charge"), control)

        // 顺带把功率补进 AppStore 的短历史：实时功耗页与小组件读的都是它，
        // 而它此前**没有任何地方写入过** —— 所以小组件上的功率永远显示 "--"。
        if isCharging, let p = pow, p > 0.1 {
            let due = chargingPowerHistory.last.map { Date().timeIntervalSince($0.time) >= 60 } ?? true
            if due {
                chargingPowerHistory.append(ChargingPowerRecord(time: Date(), power: p))
                if chargingPowerHistory.count > 240 {
                    chargingPowerHistory.removeFirst(chargingPowerHistory.count - 240)
                }
            }
        }

        // 四轮胎压（kPa）：顺序与键名与 VM.tyreStatus 保持一致
        let tyres: [Double?] = ["LfTyrePressure", "RfTyrePressure", "LrTyrePressure", "RrTyrePressure"]
            .map { ciNumber(control, [$0]) }

        HistoryStore.shared.record(socPct: e.socPct, charging: isCharging, powerKW: pow, tyres: tyres)

        // E40 充电状态监控：把这次报文交给它（只在「开始/结束/充满」的跃迁时才会推送）。
        // 在此之前它是个空桩，而壳层只写了 `_ = ChargingStatusMonitor.shared` —— 从没被调用。
        ChargingStatusMonitor.shared.observe(soc: e.socPct, charging: isCharging, powerKW: pow)

        // #NEW-118 维保提醒的真实里程。
        // 里程键是 `totalOdometer`（本车 53766.4，Double）。此前这里读的是
        // `Mileage` / `mileage` / `TotalMileage` —— 三个键**都不存在**，于是
        // `carkeeper_current_mileage` 恒为 0，提醒里永远是「距下次保养 10000 km」，
        // 永远不会触发；手表与小组件的「总里程」也恒为 0。
        if let km = ciNumber(control, ["TotalOdometer"]), km > 0 {
            let intKm = Int(km.rounded())
            let previous = UserDefaults.standard.integer(forKey: Self.currentMileageKey)
            if previous != intKm {
                UserDefaults.standard.set(intKm, forKey: Self.currentMileageKey)
                // 小组件（widget_mileage）与表盘（watch_mileage）读的都是这个属性
                if totalMileage != intKm { totalMileage = intKm }
            }
            // 保养计划：间隔与上次保养里程来自服务端（maintainSpaceMileage /
            // lastMaintainMileage），不再是硬编码的 10000 km。
            if let plan = maintenancePlan, previous != intKm {
                Task { await MaintenanceReminderScheduler.shared.scheduleMaintenanceReminder(
                    lastServiceMileage: plan.last,
                    currentMileage: plan.current,
                    interval: plan.interval) }
            }
        }
    }

    // 这里曾有 `syncSharedDefaults()`：把车况写进 App Group，供小组件（Widgets/）、
    // 表盘（WatchApp/）与灵动岛读取。**2026-09-23 整段删除**，因为那条链路在免费
    // （未缴 99 美元）开发者账号下根本没有一条可用路径：App Group 这个能力拿不到，
    // 侧载重签会把它摘掉；扩展本身也未必被签进包里。于是三个 target、两份共享文件、
    // 三份 entitlements 与 App 侧的这段写入逻辑一并删掉 —— 不再往外写任何快照。
    // 详见 project.yml 里「WidgetBundle / WatchApp / WatchKitApp 三个 target 全删」那一段。

    /// 清空所有数据源（退出登录、切车时用）。
    ///
    /// 这里曾有一对 `isCacheExpired` / `staleKeys`（3 分钟 TTL）与一个 `needsRefresh`：
    /// 它们只用来决定「要不要再请求一次」，而那一套恰恰是缓存思维的产物 ——
    /// 数据只在 TTL 内算数、过期了又舍不得删。现在每个消费者只问一件事：
    /// **这次请求回来了没有**；没回来就显示没回来。
    func clearCache() {
        caches = ["charge": nil, "pm25": nil, "location": nil, "control": nil, "check": nil, "messages": nil]
    }

    // #24 首页卡片自定义排序
    static let cardOrderKey = "carkeeper_home_card_order"

    /// 首页真正实现了渲染的卡片 id 全集。
    /// ⚠️ 首页 `cardStack` 的 switch 里，未列出的 id 会落到 `default:`（原本渲染的是位置卡），
    /// 而默认顺序里曾包含 `energyGauge` —— 它不在 switch 里，于是首页会**多出一张一模一样的位置卡**。
    /// 所以这里给出唯一真源：不在这个列表里的 id 一律在渲染前过滤掉。
    static let knownCardIds: [String] = [
        "socHero", "driveMetrics", "carSelector", "quickControl", "domainCard",
        "realtimeEnergy", "sohDashboard", "driveMode", "batterySection", "vehicle2D",
        "tyreCard", "comfortCard", "carbonSavings", "locationCard"
    ]

    var cardOrder: [String] {
        get {
            if let saved = UserDefaults.standard.array(forKey: Self.cardOrderKey) as? [String] {
                // 过滤掉已不存在 / 拼错的 id（否则会被 switch 的 default 分支误当成位置卡）
                let filtered = saved.filter { Self.knownCardIds.contains($0) }
                return filtered.isEmpty ? Self.knownCardIds : filtered
            }
            return Self.knownCardIds
        }
        set { UserDefaults.standard.set(newValue, forKey: Self.cardOrderKey) }
    }

    // MARK: 登录 / 退出

    func logout() {
        cancelPreload()
        // 退出登录后新账号那一趟取数**必须另起**，不能搭上退出前还在飞的那一趟 ——
        // 搭上了就等于用前一个账号的请求给新账号结账（拿到空列表、或者更糟）。
        // 这里只丢掉句柄：飞行中的请求由它自己的超时结束，不去假装取消得掉。
        bootstrapTask = nil
        // 令牌在 Keychain 里 —— 只删 UserDefaults 那个旧键等于没退出登录。
        TokenStore.clear()
        UserDefaults.standard.removeObject(forKey: cacheStorageKey)
        UserDefaults.standard.removeObject(forKey: Self.selectedCarIdKey)
        deletePin()  // #8 退出时清除Keychain中的PIN
        isLoggedIn = false
        phone = ""
        cars = []
        carId = ""
        car = nil
        user = nil
        clearCache()
        // ⚠️ 以下都是「跟账号绑定」的数据：不清理的话，换账号后
        // 前一个账号的行程轨迹 / 停车位置 / 车控历史 会对新用户直接可见。
        tripHistory = []
        currentTrip = nil
        energyHistory = []
        chargingPowerHistory = []
        commandHistory = []
        // （这里曾有 LiveActivityBridge.endAll() 与 SharedStore.clear()：清掉锁屏实时活动
        //  与小组件快照。两者随小组件体系一并删除，现在 App 不再往外写任何快照。）
        // 趋势曲线同样是这个账号的车端数据：不清理会留给下一个登录的账号
        HistoryStore.shared.clear()
        isOfflineMode = false
        offlineMessage = ""
        parkingLocation = nil
        lastParkingTime = nil
        UserDefaults.standard.removeObject(forKey: Self.lastServiceMileageKey)
        UserDefaults.standard.removeObject(forKey: "carkeeper_parking_time")
        // 家庭成员 / 临时钥匙 / 里程账本 / 保险费 —— 全是跟账号绑定的数据
        FamilyManager.shared.resetAll()
        TempKeyManager.shared.resetAll()
        UserDefaults.standard.removeObject(forKey: "carkeeper_mileage_entries")
        UserDefaults.standard.removeObject(forKey: "carkeeper_insurance_policies")
        // 年检记录：它有 **@Published 内存副本**，只删键不够 —— 同一次运行里下一个账号
        // 仍然看得见前一个账号的年检（把它当教训的同一处：`InspectionCalendar.addInspection`
        // 曾经只存盘、不写回内存，于是「保存年检」当次运行看上去毫无反应）。
        InspectionCalendar.shared.resetAll()
        // ---------------------------------------------------------------------
        // 以下七条是 2026-09-25 第八轮（地毯式对抗式审核）补上的。
        //
        // 它们与上面那些是**同一类**（账号/车辆绑定，判据就是 HANDOFF §6 那张表里的
        // 「退出登录是否清」一列），而这一版之前只清了由它们**派生**的内存数据 ——
        // 于是换账号后分别会出现：
        //
        //   · `parking_points`（最多 200 个停车点，含地址与时间）
        //     → 地图「停车」层的钉与「常停热区」显示的是**前一个账号**去过的地方。
        //       上一版清了停车位置（单数、`parking_loc`）与时间，漏了这个数组 ——
        //       而 `parkingHistory` 是从磁盘现算的，清了内存也不会让它消失。
        //   · `processed_event_ids`（行程去重台账）
        //     → **清派生却留台账**是最坏的一种半清：`tripHistory` 被清空了，
        //       台账里那 7 天窗口的事件仍然是「已处理」，于是同一账号重新登录后
        //       行程页一直是空的（数据再也重建不出来，直到出现新事件）。
        //   · `maintenance_photos`（用户拍的单据照，base64）
        //     → 下一个账号看得见前一个账号的照片。
        //   · `service_reminders` / `current_mileage` / `total_mileage` / `service_timestamp`
        //     → 里程与保养基线是**上一辆车/上一个账号**的，
        //       「距下次保养还有多少公里」跟着错（`last_service_mileage` 上一版已清，
        //       这四个与它是一套，只清一个是清不干净的）。
        //
        // `service_reminders` 清掉后 `ServiceReminderManager.reminders` 会回落到
        // `defaultReminders`（它的定义就是「用户还没有任何记录时的那份底」）。
        // ---------------------------------------------------------------------
        for key in ["carkeeper_parking_points", "carkeeper_processed_event_ids",
                    "carkeeper_maintenance_photos", "carkeeper_service_reminders",
                    "carkeeper_current_mileage", "carkeeper_total_mileage",
                    "carkeeper_service_timestamp"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
        NotificationCenter.default.post(name: .didLogout, object: nil)
    }

    func selectCar(_ idx: Int) {
        guard cars.indices.contains(idx) else { return }
        let c = cars[idx]
        let newId = ciString(c, ["CarId", "carId"]) ?? ""
        // 先更新 carId（触发视图重建，缓存仍在，避免闪烁）
        car = c
        carId = newId
        UserDefaults.standard.set(newId, forKey: Self.selectedCarIdKey)
        // 【已删】#N10「加密保存车牌号」（2026-09-25 地毯式审核）。
        // 它原本把车牌用 AES-GCM 加密后写进 UserDefaults（`enc_plate`），而**全仓没有
        // 一处读它**，写入失败还是静默的（密钥取不到就什么都不写、也不报）。
        // 一个只写不读的备份，加上静默的失败，等于把「敏感数据已加密」变成一句
        // 没人核过的话 —— 要真保存它，得先有读的那一头（以及“读不到时怎么办”）。
        // 随之删掉的还有 `Services/DataEncryption.swift` 与它的 `SecureStorage`。
        // 再清除旧缓存，后台异步拉新车数据
        clearCache()
        Task { await fetchVehicleData() }
    }

    // CloudSyncManager 已删：免费开发者账号没有 iCloud entitlement，
    // 调用 CKContainer 会直接抛 ObjC 异常杀进程。若将来升级付费账号再恢复。


    // #车控命令发送
    func sendControlCommand(_ cmd: String) async -> Bool {
        guard isLoggedIn, !carId.isEmpty else { return false }
        let pin = readPin() ?? ""
        do {
            _ = try await APIClient.shared.sendControlCommand(cmd: cmd, carId: carId, pin: pin)
            addCommandHistory(cmd: cmd, name: cmd, success: true, duration: 0)
            return true
        } catch {
            addCommandHistory(cmd: cmd, name: cmd, success: false, duration: 0)
            return false
        }
    }

    // 当前位置（从缓存 location 取）
    var currentLocation: CLLocation? {
        // ⚠️ 定位报文的键是 Lat / Lng（小程序 home.js 也是 Number(loc.lat)），
        // 之前读 latitude/longitude 永远取不到 → 紧急面板「我的位置」与停车距离恒为空。
        guard let loc = caches["location"] as? [String: Any],
              let lat = ciNumber(loc, ["Lat"]),
              let lng = ciNumber(loc, ["Lng"]) else { return nil }
        return CLLocation(latitude: lat, longitude: lng)
    }

    // 停车历史（视图模型用的形态；数据来自持久化的 `parkingPoints`）
    struct ParkingRecord: Identifiable {
        let id = UUID()
        let location: CLLocation
        let time: Date
        let address: String
    }
    var parkingHistory: [ParkingRecord] {
        parkingPoints.map {
            ParkingRecord(location: CLLocation(latitude: $0.lat, longitude: $0.lng),
                          time: $0.time, address: $0.address)
        }
    }

    // 总里程（写入点是 recordHistory；读到它的有车辆页的保养计划与行程统计）
    var totalMileage: Int {
        get { UserDefaults.standard.integer(forKey: "carkeeper_total_mileage") }
        set { UserDefaults.standard.set(newValue, forKey: "carkeeper_total_mileage") }
    }

    /// 车控报文缓存（`getControlStatus`）。**里程、电压电流、门窗、电芯数据都只在这里**，
    /// `getMyCars` 里的同名 `totalOdometer` 恒为 null —— 这是最容易踩空的一处。
    var controlCache: [String: Any]? { ciVal(caches, "control") }

    /// 保养计划（服务端字段优先，本机记录兜底）。页面不要自己算里程 —— 见 VM.maintenancePlan。
    var maintenancePlan: VM.MaintenancePlan? { VM.maintenancePlan(car, ciVal(caches, "control")) }

    // 维保时间戳
    var serviceTimestamp: TimeInterval {
        get { UserDefaults.standard.double(forKey: "carkeeper_service_timestamp") }
        set { UserDefaults.standard.set(newValue, forKey: "carkeeper_service_timestamp") }
    }
}

// =============================================================================
// ToastManager —— 全局液态玻璃 Toast 提示单例
// =============================================================================

@MainActor
final class ToastManager: ObservableObject {
    static let shared = ToastManager()

    @Published var currentItem: (text: String, icon: String)? = nil

    private var dismissHandle: DispatchWorkItem?

    private init() {}

    func show(_ text: String, icon: String = "checkmark.circle.fill", duration: Double = 1.8) {
        dismissHandle?.cancel()
        currentItem = (text, icon)
        let work = DispatchWorkItem { [weak self] in self?.currentItem = nil }
        dismissHandle = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }
}
