import SwiftUI
import Observation
import Foundation

// 全局应用状态（对应小程序 app.js 的 globalData）。
// 使用 @Observable 宏（iOS 17+）做细粒度响应式更新。

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
            self.cars = carsRes ?? []
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
        let api = APIClient.shared
        var patch: [String: Any?] = [:]
        // 并行拉取各数据源，单个失败不影响其它（全局重试已在 API 层兜底网络抖动）。
        let results = await gather(carId: carId, api: api, includeMessages: false, includeCheck: false)
        for (k, v) in results { patch[k] = v }
        saveCache(patch)
    }

    func fetchVehicleData() async {
        guard !carId.isEmpty else { return }
        let api = APIClient.shared
        var patch: [String: Any?] = [:]
        let results = await gather(carId: carId, api: api, includeMessages: true, includeCheck: true)
        for (k, v) in results { patch[k] = v }
        saveCache(patch)
    }

    /// 并行拉取多个数据源。使用 withTaskGroup，子任务失败单独吞掉，
    /// 返回成功的那些键值对。`includeMessages`/`includeCheck` 控制是否拉全部。
    private func gather(carId: String, api: APIClient,
                        includeMessages: Bool, includeCheck: Bool) async -> [String: [String: Any]?] {
        await withTaskGroup(of: (String, [String: Any]?).self) { group in
            group.addTask { ("charge", try? await api.getCharge(carId: carId)) }
            group.addTask { ("pm25", try? await api.getCarPm25(carId: carId)) }
            group.addTask { ("location", try? await api.getLocation(carId: carId)) }
            group.addTask { ("control", try? await api.getControl(carId: carId)) }
            if includeMessages {
                group.addTask { ("messages", try? await api.getMessages()) }
            }
            if includeCheck {
                group.addTask { ("check", try? await api.getCarCheck(carId: carId)) }
            }
            var out: [String: [String: Any]?] = [:]
            for await (key, value) in group {
                out[key] = value
            }
            return out
        }
    }

    func fetchVehicleData() async {
        guard !carId.isEmpty else { return }
        let api = APIClient.shared
        var patch: [String: Any?] = [:]
        do {
            if let v = try await api.getCharge(carId: carId) { patch["charge"] = v }
            if let v = try await api.getCarPm25(carId: carId) { patch["pm25"] = v }
            if let v = try await api.getLocation(carId: carId) { patch["location"] = v }
            if let v = try await api.getControl(carId: carId) { patch["control"] = v }
            if let v = try await api.getMessages() { patch["messages"] = v }
            if let v = try await api.getCarCheck(carId: carId) { patch["check"] = v }
            saveCache(patch)
        } catch {
            NSLog("fetchVehicleData: \(error.localizedDescription)")
        }
    }

    func saveCache(_ patch: [String: Any?]) {
        for (k, v) in patch { caches[k] = v }
    }

    func clearCache() {
        caches = ["charge": nil, "pm25": nil, "location": nil, "control": nil, "check": nil, "messages": nil]
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
    }

    func selectCar(_ idx: Int) {
        guard cars.indices.contains(idx) else { return }
        let c = cars[idx]
        car = c
        carId = ciString(c, ["CarId", "carId"]) ?? ""
    }
}
