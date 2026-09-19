// =============================================================================
// DrivingScorePage - 驾驶评分页（雷达图 + 分项得分 + 改进建议）
// =============================================================================

import SwiftUI
import Charts

struct DrivingScorePage: View {
    @StateObject private var store = AppStore.shared
    @State private var showingDetails = false
    
    // 驾驶评分计算
    var overallScore: Int {
        guard !store.tripHistory.isEmpty else { return 0 }
        let scores = store.tripHistory.map { calculateTripScore($0) }
        return Int(scores.reduce(0, +) / Double(scores.count))
    }
    
    var smoothDrivingScore: Int {
        min(100, max(0, 100 - Int(store.hardAccelCount * 5)))
    }
    
    var safeSpeedScore: Int {
        guard let best = store.tripHistory.max(by: { $0.avgSpeed < $1.avgSpeed }) else { return 80 }
        return min(100, max(0, Int(100 - best.avgSpeed * 0.5)))
    }
    
    var efficiencyScore: Int {
        guard let eff = store.tripHistory.last?.avgEfficiency else { return 70 }
        return min(100, max(0, Int(120 - eff)))
    }
    
    var comfortScore: Int {
        min(100, max(0, 100 - Int(store.hardBrakeCount * 3)))
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
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.md)
        }
        .pageBackground(Theme.pagePurple)
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
                        .font(Theme.caption)
                        .foregroundStyle(.secondary)
                    Text("等级 \(scoreGrade)")
                        .font(Theme.subheadline)
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
        .glassCard(corner: Theme.Radius.hero)
    }
    
    // MARK: - 雷达图
    private var radarChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("驾驶能力雷达").font(Theme.subheadline.bold())
            Chart {
                RadarSlice(value: smoothDrivingScore, label: "平稳", color: .green)
                RadarSlice(value: safeSpeedScore, label: "守规", color: .blue)
                RadarSlice(value: efficiencyScore, label: "节能", color: .cyan)
                RadarSlice(value: comfortScore, label: "舒适", color: .orange)
            }
            .frame(height: 200)
            .glassCard(corner: Theme.Radius.medium)
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
                Image(systemName: icon)
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
                .font(Theme.subheadline.bold())
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
                Text("改进建议").font(Theme.subheadline.bold())
            }
            
            ForEach(improvementTips, id: \.self) { tip in
                HStack {
                    Image(systemName: "chevron.right.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.accent)
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
        VStack(alignment: .leading, spacing: 8) {
            Text("得分趋势").font(Theme.subheadline.bold())
            Chart {
                ForEach(Array(store.tripHistory.suffix(7).enumerated()), id: \.offset) { idx, trip in
                    PointMark(
                        x: .value("序号", idx + 1),
                        y: .value("评分", calculateTripScore(trip))
                    )
                    .foregroundStyle(scoreColor)
                }
                LineMark(
                    path: .value("得分", store.tripHistory.suffix(7).map { calculateTripScore($0) })
                )
                .foregroundStyle(scoreColor.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 2))
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: 1)) { _ in
                    AxisGridLine.strokeBorder()
                    AxisTick(stroke: StrokeStyle(lineWidth: 1))
                    AxisValueLabel(format: .number)
                }
            }
            .frame(height: 120)
            .glassCard(corner: Theme.Radius.medium)
        }
    }
    
    // MARK: - 辅助方法
    private func calculateTripScore(_ trip: TripRecord) -> Int {
        var score = 70 // 基础分
        
        // 能耗评分
        if let eff = trip.avgEfficiency {
            if eff < 12 { score += 20 }
            else if eff < 15 { score += 10 }
            else if eff > 20 { score -= 15 }
        }
        
        // 平稳度
        score += min(10, max(-10, (100 - trip.distanceKm) / 5))
        
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
