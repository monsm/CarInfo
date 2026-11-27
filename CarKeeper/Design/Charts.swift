
import SwiftUI
import Charts


struct DSTrendChart: View {
    struct Point: Identifiable {
        var id: String { "\(t.timeIntervalSince1970)-\(v)" }
        let t: Date
        let v: Double
    }

    var points: [Point]
    var unit: String
    var tint: Color
    var height: CGFloat = 148
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

    private static func axisTime(_ d: Date) -> String {
        Calendar.current.isDateInToday(d)
            ? d.formatted(date: .omitted, time: .shortened)
            : d.formatted(.dateTime.month().day().hour())
    }
}



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
