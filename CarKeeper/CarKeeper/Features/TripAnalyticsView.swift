// =============================================================================
//  行程 — v4（Apple 原生语言）
// =============================================================================
//  这一屏只有一个主角：里程数字。分段的柱状图通栏、不装进卡片 ——
//  图表是内容本身，不是卡片里的插图（Health / 健身的做法）。
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
        let trips = filteredTrips
        guard !trips.isEmpty else { return (0, 0, 0, nil) }

        let totalKm = trips.reduce(0) { $0 + $1.distanceKm }
        let avgKm = totalKm / Double(trips.count)
        let efficiencies = trips.compactMap { $0.avgEfficiency }
        let avgEff = efficiencies.isEmpty ? nil : efficiencies.reduce(0, +) / Double(efficiencies.count)

        return (totalKm, avgKm, trips.count, avgEff)
    }

    /// 周期筛选（此前 picker 只改了状态，没有任何一处读它 —— 选择器形同虚设）
    private var filteredTrips: [AppStore.TripRecord] {
        let cal = Calendar.current
        let now = Date()
        switch period {
        case .day:
            return store.tripHistory.filter { cal.isDate($0.startTime, inSameDayAs: now) }
        case .week:
            guard let start = cal.dateInterval(of: .weekOfYear, for: now)?.start else { return store.tripHistory }
            return store.tripHistory.filter { $0.startTime >= start }
        case .month:
            guard let start = cal.dateInterval(of: .month, for: now)?.start else { return store.tripHistory }
            return store.tripHistory.filter { $0.startTime >= start }
        case .all:
            return store.tripHistory
        }
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
            VStack(alignment: .leading, spacing: 0) {
                periodPicker
                    .padding(.bottom, DS.Space.xxl)

                totalHeader

                trendSection
                    .padding(.top, DS.Space.xxxl)

                behaviorSection
                    .padding(.top, DS.Space.xxxl)

                routesSection
                    .padding(.top, DS.Space.xxxl)
            }
            .padding(.top, DS.Space.md)
            .padding(.bottom, DS.Space.huge)
        }
        .background(KanseiPalette.background)
        .scrollBounceBehavior(.basedOnSize)
        .navigationTitle("行程")
        .navigationBarTitleDisplayMode(.large)
        .accessibilityLabel(Text("行程数据分析"))
    }

    // MARK: - 周期

    private var periodPicker: some View {
        Picker("周期", selection: $period) {
            ForEach(AnalyticsPeriod.allCases, id: \.self) { p in
                Text(p.rawValue).tag(p)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - 唯一的大数字

    private var totalHeader: some View {
        VStack(alignment: .leading, spacing: KanseiSpacing.sm) {
            Text(period.rawValue + "合计")
                .font(KanseiTypo.footnote)
                .foregroundStyle(KanseiPalette.secondary)
            DSBigNumber(
                value: String(format: "%.0f", tripStats.totalKm),
                unit: "km",
                size: 112,
                tint: KanseiPalette.ambient
            )
        }
    }

    // MARK: - 趋势（通栏、无框）

    private var trendSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("近 7 日里程")
                    .font(KanseiTypo.footnote)
                    .foregroundStyle(KanseiPalette.secondary)
                Spacer(minLength: KanseiSpacing.sm)
                Text(tripStats.avgKm > 0 ? String(format: "平均 %.0f km/次", tripStats.avgKm) : "--")
                    .font(KanseiTypo.caption)
                    .foregroundStyle(KanseiPalette.tertiary)
            }

            Chart {
                ForEach(weeklyTrend.indices, id: \.self) { i in
                    let item = weeklyTrend[i]
                    BarMark(
                        x: .value("日期", item.0, unit: .day),
                        y: .value("里程", item.1)
                    )
                    .foregroundStyle(isToday(item.0) ? KanseiPalette.ambient : KanseiPalette.glassBorder)
                    .cornerRadius(6)
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { value in
                    AxisValueLabel(format: .dateTime.weekday(.narrow))
                        .font(KanseiTypo.caption2)
                        .foregroundStyle(KanseiPalette.tertiary)
                }
            }
            .chartYAxis(.hidden)
            .chartLegend(.hidden)
            .frame(height: 148)
            .padding(.top, DS.Space.xl)
        }
    }

    private func isToday(_ date: Date) -> Bool {
        Calendar.current.isDateInToday(date)
    }

    // MARK: - 汇总（iOS 行）

    private var behaviorSection: some View {
        VStack(alignment: .leading, spacing: KanseiSpacing.sm) {
            DSSectionHeader(title: "行程汇总")
            DSCard {
                VStack(alignment: .leading, spacing: 0) {
                    DSRow(icon: "car.fill", title: "行程数", value: "\(tripStats.totalTrips) 次")
                    DSSeparator()
                    DSRow(icon: "gauge", title: "平均单次",
                          value: String(format: "%.1f km", tripStats.avgKm))
                    if let eff = tripStats.avgEfficiency {
                        DSSeparator()
                        DSRow(icon: "bolt.fill", title: "平均电耗",
                              value: String(format: "%.1f kWh/100km", eff))
                    }
                    DSSeparator()
                    DSRow(icon: "road.lanes", title: "本周期总里程",
                          value: String(format: "%.1f km", tripStats.totalKm))
                }
            }
        }
    }

    // MARK: - 最近行程

    private var routesSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            DSSectionHeader(title: "最近行程")
            DSCard {
                VStack(alignment: .leading, spacing: 0) {
                    let trips = Array(filteredTrips.prefix(5))
                    if trips.isEmpty {
                        DSPlaceholder(
                            icon: "point.topleft.down.to.point.bottomright.curvepath",
                            title: "还没有行程记录",
                            message: "开始行驶后，这里会显示每一次出行的里程与能耗。"
                        )
                    } else {
                        ForEach(Array(trips.enumerated()), id: \.offset) { idx, trip in
                            DSRow(
                                icon: tripIcon(idx),
                                title: tripTitle(trip),
                                subtitle: tripSubtitle(trip),
                                value: String(format: "%.1f km", trip.distanceKm),
                                showsChevron: true
                            ) {
                                NavState.shared.selectedTab = .home
                            }
                            if idx < trips.count - 1 { DSSeparator() }
                        }
                    }
                }
            }
        }
    }

    private func tripIcon(_ idx: Int) -> String {
        idx == 0 ? "flag.checkered" : "arrow.triangle.turn.up.right.diamond.fill"
    }

    private func tripTitle(_ trip: AppStore.TripRecord) -> String {
        if let end = trip.endTime {
            return end.formatted(date: .abbreviated, time: .shortened)
        }
        return trip.startTime.formatted(date: .abbreviated, time: .shortened)
    }

    private func tripSubtitle(_ trip: AppStore.TripRecord) -> String {
        guard let eff = trip.avgEfficiency else { return "无能耗数据" }
        return String(format: "电耗 %.1f kWh/100km", eff)
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
