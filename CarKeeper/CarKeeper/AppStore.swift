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

    // 缓存（charge / pm25 / location / control / check / messages）
    var caches: [String: Any?] = [
        "charge": nil, "pm25": nil, "location": nil,
        "control": nil, "check": nil, "messages": nil
    ]
    // 缓存时间戳，用于 TTL 过期（3 分钟）
    private var cacheTimestamps: [String: Date] = [:]
    static let cacheTTL: TimeInterval = 180

    // #9 控制命令历史记录
    var commandHistory: [HistoryEntry] = []
    struct HistoryEntry: Identifiable {
        let id = UUID()
        let cmd: String
        let name: String
        let startedAt: Date
        let finishedAt: Date?
        let success: Bool
        let duration: TimeInterval  // 执行耗时（秒）

        var statusColor: Color { success ? .green : .red }
        var iconName: String { success ? "checkmark.circle.fill" : "xmark.circle.fill" }
        var durationText: String { duration > 0 ? "\(Int(duration/60))min" : "--" }
    }

    func addCommandHistory(cmd: String, name: String, success: Bool, duration: TimeInterval) {
        commandHistory.insert(HistoryEntry(cmd: cmd, name: name, startedAt: Date().advanced(by: -duration), finishedAt: Date(), success: success, duration: duration), at: 0)
        // 只保留最近 50 条
        if commandHistory.count > 50 { commandHistory = Array(commandHistory.prefix(50)) }
    }

    // #16 维保里程记录（UserDefaults 持久化）
    static let lastServiceMileageKey = "carkeeper_last_service_mileage"

    /// 上次选中的车辆 id（重启后恢复，否则每次都跳回第一辆）
    static let selectedCarIdKey = "carkeeper_selected_car_id"

    /// App Group id：必须与 CarKeeper.entitlements / project.yml / Widgets / WatchApp 保持一致，
    /// 不一致时小组件、表盘、灵动岛读不到任何数据（永远是 0）。
    static let appGroupId = "group.com.you.CarKeeper"
    var lastServiceMileage: Int {
        get { UserDefaults.standard.integer(forKey: Self.lastServiceMileageKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.lastServiceMileageKey) }
    }
    static let defaultServiceInterval: Int = 10000  // 默认保养间隔 10000 km

    // #40 维保价格估算
    static let servicePriceEstimate: Int = 800  // 默认保养价格 800 元
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
        let avgEfficiency: Double?  // kWh/100km
    }
    var tripHistory: [TripRecord] = []
    private var currentTrip: (startTime: Date, startSoc: Int, startLocation: CLLocation?)? = nil

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

    // #NEW-4 上车打卡
    var lastCheckInDate: Date? {
        get { UserDefaults.standard.object(forKey: "carkeeper_last_checkin") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "carkeeper_last_checkin") }
    }
    var checkInCount: Int {
        get { UserDefaults.standard.integer(forKey: "carkeeper_checkin_count") }
        set { UserDefaults.standard.set(newValue, forKey: "carkeeper_checkin_count") }
    }

    // #NEW-3 离线模式标记
    var isOfflineMode: Bool = false
    var offlineMessage: String = ""

    // #驾驶安全评分 — 基于行程历史计算（0-100）
    var drivingScore: Int {
        guard !tripHistory.isEmpty else { return 75 } // 默认中等评分
        let recent = Array(tripHistory.prefix(10))
        let avgEfficiency = recent
            .compactMap { $0.avgEfficiency }
            .reduce(0.0, +) / Double(recent.count)
        // 能耗越低评分越高（基准 18 kWh/100km，越低越好）
        let efficiencyScore = max(0, min(100, Int(100 - (avgEfficiency - 10) * 5)))
        // 短途行程越多越稳定
        let shortTripRatio = Double(recent.filter { $0.distanceKm < 5 }.count) / Double(recent.count)
        let stabilityScore = Int(shortTripRatio * 50 + 50)
        return max(0, min(100, (efficiencyScore + stabilityScore) / 2))
    }

    // #NEW-6 Siri 快捷指令最近使用统计
    var siriUsageCount: [String: Int] {
        get {
            let dict = UserDefaults.standard.dictionary(forKey: "carkeeper_siri_usage") as? [String: Int] ?? [:]
            return dict
        }
        set { UserDefaults.standard.set(newValue, forKey: "carkeeper_siri_usage") }
    }

    func recordSiriUsage(_ action: String) {
        var count = siriUsageCount[action] ?? 0
        count += 1
        siriUsageCount[action] = count
    }

    func recordEnergySnapshot(soc: Int, rangeKm: Int) {
        // 防止重复记录（同一分钟内只记一次）
        let recent = energyHistory.filter { Date().timeIntervalSince($0.timestamp) < 60 }
        guard recent.isEmpty else { return }
        energyHistory.append(EnergyRecord(timestamp: Date(), soc: soc, range: rangeKm))
        // 只保留最近 20 条
        if energyHistory.count > 20 { energyHistory = Array(energyHistory.suffix(20)) }
    }

    // #NEW-1 记录停车位置
    func saveParkingLocation(_ location: CLLocation?, at time: Date? = nil) {
        parkingLocation = location
        lastParkingTime = time ?? Date()
    }

    // #NEW-2 开始新行程
    func startTrip(_ location: CLLocation? = nil, soc: Int? = nil) {
        let currentSoc = soc ?? (energyHistory.last?.soc ?? 0)
        currentTrip = (Date(), currentSoc, location)
    }

    // #NEW-2 结束行程
    func endTrip(distanceKm: Double, endSoc: Int? = nil, endLocation: CLLocation? = nil) -> TripRecord? {
        guard let trip = currentTrip else { return nil }
        let endSoc = endSoc ?? (energyHistory.last?.soc ?? 0)
        let avgEfficiency: Double?
        if trip.startSoc > endSoc && distanceKm > 0 {
            let energyUsed = Double(trip.startSoc - endSoc) / 100.0 * 15.0  // 假设电池容量15kWh
            avgEfficiency = (distanceKm > 0) ? energyUsed / distanceKm * 100 : nil
        } else { avgEfficiency = nil }
        let record = TripRecord(
            startTime: trip.startTime,
            endTime: Date(),
            startLocation: trip.startLocation,
            endLocation: endLocation,
            distanceKm: distanceKm,
            startSoc: trip.startSoc,
            endSoc: endSoc,
            avgEfficiency: avgEfficiency
        )
        tripHistory.insert(record, at: 0)
        if tripHistory.count > 50 { tripHistory = Array(tripHistory.prefix(50)) }
        currentTrip = nil
        return record
    }

    // #NEW-4 打卡
    func checkIn() {
        lastCheckInDate = Date()
        checkInCount += 1
        UserDefaults.standard.synchronize()
    }

    // #NEW-5 消息已读计数（服务端没有 mark-all，本地统计）
    var unreadMessageCount: Int { 0 }  // 由 MessagesView 自己管理

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

    // #7 夜间模式自动切换
    static let nightModeStartHour = UserDefaults.standard.integer(forKey: "carkeeper_night_start_hour")
    static let nightModeEndHour = UserDefaults.standard.integer(forKey: "carkeeper_night_end_hour")
    static let forceDarkMode = UserDefaults.standard.bool(forKey: "carkeeper_force_dark_mode")
    static let forceLightMode = UserDefaults.standard.bool(forKey: "carkeeper_force_light_mode")

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
        let pinData = pin.data(using: .utf8)!
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

    /// 判断当前是否应使用深色模式
    func shouldUseDarkMode() -> Bool {
        if Self.forceDarkMode { return true }
        if Self.forceLightMode { return false }
        let hour = Calendar.current.component(.hour, from: Date())
        let start = Self.nightModeStartHour > 0 ? Self.nightModeStartHour : 21  // 默认 21:00
        let end = Self.nightModeEndHour > 0 ? Self.nightModeEndHour : 7         // 默认 07:00
        if start > end {
            // 跨午夜（如 21:00-07:00）
            return hour >= start || hour < end
        } else {
            return hour >= start && hour < end
        }
    }

    // #NEW-115 夜间模式状态（跟随系统外观）
    var isNightMode: Bool {
        shouldUseDarkMode()
    }

    // #17 请求去重：记录正在进行的任务
    private var inFlightRequests: Set<String> = []
    private let requestLock = NSLock()

    func markRequestStarted(_ key: String) -> Bool {
        requestLock.lock()
        defer { requestLock.unlock() }
        if inFlightRequests.contains(key) { return false }
        inFlightRequests.insert(key)
        return true
    }

    func markRequestFinished(_ key: String) {
        requestLock.lock()
        defer { requestLock.unlock() }
        inFlightRequests.remove(key)
    }

    /// 判断指定 key 是否需要重新拉取（缓存缺失 或 已过期）
    func needsRefresh(_ key: String) -> Bool {
        guard let v = caches[key] else { return true }
        // 只判断类型是否正确（原来写成 guard let d = ... 但 d 从未被使用）
        guard v is [String: Any] else { return true }
        return isCacheExpired(key)
    }

    // 首页快控穿透（对应 globalData.pendingQuickCtrl）
    var pendingQuickCtrl: String? = nil

    private init() {
        if let cfg = TokenStore.read(), !cfg.accessToken.isEmpty {
            isLoggedIn = true
            phone = cfg.mobile
        }
    }

    // MARK: 车辆 / 用户

    // #21 冷启动预加载：App 启动时异步预取核心数据
    private var preloadTask: Task<Void, Never>? = nil

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

    func bootstrap() async {
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
            NSLog("bootstrap: \(error.localizedDescription)")
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
                // ⚠️ 只收成功的结果。任何子请求失败都不要返回 nil ——
                // 否则 saveCache 会把上一份好数据擦掉（弱网下整页从有值变成全 0）。
                guard let value else { continue }
                out[key] = value
            }
            return out
        }
    }

    func saveCache(_ patch: [String: Any?]) {
        let now = Date()
        for (k, v) in patch {
            // ⚠️ nil = 该数据源本次拉取失败：保留旧值、不刷新时间戳，
            // 绝不覆盖（这是弱网下数据凭空消失的根因）。
            guard let v else { continue }
            caches[k] = v
            cacheTimestamps[k] = now
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
            offlineMessage = "网络异常，显示缓存数据"
        }
        // 把最新车况同步到 App Group（小组件 / 表盘 / 灵动岛的数据源）
        syncSharedDefaults()
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

        // 充电功率：EnergyModel 里的 power 是给人看的字符串（"7 kW"），
        // 曲线要的是数值，所以直接读报文 —— 键名与 VM.energy 里完全一致。
        let pow = ciNumber(ciVal(caches, "charge"), ["ChargPower", "ChargingPower"])

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
    }

    // MARK: - 与 Widget / Watch / 实时活动共享数据
    /// 把车况写进 App Group，供小组件（Widgets/WidgetBundle.swift）与表盘（WatchApp）读取。
    /// · 零散键（widget_* / watch_*）给表盘用，键名与表盘代码必须一致。
    /// · 结构化快照（SharedStore.snapshotKey）给小组件与实时活动用，字段只有一份定义。
    /// 没有 App Group 能力（未签名 / 侧载重签）时写入的是普通 UserDefaults：不会崩，只是不共享。
    func syncSharedDefaults() {
        guard let defaults = UserDefaults(suiteName: Self.appGroupId) else { return }
        let e = VM.energy(caches, car)
        let comfort = VM.comfortStatus(caches)
        let control = ciVal(caches, "control")

        let soc = e.socPct
        let rangeKm = Int(e.range.filter { $0.isNumber }) ?? 0
        let temp = comfort.cabinTemp
        // 锁止状态：DriverDoorLock == 0 表示已锁（报文里没有 DoorLocked 这个键）
        let locked = ciNumber(control, ["DriverDoorLock"]).map { $0 == 0 } ?? true
        let charging = isCharging
        let powerText = chargingPowerHistory.last.map { String(format: "%.1f", $0.power) } ?? ""

        // 小组件
        defaults.set(soc, forKey: "widget_soc")
        defaults.set(rangeKm, forKey: "widget_range")
        defaults.set(temp, forKey: "widget_temp")
        defaults.set(locked, forKey: "widget_locked")
        defaults.set(charging, forKey: "widget_charging")
        defaults.set(isOfflineMode, forKey: "widget_offline")
        defaults.set(powerText, forKey: "widget_power")

        // Watch
        defaults.set(soc, forKey: "watch_soc")
        defaults.set(rangeKm, forKey: "watch_range")
        defaults.set(temp, forKey: "watch_temp")
        defaults.set(locked, forKey: "watch_locked")
        defaults.set(charging, forKey: "watch_charging")
        defaults.set(totalMileage, forKey: "watch_mileage")

        // 结构化快照：小组件与充电实时活动读的就是这一个键。
        // 字段只有一份定义（Shared/WidgetTokens.swift 的 VehicleSnapshot），
        // 不再靠"键名字符串两边都对得上"来维系 —— 写错键名不会报错，只会安静地显示 0。
        let snapshot = VehicleSnapshot(
            soc: soc,
            rangeKm: rangeKm,
            cabinTemp: temp,
            locked: locked,
            charging: charging,
            chargePower: chargingPowerHistory.last?.power,
            // ⚠️ ChargingSession.timeToFull 本身就是 String?，
            // 直接取会得到 String?? —— 用 ?? nil 拍平，否则赋给 String? 通不过编译
            timeToFull: e.charging?.timeToFull ?? nil,
            offline: isOfflineMode,
            mileageKm: totalMileage,
            chargeCls: e.chargeCls,
            updatedAt: Date()
        )
        // 内容真变了才刷小组件时间线、才动实时活动：
        // 车况每 60 秒轮询一次，无条件刷新会把小组件的刷新预算烧光。
        if SharedStore.write(snapshot) {
            LiveActivityBridge.sync(snapshot)
        }
    }

    /// 返回指定 key 的缓存是否已过期（超过 TTL）
    func isCacheExpired(_ key: String) -> Bool {
        guard let ts = cacheTimestamps[key] else { return true }
        return Date().timeIntervalSince(ts) > Self.cacheTTL
    }

    /// 返回「已过期、需要重新拉取」的数据键。
    /// ⚠️ 不再删除缓存值：断网时必须继续显示旧数据，否则每次 TTL 到期整页都会变空。
    func staleKeys() -> [String] {
        let now = Date()
        return cacheTimestamps
            .filter { now.timeIntervalSince($0.value) > Self.cacheTTL }
            .map(\.key)
    }

    func clearCache() {
        caches = ["charge": nil, "pm25": nil, "location": nil, "control": nil, "check": nil, "messages": nil]
        cacheTimestamps.removeAll()
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
        UserDefaults.standard.removeObject(forKey: tokenStorageKey)
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
        pendingQuickCtrl = nil
        // 实时活动与小组件快照同样绑定账号：退出时一起清掉，
        // 否则锁屏 / 桌面上会继续显示上一个账号的车牌与电量。
        LiveActivityBridge.endAll()
        SharedStore.clear()
        // 趋势曲线同样是这个账号的车端数据：不清理会留给下一个登录的账号
        HistoryStore.shared.clear()
        isOfflineMode = false
        offlineMessage = ""
        parkingLocation = nil
        lastParkingTime = nil
        lastCheckInDate = nil
        checkInCount = 0
        UserDefaults.standard.removeObject(forKey: Self.lastServiceMileageKey)
        UserDefaults.standard.removeObject(forKey: "carkeeper_last_checkin")
        UserDefaults.standard.removeObject(forKey: "carkeeper_checkin_count")
        UserDefaults.standard.removeObject(forKey: "carkeeper_parking_time")
        // 家庭成员 / 临时钥匙 / 里程账本 / 保险费 / Siri 使用统计 —— 全是跟账号绑定的数据
        FamilyManager.shared.resetAll()
        TempKeyManager.shared.resetAll()
        UserDefaults.standard.removeObject(forKey: "carkeeper_mileage_entries")
        UserDefaults.standard.removeObject(forKey: "carkeeper_insurance_policies")
        UserDefaults.standard.removeObject(forKey: "carkeeper_siri_usage")
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
        // #N10 加密保存车牌号
        // 车牌键是 PlateNumber / plateNumber（Plate / plateNo 在报文里不存在）
        if let plate = ciString(c, ["PlateNumber", "plateNumber"]) {
            SecureStorage.shared.savePlate(plate)
        }
        // 再清除旧缓存，后台异步拉新车数据
        clearCache()
        Task { await fetchVehicleData() }
    }

    // #NEW-111 CloudKit 同步触发（后台）
    func triggerCloudSync() async {
        // 无 iCloud 能力时绝不能 touch CloudSyncManager.shared：构造 CKContainer 会抛出
        // Swift 无法捕获的 ObjC 异常，直接崩进程（侧载/未签名包的典型启动闪退原因）。
        guard CloudSyncManager.isCloudKitEntitled else { return }
        await CloudSyncManager.shared.syncIfNeeded()
    }

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

    // 停车历史
    struct ParkingRecord: Identifiable {
        let id = UUID()
        let location: CLLocation
        let time: Date
        let address: String
    }
    var parkingHistory: [ParkingRecord] = []

    // 总里程
    var totalMileage: Int {
        get { UserDefaults.standard.integer(forKey: "carkeeper_total_mileage") }
        set { UserDefaults.standard.set(newValue, forKey: "carkeeper_total_mileage") }
    }

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
