import SwiftUI

// =============================================================================
//  StackSpec —— 「上下叠叠乐」的全部几何与判定
// =============================================================================
//
//  这些数字不是调出来的，是**量出来的**：原型 `design-preview/stack.html` 里
//  每一条都有出处（卡片间距、上下消失带、滚轮节距、过冲比例、吸附临界）。
//  集中在一处的理由与令牌一样 —— 同一个决定只能做一次。六页各自写一遍，
//  就会出现「出行页手感对、充电页不对」。
//
//  三件事分开：
//    ① `StackVariant`  —— 叠法（原型里 A~G 七种，用来让人挑）
//    ② `StackMetrics`  —— 一个叠法的全部数值
//    ③ `StackMath`     —— 纯函数：焦点序号、吸附落点、两端硬停
//
//  ③ 之所以要单独拎出来：它是**没有视图也能验的**那部分。手感的对错最终要靠
//  真机，但「拖到 47% 该不该翻页」「最后一张能不能吸到阅读线」是算出来的，
//  算错了在真机上表现为「怪」，而怪是很难归因的。
enum StackSpec {

    /// 卡片自己的尺寸与圆角（原型 `.card{padding:17px 18px 16px;border-radius:26px}`）
    enum Card {
        static let radius = CGFloat(26)
        static let padH = CGFloat(18)
        static let padTop = CGFloat(17)
        static let padBottom = CGFloat(16)
        /// 卡片的外边距：屏幕左右各留 18（原型 `.stack{padding:… 18px …}`）
        static let inset = CGFloat(18)
    }

    /// 阅读线：被吸住的卡片停在这里（窗口高的比例，从顶部算）。
    /// 不取正中：正中会浪费掉上面一半，一屏能读到的卡从 3 张变成 2 张。
    static let dockRatio = CGFloat(0.30)

    /// 滚动的硬限位：到顶/到底就是**停**（用户 2026-09-23 的要求）。
    /// 越界阻尼试过一版：两端拖得动但越拖越沉 —— 结果是到底时末卡被拖上阅读线、
    /// 下面留一段空白，「时刻有卡可看」破了。硬停不会：卡停在阅读线上。
    static let endStop = CGFloat(0)

    /// 吸附的判据来自原型 `startSettle`：
    ///   · 方向偏置 0.85 → 临界点约 47%（小于它退回原来那张，过了就往手指方向那张去）
    ///   · 峰值速度超过阈值 → 甩出去的直接再走一格
    /// 原型里那个 0.55 的单位是 px/ms（500~600 px/s），换算过来就是这里这个数。
    static let directionBias = CGFloat(0.85)
    static let flingVelocity = CGFloat(550)

    /// 拖动的跟手滞后：形变（弧度/缩放）比位移晚一点点，所以是「追上来再贴合」。
    static let shapeLag = Animation.spring(response: 0.16, dampingFraction: 0.92)

    /// 用户在叠法对照页（`StackLabView`）里挑中的那一种存在这里。
    /// 六页的 `StackPageView` 默认读它 —— 于是「挑一种」是立刻生效的，
    /// 而不是「告诉我，我再改代码」。
    static let variantKey = "carkeeper_stack_variant"

    /// 当前生效的叠法。**默认弧出**（没挑过就是它）。
    static var chosen: StackVariant {
        guard let raw = UserDefaults.standard.string(forKey: variantKey),
              let v = StackVariant(rawValue: raw) else { return .arc }
        return v
    }

    /// 记下挑中的那一种。
    static func remember(_ v: StackVariant) {
        UserDefaults.standard.set(v.rawValue, forKey: variantKey)
    }

    /// 回落用的弹簧。阻尼比 ≈ 0.67 → 过冲约 5%，那一下就是「吸住」。
    /// 用 `interpolatingSpring` 而不是 `easeOutBack` 是因为前者能被手指打断
    /// （原地重开一个 withAnimation 就接管了），后者是个不可打断的自动播放。
    static let settle = Animation.interpolatingSpring(mass: 1, stiffness: 180, damping: 18)

    /// 回落弹簧，带**手指那一瞬的速度**。
    ///
    /// `initialVelocity` 的单位是「剩余距离的倍数 / 秒」—— 所以传来的值要先除以
    /// 剩余距离（见 `ArcStack.drag`）。不接这个参数也能吸到位，但那样无论快甩还是
    /// 轻推都是同一条曲线：差别只剩「落在哪一张」，手上没有「顺着惯性冲过去」那一下。
    /// 上限 ±8：手势里那一帧的峰值速度可能极大，不封顶会甩到天上。
    static func settle(velocity: CGFloat) -> Animation {
        let v = Double(min(max(velocity, -8), 8))
        return Animation.interpolatingSpring(mass: 1, stiffness: 180, damping: 18,
                                             initialVelocity: v)
    }
}

// =============================================================================
//  MARK: - 七种叠法
// =============================================================================

/// 叠法。rawValue 即持久化的键：在对照页里挑中哪个，下次进来还是它。
enum StackVariant: String, CaseIterable, Identifiable {
    /// A 弧出：等距排开 + 上下消失带 + 一点弧度转出去（**默认**）
    case arc
    /// B 吸附堆叠：每张滚到顶部就贴住不动，下一张从下面盖上来
    case sticky
    /// C 压层叠：所有卡重合，靠「往下错 74」让每层都露出来一条
    case deck
    /// D 纵深叠：同上，但错位小（26）、缩放更明显，看起来是一条隧道
    case depth
    /// E 错位叠：每张留在自己的排版位，只左右交替错开
    case offset
    /// F 钱夹叠：往上错（−30），像一叠卡从下面抽出来
    case wallet
    /// G 滚轮：卡片绕一个圆柱面转，转到背面就看不见
    case wheel

    var id: String { rawValue }

    /// 对照页上的名字
    var title: String {
        switch self {
        case .arc: return "弧出"
        case .sticky: return "吸附堆叠"
        case .deck: return "压层叠"
        case .depth: return "纵深叠"
        case .offset: return "错位叠"
        case .wallet: return "钱夹叠"
        case .wheel: return "滚轮"
        }
    }

    /// 一句话说清它和别的有什么不同（对照页的第二行）
    var note: String {
        switch self {
        case .arc: return "等距排开，贴边淡出并转出画面"
        case .sticky: return "滚到顶部贴住，下一张盖上来"
        case .deck: return "重合叠放，每层露出一条"
        case .depth: return "重合叠放，近大远小"
        case .offset: return "各自就位，左右交错"
        case .wallet: return "向上错开，像抽卡"
        case .wheel: return "绕圆柱面转动"
        }
    }

    var metrics: StackMetrics {
        switch self {
        case .arc:
            // tiltDeg = 0：用户 2026-09-23 明确要求「卡片显示保持正常，不要倾斜特效」。
            // 叠叠乐的艺术感由消失带与间距支撑，不靠把卡转个角度。
            return StackMetrics(kind: .flow, padTop: 152, padBottom: 180, gap: 20,
                                fadeTop: 150, fadeBottom: 140,
                                tiltDeg: 0, shrink: 0.07, fadeOut: 0.16)
        case .sticky:
            // 卡片至少要有一屏高的六成才吸得住（太矮就永远滚不到贴顶那一步）
            return StackMetrics(kind: .flow, padTop: 16, padBottom: 90, gap: 14,
                                tiltDeg: 0, shrink: 0, fadeOut: 0.10,
                                stickLine: 10, minCardHeight: 300)
        case .deck:
            return StackMetrics(kind: .deck, gap: 0,
                                tiltDeg: 0, shrink: 0.02, fadeOut: 0.10,
                                deckStep: 74)
        case .depth:
            return StackMetrics(kind: .deck, gap: 0,
                                tiltDeg: 0, shrink: 0.05, fadeOut: 0.14,
                                deckStep: 26)
        case .offset:
            return StackMetrics(kind: .flow, padTop: 24, padBottom: 90, gap: 12,
                                tiltDeg: 0, shrink: 0, fadeOut: 0,
                                sideStep: 26)
        case .wallet:
            return StackMetrics(kind: .deck, gap: 0,
                                tiltDeg: 0, shrink: 0.03, fadeOut: 0.10,
                                deckStep: -30)
        case .wheel:
            return StackMetrics(kind: .wheel, gap: 0, fadeTop: 40, fadeBottom: 80,
                                tiltDeg: 30, shrink: 0, fadeOut: 0,
                                wheelRadius: 520, wheelFOV: 74)
        }
    }
}

/// 排版方式。三种，不是七种 —— 七种只是参数不同。
enum StackKind {
    /// 卡片留在自己的排版位（一张一张往下排）
    case flow
    /// 卡片全部重合，靠「焦点差 × 步长」错开
    case deck
    /// 圆柱面
    case wheel

    /// 滚轮与重合叠放没有「自然的上下留白」（卡片不在流里排队），
    /// 它们的两端留白由窗口自己扛。
    var usesFlowPadding: Bool { self == .flow }
}

/// 一个叠法的全部数值。用不到的项留 0 —— 判定里就有据可依，不必到处写特例。
struct StackMetrics {
    var kind: StackKind = .flow
    var padTop: CGFloat = 0
    var padBottom: CGFloat = 0
    var gap: CGFloat = 20
    /// 上下消失带：这两段里卡片渐隐（0 = 不做消失带）
    var fadeTop: CGFloat = 0
    var fadeBottom: CGFloat = 0
    /// 离阅读线越远，转出去的角度上限（度）
    var tiltDeg: CGFloat = 0
    /// 离阅读线越远，缩小的比例
    var shrink: CGFloat = 0
    /// 离阅读线越远，变淡的比例
    var fadeOut: CGFloat = 0
    /// 吸附堆叠：贴住的位置；minCardHeight 是它能成立的前提
    var stickLine: CGFloat = 0
    var minCardHeight: CGFloat = 0
    /// 重合叠放：每层错开多少（负 = 向上）
    var deckStep: CGFloat = 0
    /// 错位叠：左右交替错开多少
    var sideStep: CGFloat = 0
    /// 滚轮
    var wheelRadius: CGFloat = 520
    var wheelFOV: CGFloat = 74

    /// 滚轮与重合叠放里，卡片**占用的滚动距离**（不是它的高度）。
    ///
    /// 滚轮的一格与卡片高度无关 —— 卡片高度自适应之后，排版高度不再能当刻度用。
    /// 实测过：出行页的自适应高度让「可滚距离」量出来是 0，轮子一格都转不动。
    static let wheelPitch = CGFloat(104)

}

// =============================================================================
//  MARK: - 判定（纯函数，无视图）
// =============================================================================

enum StackMath {

    /// 滚动的硬限位：夹在 `[0, 末档]`。到顶/到底就是停（见 `endStop` 上的说明）。
    static func clamped(_ p: CGFloat, last: CGFloat) -> CGFloat {
        min(max(p, 0), max(0, last))
    }

    /// 连续的焦点序号：`2.0` = 第二张正停在阅读线，`1.4` = 正拖在一、二张之间。
    ///
    /// 不用「平均节距」去除（`y / pitch`）—— 卡片高度不一致时，相邻两张会差出
    /// 一整档（原型里实测差到 1.44 张）。这里按**真实间距**在两张之间插值。
    static func focus(centers: [CGFloat], scroll: CGFloat, dock: CGFloat) -> CGFloat {
        guard let first = centers.first, let last = centers.last, centers.count > 1 else { return 0 }
        let y = min(max(scroll + dock, first), last)
        var i = 0
        while i < centers.count - 2 && centers[i + 1] < y { i += 1 }
        let span = centers[i + 1] - centers[i]
        let t = span > 0.01 ? (y - centers[i]) / span : 0
        return CGFloat(i) + min(max(t, 0), 1)
    }

    /// 吸附点：每一个值相对第一个的位移（滚到它 = 那张卡停在阅读线）。
    /// 它是**相对量**，所以窗口高度、消失带宽度都不影响落点 —— 换机型不会漂。
    static func relative(_ values: [CGFloat]) -> [CGFloat] {
        guard let first = values.first else { return [] }
        return values.map { $0 - first }
    }

    /// 松手后落在哪一个吸附点（返回下标），以及要不要被甩出去一格。
    ///
    /// 判据直接来自原型 `startSettle`：
    ///   ① 往手指方向的那个吸附点，距离打 0.85 折（临界点约 47%，不是 50%）
    ///   ② 这一段手势的峰值速度超过阈值 → 顺着方向再走一格
    ///
    /// ⚠️ 速度记的是**这一段手势的峰值**，不是松手那一帧的速度：
    /// 收尾时最后几帧本来就几乎不动，取最后一帧算出来恒为 0，甩永远不触发。
    static func snapIndex(targets: [CGFloat], scroll: CGFloat, velocity: CGFloat) -> Int {
        guard !targets.isEmpty else { return 0 }
        let dir: CGFloat = velocity >= 0 ? 1 : -1
        let fling = abs(velocity) > StackSpec.flingVelocity
        var best = 0
        var bestD = CGFloat.greatestFiniteMagnitude
        for (i, o) in targets.enumerated() {
            var d = o - scroll
            if abs(velocity) > 0.001 && (d >= 0 ? 1 : -1) == dir {
                d *= StackSpec.directionBias
            }
            if abs(d) < abs(bestD) { bestD = d; best = i }
        }
        if fling {
            let j = best + (dir > 0 ? 1 : -1)
            best = min(max(j, 0), targets.count - 1)
        }
        return best
    }
}
