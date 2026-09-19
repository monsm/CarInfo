// =============================================================================
// TripAnalyticsView - 行程分析（里程趋势 + 驾驶模式统计 + 每周报告）
// =============================================================================

import SwiftUI
import Charts

struct TripAnalyticsView: View {
    private let store = AppStore.shared
    @State private var period: AnalyticsPeriod = .week
    
    enum AnalyticsPeriod: String, CaseIterable {
        case day = "今日"
        case week = "本周"
        case month = "本月"
        case all = "全部"
    }
    
    // 聚合统计数据
    var tripStats: (totalKm: Double, avgKm: Double, totalTrips: Int, avgEfficiency: Double?) {
        let trips = store.tripHistory
        guard !trips.isEmpty else { return (0, 0, 0, nil) }
        
        let totalKm = trips.reduce(0) { $0 + $1.distanceKm }
        let avgKm = totalKm / Double(trips.count)
        let efficiencies = trips.compactMap { $0.avgEfficiency }
        let avgEff = efficiencies.isEmpty ? nil : efficiencies.reduce(0, +) / Double(efficiencies.count)
        
        return (totalKm, avgKm, trips.count, avgEff)
    }
    
    var weeklyTrend: [(Date, Double)] {
        let calendar = Calendar.current
        let now = Date()
        var result: [(Date, Double)] = []
        for dayOffset in (0..<7).reversed() {
            let date = calendar.date(byAdding: .day, value: -dayOffset, to: now) ?? now
            let dayTrips = store.tripHistory.filter {
                calendar.isDate($0.startTime, inSameDayAs: date)
            }
            let totalKm = dayTrips.reduce(0) { $0 + $1.distanceKm }
            result.append((date, totalKm))
        }
        return result
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 周期选择
                periodPicker
                
                // 核心指标
                statsGrid
                
                // 里程趋势图
                trendChart
                
                // 驾驶行为分布
                behaviorChart
                
                // 常用路线
                commonRoutes
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.md)
        }
        .pageBackground(Theme.pageBlue)
        .navigationTitle("行程分析")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityLabel(Text("行程数据分析"))
    }
    
    // MARK: - 周期选择
    private var periodPicker: some View {
        Picker("周期", selection: $period) {
            ForEach(AnalyticsPeriod.allCases, id: \.self) { p in
                Text(p.rawValue).tag(p)
            }
        }
        .pickerStyle(SegmentedPickerStyle())
        .glassCard(corner: Theme.Radius.medium)
    }
    
    // MARK: - 统计网格
    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            statTile(icon: "speedometer", label: "总里程", value: "\(tripStats.totalKm, format: .number.precision(.significantDigits(4))) km", tint: .blue)
            statTile(icon: "car.fill", label: "行程数", value: "\(tripStats.totalTrips)", tint: .green)
            statTile(icon: "gauge", label: "平均单次", value: "\(tripStats.avgKm, format: .number.precision(.significantDigits(3))) km", tint: .orange)
            if let eff = tripStats.avgEfficiency {
                statTile(icon: "bolt.fill", label: "平均能耗", value: String(format: "%.1f", eff) + " kWh", tint: .purple)
            }
        }
        .glassCard(corner: Theme.Radius.medium)
    }
    
    private func statTile(icon: String, label: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(tint)
                Spacer()
            }
            Text(value)
                .font(Theme.h3)
                .foregroundStyle(.primary)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    // MARK: - 趋势图
    private var trendChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("里程趋势").font(Theme.font(.subheadline as Font).bold())
            Chart {
                ForEach(weeklyTrend.indices, id: \.self) { i in
                    let item = weeklyTrend[i]
                    BarMark(
                        x: .value("日期", item.0.formatted(date: .abbreviated, time: .omitted)),
                        y: .value("里程", item.1)
                    )
                    .foregroundStyle(item.1 > 0 ? Color.accent : Color.secondary.opacity(0.3))
                    .cornerRadius(4)
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 2)) { _ in
                    AxisGridLine.strokeBorder(lineWidth: 0.5)
                    AxisTick().strokeBorder(lineWidth: 0.5)

                    AxisValueLabel(format: .dateTime.hour(.default(amPM: .narrow)).minute())
                }
            }
            .frame(height: 160)
            .glassCard(corner: Theme.Radius.medium)
        }
    }
    
    // MARK: - 驾驶行为分布
    private var behaviorChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("驾驶行为评分").font(Theme.font(.subheadline as Font).bold())
            HStack(spacing: 16) {
                gaugeTile(icon: "checkmark.seal.fill", label: "平稳驾驶", value: "92%", color: .green)
                gaugeTile(icon: "exclamation.triangle.fill", label: "急加速", value: "3次", color: .orange)
                gaugeTile(icon: "stop.fill", label: "急刹车", value: "2次", color: .red)
            }
        }
        .glassCard(corner: Theme.Radius.medium)
    }
    
    private func gaugeTile(icon: String, label: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            Text(value).font(Theme.h4.bold()).foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - 常用路线
    private var commonRoutes: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("常用目的地").font(Theme.font(.subheadline as Font).bold())
            VStack(spacing: 0) {
                ForEach(0..<min(3, store.tripHistory.count)) { i in
                    let trip = store.tripHistory[i]
                    HStack {
                        Text((i + 1)).font(.caption.monospaced()).foregroundStyle(.secondary)
                        VStack(alignment: .leading) {
                            Text(trip.endTime.map { "\($0, style: .date)" } ?? "")
                                .font(.subheadline)
                            Text("\(trip.distanceKm, format: .number.precision(.significantDigits(3))) km")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 8)
                    if i < 2 { Divider().opacity(0.3) }
                }
            }
        }
        .glassCard(corner: Theme.Radius.medium)
    }
}

// MARK: - Preview
struct TripAnalyticsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            TripAnalyticsView()
        }
    }
}
