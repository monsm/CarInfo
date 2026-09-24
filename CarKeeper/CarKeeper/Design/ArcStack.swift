import SwiftUI

// =============================================================================
//  ArcStack —— 功能界面里那一叠玻璃卡（上下叠叠乐）
// =============================================================================
//
//  为什么不用 `ScrollView`：`ScrollView` + `.scrollTargetBehavior` 更省事、还白拿
//  三指滚动与系统惯性，但它**以「卡片的边」为对齐基准**（`viewAligned` 把目标视图的
//  上沿对齐到内容上边距），而这里要的是「卡片的顶停在消失带下沿」—— 一条自定义的
//  阅读线。两者对不上就只能放弃系统吸附，而「吸住」那一下正是这一版的全部手感。
//  所以这里是**自管手势 + 自管弹簧**。
//
//  ⚠️ 代价必须写下来（不然下一个人会以为白拿了）：没有 `ScrollView` 就没有
//  三指滚动 —— VoiceOver 用户会**完全无法翻页**。所以容器上挂了两条动作，
//  各管一种手势：`.accessibilityAdjustableAction`（焦点在这叠纸上时上下轻扫
//  = 上一张 / 下一张）与 `.accessibilityScrollAction`（三指扫，区域级）。
//  这类缺失不会有任何报错提醒你。
//
//  📌 2026-09-23：这里原本写的是 `.accessibilityAction(.scrollUp/.scrollDown)`——
//  那两个成员**不存在**（`AccessibilityActionKind` 只有 default / delete /
//  escape / magicTap / showMenu），而且当时 23 项门禁全绿，只有 CI 编译器报错。
//  原因不是打错一个字：那份名字白名单只核对「名字在不在表里」，
//  而白名单的**说明文字**自己就把那两个不存在的成员写成了事实。
//  现在 `scan/enumguard.py` 会拿 Apple 文档 JSON 里的成员表去卡这一类简写。
//
//  几何只有一条式子：
//      第 i 张卡相对阅读线的位移  d_i = targets[i] − scroll
//  七种叠法（弧出 / 吸附堆叠 / 压层叠 / 纵深叠 / 错位叠 / 钱夹叠 / 滚轮）**只是
//  把 d_i 换成不同的东西**。参数在 `StackSpec`，判定在 `StackMath`，这里只画和收手势。
struct ArcStack: View {

    /// 叠法。用户 2026-09-24：只用吸附堆叠（其他叠法全删），所以唯一的叠法。
    var variant: StackVariant = .sticky
    /// 卡片，按显示顺序。
    ///
    /// 这里收的是**未包装**的 `StackCard`，不是 `AnyView` —— 因为「这张卡要不要挂
    /// 系统玻璃」取决于它此刻离阅读线多远，而那个距离只有本类型知道。
    /// 提前在页面里包成 AnyView 的话，玻璃的开关就变成一个常量了。
    var cards: [StackCard]
    /// 这一页的个性色（卡片左上角那一抹）
    var accent: Color = TokensPalette.accent
    /// 无障碍里这一叠叫什么（"充电"…）
    var label: String = ""

    /// 阅读线：焦点卡片的**顶**停在这里（消失带下沿再让 8pt）。
    /// 不用「窗口高的某个比例」——那个比例会让首卡一高就被消失带吃掉上半截。
    private let focusInset: CGFloat = 8

    /// 还没量到高度时用的估值：宁可先画一张矮卡（下一帧就被真的盖掉），
    /// 也不要因为「高度未知」整叠不出现。
    private let fallbackHeight: CGFloat = 120

    @State private var scroll: CGFloat = 0
    /// 形变用的位移：同一个 `scroll` 的**慢半拍版本**（原型 `_smO += (origin-_smO)*0.16`）。
    ///
    /// 它只喂旋转 / 缩放 / 淡出 / 玻璃 / 可否点击，不喂位置 —— 卡片是「追上来再贴合」，
    /// 而不是硬贴在滚动上。
    ///
    /// ⚠️ 2026-09-23：它从第一版起就没被赋过值（恒为 0），于是形变读的其实是
    /// `targets[i] − 0` = 「这张卡离第一张多远」，而不是「它此刻离阅读线多远」：
    /// 滚到第四张时，**停在阅读线上的那张卡**透明度只有 0.68、缩到 0.9、
    /// 而且因为 0.9 那个阈值**点不动**。用户看到的「卡在两端不对」就是这个
    ///（用户 2026-09-23 的第 3 条）。现在它由 `dragTo` / `settleTo` 跟着一起更新。
    @State private var shapeScroll: CGFloat = 0
    @State private var heights: [Int: CGFloat] = [:]
    @State private var dragBase: CGFloat?
    @State private var current = 0

    private var spec: StackMetrics { variant.metrics }

    var body: some View {
        GeometryReader { geo in
            let m = spec
            let vh = max(1, geo.size.height)
            let hs = measured(around: cards.count)
            // 排版：flow 按真实高度排队；deck/wheel 的卡片不排队（tops 只用来定第一张在哪）
            let tops = topCoords(hs: hs, m: m)
            let targets = scrollTargets(tops: tops, m: m)
            // 可滚范围的**末端**：「最后一张的底边停在可见区下沿」（见 `endScroll`）。
            // 它不是 `targets.last` —— 末卡短的时候它更靠前（末卡因此不会被钉在阅读线上、
            // 底下空一大片），末卡高的时候它更靠后（下半截也读得到）。
            let maxScroll = endScroll(dock: targets, hs: hs, m: m, vh: vh)
            // 松手能停住的位置（每一张的阅读线 + 末端那一个）
            let rests = restPoints(dock: targets, maxScroll: maxScroll)
            let focusTop = m.fadeTop + focusInset
            let base = focusTop - (tops.first ?? 0)

            ZStack(alignment: .top) {
                VStack(spacing: m.gap) {
                    ForEach(Array(cards.enumerated()), id: \.offset) { i, card in
                        cardView(i, card: card, targets: targets, m: m, vh: vh)
                    }
                }
                // 整叠的位移：让第一张卡停在阅读线，再按 `scroll` 前进。
                // 每张卡自己的额外偏移都是**相对这条基线**的（见 placement）。
                .offset(y: base - scroll)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .clipped()
            .mask { fadeMask(vh: vh, m: m) }
            .contentShape(Rectangle())
            .gesture(drag(maxScroll: maxScroll, rests: rests))
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text(label.isEmpty ? "卡片列表" : label))
            // 叠叠乐**没有 ScrollView**，系统因此不会替我们提供任何翻页方式。
            // 下面两条各管一种手势，缺一不可：
            //   ① 可调整动作 —— VoiceOver 焦点落在这叠纸上时，上下轻扫 = 上一张 / 下一张；
            //   ② 滚动动作 —— 三指上下扫（区域级）＝ 朝那一边滚；扫向底边就是往下看，即下一张，
            //      方向与系统 ScrollView 一致。
            // 注：`AccessibilityActionKind` **没有** `.scrollUp` / `.scrollDown`
            //（它只有 default / escape / magicTap / showMenu）—— 第一版按印象写了这两个
            // 名字，同时又把它们写进了 scan.py 的白名单说明里，于是门禁放行、编译器拦下。
            // scan/enumguard.py 现在专门盯这一类「SDK 枚举成员凭印象拼」的错。
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: step(1, rests: rests)
                default: step(-1, rests: rests)
                }
            }
            .accessibilityScrollAction { edge in
                switch edge {
                case .bottom: step(1, rests: rests)
                default: step(-1, rests: rests)
                }
            }
        }
    }

    // =========================================================================
    // MARK: 一张卡
    // =========================================================================

    @ViewBuilder
    private func cardView(_ i: Int, card: StackCard, targets: [CGFloat],
                          m: StackMetrics, vh: CGFloat) -> some View {
        // 位置用**真实位移**，形变用**带滞后那一条**。
        // 两者混用会让卡片一边走一边被自己的滞后拖着，看起来像卡顿。
        //
        // ⚠️ 两个量都不是「这张卡离第一张多远」，而是「它此刻离阅读线多远」：
        // `targets[i] − scroll` 正好等于「这张卡的顶边到阅读线的距离」
        //（屏幕 y = 阅读线 + 这个差值）。形变一旦读成前者，停在阅读线上的那张卡
        // 也会被当成「在消失带里」——淡出、缩小、不可点。见 `shapeScroll` 的说明。
        let dPos = target(targets, i) - scroll
        let tShape = shapeT(target(targets, i) - shapeScroll, m: m, vh: vh)
        let p = placement(i: i, dPos: dPos, tShape: tShape, m: m)

        // 只给靠近阅读线的卡挂系统玻璃：多张 material 同时重绘很贵，
        // 而消失带里的卡已经被遮罩淡到看不清了 —— 给它们用纯色底看不出区别。
        // 阈值取 0.9：那里正好是遮罩开始明显变淡的位置，所以材质切换看不见。
        card.render(accent: accent, glassy: abs(tShape) < 0.9)
            .background {
                // 高度必须自己量：卡片高度是**内容撑出来的**（不写死），
                // 所以「下一张在哪儿」只能靠这一帧的真实高度。
                GeometryReader { g in
                    Color.clear
                        .onAppear { record(i, g.size.height) }
                        .onChange(of: g.size.height) { _, h in record(i, h) }
                }
            }
            .padding(.horizontal, StackSpec.Card.inset)
            .offset(x: p.x, y: p.y)
            .rotation3DEffect(.degrees(p.tilt), axis: (x: 1, y: 0, z: 0),
                              perspective: 0.5)
            .scaleEffect(p.scale)
            .opacity(p.opacity)
            .zIndex(Double(-abs(tShape)))
            // 接近阅读线的卡**可点**，被推出消失带的卡不接触摸（点哪儿都不对，且没有任何提示）。
            // 阈值跟玻璃阈值对齐（0.9）：玻璃一撤（看不太清的那段）才锁点击，
            // 看得见的卡始终可点。
            .allowsHitTesting(abs(tShape) < 0.9 && p.opacity > 0.25)
    }

    /// 每张卡相对阅读线的位移，换算成「一个 −1…1 的参数」：
    /// 弧出/错位叠用「半个窗口」，重合叠放用「一张半的步长」，滚轮用角度。
    private func shapeT(_ d: CGFloat, m: StackMetrics, vh: CGFloat) -> CGFloat {
        switch m.kind {
        case .flow:  return clamp(d / max(1, vh * 0.5), -2, 2)
        case .deck:  return clamp(d / (max(1, abs(m.deckStep)) * 1.5), -2, 2)
        case .wheel: return wheelAngle(d, m: m) / 90
        }
    }

    /// 一张卡最终落在哪：位置、倾斜、缩放、透明度。
    ///
    /// `y` 是**额外**偏移（在整叠基线之上再加多少）。
    /// 重合叠放与滚轮的卡片不按排版排队，所以要把排版位移整个抵消掉再放到该放的地方 ——
    /// 原型里第一版漏了这一步，结果「卡片只是各自停在排版位、加了点倾斜」，成不了轮子。
    private func placement(i: Int, dPos: CGFloat, tShape: CGFloat,
                           m: StackMetrics) -> (x: CGFloat, y: CGFloat,
                                                tilt: Double, scale: CGFloat,
                                                opacity: Double) {
        var yExtra: CGFloat = 0
        var tilt = 0.0
        var scale: CGFloat = 1
        var opacity = 1.0
        var x: CGFloat = 0

        switch m.kind {
        case .flow:
            if m.sideStep > 0 {
                x = (i % 2 == 0) ? m.sideStep : -m.sideStep
            }
            opacity = 1 - Double(clamp(abs(tShape), 0, 2)) * Double(m.fadeOut)
        case .deck:
            // 目标位置 = 阅读线 + d × 方向；基线已经给了 d，所以补上剩下的
            let dir: CGFloat = m.deckStep < 0 ? -1 : 1
            yExtra = dPos * (dir - 1)
            opacity = 1 - Double(clamp(abs(tShape), 0, 2)) * Double(m.fadeOut)
        case .wheel:
            let a = wheelAngle(dPos, m: m)
            // 圆柱面：角度 → 竖直位移。算在 Double 里再回 CGFloat ——
            // `cos(CGFloat)` 靠 CoreGraphics 的重载，而 `cos(Double)` 是标准库，不会挑错。
            let lift = CGFloat(cos(Double(a) * Double.pi / 180))
            yExtra = m.wheelRadius * (1 - lift) - dPos
            tilt = -Double(a)
            // 转出 70° 之后才开始淡出，110° 完全消失 ——
            // 淡出按**角度**而不是按「第几张」：卡片高度不一，按张数算会让
            // 高卡还在画面里就已经透了。（第一版写成 `a > 70 ? … : …` 的两分支，
            // 下面那一支在 a 为正时会算出 opacity > 1。）
            opacity = Double(max(0, 1 - max(0, abs(a) - 70) / 40))
        }

        if m.tiltDeg > 0 && m.kind != .wheel {
            // 阅读线上方（t<0）的卡片顶向后倒；正角度就是顶向后倒，所以取负号。
            tilt = -Double(tShape) * Double(m.tiltDeg)
        }
        if m.shrink > 0 {
            scale = 1 - clamp(abs(tShape), 0, 1.5) * m.shrink
        }
        return (x, yExtra, tilt, scale, opacity)
    }

    private func wheelAngle(_ d: CGFloat, m: StackMetrics) -> CGFloat {
        d / StackMetrics.wheelPitch * 30
    }

    // =========================================================================
    // MARK: 消失带
    // =========================================================================

    /// 上下两段渐隐。它不只是装饰 —— 卡片是**转出去**的，硬裁会在边上露出一个直角，
    /// 而渐隐让「越界」变成「走出画面」。
    private func fadeMask(vh: CGFloat, m: StackMetrics) -> some View {
        let top = max(0.5, m.fadeTop)
        let bottom = max(0.5, m.fadeBottom)
        let solid = max(top + 1, vh - bottom)
        return LinearGradient(
            stops: [
                .init(color: TokensPalette.canvas.opacity(0), location: 0),
                .init(color: TokensPalette.canvas, location: min(0.85, top / vh)),
                .init(color: TokensPalette.canvas, location: min(0.97, solid / vh)),
                .init(color: TokensPalette.canvas.opacity(0), location: 1)
            ],
            startPoint: .top, endPoint: .bottom)
    }

    // =========================================================================
    // MARK: 手势
    // =========================================================================

    /// 跟手：位置立刻跟手指（`dragTo` 不做位移上的任何「聪明事」），形变慢半拍。
    ///
    /// 用户 2026-09-24：「叠叠乐只用吸附堆叠（但是要删除吸附）」—— 于是松手**不再**：
    ///   · 找吸附点（`StackMath.snapIndex` 已不再调用），
    ///   · 弹回（`settleTo` 的弹簧只给无障碍翻页与外部换档用，手势松手不走它），
    ///   · 甩出去（`peakVelocity` 那一套峰值速度整段已删）。
    /// 手停在哪儿，卡就停在哪儿；两端的「到顶/到底」由 `clamped` 硬限位守住。
    private func drag(maxScroll: CGFloat, rests: [CGFloat]) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { v in
                if dragBase == nil { dragBase = scroll }
                let raw = (dragBase ?? 0) - v.translation.height
                // 硬停在 `[0, maxScroll]`：到顶/到底就是停，两端都不会被拖出去留下空白。
                dragTo(StackMath.clamped(raw, last: maxScroll))
            }
            .onEnded { _ in
                // 清掉临时量：位移已经在 `onChanged` 里跟手到位，这里没有任何「落点」。
                dragBase = nil
            }
    }

    /// 拖动中：位置立刻跟手，形变慢半拍（原型 `_smO += (origin − _smO) * 0.16`）。
    private func dragTo(_ v: CGFloat) {
        scroll = v
        withAnimation(StackSpec.shapeLag) { shapeScroll = v }
    }

    /// 落点：位置与形变用**同一条弹簧**一起到位。
    ///
    /// 原型在回弹时把滞后系数从 0.16 提到 0.34 —— 意思是「回来的时候跟得紧一点」。
    /// 这里让两者共用同一条曲线：落点因此不可能出现「位置已经到了、形变还在后面追」。
    private func settleTo(_ v: CGFloat, velocity: CGFloat) {
        withAnimation(StackSpec.settle(velocity: velocity)) {
            scroll = v
            shapeScroll = v
        }
    }

    /// 点「下一张 / 上一张」（无障碍与深链都用它）。
    /// 走的是**落点清单**而不是卡片序号：末尾那个「末卡停到底」也是一个落点。
    private func step(_ delta: Int, rests: [CGFloat]) {
        guard !rests.isEmpty else { return }
        let next = min(max(current + delta, 0), rests.count - 1)
        guard next != current else { return }
        current = next
        TokensHaptic.select()
        settleTo(rests[next], velocity: 0)
    }

    // =========================================================================
    // MARK: 几何
    // =========================================================================

    private func record(_ i: Int, _ h: CGFloat) {
        let old = heights[i] ?? -1
        guard abs(old - h) > 0.5 else { return }
        heights[i] = h
    }

    private func measured(around n: Int) -> [CGFloat] {
        (0..<max(0, n)).map { heights[$0] ?? fallbackHeight }
    }

    /// 内容坐标里每张卡的上沿。flow 用真实高度排队；另两种叠法的卡片不排队，
    /// 上沿只用来算「第一张在哪儿」。
    private func topCoords(hs: [CGFloat], m: StackMetrics) -> [CGFloat] {
        var out: [CGFloat] = []
        var y = m.padTop
        for h in hs {
            out.append(y)
            y += h + m.gap
        }
        return out
    }

    /// 第 i 张卡停在阅读线时需要的位移。
    /// flow：真实的卡顶间距；deck 与 wheel：固定步长（与卡片高度无关）。
    private func scrollTargets(tops: [CGFloat], m: StackMetrics) -> [CGFloat] {
        switch m.kind {
        case .flow:
            return StackMath.relative(tops)
        case .deck:
            let step = abs(m.deckStep)
            return tops.indices.map { CGFloat($0) * step }
        case .wheel:
            return tops.indices.map { CGFloat($0) * StackMetrics.wheelPitch }
        }
    }

    /// 可滚范围的末端：**最后一张的底边停在可见区下沿**（淡出带上沿）。
    ///
    /// 两端是对称的（用户 2026-09-23 的第 3 条）：
    ///   · 首端：`scroll = 0` 时首卡的顶边正好落在可见区上沿（`padTop` 就是按
    ///     `focusTop` 定的）——「往下滑到底，第一张不离开顶」；
    ///   · 末端：末卡的底边落在可见区下沿 ——「往上滑到底，最后一张不离开底」。
    ///     它意味着末卡**不停在阅读线上**（比它低），底下不留一大片空白；
    ///     而末卡比可见区还高的时候，这个值会**大于**「它吸在阅读线上」的位置 ——
    ///     多出来的那一段就是为了把它的下半截也读得到，而不是永远被淡出带吃掉。
    private func endScroll(dock: [CGFloat], hs: [CGFloat], m: StackMetrics, vh: CGFloat) -> CGFloat {
        guard let lastDock = dock.last else { return 0 }
        let h = hs.last ?? fallbackHeight
        let bottom = m.fadeTop + focusInset + h          // 末卡吸住时，它的底边离屏顶多远
        let crispBottom = vh - max(0.5, m.fadeBottom)    // 可见区的下沿（淡出带之上）
        return max(0, lastDock + bottom - crispBottom)
    }

    /// 松手能停住的位置。
    ///
    /// 它是两份清单的组合：每一张卡吸在阅读线上的位置 + 末端那一个；
    /// **超出可滚范围的那些不再算数** —— 末卡很短时，「吸住」比「停到底」还靠下，
    /// 那一段根本走不到，留在清单里就会让松手往一个够不着的地方弹。
    private func restPoints(dock: [CGFloat], maxScroll: CGFloat) -> [CGFloat] {
        var out = dock.filter { $0 <= maxScroll + 0.5 }
        if out.isEmpty { out = [maxScroll] }
        if let last = out.last, maxScroll - last > 1 { out.append(maxScroll) }
        return out
    }

    private func target(_ targets: [CGFloat], _ i: Int) -> CGFloat {
        targets.indices.contains(i) ? targets[i] : 0
    }

    private func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
        min(max(v, lo), hi)
    }
}

// =============================================================================
//  MARK: - 把一页写成卡列表
// =============================================================================
//
//  六页里五页都是「一叠卡」，它们不该各自去拼 `AnyView` 数组、各自决定间距。
//  这个类型只做一件事：让页面**按顺序声明**自己的卡，然后交给 `ArcStack`。
//
//  为什么是 `AnyView` 而不是泛型元组：卡片的类型本来就不同（一张是巨字头、
//  一张是图表、一张是列表），而顺序是**运行时可变的**（分段控件换段、行程条数
//  随数据变）。泛型元组表达不了这件事，硬撑的代价是每页写一套自定义 ViewBuilder。
struct StackPageView: View {
    /// 叠法已固定为唯一的吸附堆叠（用户 2026-09-24）。六页不传 = 全用那一种。
    var variant: StackVariant = .sticky
    var accent: Color = TokensPalette.accent
    var label: String = ""
    var cards: [StackCard]

    var body: some View {
        ArcStack(variant: variant, cards: cards, accent: accent, label: label)
    }
}

/// 一张卡：一个短标题 + 内容。
struct StackCard: Identifiable {
    let id: String
    var title: String = ""
    var value: String? = nil
    var cls: String = "na"
    var at: Date? = nil
    var content: AnyView

    /// `glassy` 由 `ArcStack` 按「离阅读线多远」决定（见那里关于性能的说明）。
    func render(accent: Color, glassy: Bool = true) -> AnyView {
        AnyView(
            GlassCard(accent: accent, glassy: glassy) {
                VStack(alignment: .leading, spacing: TokensSpacing.md) {
                    if !title.isEmpty {
                        GlassCardHead(title: title, value: value, cls: cls, at: at)
                    }
                    content
                }
            }
        )
    }
}
