import SwiftUI

// =============================================================================
//  DSSwipeStrip —— 相机 App 的模式条（可手拖、带吸附）
// =============================================================================
//
//  这是全套界面**唯一**的入口控件：地图是取景框，模式条决定取景框里此刻
//  在回答哪个问题。它不是「导航」，因为它**不换屏** —— 换的是同一块画布上
//  、同一张纸里的内容。
//
//  交互（对齐 iOS 27 相机）：
//    ① 手指按在条子上横拖 —— 项**跟手**走，不是等手势结束才跳
//    ② 中心那一档最大最亮，两侧随距离缩小、变淡（距离是**连续**的）
//    ③ 松手**吸附**到最近的一档（spring，不是硬跳）
//    ④ 直接点某一档也会滑过去
//    ⑤ 两端有阻尼：继续拖还会动，但一次最多越界 0.35 档
//
//  有一件**刻意不照搬**：相机里左右滑取景框就换模式。地图上的横向拖拽是
//  **平移** —— 抢掉它会让「拖地图」变成「换模式」，比少一个手势糟得多。
//  所以这里只做条子自身，取景框的手势一个都不动。
//
//  为什么一档是**定宽**：吸附与「居中放大」都靠几何算。若宽度随文字变，
//  同一次拖动在不同档之间走过的距离就不同，吸附会飘 —— 这是相机那条
//  等距模式条的物理前提，不是审美选择。
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

    let items: [Item]
    /// 当前档（双向：拖动/点击会写回，外部改它也会滑过去）
    @Binding var selectedID: String
    /// 连续位置：`3.0` = 停在第四档，`2.4` = 正拖在第二、三档之间。
    /// 宿主用它做**内容的交叉淡入** —— 换模式是渐变，不是闪一下。
    var onPosition: ((Double) -> Void)?

    /// 一档的宽度（见文件头「为什么定宽」）
    private let slot: CGFloat = 92
    /// 越界阻尼上限（档）
    private let overscroll = 0.35

    /// 视觉位置（连续）。**它是唯一的几何来源**：
    /// 布局、缩放、淡出全从它算，所以手一停就停，不会有两个状态互相追。
    @State private var visual: Double = 0

    /// 显式 init：`@Binding` 靠合成的逐成员初始化器也能用，但写出来
    /// 参数顺序与类型就固定了 —— 调用点不会被隐式的包装器类型弄糊涂。
    init(items: [Item], selectedID: Binding<String>, onPosition: ((Double) -> Void)? = nil) {
        self.items = items
        self._selectedID = selectedID
        self.onPosition = onPosition
    }

    private var index: Int { items.firstIndex { $0.id == selectedID } ?? 0 }

    var body: some View {
        GeometryReader { geo in
            let mid = geo.size.width / 2
            ZStack {
                ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                    let d = Double(i) - visual
                    let away = min(abs(d), 2.4)
                    // 只渲染中心附近的几档（±2.6 档）：更远的字**直接不画**。
                    // 这比给条子套一层裁剪便宜，也不会让远处的字漏到卡片外面
                    // （模式条是画在纸上的，溢出就会落到地图上）。
                    if abs(d) <= 2.6 {
                        Text(item.title)
                            .font(TokensTypo.subheadline.weight(away < 0.5 ? .semibold : .regular))
                            .foregroundStyle(away < 0.5 ? TokensPalette.accent : TokensPalette.secondary)
                            .scaleEffect(1.0 - away * 0.10)
                            .opacity(1.0 - away * 0.30)
                            .frame(width: slot)
                            .position(x: mid + CGFloat(d) * slot, y: geo.size.height / 2)
                            .onTapGesture { pick(i) }
                            .accessibilityAddTraits(i == index ? [.isSelected] : [])
                            .accessibilityLabel(Text("看\(item.title)"))
                            .accessibilityAddTraits(.isButton)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { v in
                        // 跟手：拖动过程**不**走动画。加了动画条子会拖泥带水，
                        // 手指和文字之间会有可见的延迟。
                        visual = damped(Double(index) - Double(v.translation.width / slot))
                    }
                    .onEnded { _ in snap() }
            )
        }
        // 高度固定 44（HIG 最小触控目标）：条子的**位置与高度在每一档里不变**，
        // 这样换内容时它不会跳。
        .frame(height: TokensSpacing.row)
        .onAppear { visual = Double(index) }
        // 外部（深链、「我的」里的入口、@AppStorage 恢复）改档位 → 滑过去
        .onChange(of: selectedID) { _, _ in
            withAnimation(TokensMotion.count) { visual = Double(index) }
        }
        .onChange(of: visual) { _, v in onPosition?(v) }
    }

    /// 越界阻尼：把连续位置夹在 `[-0.35, 末档 + 0.35]` 内。
    /// 两端不是「拖不动」也不是「能拖出去」—— 拖得动但越拖越沉，
    /// 手指能感觉到「到头了」，同时松手一定回到合法档位。
    private func damped(_ p: Double) -> Double {
        let last = Double(items.count - 1)
        if p < 0 { return max(p, -overscroll) }
        if p > last { return min(p, last + overscroll) }
        return p
    }

    /// 松手：吸附到最近一档。位置先动画回去，档位跟着落定 ——
    /// 两者用的是同一条 spring，所以看上去是「滑过去」，不是「跳过去」。
    private func snap() {
        guard !items.isEmpty else { return }
        let target = min(max(Int(visual.rounded()), 0), items.count - 1)
        if items[target].id == selectedID {
            withAnimation(TokensMotion.count) { visual = Double(target) }
        } else {
            // 选中变化会触发 onChange 把 visual 动画到 target
            selectedID = items[target].id
            TokensHaptic.select()
        }
    }

    /// 点某一档
    private func pick(_ i: Int) {
        guard items.indices.contains(i), items[i].id != selectedID else { return }
        selectedID = items[i].id
        TokensHaptic.select()
    }
}
