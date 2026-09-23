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
//  三指滚动 —— VoiceOver 用户会**完全无法翻页**。所以容器上挂了
//  `.accessibilityAction(.scrollUp/.scrollDown)`。这类缺失不会有任何报错提醒你。
//
//  几何只有一条式子：
//      第 i 张卡相对阅读线的位移  d_i = targets[i] − scroll
//  七种叠法（弧出 / 吸附堆叠 / 压层叠 / 纵深叠 / 错位叠 / 钱夹叠 / 滚轮）**只是
//  把 d_i 换成不同的东西**。参数在 `StackSpec`，判定在 `StackMath`，这里只画和收手势。
struct ArcStack: View {

    /// 叠法（原型 A~G）。默认 `.arc` —— 用户 2026-09-23 选中的那一种。
    var variant: StackVariant = .arc
    /// 卡片，按显示顺序
    var cards: [AnyView]
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
            .accessibilityAction(.scrollUp) { step(-1, targets: targets) }
            .accessibilityAction(.scrollDown) { step(1, targets: targets) }
        }
    }

    // =========================================================================
    // MARK: 一张卡
    // =========================================================================

    @ViewBuilder
    private func cardView(_ i: Int, card: AnyView, targets: [CGFloat],
                          m: StackMetrics, vh: CGFloat) -> some View {
        // 位置用**真实位移**，形变用**带滞后那一条**。
        // 两者混用会让卡片一边走一边被自己的滞后拖着，看起来像卡顿。
        let dPos = target(targets, i) - scroll
        let tShape = shapeT(target(targets, i) - shapeScroll, m: m, vh: vh)
        let p = placement(i: i, dPos: dPos, tShape: tShape, m: m)

        card
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
            // 被推出消失带的卡片**不再接受触摸**。不做这件事的话，
            // 一块已经看不见的玻璃还在吃点击 —— 点哪儿都不对，且没有任何提示。
            .allowsHitTesting(abs(tShape) < 0.85 && p.opacity > 0.25)
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
                scroll = StackMath.damped(raw, last: maxScroll)
            }
            .onEnded { v in
                sampleVelocity(scroll: (dragBase ?? 0) - v.translation.height)
                // 甩出去的判据用的是**这一段手势的峰值速度**，不是松手那一帧：
                // 收尾时最后几帧本来就几乎不动，取最后一帧算出来恒为 0，甩永远不触发。
                let idx = StackMath.snapIndex(targets: targets, scroll: scroll,
                                              velocity: peakVelocity)
                current = idx
                TokensHaptic.select()
                withAnimation(StackSpec.settle) { scroll = targets[idx] }
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
        ArcStack(variant: variant,
                 cards: cards.map { $0.render(accent: accent) },
                 accent: accent,
                 label: label)
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

    func render(accent: Color) -> AnyView {
        AnyView(
            GlassCard(accent: accent) {
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
