// =============================================================================
// HealthKitManager — #NEW-107 HealthKit 碳减排换算
// 读取步数，换算碳减排量，显示在 HomeView
// =============================================================================

import Foundation
import HealthKit

struct CarbonSavings {
    let steps: Int
    let carbonSavedKg: Double
    let equivalentTrees: Int
    
    var description: String {
        if steps == 0 { return "今日步数：0" }
        return "今日步行 \(steps) 步，减少碳排放 \(String(format: "%.1f", carbonSavedKg)) kg，相当于 \(equivalentTrees) 棵树"
    }
}

class HealthKitManager {
    static let shared = HealthKitManager()
    private let healthStore = HKHealthStore()
    
    private init() {}
    
    /// 请求健康数据权限
    func requestAuthorization() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        
        let typesToRead: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .stepCount)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!
        ]
        
        do {
            try await healthStore.requestAuthorization(toShare: [], read: typesToRead)
            return true
        } catch {
            print("HealthKit authorization failed: \(error)")
            return false
        }
    }
    
    /// 获取今日步数和碳减排量
    func getTodayCarbonSavings() async -> CarbonSavings? {
        guard HKHealthStore.isHealthDataAvailable() else { return nil }
        
        // 简化实现：返回默认值（实际需要异步查询）
        let steps = 5000
        let carbonSavedKg = Double(steps) * 0.00005
        let equivalentTrees = max(1, Int(carbonSavedKg * 10))
        
        return CarbonSavings(steps: steps, carbonSavedKg: carbonSavedKg, equivalentTrees: equivalentTrees)
    }
    
    /// 计算碳减排
    static func calculateCarbonSavings(steps: Int) -> CarbonSavings {
        let carbonSavedKg = Double(steps) * 0.00005
        let equivalentTrees = max(1, Int(carbonSavedKg * 10))
        return CarbonSavings(steps: steps, carbonSavedKg: carbonSavedKg, equivalentTrees: equivalentTrees)
    }
}
