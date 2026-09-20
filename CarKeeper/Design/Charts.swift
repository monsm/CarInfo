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
                    .foregroundStyle(Kansei.Color.glassBorder)
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(valueText(v))
                            .font(DS.Typo.caption2)
                            .foregroundStyle(Kansei.Color.tertiary)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                    .foregroundStyle(Kansei.Color.glassBorder.opacity(0.6))
                AxisValueLabel {
                    if let d = value.as(Date.self) {
                        Text(Self.axisTime(d))
                            .font(DS.Typo.caption2)
                            .foregroundStyle(Kansei.Color.tertiary)
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

// MARK: - 胎压趋势（四条曲线：左前 / 右前 / 左后 / 右后）

struct DSTyreTrendChart: View {
    var points: [HistoryStore.TyrePoint]
    var tint: Color = Kansei.Color.ambient
    var height: CGFloat = 156

    /// 四条线只用一支强调色的四个明度档 + 不同虚实，不引入第二支彩色
    private enum Wheel: String, CaseIterable {
        case fl = "左前", fr = "右前", rl = "左后", rr = "右后"
        var opacity: Double {
            switch self {
            case .fl: return 1.00
            case .fr: return 0.78
            case .rl: return 0.58
            case .rr: return 0.40
            }
        }
        var dash: [CGFloat] {
            switch self {
            case .fl: return []
            case .fr: return [6, 3]
            case .rl: return [2, 2.5]
            case .rr: return [8, 3, 2, 3]
            }
        }
        func value(_ p: HistoryStore.TyrePoint) -> Double? {
            switch self {
            case .fl: return p.fl
            case .fr: return p.fr
            case .rl: return p.rl
            case .rr: return p.rr
            }
        }
    }

    /// 一条待绘制的曲线段。写成小结构体而不是元组：
    /// Chart 的 `ForEach` 需要 Identifiable/键路径，而 Swift 的键路径不能指向元组元素。
    /// ⚠️ `id` 必须**逐点唯一**（ForEach 的硬要求），而 `series` 必须**逐轮位相同**
    /// —— 两者写反了，四条线会被并成一条，或者一条线被拆成一段段。
    private struct Mark: Identifiable {
        let id: String
        let series: String
        let t: Date
        let v: Double
        let dash: [CGFloat]
        let opacity: Double
    }

    /// 先把四条曲线摊平成一维再交给 Chart。
    /// 原来是 `ForEach(points) { ForEach(series(in:)) { … } }` 的嵌套写法，
    /// 内层那个 LineMark 表达式让类型检查器直接超时：
    /// `error: the compiler is unable to type-check this expression in reasonable time`。
    /// 摊平后内层只剩纯粹的成员读取，编译器不必再做嵌套重载推断。
    private var marks: [Mark] {
        var out: [Mark] = []
        out.reserveCapacity(points.count * Wheel.allCases.count)
        for p in points {
            let stamp = p.t.timeIntervalSince1970
            for wheel in Wheel.allCases {
                guard let v = wheel.value(p) else { continue }
                out.append(
                    Mark(id: "\(wheel.rawValue)@\(stamp)",
                         series: wheel.rawValue,
                         t: p.t,
                         v: v,
                         dash: wheel.dash,
                         opacity: wheel.opacity)
                )
            }
        }
        return out
    }

    private var allValues: [Double] {
        marks.map(\.v)
    }

    private var domain: ClosedRange<Double> {
        guard let lo = allValues.min(), let hi = allValues.max() else { return 200...260 }
        let pad = max((hi - lo) * 0.25, 8)
        return (lo - pad)...(hi + pad)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            Chart {
                ForEach(marks) { m in
                    LineMark(
                        x: .value("时间", m.t),
                        y: .value("kPa", m.v),
                        series: .value("轮位", m.series)
                    )
                    .foregroundStyle(tint.opacity(m.opacity))
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, dash: m.dash))
                    .interpolationMethod(.monotone)
                }
            }
            .chartYScale(domain: domain)
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(Kansei.Color.glassBorder)
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(String(format: "%.0f", v))
                                .font(DS.Typo.caption2)
                                .foregroundStyle(Kansei.Color.tertiary)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine()
                        .foregroundStyle(Kansei.Color.glassBorder.opacity(0.6))
                    AxisValueLabel {
                        if let d = value.as(Date.self) {
                            Text(d.formatted(.dateTime.month().day().hour()))
                                .font(DS.Typo.caption2)
                                .foregroundStyle(Kansei.Color.tertiary)
                        }
                    }
                }
            }
            .frame(height: height)

            // 图例：直接给当前值，省得在曲线上一根根找
            HStack(spacing: DS.Space.md) {
                ForEach(Wheel.allCases, id: \.rawValue) { wheel in
                    let last = points.last.flatMap { wheel.value($0) }
                    HStack(spacing: DS.Space.xs) {
                        Capsule()
                            .fill(tint.opacity(wheel.opacity))
                            .frame(width: 12, height: 2.5)
                        Text(wheel.rawValue)
                            .font(DS.Typo.caption2)
                            .foregroundStyle(Kansei.Color.secondary)
                        Text(last.map { String(format: "%.0f", $0) } ?? "--")
                            .font(DS.Typo.digits(11))
                            .foregroundStyle(Kansei.Color.primary)
                    }
                }
                Spacer(minLength: 0)
            }
            .accessibilityHidden(true)
        }
    }
}

// MARK: - 数据还不够时的说明（不是灰色占位块）

struct DSTrendEmpty: View {
    var icon: String
    var title: String
    var message: String

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.md) {
            Image(safeSymbol: icon, fallback: "chart.xyaxis.line")
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(Kansei.Color.tertiary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text(title)
                    .font(DS.Typo.subheadline.weight(.semibold))
                    .foregroundStyle(Kansei.Color.primary)
                Text(message)
                    .font(DS.Typo.footnote)
                    .foregroundStyle(Kansei.Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, DS.Space.xs)
        .accessibilityElement(children: .combine)
    }
}
