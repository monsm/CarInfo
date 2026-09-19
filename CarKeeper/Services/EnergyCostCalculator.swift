// =============================================================================
// #NEW-127 能耗成本计算器 — 基于电价计算充电花费
// =============================================================================

import Foundation
import Charts

struct ChargeCostRecord: Identifiable {
    let id = UUID()
    let date: Date
    let kWh: Double
    let cost: Double
    let rate: Double  // 电价元/kWh
    let socStart: Int
    let socEnd: Int
}

class EnergyCostCalculator {
    static let shared = EnergyCostCalculator()
    
    // 默认电价（元/kWh）
    private var electricityRate: Double = 0.6
    
    private init() {}
    
    /// 设置电价
    func setRate(_ rate: Double) {
        electricityRate = rate
    }
    
    /// 计算充电成本
    func calculateChargeCost(kWh: Double) -> Double {
        return kWh * electricityRate
    }
    
    /// 记录一次充电
    func recordCharge(kWh: Double, socStart: Int, socEnd: Int) -> ChargeCostRecord {
        let record = ChargeCostRecord(
            date: Date(),
            kWh: kWh,
            cost: calculateChargeCost(kWh: kWh),
            rate: electricityRate,
            socStart: socStart,
            socEnd: socEnd
        )
        saveRecord(record)
        return record
    }
    
    /// 获取历史充电记录
    func getHistory(limit: Int = 30) -> [ChargeCostRecord] {
        guard let data = UserDefaults.standard.data(forKey: "carkeeper_charge_history"),
              let records = try? JSONDecoder().decode([ChargeCostRecord].self, from: data) else {
            return []
        }
        return Array(records.prefix(limit))
    }
    
    /// 计算总花费
    func totalCost() -> Double {
        getHistory().map { $0.cost }.reduce(0, +)
    }
    
    /// 计算平均成本
    func averageCostPerKWh() -> Double {
        let records = getHistory()
        guard !records.isEmpty else { return electricityRate }
        let totalKWh = records.map { $0.kWh }.reduce(0, +)
        let totalCost = records.map { $0.cost }.reduce(0, +)
        return totalKWh > 0 ? totalCost / totalKWh : electricityRate
    }
    
    private func saveRecord(_ record: ChargeCostRecord) {
        var records = getHistory()
        records.insert(record, at: 0)
        if records.count > 100 {
            records = Array(records.prefix(100))
        }
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: "carkeeper_charge_history")
        }
    }
}

// MARK: - 图表组件
struct CostTrendChart: View {
    let records: [ChargeCostRecord]
    
    var body: some View {
        Chart {
            ForEach(records.indices, id: \.self) { i in
                let r = records[i]
                LineMark(
                    x: .value("日期", r.date),
                    y: .value("费用 (元)", r.cost)
                )
                .lineStyle(StrokeStyle(lineWidth: 2))
                .foregroundStyle(.green)
                
                PointMark(
                    x: .value("日期", r.date),
                    y: .value("费用 (元)", r.cost)
                )
                .foregroundStyle(.green)
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month().day())
            }
        }
        .frame(height: 150)
    }
}
