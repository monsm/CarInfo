// =============================================================================
// #NEW-111 CloudKit 跨设备同步 — 基础框架
// =============================================================================

import Foundation
import CloudKit

class CloudSyncManager: ObservableObject {
    static let shared = CloudSyncManager()
    
    private let container = CKContainer(identifier: "iCloud.com.you.CarKeeper")
    private let publicDB = CKContainer(identifier: "iCloud.com.you.CarKeeper").publicCloudDatabase
    
    // 同步的记录类型
    enum RecordType: String {
        case settings = "CarSettings"
        case tripHistory = "TripHistory"
        case energyHistory = "EnergyHistory"
    }
    
    private init() {}
    
    /// 检查 CloudKit 是否可用
    var isCloudAvailable: Bool {
        return CKContainer.defaultContainer().status() == .available
    }
    
    /// 同步设置到云端
    func syncSettings(_ settings: [String: Any]) async -> Bool {
        guard isCloudAvailable else { return false }
        
        do {
            let record = CKRecord(recordType: RecordType.settings.rawValue, recordID: CKRecordID(recordName: "user_settings"))
            record["preferences"] = try JSONSerialization.data(withJSONObject: settings)
            try await publicDB.save(record)
            return true
        } catch {
            print("Cloud sync failed: \(error)")
            return false
        }
    }
    
    /// 从云端拉取设置
    func fetchSettings() async -> [String: Any]? {
        guard isCloudAvailable else { return nil }
        
        do {
            let record = try await publicDB.record(forRecordId: CKRecordID(recordName: "user_settings"))
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
        guard isCloudAvailable else { return false }
        
        do {
            for trip in trips {
                let record = CKRecord(recordType: RecordType.tripHistory.rawValue, recordID: CKRecordID(recordName: trip.id.uuidString))
                record["startTime"] = trip.startTime.timeIntervalSince1970
                record["endTime"] = trip.endTime?.timeIntervalSince1970
                record["distanceKm"] = trip.distanceKm
                record["startSoc"] = trip.startSoc
                record["endSoc"] = trip.endSoc
                try await publicDB.save(record)
            }
            return true
        } catch {
            print("Cloud sync trips failed: \(error)")
            return false
        }
    }
    
    /// 获取云端行程记录
    func fetchTrips() async -> [TripRecord] {
        guard isCloudAvailable else { return [] }
        
        var trips: [TripRecord] = []
        let query = CKQuery(recordType: RecordType.tripHistory.rawValue, predicate: NSPredicate(value: true))
        
        do {
            let results = try await publicDB.records(matching: query)
            for (id, record) in results {
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
}
