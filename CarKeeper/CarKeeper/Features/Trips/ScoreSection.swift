
import SwiftUI
import Charts
import Foundation

struct ScoreSection: View {
    private let store = AppStore.shared

    private var efforts: [Double] {
        store.tripHistory.compactMap { $0.avgEfficiency }
    }

    private var percents: [Double] {
        store.tripHistory.compactMap { $0.kmPerPercent }
    }

    private var score: DriveScore { DriveScore(efforts: efforts, percents: percents) }

    private var usesPercent: Bool { score.usesPercent }
    private var metric: [Double] { score.metric }
    private var baseline: Double? { score.baseline }
    private var energyScore: Int? { score.energy }
    private var steadyScore: Int? { score.steady }
    private var hitScore: Int? { score.hit }
    private var overallScore: Int? { score.overall }
    private var grade: String? { score.grade }

    private var scoreTint: Color {
        guard let s = overallScore else { return TokensPalette.tertiary }
        switch s {
        case 80...: return TokensPalette.success
        case 60..<80: return TokensPalette.info
        case 40..<60: return TokensPalette.warning
        default: return TokensPalette.error
        }
    }


    var body: some View {
        Group {
            VStack(alignment: .leading, spacing: TokensSpacing.lg) {
                hero

                if overallScore == nil {
                    emptyState
                } else {
                    dimensions
                    perTrip
                }

                caveat
            }
        }
        .accessibilityLabel(Text("驾驶评分详情"))
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: TokensSpacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: TokensSpacing.sm) {
                if let s = overallScore {
                    DSBigNumber(value: "\(s)", unit: "分", size: 64, tint: scoreTint)
                    if let g = grade {
                        Text("等级 \(g)")
                            .font(TokensTypo.subheadline)
                            .foregroundStyle(scoreTint)
                    }
                } else {
                    Text("—")
                        .font(TokensTypo.display(64))
                        .foregroundStyle(TokensPalette.tertiary)
                }
                Spacer(minLength: 0)
            }

            Text("\(store.tripHistory.count) 段行程 · 其中 \(percents.count) 段有每 1% SOC 的续航读数")
                .font(TokensTypo.caption)
                .foregroundStyle(TokensPalette.secondary)

            Text(usesPercent
                 ? "每 1% SOC 的续航，基准是自己的中位数"
                 : "基准 \(Int(DriveScore.baselineEfficiency)) kWh/100km · 每高出 1 度扣 4 分")
                .font(TokensTypo.caption2)
                .foregroundStyle(TokensPalette.tertiary)
        }
    }

    private var dimensions: some View {
        VStack(alignment: .leading, spacing: TokensSpacing.md) {
            DSSectionHeader(title: "三项来源")
            dimRow(usesPercent ? "续航" : "能耗", "bolt.fill", energyScore, TokensPalette.info,
                   note: usesPercent ? "平均续航 vs 自己的中位数"
                                    : "平均电耗 vs 基准")
            dimRow("平稳", "waveform.path.ecg", steadyScore, TokensPalette.success,
                   note: metric.count >= 3
                       ? "读数一致程度"
                       : "至少 3 段有读数")
            dimRow("达标", "checkmark.seal.fill", hitScore, TokensPalette.accent,
                   note: usesPercent ? "达中位数九成的占比"
                                    : "电耗不超基准的占比")
        }
    }

    private func dimRow(_ title: String, _ icon: String, _ value: Int?,
                        _ tint: Color, note: String) -> some View {
        VStack(alignment: .leading, spacing: TokensSpacing.sm) {
            HStack(spacing: TokensSpacing.sm) {
                Image(safeSymbol: icon, fallback: "gauge")
                    .font(TokensTypo.caption)
                    .foregroundStyle(value == nil ? TokensPalette.tertiary : tint)
                Text(title)
                    .font(TokensTypo.subheadline)
                    .foregroundStyle(TokensPalette.primary)
                Spacer(minLength: 0)
                Text(value.map { "\($0)" } ?? "—")
                    .font(TokensTypo.digits(15).monospacedDigit())
                    .foregroundStyle(value == nil ? TokensPalette.tertiary : tint)
            }

            if let v = value {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(TokensPalette.track)
                            .frame(height: 5)
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(tint)
                            .frame(width: geo.size.width * CGFloat(v) / 100, height: 5)
                    }
                }
                .frame(height: 5)
            }

            Text(note)
                .font(TokensTypo.caption2)
                .foregroundStyle(TokensPalette.tertiary)
        }
    }

    private struct ScorePoint: Identifiable {
        let id: Int
        let v: Int
    }

    @ViewBuilder
    private var perTrip: some View {
        let recent = Array(store.tripHistory.prefix(8)).reversed()
        let base = baseline
        let points: [ScorePoint] = recent.enumerated().compactMap { idx, t in
            guard let base else { return nil }
            let v = usesPercent ? t.kmPerPercent : t.avgEfficiency
            guard let v else { return nil }
            return ScorePoint(id: idx + 1,
                              v: DriveScore.efficiencyPoints(v, baseline: base,
                                                      lowerIsBetter: !usesPercent))
        }
        if points.count >= 2 {
            VStack(alignment: .leading, spacing: TokensSpacing.sm) {
                DSSectionHeader(title: "逐段得分",
                                trailing: usesPercent ? "只看续航" : "只看电耗")
                Chart {
                    ForEach(points) { p in
                        LineMark(x: .value("第几段", p.id), y: .value("得分", p.v))
                            .foregroundStyle(TokensPalette.accent.opacity(0.6))
                        PointMark(x: .value("第几段", p.id), y: .value("得分", p.v))
                            .foregroundStyle(scoreTint)
                    }
                }
                .chartYScale(domain: 0...100)
                .frame(height: 130)
            }
        } else {
            emptyNotice("至少两段才连得成线")
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: TokensSpacing.sm) {
            DSSectionHeader(title: "还没有评分")
            emptyNotice("还没有一段行程留下读数。")
            emptyNotice("跑一段路、熄火，就会自动生成行程")
                .font(TokensTypo.footnote)
                .foregroundStyle(TokensPalette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(TokensSpacing.md)
        .background {
            RoundedRectangle(cornerRadius: TokensRadius.medium, style: .continuous)
                .fill(TokensPalette.panel)
        }
    }

    private var caveat: some View {
        VStack(alignment: .leading, spacing: TokensSpacing.sm) {
            Text("为什么只有三项")
                .font(TokensTypo.caption.weight(.semibold))
                .foregroundStyle(TokensPalette.secondary)
            Text("车端不提供加速度、踏板、转向角。")
                .font(TokensTypo.caption2)
                .foregroundStyle(TokensPalette.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func emptyNotice(_ text: String) -> some View {
        Text(text)
            .font(TokensTypo.caption)
            .foregroundStyle(TokensPalette.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
