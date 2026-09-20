// =============================================================================
// #36 DashboardView — 仪表盘组件（整合能耗/驾驶/健康关键指标）
// =============================================================================

import SwiftUI
import Charts

struct DashboardView: View {
    private let store = AppStore.shared
    @State private var period: String = "7天"

    // ⚠️ 报文里没有 car["energy"] / car["climate"] 这两个嵌套对象（小程序也是用 charge / control / pm25 现算的），
    // 原来这样读 → 仪表盘的 SOC / 续航 / 温度恒显示 0% / 0km / 22°C。
    private var energyModel: EnergyModel { VM.energy(store.caches, store.car) }
    private var comfortModel: ComfortModel { VM.comfortStatus(store.caches) }
    
    let periods = ["24小时", "7天", "30天"]
    
    var body: some View {
        ScrollView {
            VStack(spacing: DS.Space.gap) {
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
                    DashTile(icon: "bolt.fill", label: "SOC",
                             value: energyModel.soc == "--" ? "--" : "\(energyModel.socPct)%", color: .green)
                    DashTile(icon: "gauge", label: "续航",
                             value: energyModel.range == "--" ? "--" : "\(energyModel.range)km", color: .blue)
                    DashTile(icon: "thermometer", label: "温度", value: comfortModel.cabinTemp, color: .orange)
                }
                
                // 能耗图表
                let history = store.energyHistory
                if !history.isEmpty {
                    let last = Array(history.prefix(7))
                    Chart {
                        ForEach(last.indices, id: \.self) { i in
                            LineMark(
                                x: .value("日期", last[i].timestamp),
                                y: .value("SOC", Double(last[i].soc))
                            )
                            .lineStyle(StrokeStyle(lineWidth: 2))
                            .foregroundStyle(Theme.Colors.accent)
                        }
                    }
                    .frame(height: 150)
                    .glassCard()
                }
                
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
            .padding(.vertical, DS.Space.sm)
        }
        .dsCanvas()
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
            Image(safeSymbol: icon, fallback: "gauge")
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
