import SwiftUI

// =============================================================================
//  DSSwipeStrip —— 相机 App 的模式条（可手拖、带吸附、按下展开）
// =============================================================================
//
//  这是全套界面**唯一**的入口控件：地图是取景框，模式条决定取景框里此刻
//  在回答哪个问题。它不是「导航」，因为它**不换屏** —— 换的是同一块画布上
//  同一张纸里的内容。
//
//  形态是量出来的（用户 2026-09-23 提供的 iOS 27 相机截图，按像素量过再按比例落成）：
//    · 横条是**圆角矩形**，圆角 0.31 × 条高（不是胶囊形）
//    · 选中指示是一枚**玻璃透镜**，高 0.85 × 条高，左右各留 0.37 × 条高
//    · 相邻标签间距恒定 0.73 × 条高（所以静止只露得下三档）
//    · 静止时第 4 档的**头一个字母被条自己的圆角边硬裁**掉 ——
//      这一条决定了整个做法：**静止只露三档是「条宽」造成的，不是屏幕不够宽**。
//      所以「手一滑就横向全显示」的正确形态是**条向两侧长出去**，而不是把间距压扁。
//
//  两种跟手方式（`Follow`）：
//    · `.row`   手指拖的是**整行**，透镜钉在条正中，字从它下面滑过去（iOS 26 默认）
//    · `.loupe` 手指拖的是**透镜**，它从字上滑过去，整行基本不动（iOS 26 的反向开关）
//
//  有一件**刻意不照搬**：相机里左右滑取景框就换模式。地图上的横向拖拽是**平移** ——
//  抢掉它会让「拖地图」变成「换模式」，比少一个手势糟得多。所以这里只做条子自身。
//
//  为什么一档是**定宽**：吸附与「透镜压在谁身上」都靠几何算。若宽度随文字变，
//  同一次拖动在不同档之间走过的距离就不同，吸附会飘 —— 这是相机那条等距模式条的
//  物理前提，不是审美选择。（本 App 六个档名**都是两个汉字**，定宽恰好也是真实宽度。）
//
//  ⚠️ 几何全部由 `width` 参数推出来，**没有一处存起来**。
//  第一版把「可用宽度」存成 @State，于是它只会被测量那一次写对：
//  在非 390pt 的机器上，首帧的档位位置是按默认宽度算的，要等用户碰一下才归位。
//  派生量不会有陈旧值 —— 这是这一版与上一版的唯一结构性差别。
struct DSSwipeStrip: View {

    /// 一档。`id` 同时是持久化的键（存在 UserDefaults 里，重启回到上次那一档）。
    struct Item: Identifiable, Hashable {
        let id: String
        let title: String

        init(id: String, title: String) {
            self.id = id
            self.title = title
        }
    }

    /// 手指拖的是整行，还是透镜
    enum Follow: String, CaseIterable, Identifiable {
        case row
        case loupe

        var id: String { rawValue }

        var title: String {
            switch self {
            case .row: return "整行跟手"
            case .loupe: return "透镜跟手"
            }
        }
    }

    let items: [Item]
    /// 当前档（双向：拖动/点击会写回，外部改它也会滑过去）
    @Binding var selectedID: String
    /// 默认整行跟手（iOS 26 的默认；`.loupe` 是它那个反向开关的形态）
    var follow: Follow = .row
    /// 连续位置：`2.0` = 停在第三档，`1.4` = 正拖在第二、三档之间。
    /// 宿主用它做内容的交叉过渡 —— 换模式是渐变，不是闪一下。
    var onPosition: ((Double) -> Void)?

    // ---- 几何（全部由条高推出来，见文件头）----
    /// 条高。HIG 最小触控目标是 44，这里是 46 —— 截图量出来的比例全部以它为基准。
    private let barHeight: CGFloat = 46
    /// 一档的宽度（定宽，见文件头）
    private let slot: CGFloat = 34
    /// 标签在透镜里左右各留多少
    private var pillPad: CGFloat { barHeight * 0.37 }
    /// 相邻标签的最大间距
    private var gapMax: CGFloat { barHeight * 0.73 }

    @State private var c: CGFloat = 0            // 条正中对应到行内的坐标
    @State private var expand: Double = 0
    @State private var cBase: CGFloat?
    @State private var pvBase: Double?
    @State private var moved = false

    private var index: Int { items.firstIndex { $0.id == selectedID } ?? 0 }

    // =========================================================================
    // MARK: 行几何（全部是纯函数，宽度是参数）
    // =========================================================================

    /// 行内坐标：第 i 档的中心（i 可以是小数）
    private func ideal(_ i: Double, gap: CGFloat) -> CGFloat {
        CGFloat(i) * (slot + gap) + slot / 2
    }

    /// 一档的节距
    private func pitch(_ gap: CGFloat) -> CGFloat { slot + gap }

    /// 展开后必须装得下全部：装不下就把**间距**压到刚好（压间距，而不是让字互相盖住）。
    private func gap(for width: CGFloat) -> CGFloat {
        let n = max(1, items.count)
        let fits = (width - 2 * pillPad - CGFloat(n) * slot) / CGFloat(max(1, n - 1))
        return min(gapMax, max(6, fits))
    }

    /// 整行的宽度
    private func rowWidth(gap: CGFloat) -> CGFloat {
        let n = CGFloat(max(1, items.count))
        return n * slot + (n - 1) * gap
    }

    /// 静止条宽：刚好装得下三档（不足三档就是整条）
    private func restWidth(width: CGFloat, gap: CGFloat) -> CGFloat {
        let shown = min(CGFloat(max(1, items.count)), 3)
        let need = (shown - 1) * pitch(gap) + slot + 2 * pillPad
        return min(width, need)
    }

    /// 展开后的条宽
    private func openWidth(width: CGFloat, gap: CGFloat) -> CGFloat {
        min(width, rowWidth(gap: gap) + 2 * pillPad)
    }

    /// 当前条宽（`expand` 在静止与展开之间插值）
    private func barWidth(width: CGFloat, gap: CGFloat) -> CGFloat {
        let rest = restWidth(width: width, gap: gap)
        let open = openWidth(width: width, gap: gap)
        return rest + (open - rest) * CGFloat(expand)
    }

    /// 静止时的限位：首尾那两档的透镜不能被条边切掉，
    /// 所以两端各留「透镜的呼吸位」而不是硬 0（否则首档一选上，左边就空出一大片）。
    private func limits(width: CGFloat, gap: CGFloat) -> ClosedRange<CGFloat> {
        let half = restWidth(width: width, gap: gap) / 2
        let lo = half - pillPad
        let hi = max(lo, rowWidth(gap: gap) - half + pillPad)
        return lo...hi
    }

    /// 行内坐标 → 条内屏幕坐标。**只差一个 `c`**：
    /// 条宽变化不影响这个式子，所以展开时字不会自己往前跳
    /// （第一版用「条左边缘」当几何量，条一变宽窗口就单边向右长，拖 140px 跳了 4 档）。
    private func screenX(_ rowX: CGFloat, width: CGFloat, c: CGFloat) -> CGFloat {
        width / 2 + rowX - c
    }

    /// 透镜所在的连续档位
    private func pvValue(c: CGFloat, gap: CGFloat) -> Double {
        Double((c - slot / 2) / pitch(gap))
    }

    /// 越界阻尼：拖得动，但越拖越沉。两端各留 0.35 档。
    private func clampC(_ raw: CGFloat, lim: ClosedRange<CGFloat>, gap: CGFloat) -> CGFloat {
        let slack = pitch(gap) * 0.35
        return min(max(raw, lim.lowerBound - slack), lim.upperBound + slack)
    }

    // =========================================================================
    // MARK: 视图
    // =========================================================================

    var body: some View {
        GeometryReader { geo in
            let width = max(120, geo.size.width)
            let gap = gap(for: width)
            let lim = limits(width: width, gap: gap)
            // 显示用的位置：即使 `c` 是上一次几何下的值，也先夹到合法范围再画 ——
            // 于是「宽度变了」只会表现为吸一下，而不是首帧停在错的地方。
            let cShown = clampC(c, lim: lim, gap: gap)
            ZStack(alignment: .leading) {
                bar(width: barWidth(width: width, gap: gap))
                capsule(gap: gap, width: width, c: cShown)
                labels(gap: gap, width: width, c: cShown,
                       barW: barWidth(width: width, gap: gap))
            }
            .frame(width: geo.size.width, height: barHeight, alignment: .center)
            .contentShape(Rectangle())
            .highPriorityGesture(swipe(gap: gap, lim: lim, width: width))
            .onAppear { settle(animated: false, gap: gap, lim: lim) }
            .onChange(of: selectedID) { _, _ in settle(animated: true, gap: gap, lim: lim) }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("功能"))
        }
        .frame(height: barHeight)
    }

    // =========================================================================
    // MARK: 三层
    // =========================================================================

    private func bar(width: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: barHeight * 0.31, style: .continuous)
        return shape
            .fill(TokensPalette.fillSubtle)
            .glassEffect(.regular, in: shape)
            .overlay { shape.strokeBorder(TokensPalette.glassBorder, lineWidth: TokensHair.border) }
            .frame(width: width, height: barHeight)
            .frame(maxWidth: .infinity, alignment: .center)
            .allowsHitTesting(false)
    }

    /// 玻璃透镜。它是**连续**的：拖动时压在两个字之间，而不是先亮谁后亮谁。
    private func capsule(gap: CGFloat, width: CGFloat, c: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: barHeight * 0.85 * 0.33, style: .continuous)
        let x = screenX(ideal(pvValue(c: c, gap: gap), gap: gap), width: width, c: c)
        return shape
            .fill(TokensPalette.glassHighlight)
            .overlay { shape.strokeBorder(TokensPalette.glassBorder, lineWidth: TokensHair.border) }
            .frame(width: slot + 2 * pillPad, height: barHeight * 0.85)
            .position(x: x, y: barHeight / 2)
            .allowsHitTesting(false)
    }

    private func labels(gap: CGFloat, width: CGFloat, c: CGFloat, barW: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            let mid = width / 2
            let half = barW / 2
            ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                let x = screenX(ideal(Double(i), gap: gap), width: width, c: c)
                // 只画窗口附近的两档：更远的字**直接不画**（条子自己有圆角裁切，
                // 但画出来再裁是白花的 GPU，而且远处的字会以半透明形式漏到条外）
                if x > mid - half - slot && x < mid + half + slot {
                    Text(item.title)
                        .font(TokensTypo.fixed(15, weight: .semibold))
                        .tracking(TokensTracking.label)
                        .foregroundStyle(i == index ? TokensPalette.primary : TokensPalette.secondary)
                        .frame(width: slot)
                        .position(x: x, y: barHeight / 2)
                        .accessibilityLabel(Text(item.title))
                        .accessibilityAddTraits(i == index ? [.isSelected, .isButton] : [.isButton])
                        .accessibilityAction { pick(i) }
                }
            }
        }
        .frame(width: barW, height: barHeight)
        // 条自己把越界的那半格裁掉：原型 `.strip{overflow:hidden}`。
        // 少了这一步，半压在条边上的那个字会**漏到条外** —— 而条是带圆角的，
        // 露出去的那半截正好把「静止只露三档」这个形态破掉。
        .clipShape(RoundedRectangle(cornerRadius: barHeight * 0.31, style: .continuous))
        .frame(maxWidth: .infinity, alignment: .center)
        .allowsHitTesting(false)
    }

    // =========================================================================
    // MARK: 手势
    // =========================================================================

    /// `minimumDistance: 0` 是为了**按下就展开**（相机的条子也是按住就长开）。
    /// 代价是点选要自己做 —— 位移小于 8pt 就当成「点了最近的那一档」，
    /// 而不是让每个标签各挂一个 Button（那样按下展开会晚半拍，而且按下时的
    /// 展开与点选会打架）。
    private func swipe(gap: CGFloat, lim: ClosedRange<CGFloat>, width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                if cBase == nil {
                    cBase = c
                    pvBase = pvValue(c: c, gap: gap)
                    moved = false
                    withAnimation(TokensMotion.fade) { expand = 1 }
                }
                if abs(v.translation.width) > 8 { moved = true }
                let dx = v.translation.width
                if follow == .loupe {
                    // 透镜跟手：字基本不动
                    let from = pvBase ?? pvValue(c: c, gap: gap)
                    setPV(from - Double(dx / pitch(gap)), lim: lim, gap: gap)
                } else {
                    // 整行跟手：行跟着手指走，透镜钉在正中
                    let raw = (cBase ?? c) - dx
                    c = clampC(raw, lim: lim, gap: gap)
                    onPosition?(pvValue(c: c, gap: gap))
                }
            }
            .onEnded { v in
                if !moved {
                    pick(nearest(to: v.location.x, gap: gap, width: width))
                } else {
                    snap(gap: gap, lim: lim)
                }
                // 松手 620ms 后再收回：给眼睛一点时间看清刚才划过哪些档
                withAnimation(TokensMotion.fade.delay(0.62)) { expand = 0 }
                cBase = nil
                pvBase = nil
            }
    }

    private func setPV(_ value: Double, lim: ClosedRange<CGFloat>, gap: CGFloat) {
        let last = Double(max(0, items.count - 1))
        let v = max(-0.35, min(last + 0.35, value))
        c = clampC(ideal(v, gap: gap), lim: lim, gap: gap)
        onPosition?(v)
    }

    private func nearest(to x: CGFloat, gap: CGFloat, width: CGFloat) -> Int {
        let rowX = x - width / 2 + c
        let raw = (rowX - slot / 2) / pitch(gap)
        return min(max(Int(raw.rounded()), 0), max(0, items.count - 1))
    }

    /// 松手：吸附到最近一档。位置与档位用的是同一条 spring，所以看上去是「滑过去」。
    private func snap(gap: CGFloat, lim: ClosedRange<CGFloat>) {
        let i = min(max(Int(pvValue(c: c, gap: gap).rounded()), 0), max(0, items.count - 1))
        guard items.indices.contains(i) else { return }
        if items[i].id == selectedID {
            // 档位没变：只把位置吸回去（onChange 不会触发，所以自己走一次）
            withAnimation(TokensMotion.count) {
                c = clampC(ideal(Double(i), gap: gap), lim: lim, gap: gap)
            }
            onPosition?(Double(i))
        } else {
            selectedID = items[i].id
            TokensHaptic.select()
        }
    }

    /// 外部改档位（深链 / 「我的」里的入口 / 上次停在哪一档）→ 滑过去
    private func settle(animated: Bool, gap: CGFloat, lim: ClosedRange<CGFloat>) {
        let target = clampC(ideal(Double(index), gap: gap), lim: lim, gap: gap)
        if animated {
            withAnimation(TokensMotion.count) { c = target }
        } else {
            c = target
        }
        onPosition?(Double(index))
    }

    private func pick(_ i: Int) {
        guard items.indices.contains(i), items[i].id != selectedID else { return }
        selectedID = items[i].id
        TokensHaptic.select()
    }
}
