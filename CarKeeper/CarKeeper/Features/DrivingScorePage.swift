// =============================================================================
// DrivingScorePage - 驾驶评分页（雷达图 + 分项得分 + 改进建议）
// =============================================================================

import SwiftUI
import Charts

struct DrivingScorePage: View {
    private let store = AppStore.shared
    @State private var showingDetails = false

    // 驾驶评分计算
    var overallScore: Int {
        guard !store.tripHistory.isEmpty else { return 0 }
        let scores = store.tripHistory.map { calculateTripScore($0) }
        let avg = Double(scores.reduce(0, +)) / Double(scores.count)
        return Int(avg)
    }

    var smoothDrivingScore: Int {
        min(100, max(0, 100 - Int(0 * 5)))
    }

    var safeSpeedScore: Int {
        guard let best = store.tripHistory.max(by: { avgSpeed($0) < avgSpeed($1) }) else { return 80 }
        return min(100, max(0, Int(100 - avgSpeed(best) * 0.5)))
    }

    /// 平均车速（km/h）：依据行程距离与时长估算
    private func avgSpeed(_ trip: AppStore.TripRecord) -> Double {
        guard let end = trip.endTime else { return 0 }
        let hours = end.timeIntervalSince(trip.startTime) / 3600
        return hours > 0 ? trip.distanceKm / hours : 0
    }

    var efficiencyScore: Int {
        guard let eff = store.tripHistory.last?.avgEfficiency else { return 70 }
        return min(100, max(0, Int(120 - eff)))
    }

    var comfortScore: Int {
        min(100, max(0, 100 - Int(0 * 3)))
    }

    // 总分颜色
    var scoreColor: Color {
        switch overallScore {
        case 90...: return .green
        case 70..<90: return .blue
        case 50..<70: return .orange
        default: return .red
        }
    }

    var scoreGrade: String {
        switch overallScore {
        case 90...: return "S"
        case 80..<90: return "A"
        case 70..<80: return "B"
        case 60..<70: return "C"
        default: return "D"
        }
    }

    var improvementTips: [String] {
        var tips: [String] = []
        if smoothDrivingScore < 70 { tips.append("减少急加速次数") }
        if safeSpeedScore < 70 { tips.append("控制行驶速度") }
        if efficiencyScore < 70 { tips.append("保持平稳驾驶降低能耗") }
        if comfortScore < 70 { tips.append("提前预判减少急刹车") }
        if tips.isEmpty { tips.append("驾驶表现优秀，继续保持！") }
        return tips
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 总评分
                scoreHero

                // 雷达图
                radarChart

                // 分项得分
                splitScores

                // 改进建议
                improvementCard

                // 历史趋势
                scoreTrend
            }
            .padding(.horizontal, Kansei.Spacing.lg)
            .padding(.vertical, Kansei.Spacing.md)
        }
        .background(Kansei.Color.background)
        .navigationTitle("驾驶评分")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityLabel(Text("驾驶评分详情"))
    }

    // MARK: - 评分英雄卡
    private var scoreHero: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(scoreColor.opacity(0.1))
                    .frame(width: 140, height: 140)
                Circle()
                    .stroke(scoreColor, lineWidth: 3)
                    .frame(width: 140, height: 140)

                VStack {
                    Text("\(overallScore)")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundStyle(scoreColor)
                    Text("分")
                        .font(KanseiTypo.caption)
                        .foregroundStyle(Kansei.Color.secondary)
                    Text("等级 \(scoreGrade)")
                        .font(KanseiTypo.subheadline)
                        .foregroundStyle(scoreColor)
                }
            }

            // 总览文字
            HStack {
                Label("驾龄", systemImage: "calendar")
                Spacer()
                Label("行程数", systemImage: "route")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .glassCard(corner: Kansei.Radius.large)
    }

    // MARK: - 雷达图
    private var radarChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("驾驶能力雷达").font(KanseiTypo.subheadline.weight(.bold))
            Chart {
                RadarSlice(value: smoothDrivingScore, label: "平稳", color: .green)
                RadarSlice(value: safeSpeedScore, label: "守规", color: .blue)
                RadarSlice(value: efficiencyScore, label: "节能", color: .cyan)
                RadarSlice(value: comfortScore, label: "舒适", color: .orange)
            }
            .frame(height: 200)
            .glassCard(corner: Kansei.Radius.medium)
        }
    }

    // MARK: - 分项得分
    private var splitScores: some View {
        VStack(spacing: 10) {
            scoreRow(icon: "checkmark.seal.fill", label: "平稳驾驶", value: smoothDrivingScore, color: .green)
            scoreRow(icon: "speedometer", label: "速度控制", value: safeSpeedScore, color: .blue)
            scoreRow(icon: "leaf.fill", label: "能耗效率", value: efficiencyScore, color: .cyan)
            scoreRow(icon: "comfort", label: "舒适体验", value: comfortScore, color: .orange)
        }
        .glassCard(corner: Theme.Radius.medium)
    }

    private func scoreRow(icon: String, label: String, value: Int, color: Color) -> some View {
        HStack {
            HStack(spacing: 8) {
                Image(safeSymbol: icon, fallback: "gauge")
                    .font(.caption)
                    .foregroundStyle(color)
                Text(label).font(.subheadline).foregroundStyle(.primary)
            }
            Spacer()
            // 进度条
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color.opacity(0.2))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: geo.size.width * CGFloat(value) / 100, height: 6)
                }
            }
            .frame(height: 6)
            .frame(maxWidth: 100)

            Text("\(value)")
                .font(KanseiTypo.subheadline.weight(.bold))
                .foregroundStyle(color)
                .frame(width: 30)
        }
    }

    // MARK: - 改进建议
    private var improvementCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "lightbulb.fill")
                    .font(.caption)
                    .foregroundStyle(.yellow)
                Text("改进建议").font(Theme.font(.subheadline as Font).bold())
            }

            ForEach(improvementTips, id: \.self) { tip in
                HStack {
                    Image(systemName: "chevron.right.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(Kansei.Color.ambient)
                    Text(tip)
                        .font(.caption)
                        .foregroundStyle(.primary)
                }
            }
        }
        .padding()
        .glassCard(corner: Theme.Radius.medium)
        .background(Color.yellow.opacity(0.05))
    }

    // MARK: - 历史趋势
    private var scoreTrend: some View {
        let trips = Array(store.tripHistory.suffix(7))
        let points = trips.map { calculateTripScore($0) }
        return VStack(alignment: .leading, spacing: 8) {
            Text("得分趋势").font(Theme.font(.subheadline as Font).bold())
            Chart {
                ForEach(trips.indices, id: \.self) { i in
                    PointMark(
                        x: .value("序号", i + 1),
                        y: .value("评分", points[i])
                    )
                    .foregroundStyle(scoreColor)
                }
                ForEach(trips.indices, id: \.self) { i in
                    LineMark(
                        x: .value("序号", i + 1),
                        y: .value("得分", points[i])
                    )
                    .foregroundStyle(scoreColor.opacity(0.5))
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: 1)) { _ in
                    AxisGridLine()
                    AxisTick(stroke: StrokeStyle(lineWidth: 1))
                    AxisValueLabel()
                }
            }
            .frame(height: 120)
            .glassCard(corner: Kansei.Radius.medium)
        }
    }

    // MARK: - 辅助方法
    private func calculateTripScore(_ trip: AppStore.TripRecord) -> Int {
        var score = 70 // 基础分

        // 能耗评分
        if let eff = trip.avgEfficiency {
            if eff < 12 { score += 20 }
            else if eff < 15 { score += 10 }
            else if eff > 20 { score -= 15 }
        }

        // 平稳度
        score += min(10, max(-10, Int((100 - trip.distanceKm) / 5)))

        return max(0, min(100, score))
    }
}

// MARK: - Radar Chart Helper
struct RadarSlice: ChartContent {
    let value: Int
    let label: String
    let color: Color

    var body: some ChartContent {
        LineMark(
            x: .value("维度", label),
            y: .value("得分", value)
        )
        .foregroundStyle(color)
    }
}

// MARK: - Preview
struct DrivingScorePage_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            DrivingScorePage()
        }
    }
}
