// =============================================================================
//  ScoreSection — 驾驶评分（出行页里的一节）
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

/// 驾驶评分 —— 出行页里的一节（原为独立页 `DrivingScorePage`）。
///
/// 评分完全由**这一段行程的电耗**算出来（见下面三项），所以它就该长在
/// 行程时间轴旁边：看到一段开得费电，紧接着就能看到它对分数做了什么。
struct ScoreSection: View {
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

    /// 每 1% SOC 的续航（km）。报文里的 `capacity` 是 `null`，所以 kWh/100km 算不出来；
    /// 而这个口径**不需要容量**，是目前唯一真算得出的能效指标。
    private var percents: [Double] {
        store.tripHistory.compactMap { $0.kmPerPercent }
    }

    /// 当前用哪套口径。`true` = 每 1% SOC 多少 km。
    /// 口径**二选一、不混用** —— 混起来会把两种单位放进同一个均值。
    private var usesPercent: Bool { efforts.isEmpty }

    /// 参与计算的读数
    private var metric: [Double] { usesPercent ? percents : efforts }

    /// 基准。kWh 口径用固定基准；km/% 口径只能**与自己比**（车、人、路况、季节都不同，
    /// 拿别人的数当基准没有意义），所以取自己最近行程的中位数。
    private var baseline: Double? {
        if !usesPercent { return Self.baselineEfficiency }
        guard percents.count >= 2 else { return nil }
        let sorted = percents.sorted()
        return sorted[sorted.count / 2]
    }

    /// ① 能效分
    private var energyScore: Int? {
        guard let baseline, !metric.isEmpty else { return nil }
        let avg = metric.reduce(0, +) / Double(metric.count)
        return Self.efficiencyPoints(avg, baseline: baseline, lowerIsBetter: !usesPercent)
    }

    /// ② 平稳分：读数的变异系数（与口径方向无关，所以两套口径共用）。
    /// 两段之间谈不上"离散程度"，所以少于 3 段不给分。
    private var steadyScore: Int? {
        guard metric.count >= 3 else { return nil }
        let mean = metric.reduce(0, +) / Double(metric.count)
        guard mean > 0 else { return nil }
        let variance = metric.reduce(0.0) { $0 + ($1 - mean) * ($1 - mean) } / Double(metric.count)
        let cv = variance.squareRoot() / mean
        return Self.clamp(Int(100 - cv * 200))
    }

    /// ③ 达标分：比基准"不差"的段数占比（kWh 口径是不高于，km/% 口径是不低于九成）
    private var hitScore: Int? {
        guard let baseline, !metric.isEmpty else { return nil }
        let hit: Int
        if usesPercent {
            hit = metric.filter { $0 >= baseline * 0.9 }.count
        } else {
            hit = metric.filter { $0 <= baseline }.count
        }
        return Self.clamp(Int(Double(hit) / Double(metric.count) * 100))
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

    /// 读数 → 分数。
    ///   · kWh/100km（`lowerIsBetter`）：比基准还省就封顶 100，每高出 1 度扣 4 分。
    ///   · km/1%（否则）：比自己的中位数高就高分，±30% 对应满分 / 零分。
    private static func efficiencyPoints(_ v: Double, baseline: Double, lowerIsBetter: Bool) -> Int {
        guard baseline > 0 else { return 0 }
        if lowerIsBetter { return clamp(Int(100 - (v - baseline) * 4)) }
        return clamp(Int((v / baseline - 0.7) / 0.6 * 100))
    }

    // -------------------------------------------------------------------------
    // MARK: 界面
    // -------------------------------------------------------------------------

    var body: some View {
        Group {
            //  正文里原来有一行 `DSSectionHeader(title: "驾驶评分")`，而这张卡叫「评分」
            //  —— 卡头已经写了名字，正文的第一行就是主角（那个分数）。
            //  （用户 2026-09-24：「全部页面检查精致度」）
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
                        // display() 会带上主题的字重（原生 = 超细）—— 换主题时这几个巨字
                        // 本来就该跟着变：巨字方向的仪器感就来自这里。
                        .font(TokensTypo.display(64))
                        .foregroundStyle(TokensPalette.tertiary)
                }
                Spacer(minLength: 0)
            }

            Text("\(store.tripHistory.count) 段行程 · 其中 \(percents.count) 段有每 1% SOC 的续航读数")
                .font(TokensTypo.caption)
                .foregroundStyle(TokensPalette.secondary)

            // 口径写清楚：这句以前写死「基准 15 kWh/100km」，而那个口径需要电池容量，
            // 而报文里的 `capacity` 是 null —— 于是评分永远算不出来，这句话也就永远不该出现。
            Text(usesPercent
                 ? "每 1% SOC 的续航，基准是自己的中位数"
                 : "基准 \(Int(Self.baselineEfficiency)) kWh/100km · 每高出 1 度扣 4 分")
                .font(TokensTypo.caption2)
                .foregroundStyle(TokensPalette.tertiary)
        }
    }

    // MARK: 三项
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
        let base = baseline
        let points: [ScorePoint] = recent.enumerated().compactMap { idx, t in
            guard let base else { return nil }
            // 与上面同一套口径：有 kWh 用 kWh，否则用每 1% SOC 的续航。
            let v = usesPercent ? t.kmPerPercent : t.avgEfficiency
            guard let v else { return nil }
            return ScorePoint(id: idx + 1,
                              v: Self.efficiencyPoints(v, baseline: base,
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

    // MARK: 没有数据时：说清为什么，不给分
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
        // 这层底在**卡里**：读 `panel`（半透明分组面）而不是不透明的 `surface` ——
        // 用户 2026-09-25 第 5 条的截图里，这块「还没有评分」就是那个黑洞。
        .background {
            RoundedRectangle(cornerRadius: TokensRadius.medium, style: .continuous)
                .fill(TokensPalette.panel)
        }
    }

    // MARK: 这一页量不出来的东西（写在明面上，不装成没这回事）
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
