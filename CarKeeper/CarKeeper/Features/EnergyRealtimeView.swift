// =============================================================================
// E1 实时能耗率显示
// E2 电池健康度 SOH 可视化
// E3 胎压趋势折线图
// E6 实时能耗仪表盘
// =============================================================================

import SwiftUI
import Charts

// MARK: - E1 实时能耗率
struct RealtimeEnergyDisplay: View {
    let store: AppStore

    var currentEnergyRate: Double {
        let history = store.energyHistory
        guard history.count >= 2 else { return 0 }
        let recent = history.filter { Date().timeIntervalSince($0.timestamp) < 3600 }
        guard recent.count >= 2 else { return 0 }
        let first = recent.first!
        let last = recent.last!
        let timeDiff = last.timestamp.timeIntervalSince(first.timestamp) / 3600 // hours
        let socDiff = Double(last.soc - first.soc)
        guard timeDiff > 0 else { return 0 }
        // 简化估算：每% SOC ≈ 0.15 kWh（假设15kWh电池）
        let energyUsed = abs(socDiff) / 100.0 * 15.0
        return energyUsed / timeDiff // kWh/h
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("实时能耗")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text("\(String(format: "%.1f", currentEnergyRate)) kWh")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundColor(currentEnergyRate > 30 ? .orange : .green)
            }
            Spacer()
            if currentEnergyRate > 25 {
                Image(systemName: "bolt.fill")
                    .foregroundColor(.orange)
                    .imageScale(.small)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .glassCard()
    }
}

// MARK: - E2 电池健康度 SOH
struct SOHDashboard: View {
    let store: AppStore
    private var maxRangeHistory: [Int] {
        store.energyHistory.map { $0.range }.reversed()
    }
    private var initialRange: Int {
        maxRangeHistory.last ?? 350
    }
    private var currentMaxRange: Int {
        maxRangeHistory.first ?? 350
    }
    private var soh: Double {
        guard initialRange > 0 else { return 100 }
        return Double(currentMaxRange) / Double(initialRange) * 100
    }
    private var sohColor: Color {
        switch soh {
        case 90...: return .green
        case 80...: return .blue
        case 70...: return .orange
        default: return .red
        }
    }

    var body: some View {
        VStack(spacing: Kansei.Spacing.sm) {
            Text("电池健康度 SOH")
                .font(.subheadline)
                .fontWeight(.semibold)

            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 12)
                Circle()
                    .stroke(style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .foregroundStyle(sohColor)
                    .rotationEffect(.degrees(270))
                    .animation(.spring(response: 0.6, dampingFraction: 0.7), value: soh)

                VStack {
                    Text(String(format: "%.0f%%", soh))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(sohColor)
                    Text("健康")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 100, height: 100)

            HStack {
                Text("最大续航: \(currentMaxRange) km")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("初始: \(initialRange) km")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .glassCard()
    }
}

// MARK: - E3 胎压趋势折线图
struct TirePressureTrendChart: View {
    let pressures: [TirePressureRecord]

    var body: some View {
        if pressures.count < 2 {
            Text("暂无胎压历史数据")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity)
                .glassCard()
        } else {
            Chart {
                ForEach(pressures.indices.dropLast(), id: \.self) { i in
                    LineMark(
                        x: .value("时间", pressures[i].time),
                        y: .value("压力 bar", pressures[i].pressure)
                    )
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                    .foregroundStyle(.blue)

                    PointMark(
                        x: .value("时间", pressures[i].time),
                        y: .value("压力 bar", pressures[i].pressure)
                    )
                    .foregroundStyle(.blue)
                    .symbolSize(20)
                }

                // 正常范围带
                RuleMark(y: .value("下限", 2.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
                    .foregroundStyle(.green.opacity(0.5))
                RuleMark(y: .value("上限", 3.0))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
                    .foregroundStyle(.green.opacity(0.5))
            }
            .chartYAxis {
                AxisMarks(values: [2.0, 2.5, 3.0, 3.5])
            }
            .frame(height: 120)
            .glassCard()
        }
    }
}

struct TirePressureRecord: Identifiable {
    let id = UUID()
    let time: Date
    let pressure: Double
}

// MARK: - E6 实时能耗仪表盘（弧形）
struct EnergyGaugeView: View {
    let rate: Double // kWh/100km
    let color: Color

    var body: some View {
        ZStack {
            // 背景弧
            RadiusArc(
                startAngle: .degrees(-225),
                endAngle: .degrees(45),
                color: .secondary.opacity(0.2),
                lineWidth: 12
            )
            // 进度弧
            RadiusArc(
                startAngle: .degrees(-225),
                endAngle: .degrees(45 + (rate / 40.0) * 270),
                color: color,
                lineWidth: 12
            )
                .animation(.easeOut(duration: 0.5), value: rate)

            VStack {
                Text("\(String(format: "%.1f", rate))")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text("kWh/100km")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: 80, height: 80)
    }
}

struct RadiusArc: View {
    let startAngle: Angle
    let endAngle: Angle
    let color: Color
    let lineWidth: CGFloat

    var body: some View {
        Circle()
            .trim(from: 0, to: 1)
            .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .foregroundStyle(color)
            .rotationEffect(.degrees(135))
            .clipShape(Circle())
            .overlay(
                Path { path in
                    let center = CGPoint(x: 50, y: 50)
                    let radius: CGFloat = 44
                    let start = point(onCircle: center, radius: radius, angle: startAngle)
                    let end = point(onCircle: center, radius: radius, angle: endAngle)
                    path.move(to: start)
                    path.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle,
                               clockwise: false)
                }
                .fill(color)
            )
            .frame(width: 100, height: 100)
    }

    private func point(onCircle center: CGPoint, radius: CGFloat, angle: Angle) -> CGPoint {
        let radians = angle.radians
        return CGPoint(x: center.x + radius * cos(radians), y: center.y + radius * sin(radians))
    }
}
