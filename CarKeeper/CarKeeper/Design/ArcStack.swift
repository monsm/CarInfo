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

    /// 叠法（原型 A~G）。默认 `.arc` —— 用户 2026-09-23 选中的那一种。
    var variant: StackVariant = .arc
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
    /// 形变用的位移，比 `scroll` 慢一点点（跟手滞后）
    @State private var shapeScroll: CGFloat = 0
    @State private var heights: [Int: CGFloat] = [:]
    @State private var dragBase: CGFloat?
    @State private var peakVelocity: CGFloat = 0
    @State private var lastSample: (at: Date, scroll: CGFloat)?
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
            let maxScroll = targets.last ?? 0
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
            .gesture(drag(maxScroll: maxScroll, targets: targets))
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
                case .increment: step(1, targets: targets)
                default: step(-1, targets: targets)
                }
            }
            .accessibilityScrollAction { edge in
                switch edge {
                case .bottom: step(1, targets: targets)
                default: step(-1, targets: targets)
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

    private func drag(maxScroll: CGFloat, targets: [CGFloat]) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { v in
                if dragBase == nil {
                    dragBase = scroll
                    peakVelocity = 0
                    lastSample = nil
                }
                let raw = (dragBase ?? 0) - v.translation.height
                sampleVelocity(scroll: raw)
                // 硬停在 `[0, maxScroll]`（`endStop = 0`，见 `StackSpec` 的说明）：
                // 到顶/到底就是停，末卡不会被拖上去留下空白。
                scroll = StackMath.clamped(raw, last: maxScroll)
            }
            .onEnded { v in
                sampleVelocity(scroll: (dragBase ?? 0) - v.translation.height)
                // 甩出去的判据用的是**这一段手势的峰值速度**，不是松手那一帧：
                // 收尾时最后几帧本来就几乎不动，取最后一帧算出来恒为 0，甩永远不触发。
                let idx = StackMath.snapIndex(targets: targets, scroll: scroll,
                                              velocity: peakVelocity)
                current = idx
                TokensHaptic.select()
                // 把手指速度交给弹簧：`initialVelocity` 要的是「占剩余路程的倍数/秒」，
                // 所以除以剩余距离。剩余距离接近 0 时不给（否则会放大成无穷）。
                let dist = targets[idx] - scroll
                let v = abs(dist) > 1 ? peakVelocity / dist : 0
                withAnimation(StackSpec.settle(velocity: v)) { scroll = targets[idx] }
                dragBase = nil
                lastSample = nil
                peakVelocity = 0
            }
    }

    /// 记**峰值**而不是最后一次：峰值是这一段手势里最快的那个瞬间。
    /// 隔 200ms 没有新样本就当作新手势重新开始记 —— 否则上一次的快甩会一直挂在
    /// 身上，让后面每一次轻推都变成「甩出去」。
    private func sampleVelocity(scroll s: CGFloat) {
        let now = Date()
        if let last = lastSample {
            let dt = now.timeIntervalSince(last.at)
            if dt >= 0.2 {
                peakVelocity = 0
            } else if dt > 0.001 {
                let v = (s - last.scroll) / CGFloat(dt)
                if abs(v) > abs(peakVelocity) { peakVelocity = v }
            }
        }
        lastSample = (now, s)
    }

    /// 点「下一张 / 上一张」（无障碍与深链都用它）
    private func step(_ delta: Int, targets: [CGFloat]) {
        guard !targets.isEmpty else { return }
        let next = min(max(current + delta, 0), targets.count - 1)
        guard next != current else { return }
        current = next
        TokensHaptic.select()
        withAnimation(StackSpec.settle) { scroll = targets[next] }
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
    /// 不传就是用户挑的那一种（见 `StackSpec.chosen`，默认弧出）。
    /// 六页都不传 —— 于是「在对照页里挑一种」是立刻全站生效的。
    var variant: StackVariant = StackSpec.chosen
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
