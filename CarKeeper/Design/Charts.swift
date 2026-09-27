// =============================================================================
//  趋势图 — v4（Apple 原生语言）
// =============================================================================
//  三条曲线全部读 Services/HistoryStore.swift 的真实车端采样，
//  **不再有示例值**：这个文件里原来有几个"接线前先摆着"的图表，其中一个
//  （EnergyCompareChart 的便捷初始化）直接把 12 / 14 / 60 kWh 写死成柱状图 ——
//  那种东西看起来像数据，但不是数据，比空图更坏，所以整批删除。
//
//  规则与全 App 一致：通栏、不装卡片；网格只用发丝线；颜色只表达语义；
//  数字走等宽；没有足够采样时说清"为什么还没有数据"，不画灰色占位块。
// =============================================================================

import SwiftUI
import Charts

// MARK: - 单序列趋势（SOC 历史 / 充电功率共用）

struct DSTrendChart: View {
    struct Point: Identifiable {
        let id = UUID()
        let t: Date
        let v: Double
    }

    var points: [Point]
    /// Y 轴单位（也用于无障碍描述）
    var unit: String
    var tint: Color
    var height: CGFloat = 148
    /// 固定量程（SOC 用 0...100，因为"百分比"本身有自然边界）；nil = 按数据自适应
    var yDomain: ClosedRange<Double>? = nil
    var valueText: (Double) -> String = { String(format: "%.0f", $0) }

    private var domain: ClosedRange<Double> {
        if let yDomain { return yDomain }
        let values = points.map(\.v)
        guard let lo = values.min(), let hi = values.max() else { return 0...1 }
        if hi - lo < 0.5 { return (lo - 1)...(hi + 1) }
        let pad = (hi - lo) * 0.18
        return (lo - pad)...(hi + pad)
    }

    var body: some View {
        Chart {
            ForEach(points) { p in
                AreaMark(
                    x: .value("时间", p.t),
                    y: .value(unit, p.v)
                )
                .foregroundStyle(
                    LinearGradient(colors: [tint.opacity(0.18), tint.opacity(0.01)],
                                   startPoint: .top, endPoint: .bottom)
                )
                .interpolationMethod(.monotone)

                LineMark(
                    x: .value("时间", p.t),
                    y: .value(unit, p.v)
                )
                .foregroundStyle(tint)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.monotone)
            }
            // 只给最后一个点画标记：曲线本身已经说明了方向，不用一串圆点装饰。
            // （写成 ForEach(suffix(1)) 而不是 if-let：Chart 的 buildIf 分支尽量少用）
            ForEach(points.suffix(1)) { last in
                PointMark(
                    x: .value("时间", last.t),
                    y: .value(unit, last.v)
                )
                .foregroundStyle(tint)
                .symbolSize(46)
            }
        }
        .chartYScale(domain: domain)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(TokensPalette.hairline)
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(valueText(v))
                            .font(TokensTypo.caption2)
                            .foregroundStyle(TokensPalette.tertiary)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                    .foregroundStyle(TokensPalette.hairline.opacity(0.6))
                AxisValueLabel {
                    if let d = value.as(Date.self) {
                        Text(Self.axisTime(d))
                            .font(TokensTypo.caption2)
                            .foregroundStyle(TokensPalette.tertiary)
                    }
                }
            }
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("趋势图，共 \(points.count) 个采样点"))
        .accessibilityValue(Text(points.last.map { "最新 \(valueText($0.v)) \(unit)" } ?? "暂无数据"))
    }

    /// 轴上的时间：同一天只显示时刻，跨天显示"日 时"
    private static func axisTime(_ d: Date) -> String {
        Calendar.current.isDateInToday(d)
            ? d.formatted(date: .omitted, time: .shortened)
            : d.formatted(.dateTime.month().day().hour())
    }
}

// MARK: - 胎压趋势图（`DSTyreTrendChart`）已于 2026-09-27 删除
//
//  它是四个轮位的四条曲线（为了让编译器不超时，还把嵌套 ForEach 摊平成了一维
//  `CurveSegment`）。删它的理由是**零读者**：
//    · 充电页的「趋势」那一张卡只画 SOC 与充电功率（`DSTrendChart`），不画胎压；
//    · 胎压本身仍然看得到（地图抽屉、充电页明细、体检），只是没有曲线；
//    · 没人建它，而它养着 `HistoryStore` 里一份只为它采样的 `TyrePoint` ——
//      那一条链的下一环现在也只剩「写者」（见 HANDOFF 里那一类清单）。
//  真要看胎压趋势，到时候再从 git 历史里取回这一版（它当时已经跑通了）。

// MARK: - 数据还不够时的说明（不是灰色占位块）

struct DSTrendEmpty: View {
    var icon: String
    var title: String
    var message: String

    var body: some View {
        HStack(alignment: .top, spacing: TokensSpacing.md) {
            Image(safeSymbol: icon, fallback: "chart.xyaxis.line")
                .font(TokensTypo.fixed(20, weight: .light))
                .foregroundStyle(TokensPalette.tertiary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: TokensSpacing.xxs) {
                Text(title)
                    .font(TokensTypo.subheadline.weight(.semibold))
                    .foregroundStyle(TokensPalette.primary)
                Text(message)
                    .font(TokensTypo.footnote)
                    .foregroundStyle(TokensPalette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, TokensSpacing.xs)
        .accessibilityElement(children: .combine)
    }
}
