// =============================================================================
// AppDataModel — #NEW-108 SwiftData 本地数据库
// 替换 UserDefaults，提供真正的持久化存储
// =============================================================================

import SwiftUI
import SwiftData

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
}

@Model
class EnergySnapshot {
    var id: UUID
    var timestamp: Date
    var soc: Int
    var range: Int
    
    init(timestamp: Date, soc: Int, range: Int) {
        self.id = UUID()
        self.timestamp = timestamp
        self.soc = soc
        self.range = range
    }
}

@Model
class MaintenancePhoto {
    var id: UUID
    var imageData: Data?
    var capturedAt: Date
    var notes: String?
    
    init(imageData: Data?, capturedAt: Date, notes: String?) {
        self.id = UUID()
        self.imageData = imageData
        self.capturedAt = capturedAt
        self.notes = notes
    }
}

@Model
class UserSettings {
    var id: UUID = UUID()
    var darkModeEnabled: Bool = false
    var reduceMotionEnabled: Bool = false
    var powerSavingEnabled: Bool = false
    var nightModeStartHour: Int = 21
    var nightModeEndHour: Int = 7
    var lastServiceMileage: Int = 0
    var defaultTemperature: Int = 22
    
    init() {}
}

// MARK: - ModelContainer 工厂方法

enum AppModelContainer {
    static let shared: ModelContainer = {
        let schema = Schema([TripRecord.self, EnergySnapshot.self, MaintenancePhoto.self, UserSettings.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        return try! ModelContainer(for: schema, configurations: [config])
    }()
}

// MARK: - 仓库类

class TripRepository {
    private let container: ModelContainer
    
    init(container: ModelContainer = AppModelContainer.shared) {
        self.container = container
    }
    
    func fetchAll() -> [TripRecord] {
        let descriptor = FetchDescriptor<TripRecord>(sortBy: [SortDescriptor(\.startTime, order: .reverse)])
        return (try? container.mainContext.fetch(descriptor)) ?? []
    }
    
    func add(_ trip: TripRecord) {
        container.mainContext.insert(trip)
        try? container.mainContext.save()
    }
    
    func delete(_ trip: TripRecord) {
        container.mainContext.delete(trip)
        try? container.mainContext.save()
    }
}

class EnergySnapshotRepository {
    private let container: ModelContainer
    
    init(container: ModelContainer = AppModelContainer.shared) {
        self.container = container
    }
    
    func fetchRecent(_ count: Int = 20) -> [EnergySnapshot] {
        let descriptor = FetchDescriptor<EnergySnapshot>(
            predicate: nil,
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)],
            limit: count
        )
        return (try? container.mainContext.fetch(descriptor)) ?? []
    }
    
    func add(_ snapshot: EnergySnapshot) {
        container.mainContext.insert(snapshot)
        try? container.mainContext.save()
    }
}

class MaintenancePhotoRepository {
    private let container: ModelContainer
    
    init(container: ModelContainer = AppModelContainer.shared) {
        self.container = container
    }
    
    func fetchAll() -> [MaintenancePhoto] {
        let descriptor = FetchDescriptor<MaintenancePhoto>(sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
        return (try? container.mainContext.fetch(descriptor)) ?? []
    }
    
    func add(_ photo: MaintenancePhoto) {
        container.mainContext.insert(photo)
        try? container.mainContext.save()
    }
}

class SettingsRepository {
    private let container: ModelContainer
    
    init(container: ModelContainer = AppModelContainer.shared) {
        self.container = container
    }
    
    func fetchOrCreate() -> UserSettings {
        if let settings = (try? container.mainContext.fetch(FetchDescriptor<UserSettings>()))?.first {
            return settings
        }
        let newSettings = UserSettings()
        container.mainContext.insert(newSettings)
        try? container.mainContext.save()
        return newSettings
    }
    
    func update(_ settings: UserSettings) {
        try? container.mainContext.save()
    }
}
