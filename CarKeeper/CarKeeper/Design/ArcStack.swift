import SwiftUI

// =============================================================================
//  ArcStack —— 功能界面里那一叠玻璃卡
// =============================================================================
//
//  2026-09-25（第二轮）：这一叠**只剩下系统的 `ScrollView`**。
//
//  上一轮已经把手势换成 `ScrollView`（惯性、橡皮筋、起步那一下、三指滚动都回来了），
//  但壳上还挂着三层自己画的东西 —— 用户 2026-09-25 第 1 条说的「不像 iOS」
//（「除了地图外其他的界面怎么滑动起来都很不 iOS？iOS 的原生流畅呢」）
//  正是它们，每一条都能指出来：
//    · 一条**消失带遮罩**（`.mask` 上下渐隐）。它的来历是旧的「卡片转出画面」：
//      卡片当时是斜的、要转出去，硬裁会在边上露出直角，于是用渐隐收尾。
//      转出在 09-24 删掉之后，这条遮罩只剩一个作用 —— 让一个原生滚动容器的两端
//      平白变淡。列表滚到边上是**裁**，不是化掉；而且它把卡片淡进
//      `TokensPalette.canvas`，子页铺的是壁纸，于是那两段是在往一块**不存在的底色**里淡。
//    · 每张卡的 `offset / rotation3DEffect / scaleEffect / opacity / allowsHitTesting`
//      —— 唯一的叠法（吸附堆叠）下它们的系数全是 0/1（`tiltDeg 0`、`shrink 0`、
//      `fadeOut 0.10`、`deckStep 0`）：五个修饰符里四个什么也没做，
//      剩下那个 opacity 把「滚出去的卡」淡成 0.9 —— 原生滚动没有这件事。
//    · `.scrollIndicators(.hidden)` 与 `.clipped()`：前者把系统在滚动时给的那条
//      指示条也关掉了（那正是「它在动」的反馈本身），后者在遮罩删掉之后无事可做。
//
//  现在这一层就是：`ScrollView { VStack(spacing: gap) { 卡片 } }`，仅此。
//  位置、惯性、两端（含橡皮筋）、滚动指示条、三指滚动、VoiceOver 的三指滚动
//  全归系统 —— 与系统列表的行为一模一样，没有任何一步是我们算的。
//
//  留下的唯一**非系统**行为是无障碍的「逐张翻页」（`accessibilityAdjustableAction`）：
//  它是给读屏用户的一挡，不画任何东西、也不碰滚动的物理（系统的三指滚动照旧并存）。
//  ⚠️ 它只跟「被点了几次」走：手指自己滚过好几张之后，下一次翻页仍从上次那个序号继续。
//  写在这里是因为它是事实的一部分 —— 系统没有「你现在滚到第几张」这个数可以读。
//
//  为什么不再量卡片高度：上一版量高度是为了自己算每张卡的位置与形变。位置归系统之后，
//  「下一张在哪儿」由布局给出，量高度（以及 `tops` / 落点清单）的理由一起消失了。
//  ⚠️ 代价记在这里：`CardFit` 的输入因此**只有宽度**
//（它用 `cardViewport.width` 算「展开后挤不挤、放得下几行」，见 `CardFit` 头注）。
//
//  📌 2026-09-23 的教训（`scan/enumguard.py` 就是它逼出来的，这里只留一句）：
//  这一层曾经写过 `.accessibilityAction(.scrollUp/.scrollDown)` ——
//  `AccessibilityActionKind` **没有**这两个成员，而当时 23 项门禁全绿、只有 CI 报错。
//  原因不在打错一个字：那份白名单只核对「名字在不在表里」，而白名单的**说明文字**
//  自己就把那两个不存在的成员写成了事实。enumguard 现在拿 Apple 文档 JSON 的成员表卡它。
struct ArcStack: View {

    /// 卡片，按显示顺序。
    var cards: [StackCard]
    /// 这一页的个性色（卡片左上角那一抹）
    var accent: Color = TokensPalette.accent
    /// 无障碍里这一叠叫什么（"充电"…）
    var label: String = ""
    /// **滑到底了**。给了它，这一叠就变成「可以续的列表」（出行页用它做懒加载）。
    ///
    /// 用户 2026-09-25 第 1 条：「行程卡片采用懒加载，而不是需要人点加载 N 条」。
    /// 为什么这件事必须住在这里、而不能由页面自己算：滚动的几何只有 `ScrollView`
    /// 自己知道，而它是这一层的东西（页面拿不到）。上一轮删掉那些自算的位置时，
    /// 头注里写的就是「系统没有『你现在滚到第几张』这个数可以读」—— 那个数现在
    /// **有**了（`onScrollGeometryChange`，iOS 18+），所以续页可以按真实的滚动位置发。
    ///
    /// ⚠️ 它只会在「从不到底 → 到底」那一刻叫一次（`onScrollGeometryChange` 的判据是
    /// 值变了才回调，而它的值是 `Bool`）。所以调用点不必自己去重：
    /// 续了 5 张之后内容变高，「到底」自己就变回否了。
    var onReachBottom: (() -> Void)? = nil

    /// 无障碍翻页停在清单里的第几张（`step` 的输入）。
    @State private var current = 0

    /// 滚动内容的顶部内衬（由宿主量出来的安全区 + 一格呼吸位，见 `stackTopInset`）。
    /// 0 = 没人量过 —— 那时这一叠完全按系统布局走（默认行为，一个字都不变）。
    @Environment(\.stackTopInset) private var topInset

    var body: some View {
        GeometryReader { geo in
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    VStack(spacing: StackSpec.Card.gap) {
                        ForEach(Array(cards.enumerated()), id: \.offset) { i, card in
                            card.render(accent: accent)
                                .padding(.horizontal, StackSpec.Card.inset)
                                .id(i)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                    // 卡片视口 = 这一叠**量到的**尺寸（左右各留 `inset`）。
                    //
                    // 它只喂一件事：`CardFit` 算「展开后有多挤、放得下几行」。所以这里必须是
                    // 量出来的真数 —— 写一个「大概 800pt」的话，`CardFit` 那套算法就成了拿猜的
                    // 数字去做除法。读不到时环境值是 `.zero`，算法据此说「不知道」并放弃分块
                    //（见 `CardFit` 头注）。
                    .environment(\.cardViewport,
                                 CGSize(width: max(0, geo.size.width - 2 * StackSpec.Card.inset),
                                        height: max(1, geo.size.height)))
                }
                // 无障碍：卡片一张一张读的时候，一步一张比连续滚动好找。
                // 三指滚动**不需要**这一条 —— 那是 `ScrollView` 自带的。
                .accessibilityAdjustableAction { direction in
                    step(direction == .increment ? 1 : -1, proxy: proxy)
                }
                // 顶部：**内容顶到屏顶、卡片从时钟下连续滑过**（用户 2026-09-25 第 2 条：
                // 「顶部的时间和信号应该和地图页一样，不要遮盖」）。
                //
                // 改之前是「这一叠画在安全区里面」—— 静止时第一张卡确实让开了状态栏，
                // 但代价是它的上沿就是一道**硬裁线**：卡片滑到那里就凭空断掉，
                // 顶上永远横着一条什么都没有的空白带；而地图那一档是画到屏幕最上沿的。
                // 现在两者同一套行为：这一叠往上铺满（`.ignoresSafeArea(edges: .top)`），
                // 静止位置由**滚动内容的顶部内衬**保住（量出来的安全区 + 16，见
                // `stackTopInset`）—— 第 7 轮那条「第一张卡的圆角要看得见」因此没被推翻。
                // 顶上再交给系统的滚动边缘效果：内容从时钟下经过时由它给出可读性
                //（那是系统自己的处理，不是我们自造的又一层压暗）。
                .ignoresSafeArea(edges: .top)
                .contentMargins(.top, topInset)
                .scrollEdgeEffectStyle(.soft, for: .top)
                // 「滑到底了」—— 只在这一叠真的能滚时才算数。
                //
                // 那条 `contentSize > containerSize` 的守卫是必须的：内容比一屏短时
                // `contentOffset.y + 可视高` 天然就大于 `contentSize - 可视高`（后者是负数），
                // 于是判据恒真 —— 那一页会在第一帧里把自己续到底。
                // 判据留一屏的余量（不是“到底”才触发）：拇指拖到底的那一刻
                // 下一批卡已经建好了，而不是等松手才出现一张空白的等待。
                .onScrollGeometryChange(for: Bool.self) { g in
                    g.contentSize.height > g.containerSize.height
                        && g.contentOffset.y + g.containerSize.height
                            >= g.contentSize.height - g.containerSize.height
                } action: { _, near in
                    if near { onReachBottom?() }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text(label.isEmpty ? "卡片列表" : label))
        }
    }

    // =========================================================================
    // MARK: 无障碍翻页
    // =========================================================================

    /// 点「下一张 / 上一张」（无障碍翻页）。
    ///
    /// 落点由系统的 `scrollTo` 执行 —— 它自己会夹在可滚范围内，所以这里不需要
    /// 再算一遍两端（上一版要自己算：手势层没有系统来夹）。
    private func step(_ delta: Int, proxy: ScrollViewProxy) {
        let last = max(0, cards.count - 1)
        let next = min(max(current + delta, 0), last)
        guard next != current else { return }
        current = next
        TokensHaptic.select()
        withAnimation(StackSpec.settle) {
            // 末张按**底**对齐：它常常比一屏还高，顶对齐会让最后一张「差一口气读完」。
            proxy.scrollTo(next, anchor: next == last ? .bottom : .top)
        }
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
    var accent: Color = TokensPalette.accent
    var label: String = ""
    var cards: [StackCard]
    /// 转发给 `ArcStack.onReachBottom`（只有出行页用到，见那里的说明）。
    var onReachBottom: (() -> Void)? = nil

    var body: some View {
        ArcStack(cards: cards, accent: accent, label: label, onReachBottom: onReachBottom)
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

    /// 渲染。
    ///
    /// 曾经有一个 `glassy` 参数：离阅读线远的卡用不透明底、近的挂系统玻璃
    ///（多块 glass 同时重绘很贵，而消失带里那几张已经被遮罩淡到看不清）。
    /// 遮罩与阅读线都没了（见头注），而且在原生列表里「哪些卡在玻璃里」取决于
    /// 滚动位置 —— 同一张卡滚过去会自己换材质，那正是最像「贴图」的一种表现。
    /// 所以：**每张卡都是同一层玻璃**，与本叠的位置无关。
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
