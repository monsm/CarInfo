// =============================================================================
// #NEW-107 CarbonSavingsTracker — HomeView 碳减排显示
// =============================================================================

import Foundation
import SwiftUI

struct CarbonSavingStats {
    let todaySteps: Int
    let todayCarbonKg: Double
    let totalCarbonKg: Double
    let equivalentTrees: Int
    
    var summary: String {
        if todaySteps == 0 {
            return "今日步行 0 步"
        }
        return "今日步行 \(todaySteps) 步，减碳 \(String(format: "%.2f", todayCarbonKg)) kg"
    }
}

class CarbonSavingsTracker : ObservableObject {
    static let shared = CarbonSavingsTracker()
    
    private let stepsPerKm = 1300  // 每公里步数估算
    private let carbonPerKm = 0.21  // 每公里碳排放 kg
    
    private init() {}
    
    /// 获取今日碳减排统计
    func getTodayStats() -> CarbonSavingStats {
        let defaults = UserDefaults.standard
        let todaySteps = defaults.integer(forKey: "carkeeper_today_steps")
        let totalSteps = defaults.integer(forKey: "carkeeper_total_steps")
        
        let todayCarbon = (Double(todaySteps) / Double(stepsPerKm)) * carbonPerKm
        let totalCarbon = (Double(totalSteps) / Double(stepsPerKm)) * carbonPerKm
        let trees = max(1, Int(totalCarbon * 10))  // 1棵树约吸收0.01kg CO2/天
        
        return CarbonSavingStats(
            todaySteps: todaySteps,
            todayCarbonKg: todayCarbon,
            totalCarbonKg: totalCarbon,
            equivalentTrees: trees
        )
    }
    
    /// 记录步数
    func recordSteps(_ steps: Int) {
        let defaults = UserDefaults.standard
        let todayKey = "carkeeper_steps_\(Date().dateOnly)"
        let currentToday = defaults.integer(forKey: todayKey)
        defaults.set(currentToday + steps, forKey: todayKey)
        
        // 更新总计
        let total = defaults.integer(forKey: "carkeeper_total_steps")
        defaults.set(total + steps, forKey: "carkeeper_total_steps")
    }
    
    /// 模拟步数数据（测试用）
    func simulateDailySteps() {
        recordSteps(Int.random(in: 3000...10000))
    }
}

extension Date {
    var dateOnly: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: self)
    }
}
