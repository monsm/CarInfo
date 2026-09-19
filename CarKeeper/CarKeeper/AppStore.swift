import SwiftUI
import Observation
import Foundation

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
                await fetchVehicleData()
            }
        } catch {
            NSLog("bootstrap: \(error.localizedDescription)")
        }
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

    // MARK: 登录 / 退出

    func logout() {
        UserDefaults.standard.removeObject(forKey: tokenStorageKey)
        UserDefaults.standard.removeObject(forKey: cacheStorageKey)
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
        // 再清除旧缓存，后台异步拉新车数据
        clearCache()
        Task { await fetchVehicleData() }
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
