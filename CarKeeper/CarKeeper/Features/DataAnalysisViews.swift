// =============================================================================
// E26-E33 数据深度分析视图
// =============================================================================

import SwiftUI
import Charts

// MARK: - E26 充电效率趋势
struct ChargeEfficiencyTrend: View {
    let store: AppStore
    
    var efficiencyData: [(Date, Double)] {
        store.energyHistory.enumerated().map { i, record in
            let socDiff = i > 0 ? Double(record.soc - store.energyHistory[i-1].soc) : 0
            let timeDiff = i > 0 ? record.timestamp.timeIntervalSince(store.energyHistory[i-1].timestamp) / 3600 : 1
            let efficiency = timeDiff > 0 ? abs(socDiff) / 100 * 15 / timeDiff : 0
            return (record.timestamp, efficiency)
        }
    }
    
    var body: some View {
        if efficiencyData.count < 2 {
            Text("暂无足够数据").font(.caption).foregroundColor(.secondary).frame(maxWidth: .infinity).glassCard()
        } else {
            Chart {
                ForEach(efficiencyData.indices.dropLast(), id: \.offset) { i in
                    LineMark(x: .value("时间", efficiencyData[i].0), y: .value("能耗 kWh/h", efficiencyData[i].1))
                        .foregroundStyle(.green)
                    PointMark(x: .value("时间", efficiencyData[i].0), y: .value("能耗 kWh/h", efficiencyData[i].1))
                        .foregroundStyle(.green).symbolSize(10)
                }
            }
            .frame(height: 120).glassCard()
        }
    }
}

// MARK: - E27 驾驶行为周环比报告
struct WeeklyDrivingReport: View {
    let store: AppStore
    private var lastWeekTrips: [TripRecord] {
        let weekStart = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return store.tripHistory.filter { $0.startTime >= weekStart }
    }
    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Text("本周驾驶报告").font(.subheadline).fontWeight(.semibold)
            HStack {
                VStack { Text("\(lastWeekTrips.count)").font(.title2).fontWeight(.bold).foregroundColor(.blue); Text("行程数").font(.caption2).foregroundColor(.secondary) }
                VStack { Text(String(format: "%.1f", lastWeekTrips.map{$0.distanceKm}.reduce(0,+))).font(.title2).fontWeight(.bold).foregroundColor(.green); Text("总里程 km").font(.caption2).foregroundColor(.secondary) }
                VStack { Text(String(format: "%.1f", lastWeekTrips.compactMap{$0.avgEfficiency}.reduce(0,+)/max(Double(lastWeekTrips.count),1))).font(.title2).fontWeight(.bold).foregroundColor(.orange); Text("均能耗 kWh").font(.caption2).foregroundColor(.secondary) }
            }
        }.padding().glassCard()
    }
}

// MARK: - E28 能耗异常检测
class EnergyAnomalyDetector: ObservableObject {
    static let shared = EnergyAnomalyDetector()
    @Published var anomalies: [EnergyAnomaly] = []
    func checkAnomaly(in history: [AppStore.EnergyRecord]) {
        guard history.count >= 3 else { return }
        let recent = Array(history.suffix(5))
        let avgSOC = recent.map{Double($0.soc)}.reduce(0,+)/Double(recent.count)
        let maxDeviation = recent.map{abs(Double($0.soc)-avgSOC)}.max() ?? 0
        if maxDeviation > 15 {
            anomalies.append(EnergyAnomaly(timestamp: Date(), deviation: maxDeviation, message: "检测到能耗异常波动"))
        }
    }
}
struct EnergyAnomaly: Identifiable { let id = UUID(); let timestamp: Date; let deviation: Double; let message: String }

// MARK: - E29 充电习惯分析
struct ChargingHabitsAnalysis: View {
    let store: AppStore
    var peakHours: [Int] { Array(Set(store.energyHistory.map{Calendar.current.component(.hour, from:$0.timestamp)})).sorted() }
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("充电习惯分析").font(.subheadline).fontWeight(.semibold)
            HStack { Image(systemName:"clock").foregroundColor(.accentColor); Text("高峰时段: \(peakHours.first ?? 0):00").font(.subheadline) }
        }.padding().glassCard()
    }
}

// MARK: - E30 里程预测
struct MileagePrediction: View {
    let store: AppStore
    var dailyMileage: Double {
        let weekStart = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let weekTrips = store.tripHistory.filter{$0.startTime >= weekStart}
        return weekTrips.map{$0.distanceKm}.reduce(0,+)/7.0
    }
    var daysUntilEmpty: Int {
        guard dailyMileage > 0 else { return 999 }
        return Int(Double(store.car.flatMap { $0["energy"] as? [String: Any] }?.flatMap { $0["rangeKm"] as? Int } ?? 300 as? Int ?? 300) / dailyMileage)
    }
    var body: some View {
        HStack {
            VStack(alignment: .leading) { Text("日均里程").font(.caption2).foregroundColor(.secondaryLabel); Text("\(String(format:"%.1f",dailyMileage)) km").font(.title3).fontWeight(.semibold) }
            Spacer()
            VStack(alignment: .trailing) { Text("预计续航天数").font(.caption2).foregroundColor(.secondaryLabel); Text("\(daysUntilEmpty) 天").font(.title3).fontWeight(.semibold).foregroundColor(daysUntilEmpty<3 ? .red : .green) }
        }.padding().glassCard()
    }
}

// MARK: - E31 车辆健康综合评分
struct VehicleHealthScore: View {
    let store: AppStore
    private var tireHealth: Int { 85 }
    private var batteryHealth: Int { store.drivingScore }
    private var brakeHealth: Int { 90 }
    private var lightHealth: Int { 95 }
    var overallScore: Int { (tireHealth + batteryHealth + brakeHealth + lightHealth) / 4 }
    var healthLevel: String { switch overallScore { case 90...: return "优秀"; case 80...: return "良好"; case 70...: return "一般"; default: return "需检修" } }
    var healthColor: Color { switch overallScore { case 90...: return .green; case 80...: return .blue; case 70...: return .orange; default: return .red } }
    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Text("车辆健康评分").font(.subheadline).fontWeight(.semibold)
            ZStack { Circle().stroke(Color.secondary.opacity(0.2), lineWidth: 8); Circle().stroke(style: StrokeStyle(lineWidth: 8, lineCap: .round)).foregroundStyle(healthColor).rotationEffect(.degrees(270)).animation(.easeOut, value: overallScore); Text("\(overallScore)").font(.system(size: 32, weight: .bold, design: .rounded)).foregroundColor(healthColor) }.frame(width: 80, height: 80)
            Text(healthLevel).font(.caption).foregroundColor(healthColor)
        }.padding().glassCard()
    }
}

// MARK: - E32 命令成功率统计
struct CommandSuccessRate: View {
    let store: AppStore
    var successCount: Int { store.commandHistory.filter{$0.success}.count }
    var totalCount: Int { store.commandHistory.count }
    var successRate: Double { guard totalCount > 0 else { return 0 }; return Double(successCount)/Double(totalCount)*100 }
    var body: some View {
        HStack {
            VStack(alignment: .leading) { Text("命令成功率").font(.caption2).foregroundColor(.secondaryLabel); Text("\(String(format:"%.1f%%",successRate))").font(.title3).fontWeight(.semibold).foregroundColor(successRate>=90 ? .green : .orange) }
            Spacer()
            ProgressView(value: successRate/100).progressViewStyle(LinearProgressViewStyle()).frame(width: 80)
        }.padding().glassCard()
    }
}

// MARK: - E33 Siri使用习惯分析
struct SiriUsageAnalysis: View {
    let store: AppStore
    var topCommands: [(String, Int)] { store.siriUsageCount.sorted{$0.value>$1.value}.prefix(3) }
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Siri使用排行").font(.subheadline).fontWeight(.semibold)
            ForEach(Array(topCommands.enumerated()), id: \.offset) { idx, item in
                HStack { Text("#\(idx+1)").font(.caption).foregroundColor(.secondary).frame(width: 20); Text(item.key).font(.subheadline); Spacer(); Text("\(item.value)次").font(.caption).foregroundColor(.secondary) }
            }
        }.padding().glassCard()
    }
}
