// =============================================================================
// AppDataModel — #NEW-108 SwiftData 本地数据库
// 替换 UserDefaults，提供真正的持久化存储
// =============================================================================

import SwiftUI
import SwiftData
import CoreLocation

// MARK: - 模型定义

@Model
class TripRecord {
    var id: UUID
    var startTime: Date
    var endTime: Date?
    var startLocationLat: Double?
    var startLocationLng: Double?
    var endLocationLat: Double?
    var endLocationLng: Double?
    var distanceKm: Double
    var startSoc: Int
    var endSoc: Int
    var avgEfficiency: Double?
    var notes: String?

    init(startTime: Date, distanceKm: Double, startSoc: Int, endSoc: Int) {
        self.id = UUID()
        self.startTime = startTime
        self.endTime = nil
        self.distanceKm = distanceKm
        self.startSoc = startSoc
        self.endSoc = endSoc
        self.avgEfficiency = nil
    }

    /// 便于预览 / 测试的完整构造器
    init(startTime: Date, endTime: Date?, distanceKm: Double,
         startSoc: Int, endSoc: Int, avgEfficiency: Double?) {
        self.id = UUID()
        self.startTime = startTime
        self.endTime = endTime
        self.startLocationLat = nil
        self.startLocationLng = nil
        self.endLocationLat = nil
        self.endLocationLng = nil
        self.distanceKm = distanceKm
        self.startSoc = startSoc
        self.endSoc = endSoc
        self.avgEfficiency = avgEfficiency
        self.notes = nil
    }

    // MARK: - 派生属性（经纬度在此还原为 CLLocation）
    var startLocation: CLLocation? {
        guard let lat = startLocationLat, let lng = startLocationLng else { return nil }
        return CLLocation(latitude: lat, longitude: lng)
    }

    var endLocation: CLLocation? {
        guard let lat = endLocationLat, let lng = endLocationLng else { return nil }
        return CLLocation(latitude: lat, longitude: lng)
    }

    /// 消耗电量（百分点）
    var socChange: Int { max(0, startSoc - endSoc) }
}

@Model

@Model

@Model

// MARK: - ModelContainer 工厂方法


// MARK: - 仓库类




