// =============================================================================
//  DrivingScorePage — 驾驶评分
// =============================================================================
//  这一页只做**数据允许它做**的事：用行程里真有的事实打分。
//
//  车端接口不提供加速度、踏板开度、转向角 —— 所以"急加速 / 急刹车 / 舒适度"
//  这类维度在这里**根本量不出来**。这一页原先写了四项，其中两项是常量
//  （`100 - Int(0 * 5)`，恒等于 100），还有一项把"距离越短分越高"当成平稳度
//  （`(100 - distanceKm) / 5`，跑 20 公里就加满 10 分）。那不是评分，是填格子。
//
//  现在只留三项能算的，并把算法写在页面上（可争论、可改）：
//    ① 能耗 —— 每段的 kWh/100km 与基准 15 比，每高出 1 度扣 4 分
//    ② 平稳 —— 各段能耗的离散程度（变异系数越小越平顺），少于 3 段不给分
//    ③ 达标 —— 能耗不高于基准的行程占比
//
//  任何一项没有真实读数时显示 **—**，不是 0 分；三项都没有时这一页直说
//  "还没有留下能耗读数"，而不是给一个好看的默认分（原来默认给 75 分）。
// =============================================================================

import SwiftUI
import Charts
import Foundation

struct DrivingScorePage: View {
    private let store = AppStore.shared

    /// 能耗基准（kWh/100km）。与地图主屏「为什么」里引用的是同一个口径，
    /// 全 App 只有这一个数，改这里就够了。
    static let baselineEfficiency = 15.0

    // -------------------------------------------------------------------------
    // MARK: 三个维度（算不出来就是 nil）
    // -------------------------------------------------------------------------

    /// 有能耗读数的行程（没有读数的行程不参与任何计算，也不拉低分母）
    private var efforts: [Double] {
        store.tripHistory.compactMap { $0.avgEfficiency }
    }

    /// ① 能耗分
    private var energyScore: Int? {
        guard !efforts.isEmpty else { return nil }
        let avg = efforts.reduce(0, +) / Double(efforts.count)
        return Self.energyPoints(avg)
    }

    /// ② 平稳分：能耗的变异系数。两段之间谈不上"离散程度"，所以少于 3 段不给分。
    private var steadyScore: Int? {
        guard efforts.count >= 3 else { return nil }
        let mean = efforts.reduce(0, +) / Double(efforts.count)
        guard mean > 0 else { return nil }
        let variance = efforts.reduce(0.0) { $0 + ($1 - mean) * ($1 - mean) } / Double(efforts.count)
        let cv = variance.squareRoot() / mean
        return Self.clamp(Int(100 - cv * 200))
    }

    /// ③ 达标分：能耗不高于基准的段数占比
    private var hitScore: Int? {
        guard !efforts.isEmpty else { return nil }
        let hit = efforts.filter { $0 <= Self.baselineEfficiency }.count
        return Self.clamp(Int(Double(hit) / Double(efforts.count) * 100))
    }

    /// 总分 = **有读数的那几项的**平均。一项都没有就是 nil（不是 0，也不是 75）。
    private var overallScore: Int? {
        let dims = [energyScore, steadyScore, hitScore].compactMap { $0 }
        guard !dims.isEmpty else { return nil }
        return Int(Double(dims.reduce(0, +)) / Double(dims.count))
    }

    private var grade: String? {
        guard let s = overallScore else { return nil }
        switch s {
        case 90...: return "S"
        case 80..<90: return "A"
        case 70..<80: return "B"
        case 60..<70: return "C"
        default: return "D"
        }
    }

    /// 分数色：只表达"好不好"，不表达情绪；四套主题各自取值。
    private var scoreTint: Color {
        guard let s = overallScore else { return TokensPalette.tertiary }
        switch s {
        case 80...: return TokensPalette.success
        case 60..<80: return TokensPalette.info
        case 40..<60: return TokensPalette.warning
        default: return TokensPalette.error
        }
    }

    private static func clamp(_ v: Int) -> Int { max(0, min(100, v)) }

    /// 能耗 → 分数。比基准还省就封顶 100。
    private static func energyPoints(_ eff: Double) -> Int {
        clamp(Int(100 - (eff - baselineEfficiency) * 4))
    }

    // -------------------------------------------------------------------------
    // MARK: 界面
    // -------------------------------------------------------------------------

    var body: some View {
        ScrollView {
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
            .padding(.horizontal, TokensSpacing.page)
            .padding(.vertical, TokensSpacing.md)
        }
        .navigationTitle("驾驶评分")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityLabel(Text("驾驶评分详情"))
    }

    // MARK: 头部：一个数字，不装容器
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
                        .font(.system(size: 64, weight: .light).monospacedDigit())
                        .foregroundStyle(TokensPalette.tertiary)
                }
                Spacer(minLength: 0)
            }

            Text("\(store.tripHistory.count) 段行程 · 其中 \(efforts.count) 段留下了能耗读数")
                .font(TokensTypo.caption)
                .foregroundStyle(TokensPalette.secondary)

            Text("基准 \(Int(Self.baselineEfficiency)) kWh/100km · 每高出 1 度扣 4 分")
                .font(TokensTypo.caption2)
                .foregroundStyle(TokensPalette.tertiary)
        }
    }

    // MARK: 三项
    private var dimensions: some View {
        VStack(alignment: .leading, spacing: TokensSpacing.md) {
            DSSectionHeader(title: "三项来源")
            dimRow("能耗", "bolt.fill", energyScore, TokensPalette.info,
                   note: "各段平均电耗与基准的差")
            dimRow("平稳", "waveform.path.ecg", steadyScore, TokensPalette.success,
                   note: efforts.count >= 3
                       ? "各段电耗的一致程度（越一致越平顺）"
                       : "需要至少 3 段有读数的行程才算得出")
            dimRow("达标", "checkmark.seal.fill", hitScore, TokensPalette.accent,
                   note: "电耗不高于基准的行程占比")
        }
    }

    private func dimRow(_ title: String, _ icon: String, _ value: Int?,
                        _ tint: Color, note: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
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

    /// 图上的一个点。用结构体而不是元组：Charts 的 ForEach 需要 Identifiable，
    /// 而 Swift 的 key path 不能指向元组元素（`\.0` 不是合法 key path，写元组编译不过）。
    private struct ScorePoint: Identifiable {
        let id: Int
        let v: Int
    }

    // MARK: 每一段：真实逐段得分
    @ViewBuilder
    private var perTrip: some View {
        let recent = Array(store.tripHistory.prefix(8)).reversed()
        let points: [ScorePoint] = recent.enumerated().compactMap { idx, t in
            guard let eff = t.avgEfficiency else { return nil }
            return ScorePoint(id: idx + 1, v: Self.energyPoints(eff))
        }
        if points.count >= 2 {
            VStack(alignment: .leading, spacing: TokensSpacing.sm) {
                DSSectionHeader(title: "逐段得分", trailing: "只看每一段自己的电耗")
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
            emptyNotice("有能耗读数的行程还不够画出趋势 —— 两段以上才连得成线。")
        }
    }

    // MARK: 没有数据时：说清为什么，不给分
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: TokensSpacing.sm) {
            DSSectionHeader(title: "还没有评分")
            Text("评分只用行程里真有的事实算：电耗与各段电耗的一致程度。到目前为止还没有一段行程留下能耗读数 —— 所以这里不给分。")
                .font(TokensTypo.footnote)
                .foregroundStyle(TokensPalette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(TokensSpacing.md)
        .background {
            RoundedRectangle(cornerRadius: TokensRadius.medium, style: .continuous)
                .fill(TokensPalette.surface)
        }
    }

    // MARK: 这一页量不出来的东西（写在明面上，不装成没这回事）
    private var caveat: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("为什么只有三项")
                .font(TokensTypo.caption.weight(.semibold))
                .foregroundStyle(TokensPalette.secondary)
            Text("车端接口不给加速度、踏板开度或转向角，所以急加速、急刹车、舒适度这类维度在这里无法测量 —— "
                 + "它们以前是写死的常量（恒等于 100 分），现在被去掉了，而不是继续假装有。")
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
