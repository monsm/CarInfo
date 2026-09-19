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
    }

    func addCommandHistory(cmd: String, name: String, success: Bool, duration: TimeInterval) {
        commandHistory.insert(HistoryEntry(cmd: cmd, name: name, startedAt: Date().advanced(by: -duration), finishedAt: Date(), success: success, duration: duration), at: 0)
        // 只保留最近 50 条
        if commandHistory.count > 50 { commandHistory = Array(commandHistory.prefix(50)) }
    }

    // #16 维保里程记录（UserDefaults 持久化）
    private static let lastServiceMileageKey = "carkeeper_last_service_mileage"
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
        set { if let loc = newValue, let data = try? NSKeyedArchiver.archivedData(withRootObject: loc, requiringSecureCoding: true) { UserDefaults.standard.set(data, forKey: "carkeeper_parking_loc") }
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
              let socStr = charge["RemainPower"] as? String,
              let soc = Int(socStr) else { return CCQuickStatus() }
        let rangeStr = charge["RemainedPowerMile"] as? String ?? "--"
        let ctrl = caches["control"] as? [String: Any]
        let locked = (ciBool(ctrl, ["DoorLocked", "doorLocked"]) ?? true)
        let temp = VM.n0(ctrl?["InteriorTemperature"] ?? ctrl?["interiorTemperature"]) ?? "--"
        let charging = soc < 100
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

    // #NEW-115 夜间模式状态（用于 NightModeBreathing 呼吸灯）
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
        guard let d = v as? [String: Any] else { return true }
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
        let status = charge["ChrgStatus"] as? String ?? ""
        return status == "1" || status == "2"
    }
    var chargingProgress: Double {
        guard let charge = caches["charge"] as? [String: Any] else { return 0 }
        let soc = Double(charge["RemainPower"] as? String ?? "0") ?? 0
        return min(1.0, max(0.0, soc / 100.0))
    }

    func bootstrap() async {
        let api = APIClient.shared
        do {
            let carsRes = try await api.getCars()
            let userRes = try await api.getUser()
            self.cars = carsRes
            if let u = userRes { user = u }
            if let first = self.cars.first {
                let id = ciString(first, ["CarId", "carId"]) ?? ""
                self.car = first
                self.carId = id
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
                out[key] = value
            }
            return out
        }
    }

    func saveCache(_ patch: [String: Any?]) {
        let now = Date()
        for (k, v) in patch {
            caches[k] = v
            cacheTimestamps[k] = now
        }
        // #13 记录能耗快照
        if let charge = patch["charge"] as? [String: Any] {
            if let socStr = charge["RemainPower"] as? String,
               let soc = Int(socStr),
               let rangeStr = charge["RemainedPowerMile"] as? String,
               let range = Int(rangeStr) {
                recordEnergySnapshot(soc: soc, rangeKm: range)
            }
        }
        // #NEW-3 检测离线状态：缓存超过 TTL 则标记离线
        let staleKeys = evictStale()
        if !staleKeys.isEmpty && !isLoggedIn {
            isOfflineMode = true
            offlineMessage = "网络异常，显示缓存数据"
        } else {
            isOfflineMode = false
            offlineMessage = ""
        }
    }

    /// 返回指定 key 的缓存是否已过期（超过 TTL）
    func isCacheExpired(_ key: String) -> Bool {
        guard let ts = cacheTimestamps[key] else { return true }
        return Date().timeIntervalSince(ts) > Self.cacheTTL
    }

    /// 清理所有过期缓存，返回需要重拉的数据键列表
    func evictStale() -> [String] {
        var staleKeys: [String] = []
        let now = Date()
        for (k, ts) in cacheTimestamps where now.timeIntervalSince(ts) > Self.cacheTTL {
            staleKeys.append(k)
        }
        for k in staleKeys { caches[k] = nil; cacheTimestamps.removeValue(forKey: k) }
        return staleKeys
    }

    func clearCache() {
        caches = ["charge": nil, "pm25": nil, "location": nil, "control": nil, "check": nil, "messages": nil]
        cacheTimestamps.removeAll()
    }

    // #24 首页卡片自定义排序
    static let cardOrderKey = "carkeeper_home_card_order"
    var cardOrder: [String] {
        get {
            if let saved = UserDefaults.standard.array(forKey: Self.cardOrderKey) as? [String] {
                return saved
            }
            // 默认顺序（含 E1-E8 实时车况卡片）
            return [
                "socHero", "driveMetrics", "quickControl", "domainCard",
                "realtimeEnergy", "sohDashboard", "energyGauge", "driveMode",
                "batterySection", "tyreCard", "comfortCard", "vehicle2D", "locationCard"
            ]
        }
        set { UserDefaults.standard.set(newValue, forKey: Self.cardOrderKey) }
    }

    // MARK: 登录 / 退出

    func logout() {
        UserDefaults.standard.removeObject(forKey: tokenStorageKey)
        UserDefaults.standard.removeObject(forKey: cacheStorageKey)
        deletePin()  // #8 退出时清除Keychain中的PIN
        isLoggedIn = false
        phone = ""
        cars = []
        carId = ""
        car = nil
        user = nil
        clearCache()
        NotificationCenter.default.post(name: .didLogout, object: nil)
    }

    func selectCar(_ idx: Int) {
        guard cars.indices.contains(idx) else { return }
        let c = cars[idx]
        let newId = ciString(c, ["CarId", "carId"]) ?? ""
        // 先更新 carId（触发视图重建，缓存仍在，避免闪烁）
        car = c
        carId = newId
        // #N10 加密保存车牌号
        if let plate = ciString(c, ["Plate", "plate", "plateNo"]) {
            SecureStorage.shared.savePlate(plate)
        }
        // 再清除旧缓存，后台异步拉新车数据
        clearCache()
        Task { await fetchVehicleData() }
    }

    // #NEW-111 CloudKit 同步触发（后台）
    func triggerCloudSync() async {
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
        guard let loc = caches["location"] as? [String: Any],
              let lat = loc["latitude"] as? Double,
              let lng = loc["longitude"] as? Double else { return nil }
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

    // 通知检查
    func checkNotificationsIfNeeded() {
        _ = SmartNotificationManager.shared
    }

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
