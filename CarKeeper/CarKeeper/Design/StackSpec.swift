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

    // 滚动的两端（用户 2026-09-23 的要求）：
    //   · 限位是**硬停**（`StackMath.clamped`）：到顶/到底就是停。
    //     此前试过一版越界阻尼（拖得动但越拖越沉），结果是「到底了还能再拖」——
    //     那正是「硬停」要禁掉的东西。
    //   · 两端的**停法**由可滚范围自己决定：首端 = 首卡顶边落在可见区上沿，
    //     末端 = 末卡底边落在可见区下沿（算在 `ArcStack.endScroll`）。
    //     于是「往下滑到底，第一张不离开顶；往上滑到底，最后一张不离开底」——
    //     两端都是贴边的，而不是留一条空带。

    /// 吸附的判据来自原型 `startSettle`，但**强度已按用户 2026-09-24 的要求减弱**：
    /// 「上下滚动的页面减弱吸附效果」。三个数各管一件事：
    ///
    ///   · `directionBias` 1 → 临界点**正好一半**（原型是 0.85，约 47%）。
    ///     0.85 的含义是「往手指方向的那个落点便宜一成半」—— 轻推一下就会被吸过去；
    ///     1 则是「拖过一半才换张」。这是「吸附感」最主要的来源。
    ///   · `flingVelocity` 550 → 900 px/s：原型那个 0.55 px/ms 换算过来是 550，
    ///     但那个值会让一次普通滑动就多跳一格（落点比手指想去的那张还远一张）。
    ///     900 只在真的甩出去时才触发，落到「你确实想过一张」的地方。
    ///   · `settle` 弹簧变软（见下）：同样落点，拉过去的那一下不再“嗖”地一下。
    static let directionBias = CGFloat(1.0)
    static let flingVelocity = CGFloat(900)

    /// 拖动的跟手滞后：形变（弧度/缩放）比位移晚一点点，所以是「追上来再贴合」。
    static let shapeLag = Animation.spring(response: 0.16, dampingFraction: 0.92)

    /// 叠法现在是**唯一的**（用户 2026-09-24：只用吸附堆叠，其他全删）。
    /// 这个键留着是为了把旧版存下来的七选一值洗掉：读出来不是 `sticky`
    /// 就写回 `sticky`（旧值不再有效，留着会误导「还有别的叠法」）。
    static let variantKey = "carkeeper_stack_variant"

    /// 当前生效的叠法：永远 `.sticky`（唯一的叠法）。
    static var chosen: StackVariant {
        if let raw = UserDefaults.standard.string(forKey: variantKey),
           raw != StackVariant.sticky.rawValue {
            UserDefaults.standard.set(StackVariant.sticky.rawValue, forKey: variantKey)
        }
        return .sticky
    }

    /// 叠法已固定（唯一的叠法），这个入口保留给旧的对照页调用，现在写恒等于。
    static func remember(_ v: StackVariant) {
        UserDefaults.standard.set(StackVariant.sticky.rawValue, forKey: variantKey)
    }

    /// 回落用的弹簧（用户 2026-09-24「删除吸附」后，只剩无障碍翻页与外部换档
    /// 两条路用它 —— 手势松手不再走它，见 `ArcStack.drag` 的说明）。
    /// 刚度 130 / 阻尼 16：被手指打断的「滑过去」那一下。
    static let settle = Animation.interpolatingSpring(mass: 1, stiffness: 130, damping: 16)

    /// 无障碍翻页 / 外部换档的弹簧：没有惯性，固定一条曲线（`settle`）。
    /// 手势层不再调用它 —— 用户 2026-09-24 把「松手弹回」整段删了（见 `ArcStack.drag`）。
    static func settle(velocity: CGFloat = 0) -> Animation {
        Self.settle
    }
}

// =============================================================================
//  MARK: - 七种叠法
// =============================================================================

/// 叠法。用户 2026-09-24 要求：「叠叠乐只用吸附堆叠（但是要删除吸附），其他都删除」。
/// 于是七种只留这一种 —— 它不再是「七选一」，而是一个固定值：全站只有一种叠法。
/// 保留这个类型而不是直接删掉 `StackVariant`：`StackSpec.chosen` / `StackLabView`
/// 还在引用它的名字，留着这一个 case 比把整套引用删干净改动小，且语义不变。
enum StackVariant: String, CaseIterable, Identifiable {
    /// 吸附堆叠（**唯一**）：每张滚到顶部就贴住不动，下一张从下面盖上来。
    /// 「删除吸附」= 去掉松手后的弹跳回落（见 `StackSpec.settle` 与 `StackMath.snapIndex`
    /// 的使用处：手势直接跟手，到端硬停，**不再自动吸回**）。
    case sticky

    var id: String { rawValue }

    /// 对照页上的名字
    var title: String {
        switch self {
        case .sticky: return "吸附堆叠"
        }
    }

    /// 一句话说清它是什么（对照页的第二行）
    var note: String {
        switch self {
        case .sticky: return "滚到顶部贴住，下一张盖上来（无吸附回落）"
        }
    }

    var metrics: StackMetrics {
        switch self {
        case .sticky:
            // 卡片至少要有一屏高的六成才贴得住（太矮就永远滚不到贴顶那一步）。
            // 用户 2026-09-24「删除吸附」：这里的贴住是**滚动到位就停**（位置贴合），
            // 不是「弹回去」的吸附 —— 弹跳由 `ArcStack` 的手势层关闭（见那里的说明）。
            return StackMetrics(kind: .flow, padTop: 16, padBottom: 90, gap: 14,
                                tiltDeg: 0, shrink: 0, fadeOut: 0.10,
                                stickLine: 10, minCardHeight: 300)
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

    /// 滚动的硬限位：夹在 `[0, 末档]`。到顶/到底就是停（末端那个值见 `ArcStack.endScroll`）。
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
