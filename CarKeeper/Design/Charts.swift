// =============================================================================
// N21-N25 数据可视化图表 — 雷达图/柱状图/历史曲线/饼图
// =============================================================================

import SwiftUI
import Charts

// MARK: - N21 驾驶行为雷达图
struct DrivingRadarChart: View {
    let aggressiveAccel: Int
    let harshBrake: Int
    let smoothDrive: Int
    let speedLimit: Int
    
    var body: some View {
        ZStack {
            ForEach(0..<5, id: \.self) { i in
                let radius = CGFloat(50 + i * 25)
                Circle()
                    .stroke(Color.secondary.opacity(0.1), lineWidth: 0.5)
                    .frame(width: radius * 2, height: radius * 2)
            }
            
            // 轴线
            ForEach(Array(0..<4), id: \.self) { i in
                LineMark(
                    x: .value("轴", ""),
                    y: .value("值", 100),
                    series: .value("维度", ["加速", "刹车", "平稳", "限速"][i])
                )
                .foregroundStyle(Color.secondary.opacity(0.2))
                .symbol {}
            }
            
            // 数据多边形
            Chart {
                ForEach(radarPoints(), id: \.dimension) { point in
                    PointMark(
                        x: .value("角度", angle(for: point.dimension)),
                        y: .value("强度", point.value)
                    )
                    .foregroundStyle(accentColor(for: point.dimension))
                    .symbolSize(8)
                }
                
                // 填充区域 (iOS 26: PolygonMark removed — use AreaMark)
                AreaMark(
                    x: .value("角度", Array(radarPoints().indices).map { angle(for: radarPoints()[$0].dimension) }),
                    y: .value("强度", radarPoints().map { $0.value }),
                    stacking: .none
                )
                .foregroundStyle(Theme.Colors.accent.opacity(0.2))
            }
            .chartLegend(.hidden)
            .frame(width: 160, height: 160)
        }
        .overlay(
            VStack(spacing: 4) {
                Text("加速").font(.caption2).foregroundColor(.secondary)
                HStack {
                    Text("刹车").font(.caption2).foregroundColor(.secondary)
                    Spacer()
                    Text("平稳").font(.caption2).foregroundColor(.secondary)
                }
                Text("限速").font(.caption2).foregroundColor(.secondary)
            }
        )
    }
    
    private func radarPoints() -> [(dimension: String, value: Double)] {
        [
            ("加速", Double(aggressiveAccel)),
            ("刹车", Double(harshBrake)),
            ("平稳", Double(smoothDrive)),
            ("限速", Double(speedLimit))
        ]
    }
    
    private func angle(for dimension: String) -> Double {
        switch dimension {
        case "加速": return 0
        case "刹车": return 90
        case "平稳": return 180
        case "限速": return 270
        default: return 0
        }
    }
    
    private func accentColor(for dimension: String) -> Color {
        switch dimension {
        case "加速": return .orange
        case "刹车": return .red
        case "平稳": return .green
        case "限速": return .blue
        default: return Theme.Colors.accent
        }
    }
}

// MARK: - N23 能耗对比柱状图
struct EnergyCompareChart: View {
    let thisWeek: Double
    let lastWeek: Double
    let lastMonth: Double
    
    var body: some View {
        Chart {
            BarMark(
                x: .value("周期", "本周"),
                y: .value("能耗 kWh", thisWeek),
                width: .fixed(30)
            )
            .foregroundStyle(Theme.Colors.accent)
            
            BarMark(
                x: .value("周期", "上周"),
                y: .value("能耗 kWh", lastWeek),
                width: .fixed(30)
            )
            .foregroundStyle(.secondary.opacity(0.5))
            
            BarMark(
                x: .value("周期", "上月"),
                y: .value("能耗 kWh", lastMonth),
                width: .fixed(30)
            )
            .foregroundStyle(.tertiary.opacity(0.5))
        }
        .chartXAxis {
            AxisMarks(values: ["本周", "上周", "上月"])
        }
        .frame(height: 140)
    }
}

// MARK: - N24 车辆状态历史曲线
struct VehicleStatusChart: View {
    let socHistory: [(Date, Int)]
    let tempHistory: [(Date, Double)]
    
    var body: some View {
        Chart {
            ForEach(Array(socHistory.enumerated()), id: \.offset) { _, point in
                LineMark(
                    x: .value("时间", point.0),
                    y: .value("SOC %", point.1)
                )
                .foregroundStyle(.green)
                .lineStyle(StrokeStyle(lineWidth: 2))
            }
            ForEach(Array(tempHistory.enumerated()), id: \.offset) { _, point in
                LineMark(
                    x: .value("时间", point.0),
                    y: .value("温度 °C", point.1)
                )
                .foregroundStyle(.orange)
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
            }
        }
        .frame(height: 120)
    }
}

// MARK: - N25 里程费用饼图
struct CostPieChart: View {
    let chargeCost: Double
    let fuelCost: Double
    let parkingCost: Double
    let maintenanceCost: Double
    
    var body: some View {
        let total = chargeCost + fuelCost + parkingCost + maintenanceCost
        guard total > 0 else { return Text("暂无数据").font(.caption) }
        
        struct Slice: Identifiable {
            let id = UUID()
            let name: String
            let value: Double
            let color: Color
        }
        
        let slices = [
            Slice(name: "充电", value: chargeCost, color: .green),
            Slice(name: "加油", value: fuelCost, color: .orange),
            Slice(name: "停车", value: parkingCost, color: .blue),
            Slice(name: "保养", value: maintenanceCost, color: .purple)
        ]
        
        Chart {
            ForEach(slices) { slice in
                SectorMark(
                    angle: .value("", slice.value),
                    innerRadius: .ratio(0.55),
                    outerRadius: .ratio(1)
                )
                .foregroundStyle(slice.color)
                .annotation(position: .overlay) {
                    Text("\(slice.name)")
                        .font(.caption2)
                        .foregroundColor(.white)
                }
            }
        }
        .frame(width: 100, height: 100)
    }
}

// MARK: - N22 充电站热力图（简化版，使用 MKCircle）
struct ChargingHeatOverlay: View {
    let stations: [(lat: Double, lng: Double, count: Int)]
    
    var body: some View {
        ZStack {
            ForEach(Array(stations.enumerated()), id: \.offset) { idx, station in
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.red.opacity(0.6), .orange.opacity(0.2), .clear],
                            startPoint: .center, endPoint: .outerEdge
                        )
                    )
                    .frame(width: CGFloat(station.count) * 30 + 20,
                           height: CGFloat(station.count) * 30 + 20)
                    .position(x: CGFloat(idx) * 50 + 25, y: 25)
            }
        }
        .frame(height: 100)
    }
}

// MARK: - 缺失的圖表組件存根（用於編譯通過）

struct BatteryHealthCard: View {
    let model: Any
    var body: some View {
        Text("電池健康度卡片")
            .font(.title3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
    }
}

struct ChargePowerChart: View {
    let model: Any
    var body: some View {
        Text("充電功率曲線")
            .font(.title3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
    }
}

struct SOCHistoryChart: View {
    let store: Any
    var body: some View {
        Text("SOC 歷史曲線")
            .font(.title3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
    }
}

struct TireTrendChart: View {
    let checkRaw: [String: Any]
    var body: some View {
        Text("車胎趨勢圖")
            .font(.title3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
    }
}

struct DrivingStyleHeatmap: View {
    let store: Any
    var body: some View {
        Text("駕駛風格熱力圖")
            .font(.title3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
    }
}

struct ChargeCostChart: View {
    let store: Any
    var body: some View {
        Text("充電成本圖")
            .font(.title3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
    }
}

struct SiriInsightView: View {
    let store: Any
    var body: some View {
        Text("Siri 使用洞察")
            .font(.title3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
    }
}
