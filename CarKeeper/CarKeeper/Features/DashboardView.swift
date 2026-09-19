// =============================================================================
// #36 DashboardView — 仪表盘组件（整合能耗/驾驶/健康关键指标）
// =============================================================================

import SwiftUI
import Charts

struct DashboardView: View {
    private let store = AppStore.shared
    @State private var period: String = "7天"
    
    let periods = ["24小时", "7天", "30天"]
    
    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.md) {
                // 周期选择
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Spacing.sm) {
                        ForEach(periods, id: \.self) { p in
                            periodChip(text: p, selected: period == p)
                        }
                    }
                }
                
                // 核心指标
                HStack(spacing: Theme.Spacing.sm) {
                    DashTile(icon: "bolt.fill", label: "SOC", value: "\(store.car?.energy?.socPct ?? 0)%", color: .green)
                    DashTile(icon: "gauge.low", label: "续航", value: "\(store.car?.energy?.rangeKm ?? 0)km", color: .blue)
                    DashTile(icon: "thermometer.medium", label: "温度", value: "\(store.car?.climate?.tempC ?? 22)°C", color: .orange)
                }
                
                // 能耗图表
                if let history = store.energyHistory {
                    let last = Array(history.prefix(7))
                    ForEach(last.indices, id: \.self) { i in
                        let r = last[i]
                        LineMark(
                            x: .value("日期", r.timestamp),
                            y: .value("SOC", CGFloat(r.soc))
                        )
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .foregroundStyle(Theme.Colors.accent)
                    }
                }
                .frame(height: 150)
                .glassCard()
                
                // 驾驶评分
                let score = store.drivingScore
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("驾驶安全评分")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    HStack {
                        // 大圆环评分
                        ZStack {
                            Circle()
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 8)
                            Circle()
                                .stroke(style: StrokeStyle(lineWidth: 8, lineCap: .round))
                                .foregroundStyle(
                                    score >= 80 ? Color.green : score >= 60 ? Color.blue : Color.orange
                                )
                                .rotationEffect(.degrees(270))
                                .animation(.easeInOut, value: score)

                            Text("\(score)")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)
                        }
                        .frame(width: 80, height: 80)

                        VStack(alignment: .leading, spacing: 4) {
                            DashSubScore(label: "急加速", value: score / 3)
                            DashSubScore(label: "急刹车", value: score / 3 + 10)
                            DashSubScore(label: "平稳驾驶", value: score / 3 + 20)
                        }
                    }
                    .glassCard()
                }
            }
            .padding(.vertical)
        }
        .navigationTitle("仪表盘")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func periodChip(text: String, selected: Bool) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundColor(selected ? .white : .secondary)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.xs)
            .background(selected ? Theme.Colors.accent : Color.clear)
            .cornerRadius(Theme.Radius.sm)
    }
}

struct DashTile: View {
    let icon: String
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: Theme.Spacing.xs) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.sm)
        .glassCard()
    }
}

struct DashSubScore: View {
    let label: String
    let value: Int
    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text("\(value)")
                .font(.callout)
                .fontWeight(.semibold)
                .foregroundColor(value >= 80 ? .green : value >= 60 ? .blue : .orange)
        }
    }
}
