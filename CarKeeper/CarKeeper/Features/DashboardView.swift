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
                    HStack(spacing: Kansei.Spacing.sm) {
                        ForEach(periods, id: \.self) { p in
                            periodChip(text: p, selected: period == p)
                        }
                    }
                }

                // 核心指标
                HStack(spacing: Kansei.Spacing.sm) {
                    DashTile(icon: "bolt.fill", label: "SOC",
                             value: energyModel.soc == "--" ? "--" : "\(energyModel.socPct)%", color: .green)
                    DashTile(icon: "gauge", label: "续航",
                             value: energyModel.range == "--" ? "--" : "\(energyModel.range)km", color: .blue)
                    DashTile(icon: "thermometer", label: "温度", value: comfortModel.cabinTemp, color: .orange)
                }

                // SOC 历史（真实车端采样）
                // 这里原来是 `store.energyHistory.prefix(7)` 画的"日期"轴曲线 ——
                // 但 energyHistory 只是 20 条 / 60 秒的实时缓冲，7 个点全在同一分钟内，
                // 图上写的"日期"根本不成立。现在读 HistoryStore 的真实采样。
                let socPoints = HistoryStore.shared.socSeries(hours: 24 * 7)
                    .map { DSTrendChart.Point(t: $0.t, v: $0.v) }
                if socPoints.count >= 2 {
                    DSTrendChart(points: socPoints,
                                 unit: "%",
                                 tint: Kansei.Color.ambient,
                                 yDomain: 0...100,
                                 valueText: { String(format: "%.0f", $0) })
                } else {
                    DSTrendEmpty(
                        icon: "chart.xyaxis.line",
                        title: "正在积累 SOC 数据",
                        message: "服务端没有历史接口，曲线由 App 每 \(Int(HistoryStore.socInterval / 60)) 分钟采样一次。已记录 \(socPoints.count) 个点。"
                    )
                }

                // 驾驶评分
                let score = store.drivingScore
                VStack(alignment: .leading, spacing: Kansei.Spacing.sm) {
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
        .background(Kansei.Color.background)
        .navigationTitle("仪表盘")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func periodChip(text: String, selected: Bool) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundColor(selected ? .white : .secondary)
            .padding(.horizontal, Kansei.Spacing.md)
            .padding(.vertical, Kansei.Spacing.xs)
            .background(selected ? Kansei.Color.ambient : Color.clear)
            .cornerRadius(Kansei.Radius.small)
    }
}

struct DashTile: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: Kansei.Spacing.xs) {
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
        .padding(.vertical, Kansei.Spacing.sm)
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
