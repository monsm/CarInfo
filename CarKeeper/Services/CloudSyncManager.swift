// =============================================================================
// #NEW-111 CloudKit 跨设备同步 — 基础框架
// =============================================================================

import Foundation
import CloudKit

class CloudSyncManager: ObservableObject {
    static let shared = CloudSyncManager()
    
    /// iCloud 容器标识符（必须与签名时使用的 iCloud 容器完全一致）。
    static let containerIdentifier = "iCloud.com.you.CarKeeper"

    /// CloudKit 总开关，读取 Info.plist 的 `CKCloudKitEnabled`，默认 **false**。
    ///
    /// ⚠️ `CKContainer(identifier:)` 在 entitlements 里没有该容器标识符时，会抛出一个 Swift
    /// 无法捕获的 ObjC 异常（"The application's entitlements do not include the … container
    /// identifier"），进程当场被杀 —— 表现就是「安装后点图标直接闪退」。
    ///
    /// CI 的未签名构建（CODE_SIGNING_ALLOWED=NO）和用免费证书/侧载工具重签的包都拿不到
    /// iCloud 能力，所以这里默认关闭，并且只用构建配置来判断：`ubiquityIdentityToken` 在没有
    /// entitlement 时是否一定返回 nil 并无稳定保证，把它当作唯一依据仍可能再次踩到同一个崩溃。
    /// 只有用带 iCloud 容器的证书正式签名后，才把 Info.plist 的该键改成 true。
    static let isCloudKitProvisioned: Bool =
        (Bundle.main.object(forInfoDictionaryKey: "CKCloudKitEnabled") as? Bool) ?? false

    /// 当前是否真的能用 CloudKit：本包被授权 + 用户已登录 iCloud。
    static var isCloudKitEntitled: Bool {
        guard isCloudKitProvisioned else { return false }
        return FileManager.default.ubiquityIdentityToken != nil
    }

    private lazy var container: CKContainer? = {
        guard Self.isCloudKitEntitled else { return nil }
        return CKContainer(identifier: Self.containerIdentifier)
    }()
    private lazy var publicDB: CKDatabase? = container?.publicCloudDatabase
    
    // 同步的记录类型
    enum RecordType: String {
        case settings = "CarSettings"
        case tripHistory = "TripHistory"
        case energyHistory = "EnergyHistory"
    }
    
    private init() {}
    
    /// 检查 CloudKit 是否可用（自带 entitlement 探测，无 iCloud 能力时恒为 false）
    var isCloudAvailable: Bool {
        return publicDB != nil
    }
    
    /// 同步设置到云端
    func syncSettings(_ settings: [String: Any]) async -> Bool {
        guard let db = publicDB else { return false }
        
        do {
            let record = CKRecord(recordType: RecordType.settings.rawValue, recordID: CKRecord.ID(recordName: "user_settings"))
            record["preferences"] = try JSONSerialization.data(withJSONObject: settings)
            try await db.save(record)
            return true
        } catch {
            print("Cloud sync failed: \(error)")
            return false
        }
    }
    
    /// 从云端拉取设置
    func fetchSettings() async -> [String: Any]? {
        guard let db = publicDB else { return nil }
        
        do {
            let record = try await db.record(for: CKRecord.ID(recordName: "user_settings"))
            if let data = record["preferences"] as? Data,
               let prefs = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return prefs
            }
        } catch {
            print("Cloud fetch failed: \(error)")
        }
        return nil
    }
    
    /// 同步行程记录
    func syncTrips(_ trips: [TripRecord]) async -> Bool {
        guard let db = publicDB else { return false }
        
        do {
            for trip in trips {
                let record = CKRecord(recordType: RecordType.tripHistory.rawValue, recordID: CKRecord.ID(recordName: trip.id.uuidString))
                record["startTime"] = trip.startTime.timeIntervalSince1970
                record["endTime"] = trip.endTime?.timeIntervalSince1970
                record["distanceKm"] = trip.distanceKm
                record["startSoc"] = trip.startSoc
                record["endSoc"] = trip.endSoc
                try await db.save(record)
            }
            return true
        } catch {
            print("Cloud sync trips failed: \(error)")
            return false
        }
    }
    
    /// 获取云端行程记录
    func fetchTrips() async -> [TripRecord] {
        guard let db = publicDB else { return [] }
        
        var trips: [TripRecord] = []
        let query = CKQuery(recordType: RecordType.tripHistory.rawValue, predicate: NSPredicate(value: true))
        
        do {
            let results = try await db.records(matching: query)
            for (_, result) in results.matchResults {
                guard let record = try? result.get() else { continue }
                if let startTime = record["startTime"] as? TimeInterval {
                    let trip = TripRecord(
                        startTime: Date(timeIntervalSince1970: startTime),
                        distanceKm: record["distanceKm"] as? Double ?? 0,
                        startSoc: record["startSoc"] as? Int ?? 0,
                        endSoc: record["endSoc"] as? Int ?? 0
                    )
                    trips.append(trip)
                }
            }
        } catch {
            print("Cloud fetch trips failed: \(error)")
        }
        
        return trips.sorted { $0.startTime > $1.startTime }
    }

    /// 检查 CloudKit 状态并执行同步
    func syncIfNeeded() async -> Bool {
        guard isCloudAvailable else { return false }
        let settings = await fetchSettings()
        let trips = await fetchTrips()
        if let settings {
            _ = await syncSettings(settings)
        }
        if !trips.isEmpty {
            _ = await syncTrips(trips)
        }
        return true
    }
}
