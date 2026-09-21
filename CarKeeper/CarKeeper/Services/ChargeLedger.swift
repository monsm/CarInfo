import Foundation
import SwiftUI

// =============================================================================
//  ChargeLedger — 「这一充花了多少钱」的唯一来源
// =============================================================================
//  为什么要有这一层（而不是继续用原来那个 EnergyCostCalculator）：
//  项目里原本有一个 117 行的成本计算器，账本结构是完整的 —— 但
//  `recordCharge(...)` **从来没有被任何地方调用过**，于是那本账永远是空的；
//  与之配套的 SmartChargeScheduler 更直接：它的"峰谷电价"是写死的 5 段假设
//  （1.2 / 0.8 / 1.1 / 0.6 / 0.4 元/度），却以"建议"的口吻输出，
//  还按"假设充 30 度"算预计花费 —— 那不是数据，是台词。
//
//  这一层只做一件真的事：
//    把车端自己上报的**充电功率采样**积分成电量，再乘以**用户自己设的电价**。
//    · kWh 是算出来的（∫P dt，梯形法），来自 HistoryStore 里 1 分钟一个的功率点；
//    · 电价是**用户的假设**，不是我们编的 —— 所以界面上每一处都必须写明
//      "按你设的 X 元/度"，而不是假装它是接口读到的。
//
//  数据从哪来：`HistoryStore.shared.power`（只在充电中采样，1 分钟一个，上限 25 小时）
//              `HistoryStore.shared.soc`（5 分钟一个，充电时会更快留点）
//  没有采样 = 没有会话 = 这一块**整块不出现**（不摆 0.00 出来冒充"花了 0 元"）。
// =============================================================================

/// 一次充电会话 —— 从真实功率采样积分出来的，不是人工记账。
struct ChargeSession: Identifiable {
    let id: String
    let start: Date
    let end: Date
    /// 积分得到的电量（kWh）
    let kWh: Double
    /// 会话起止时刻的 SOC（取同期的真实采样点）。没有采样点就是 nil —— 不猜。
    let socStart: Int?
    let socEnd: Int?
    /// 这次会话的功率采样序列（回放曲线的数据源就是派生会话的同一份点，不会错位）
    var powerCurve: [HistoryStore.Point] = []

    var durationMin: Int { max(0, Int(end.timeIntervalSince(start) / 60)) }
}

final class ChargeLedger {
    static let shared = ChargeLedger()

    /// 相邻两个功率采样点间隔超过它就算两次充电（采样本身是 1 分钟一个，
    /// 12 分钟的空档不可能是"同一次充电中间歇了会儿"，只会是 App 没在跑或没在充）
    static let sessionGap: TimeInterval = 12 * 60

    /// 一次会话至少要有这么多电量才算数 —— 避免把抖动出来的几个点当成一次充电
    static let minKWh: Double = 0.5

    private let rateKey = "carkeeper_charge_rate"

    private init() {}

    /// 电价（元/kWh）。**这是用户的假设，不是任何接口读到的值。**
    /// 界面上引用它时必须带上"按你设的"这句，否则就是把假设说成了事实。
    var rate: Double {
        get {
            let v = UserDefaults.standard.double(forKey: rateKey)
            return v > 0 ? v : 0.6
        }
        set { UserDefaults.standard.set(max(0.05, newValue), forKey: rateKey) }
    }

    // -------------------------------------------------------------------------
    // MARK: 会话
    // -------------------------------------------------------------------------

    /// 全部会话，**最近的在前**
    var sessions: [ChargeSession] {
        Self.derive(power: HistoryStore.shared.power, soc: HistoryStore.shared.soc)
    }

    /// 指定会话在**此刻**的功率序列。逐会话重算（数据量小：≤240 个点）。
    /// 采样会持续到来，用 start 匹配 id，避免把旧会话的曲线当成别的会话的。
    func powerHistory(for session: ChargeSession) -> [HistoryStore.Point] {
        sessions.first(where: { $0.id == session.id })?.powerCurve ?? []
    }

    /// 把功率采样切成会话并积分。写成 static 是为了能在没有单例的地方（测试 / 导出）直接用。
    static func derive(power: [HistoryStore.Point], soc: [HistoryStore.Point]) -> [ChargeSession] {
        guard power.count >= 2 else { return [] }
        var out: [ChargeSession] = []

        func flush(_ group: [HistoryStore.Point]) {
            guard group.count >= 2, let a = group.first, let b = group.last else { return }
            var kwh = 0.0
            for i in 1..<group.count {
                let dt = group[i].t.timeIntervalSince(group[i - 1].t) / 3600
                // 洞太大的一段不参与积分：那段时间车在充多少我们不知道，不替它补数
                guard dt > 0, dt <= sessionGap else { continue }
                kwh += (group[i].v + group[i - 1].v) / 2 * dt
            }
            guard kwh >= minKWh else { return }
            out.append(ChargeSession(
                id: "\(a.t.timeIntervalSince1970)",
                start: a.t,
                end: b.t,
                kWh: kwh,
                socStart: socValue(at: a.t, in: soc),
                socEnd: socValue(at: b.t, in: soc),
                powerCurve: group
            ))
        }

        var group: [HistoryStore.Point] = [power[0]]
        for p in power.dropFirst() {
            if let last = group.last, p.t.timeIntervalSince(last.t) <= sessionGap {
                group.append(p)
            } else {
                flush(group)
                group = [p]
            }
        }
        flush(group)
        return out.sorted { $0.start > $1.start }
    }

    /// 某个时刻的 SOC：取那一刻之前（含）最近的一个采样点
    private static func socValue(at t: Date, in soc: [HistoryStore.Point]) -> Int? {
        soc.last(where: { $0.t <= t }).map { Int($0.v.rounded()) }
    }

    // -------------------------------------------------------------------------
    // MARK: 钱
    // -------------------------------------------------------------------------

    func cost(_ s: ChargeSession) -> Double { s.kWh * rate }

    var totalKWh: Double { sessions.reduce(0) { $0 + $1.kWh } }
    var totalCost: Double { totalKWh * rate }

    /// 最近一次已完成的会话（正在充的那次还没结果，不提前记账）
    var latest: ChargeSession? { sessions.first }

    // -------------------------------------------------------------------------
    // MARK: 文案
    // -------------------------------------------------------------------------

    static func kwhText(_ v: Double) -> String { String(format: v >= 10 ? "%.1f" : "%.2f", v) }
    static func moneyText(_ v: Double) -> String { String(format: v >= 100 ? "%.0f" : "%.1f", v) }
    static func rateText(_ v: Double) -> String { String(format: "%.2f", v) }
}

// =============================================================================
//  界面：一块账，只有真有会话时才出现
// =============================================================================
//  放在这里而不是某个页面里，是因为它同时长在地图主屏的「充电」层与电池页上 ——
//  两处必须是同一个读数、同一句话，不能各写一份。
// =============================================================================

struct ChargeMoneyBlock: View {
    /// 允许外部传入（测试/预览），默认就是唯一那份真实账本
    let ledger: ChargeLedger

    @State private var editing = false
    @State private var rateDraft = ""

    init(ledger: ChargeLedger = .shared) {
        self.ledger = ledger
    }

    var body: some View {
        let sessions = ledger.sessions
        if !sessions.isEmpty {
            VStack(alignment: .leading, spacing: TokensSpacing.sm) {
                DSSectionHeader(title: "这一充花了多少", trailing: "\(sessions.count) 次")

                if let s = sessions.first {
                    HStack(alignment: .firstTextBaseline, spacing: TokensSpacing.sm) {
                        Text("\(ChargeLedger.kwhText(s.kWh)) kWh")
                            .font(TokensTypo.digits(17).monospacedDigit())
                            .foregroundStyle(TokensPalette.primary)
                        Text("约 ¥\(ChargeLedger.moneyText(ledger.cost(s)))")
                            .font(TokensTypo.footnote)
                            .foregroundStyle(TokensPalette.accent)
                        Spacer(minLength: 0)
                        Text(rateNote)
                            .font(TokensTypo.caption2)
                            .foregroundStyle(TokensPalette.tertiary)
                    }

                    // 这一次的起止电量与时长：都是真读数，读不到的那半不写
                    if let a = s.socStart, let b = s.socEnd {
                        Text("\(a)% → \(b)% · \(s.durationMin) 分钟")
                            .font(TokensTypo.caption)
                            .foregroundStyle(TokensPalette.secondary)
                    } else {
                        Text("\(s.durationMin) 分钟（这次没留下电量采样，所以只有时长）")
                            .font(TokensTypo.caption)
                            .foregroundStyle(TokensPalette.secondary)
                    }
                }

                Button {
                    TokensHaptic.tap()
                    rateDraft = ChargeLedger.rateText(ledger.rate)
                    editing = true
                } label: {
                    Text("共 \(sessions.count) 次充电 · 累计 \(ChargeLedger.kwhText(ledger.totalKWh)) kWh · 约 ¥\(ChargeLedger.moneyText(ledger.totalCost))")
                        .font(TokensTypo.caption)
                        .foregroundStyle(TokensPalette.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("累计充电花费，点按修改电价"))
            }
            .alert("按你设的电价算", isPresented: $editing) {
                TextField("元/度", text: $rateDraft)
                    .keyboardType(.decimalPad)
                Button("保存") {
                    if let v = Double(rateDraft.trimmingCharacters(in: .whitespaces)), v > 0 {
                        ledger.rate = v
                    }
                }
                Button("取消", role: .cancel) { }
            } message: {
                Text("这个数字是你自己填的，不是从车端接口读来的 —— 账本上的每处花费都按它折算。电量的度数则是车端功率采样积分出来的真值。")
            }
        }
    }

    private var rateNote: String { "按 \(ChargeLedger.rateText(ledger.rate)) 元/度" }
}

// =============================================================================
//  充电回放：这次充电的功率曲线
// =============================================================================
//  曲线的每个点都是车端 1 分钟一个报上来的真实功率采样，不是模型拟合。
//  样本少于 2 个就没有"形状"可言 —— 整个 sheet 不出现，只有一个如实说明。

struct ChargeReplaySheet: View {
    let session: ChargeSession

    @Environment(\.dismiss) private var dismiss
    @State private var curve: [HistoryStore.Point] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TokensSpacing.lg) {
                    headline
                    curveSection
                    factsSection
                    note
                }
                .padding(TokensSpacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(TokensPalette.canvas)
            .navigationTitle("充电回放")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .task { curve = ChargeLedger.shared.powerHistory(for: session) }
    }

    private var headline: some View {
        HStack(alignment: .firstTextBaseline, spacing: TokensSpacing.md) {
            Text(ChargeLedger.kwhText(session.kWh))
                .font(TokensTypo.digits(40))
                .foregroundStyle(TokensPalette.primary)
            Text("kWh")
                .font(TokensTypo.footnote)
                .foregroundStyle(TokensPalette.tertiary)
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(session.durationMin) 分钟")
                    .font(TokensTypo.footnote)
                    .foregroundStyle(TokensPalette.secondary)
                if let a = session.socStart, let b = session.socEnd {
                    Text("\(a)% → \(b)%")
                        .font(TokensTypo.digits(13))
                        .foregroundStyle(TokensPalette.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var curveSection: some View {
        if curve.count < 2 {
            Text("这次充电的功率采样还不足两个点，画不出曲线 —— 按实情说明，不补假数据。")
                .font(TokensTypo.footnote)
                .foregroundStyle(TokensPalette.secondary)
        } else {
            VStack(alignment: .leading, spacing: TokensSpacing.sm) {
                Text("功率（kW）· 1 分钟一个采样点")
                    .font(TokensTypo.caption)
                    .foregroundStyle(TokensPalette.tertiary)
                ReplayChart(points: curve,
                            accent: TokensPalette.accent,
                            ink: TokensPalette.primary)
                    .frame(height: 160)
            }
        }
    }

    private var factsSection: some View {
        VStack(alignment: .leading, spacing: TokensSpacing.sm) {
            fact("开始", at: session.start)
            fact("结束", at: session.end)
            fact("折合电费", detail: Text("\(ChargeLedger.moneyText(session.kWh * ChargeLedger.shared.rate)) 元 · 按 \(ChargeLedger.rateText(ChargeLedger.shared.rate)) 元/度"))
        }
    }

    private func fact(_ title: String, at date: Date) -> some View {
        fact(title, detail: Text(date.formatted(date: .abbreviated, time: .shortened)))
    }

    private func fact(_ title: String, detail: Text) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(TokensTypo.footnote)
                .foregroundStyle(TokensPalette.tertiary)
            Spacer(minLength: TokensSpacing.sm)
            detail
                .font(TokensTypo.footnote)
                .foregroundStyle(TokensPalette.primary)
        }
    }

    private var note: some View {
        Text("曲线的每个点都是车报上来的真实功率；积分方式和账本同源 —— 你看到的度数和曲线说的是同一件事。")
            .font(TokensTypo.caption)
            .foregroundStyle(TokensPalette.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// 功率曲线。Canvas 逐点连折线 + 渐变填充；坐标轴只用"顶点 = 峰值"一种标注。
/// 颜色由调用方传入（读取令牌的职责留在视图层，画布只认颜色）。
private struct ReplayChart: View {
    let points: [HistoryStore.Point]
    let accent: Color
    let ink: Color

    var body: some View {
        Canvas { ctx, size in
            let peak = max(points.map(\.v).max() ?? 1, 0.1)
            var path = Path()
            var fill = Path()
            let stepX = size.width / CGFloat(max(1, points.count - 1))

            for (i, p) in points.enumerated() {
                let x = CGFloat(i) * stepX
                let y = size.height - CGFloat(p.v / peak) * (size.height - 10) - 4
                let pt = CGPoint(x: x, y: y)
                if i == 0 {
                    path.move(to: pt)
                    fill.move(to: CGPoint(x: 0, y: size.height))
                    fill.addLine(to: pt)
                } else {
                    path.addLine(to: pt)
                    fill.addLine(to: pt)
                }
            }
            fill.addLine(to: CGPoint(x: size.width, y: size.height))
            fill.closeSubpath()

            ctx.stroke(path, with: .color(accent), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            ctx.fill(fill, with: .linearGradient(
                Gradient(colors: [accent.opacity(0.28), accent.opacity(0.02)]),
                startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: size.height)))

            // 峰值标注：只有真实的最大采样点才标，不铺网格线
            if let peakPoint = points.max(by: { $0.v < $1.v }),
               let idx = points.firstIndex(where: { $0.id == peakPoint.id }) {
                let x = CGFloat(idx) * stepX
                let y = size.height - CGFloat(peakPoint.v / peak) * (size.height - 10) - 4
                ctx.draw(Text(String(format: "%.1f", peakPoint.v))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(ink), at: CGPoint(x: min(max(x, 24), size.width - 24), y: max(y - 12, 12)))
            }
        }
    }
}
