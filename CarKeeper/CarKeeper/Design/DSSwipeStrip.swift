import SwiftUI

// =============================================================================
//  DSSwipeStrip —— 相机 App 的模式条（可手拖、带吸附、按下展开）
// =============================================================================
//
//  这是全套界面**唯一**的入口控件：地图是取景框，模式条决定取景框里此刻
//  在回答哪个问题。它不是「导航」，因为它**不换屏** —— 换的是同一块画布上
//  同一张纸里的内容。
//
//  形态是量出来的（用户 2026-09-23 / 2026-09-24 两次提供相机截图，按像素量过再落成）：
//    · 横条是**胶囊**（两端半圆），不是圆角矩形 —— 2026-09-24 的三张截图里，
//      外轨与选中格都是胶囊（`.bottom` 那条 3 格轨道最清楚：半圆的头尾各一个）
//    · 选中指示是一枚**胶囊**，高 0.85 × 条高，左右各留 0.37 × 条高
//    · 选中那一档的字是**主题强调色**（相机里是黄），其余是正文色 —— 相机用「颜色」
//      而不是「加粗」标出当前那一档，玻璃胶囊已经把「位置」说清楚了
//    · 相邻标签间距恒定 0.73 × 条高
//
//  ⚠️ 2026-09-26（用户：「你并没有按照相机 app 来设计底部导航，重新仔细研究相机 app
//  的逻辑，来重构我们的底部导航」）：条子从「静止只露三档、按住才长开的浮胶囊」
//  改成**贴底的全宽横带** —— 相机那条模式行本来就是全宽的，而它在我们这里只露得下
//  三档，唯一的理由是**左右各有一枚圆钮在挤它的宽度**。
//  那一轮把两枚圆钮移到了**它上面的一行**（见 `MapSpineView.bottomBar`），
//  于是整行宽度归条子，五档一次露全、等距铺开（与相机那张图同一个形状）。
//
//  连带的删除（同一个决定的另一半 —— 不删就是留下两套形态）：
//    · **「按住展开」没有了**：那个形态存在的唯一理由是「静止只露三档」。
//      现在它一直是全宽的，没有第二种形态可言 —— `expand` / `onExpand` /
//      `retractToken` / `ArmSlot` 一起删掉（后者的职责是「展开时把两枚圆钮让出去」，
//      而两枚圆钮已经不在这一行里了）。
//    · **静止三档的间距插值没有了**：间距只有一种算法（把全部档位都装下）。
//
//  留下来的那个形态是下面这一段说的「跟手」，它与展开无关：
//  手指拖的是整行，透镜钉在条正中、字从它下面滑过去。
//
//  跟手形态**只有一种**：手指拖的是**整行**，透镜钉在条正中、字从它下面滑过去 ——
//  这是 iOS 26 模式条的默认形态。
//
//  它曾经是个参数（`Follow` 枚举，另一个是「透镜跟手」：透镜从字上滑过去、整行基本不动，
//  那是 iOS 26 给这个默认留的反向开关）。2026-09-25 用户在真机上两种都试过、选了**整行**，
//  于是另外一个连同那个枚举一起删掉 —— 「仍在挑」最贵的代价不是多写一个分支，
//  而是每一个读到这里的人都要重新判断一次该用哪个（同一类账见 `DSCard` 头注里那个
//  叫 `glass` 却不产生玻璃的参数）。
//
//  有一件**刻意不照搬**：相机里左右滑取景框就换模式。地图上的横向拖拽是**平移** ——
//  抢掉它会让「拖地图」变成「换模式」，比少一个手势糟得多。所以这里只做条子自身。
//
//  为什么一档是**定宽**：吸附与「透镜压在谁身上」都靠几何算。若宽度随文字变，
//  同一次拖动在不同档之间走过的距离就不同，吸附会飘 —— 这是相机那条等距模式条的
//  物理前提，不是审美选择。（本 App 六个档名**都是两个汉字**，定宽恰好也是真实宽度。）
//
//  ⚠️ 几何全部由 `availableWidth` 参数推出来，**没有一处存起来**。
//  第一版把「可用宽度」存成 @State，于是它只会被测量那一次写对：
//  在非 390pt 的机器上，首帧的档位位置是按默认宽度算的，要等用户碰一下才归位。
//  派生量不会有陈旧值 —— 这是「宽度只当参数」的全部意思。
//
//  ⚠️ 2026-09-23 第二次修正：`availableWidth` 必须是**容器给的**宽度。
//  上一版让条子自己去量（`GeometryReader`），量到的是「HStack 分给它的那一份」——
//  两侧圆钮各占 50 + 中缝 9×2 之后只剩 256。
//  于是 `gap(for:)` 认为「展开装不下六档」，把间距压到 6：
//    · 静止条宽算出 148（应为 190），三档挤成一团 →「静止时对不上」；
//    · 节距 40 < 透镜宽 68 → **透镜压住左右两档的字**。
//
//  ⚠️ 2026-09-24 第三次修正（同一个病根的另一面）：间距应当按**当前露出几档**算。
//  上一版只补了「宽度从哪儿来」，而 `gap` 仍然一律按六档算 —— 静止时只露三档，
//  却用着为六档压出来的节距 40，于是那枚透镜被封顶成 38（≈ 字的宽度）。
//  用户看到的是一颗几乎贴字的椭圆：「首页 选中的玻璃体太小了，大 50%」。
//  现在：间距随展开插值（静止按三档算 → 宽裕；展开按全部算 → 不够才压），
//  透镜尺寸改由**格宽 ×1.5** 与**条高 ×0.94** 推出，**不再与节距挂钩**。
//  现在宽度由外壳量一整行得出（见 `MapSpineView.bottomBar` 的 `barRowWidth`），
//  条子自己的 frame 就等于算出来的条宽 —— 它不再是被挤压的弹性视图，
//  几何与渲染因此不可能两套。
//  （当年顺手加的「透镜宽度按节距封顶」已于 2026-09-24 撤掉 —— 它在静止时把透镜
//   压成一条，而它原本要治的那个病（压住邻居）真正的成因是标签坐标系偏移，已修。）

//  ⚠️ 下面这一段（到 `struct ArmSlot` 为止）是 **2026-09-25 的原文，2026-09-26 已删**：
//  它描述的 `ArmSlot` 是「展开时把两枚圆钮让出去」的修饰符，而按住展开与它服务的
//  那个状态一起没有了（见文件头）。**原文留着**，因为它记着两条还在用的教训：
//  ① 真玻璃上的「消失」必须是**不在场**（住在 `GlassEffectContainer` 里就会被它接住，
//     当成「变小」而不是消失）；② 一个形状的尺寸不该由别的控件决定。
//  读它请当成历史，不要当成现状。
/// 底条两端那两枚圆钮的「让位」——条子展开时要占满整行，所以两臂让位。
///
/// 2026-09-25 从 `MapSpineView.swift` 搬来这里：它是这个控件的**状态机上的一个后果**
///（见下面 `onExpand` 的契约），而不是那一屏的布局细节。
///
/// 展开时两枚钮**不在场**，不是「看不见但还占着 58pt」——后者会把条子压到装不下全部档位，
/// 于是条子只能压间距，而压间距正是原型明确否掉的那一件事。
///
/// 原型是 `.bottom.open .arm{opacity:0;transform:scale(.86)}`，而**那句 `scale` 不照搬**
///（2026-09-25 删，用户第 2 条：「全部页面不需要颤抖放大特效，太耗性能」）。
/// 理由不是「不好看」，是它每次触摸都在最贵的那一刻发生：手指一按下条子就开始展开，
/// 而这条底条的三个形状同处一个 `GlassEffectContainer`、背后是一张活地图。
///
/// ⚠️ 2026-09-25（用户第 4 条）：「底部滑动选择时，左右的俩个胶囊应该消失下」。
///  它此前是 `frame(width: open ? 0 : size)` + `opacity(...)` + `clipped()` —— 按那两个
///  修饰符它确实不可见，而真机上仍看得见一点的根由是这些形状住在 `GlassEffectContainer` 里：
///  那个容器的职责就是**把一块玻璃从一种尺寸变形到另一种**（容器文档原话是
///  *“morph individual shapes into one another”*），于是「收到 0 宽」在它眼里是「变小」
///  而不是消失。现在改成**不在场**（下面的 `if open`）：不存在的东西没法被变形，
///  也进不了容器那一层合成（顺带少两枚玻璃的离屏合成 —— 与用户第 2 条同一件事）。

//  （上面那一段 `///` 是**历史**，不是 `DSSwipeStrip` 的文档 —— 它一直跟着的是被删的
//  `ArmSlot`，所以这里夹一行 `//` 把附着的链条断开。）
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
    /// 这一行**可用的横向宽度**（屏宽 − 两侧留白）。
    ///
    /// ⚠️ 它必须是「容器给的宽度」，**不能**是条子自己被布局分到的宽度（见文件头）。
    /// 兜底 374 = 390 的屏宽减去两侧各 8 的留白 —— 让「暂时量不到宽度」的那一帧也算得下去
    ///（开发页 `StackLabView` 曾经是这样一个不量宽度的调用点，它已随用户第 6 条
    ///  「诊断里删掉一切与 UI 相关的」一起删除；兜底留着，因为它服务的是首帧，
    ///  而不是某一个调用点）。
    var availableWidth: CGFloat = 374
    /// 连续位置：`2.0` = 停在第三档，`1.4` = 正拖在第二、三档之间。
    /// 宿主用它做内容的交叉过渡 —— 换模式是渐变，不是闪一下。
    var onPosition: ((Double) -> Void)?
    //  `onExpand`（条子展开 / 收回时通知宿主）已于 2026-09-26 删。它的唯一读者是
    //  宿主里那个「让两臂让位」的状态，而两枚圆钮已经不在这一行（见文件头）。

    /// 条**以外**的整行拖动：宿主把「手指在整条上的横向增量」转发进来。
    /// 跟手、越界阻尼、吸附**全部仍在条子里** —— 宿主只转发，不换算。
    ///
    /// 为什么不能让宿主自己把增量换算成档位（上一版就是这么写的）：条子的位置是
    /// **一个**连续量（`c`），谁换算谁就是第二个实现。那种写法的两个后果都真实存在过：
    ///   · 手指按在条子上下的空白带里拖时，页面在换、**条子一动不动**
    ///     （宿主改的是它自己的 `modePosition`，`c` 没人碰）；
    ///   · 松手时没有谁写回档位 —— `fade` 就停在 0.5（两页各半透明地叠着），
    ///     下一次碰条子才归位。而那 26pt 的空白带正是拇指自然停放的位置
    ///     （宿主自己写着「整条都算滑动区」）。
    struct RowDrag: Equatable {
        /// 手指从按下到此刻的横向增量
        var translation: CGFloat
        /// 系统给的「松手后手指将到的地方」（含速度）—— 吸附用它
        var predicted: CGFloat
        /// 是否已越过「算拖」的阈值（宿主判的 8pt；条子据此决定展开）
        var moved: Bool
    }

    /// `nil` = 条外没有正在进行的拖动。松手就是把这条通道关掉 ——
    /// 吸附发生在「非 nil → nil」这一步（见 `rowDragChanged`）。
    var rowDrag: RowDrag? = nil

    // ---- 几何（全部由条高推出来，见文件头）----
    /// 条高。HIG 最小触控目标是 44；2026-09-25 从 46 抬到 **54** —— 用户「滑动区变高」，
    /// 而这条子既是显示、也是它自己的拖动面（上下叠叠乐 2026-09-25 起就是系统 `ScrollView`，
    /// 条子**不能**用：它要的是「整行跟手 + 吸附到档」这一种相机式的滑动，
    /// 而不是自由滚动），所以「看起来更大」与「更好按」在这件控件上是同一件事。
    /// 54 也与 iOS 26/27 那批浮动玻璃栏（工具栏 / Tab 栏）同一个量级。
    private let barHeight: CGFloat = 54
    /// 一档的宽度（定宽，见文件头）。2026-09-25：34 → **38**（用户：「全界面的控件大小
    /// 都很不 iOS」）。它与条高一起决定静止条宽（三档装得下）与展开后能不能占满整行 ——
    /// 所以这一改是把整条做大，而不只是把字放大。
    private let slot: CGFloat = 38
    /// 标签在透镜里左右各留多少
    private var pillPad: CGFloat { barHeight * 0.37 }
    /// 相邻标签的最大间距
    private var gapMax: CGFloat { barHeight * 0.73 }

    /// 选中格（透镜）的尺寸。**它不再由节距推出来** —— 那是上一版的病根：
    /// 静止时整行只露三档、但 `gap` 是按「六档能不能装下」算的（节距只有 40），
    /// 于是透镜被封顶成 38：几乎就是字的宽度，看起来「没有玻璃」。
    /// 用户 2026-09-24：「首页 选中的玻璃体太小了，大 50%」。
    ///
    /// 定宽走**格宽**（`slot` × **1.9**；2026-09-24 是 1.75，2026-09-25 用户又说
    /// 「选中的宽度加大」），定高走**条高**（0.94 × 条高）—— 高度不能再往上：
    /// 透镜比外轨还高就是「逞出来」而不是「更大」。
    ///
    /// 注：「选中的那一格更宽」与 HIG 那条「各段等宽」不矛盾 —— 等宽说的是**分段**
    ///（它们仍然是同一个 `slot`，所以吸附不会飘），而透镜是**选中指示**，
    /// 指示器比它盖住的那一段宽，正是 iOS 26/27 玻璃控件里选中态的做法。
    private var loupeWidth: CGFloat { slot * 1.9 }
    private var loupeHeight: CGFloat { barHeight * 0.94 }

    @State private var c: CGFloat = 0            // 行内坐标：条正中对应到行里的位置
    @State private var cBase: CGFloat?
    @State private var moved = false
    //  `expand`（条宽在静止与展开之间插值）与 `retractToken`（收回计时器的代号）
    //  2026-09-26 一起删：条子一直是全宽的，没有「收回」这个动作可延迟。
    /// 条外那次拖动按下时条子停在哪儿（`nil` = 条外没有正在进行的拖动）
    @State private var rowBase: CGFloat?
    /// 条外那次拖动的最新预测落点（横向增量，含速度）
    @State private var rowPredicted: CGFloat = 0
    /// 条外那次拖动是否已越过 8pt（决定松手后是「立即收回」还是「620ms 后收回」）
    @State private var rowMoved = false

    /// 当前档在条子上的位置。**可以是 `nil`** —— 那是「此刻在这一档，而它不在条子上」：
    /// 用户 2026-09-25 把「车辆」从条子上删掉了，它的入口是左臂那枚车钮。
    /// `nil` 的三种后果都是它该有的样子（见各自的注释）：不高亮任何一个字、不画透镜、
    /// 条子停在离当前位置最近的那一档上（见 `settle`）。
    private var index: Int? { items.firstIndex { $0.id == selectedID } }

    /// 透镜（选中胶囊）画不画。
    ///
    /// 不画的那种情形只有一个：此刻那一档**不在条子上**。透镜钉在条子正中，
    /// 它说的就是「你现在在这一档」—— 而那一档不在条子上时，它会把那句话说错
    ///（用户对这件事的原话是「条子不选中任何一档」，见 `HomeMode.vehicle`）。
    /// 手指一碰到条子就重新画出来（那时用户已经在挑下一档了，胶囊要跟着走）。
    private var loupeVisible: Bool { index != nil || cBase != nil || rowBase != nil }

    // =========================================================================
    // MARK: 行几何（全部是纯函数，宽度是参数）
    // =========================================================================

    /// 行内坐标：第 i 档的中心（i 可以是小数）
    private func ideal(_ i: Double, gap: CGFloat) -> CGFloat {
        CGFloat(i) * (slot + gap) + slot / 2
    }

    /// 一档的节距
    private func pitch(_ gap: CGFloat) -> CGFloat { slot + gap }

    /// 装下 `shown` 档需要的间距：装不下就把**间距**压到刚好（压间距，而不是让字互相盖住）。
    ///
    /// `shown` 是参数而不是「总是全部档位」—— 静止时整行只露三档，而按六档去算间距
    /// 会把静止的那三档挤成一条（节距 40、透镜 38，就是 2026-09-24 那两句抱怨的同一个来源）。
    private func gap(for width: CGFloat, shown: Int) -> CGFloat {
        let n = max(1, shown)
        if n == 1 { return gapMax }
        let fits = (width - 2 * pillPad - CGFloat(n) * slot) / CGFloat(n - 1)
        return min(gapMax, max(6, fits))
    }

    /// 条宽 —— **就是整行宽度**（相机那条模式行本来就是全宽的）。
    ///
    /// ⚠️ 它曾经是一个插值（静止三档宽 → 按住长开到全宽），那三个函数
    ///（`rowWidth` / `restWidth` / `openWidth` / `barWidth` 的插值）2026-09-26 一起删了：
    /// 「只露三档」这个形态没有了，于是「条宽」不再是变量。
    /// 把宽度交给容器（而不是自己算）还有一件好处：条子的 frame 与它几何用的宽度
    /// 永远是同一个数（那个「两套宽度」的错法见文件头）。
    private func barWidth(width: CGFloat) -> CGFloat { width }

    /// 拖动时 `c`（=条正中在行里的位置）的限位：**整行可达范围** ——
    /// 第一档能拖到条正中，最后档也能。
    ///
    /// ⚠️ 这里**不是**「透镜不被条边切掉」的限位。第一版把两件事揉在一个限位里，
    /// 结果：
    ///   · 静止时首尾档的透镜压不准自己的字（用户报的第 1 条）；
    ///   · 拖动时两端夹死在「呼吸位」，最左/最右档永远够不着（用户报的第 2 条）。
    /// 原型（`stack.html`）里条正中的行程是全行程，两端没有这道钳制。
    private func limits(width: CGFloat, gap: CGFloat) -> ClosedRange<CGFloat> {
        let lo = ideal(0, gap: gap)
        let hi = ideal(Double(max(0, items.count - 1)), gap: gap)
        return lo...hi
    }

    /// 行内坐标 → **条内**坐标（条的正中对应到行里的 `c`）。**只差一个 `c`**：
    /// 条宽变化不影响这个式子，所以展开时字不会自己往前跳
    /// （第一版用「条左边缘」当几何量，条一变宽窗口就单边向右长，拖 140px 跳了 4 档）。
    private func screenX(_ rowX: CGFloat, barW: CGFloat, c: CGFloat) -> CGFloat {
        barW / 2 + rowX - c
    }

    /// 透镜所在的连续档位：`c` 反算成「第几档」（可带小数）。松手时拿它吸附（`snap`）。
    private func pvValue(c: CGFloat, gap: CGFloat) -> Double {
        Double((c - slot / 2) / pitch(gap))
    }

    /// 越界阻尼：拖得动，但越拖越沉（拖出端 0.5 档后阻力逐点变大，松手被拉回）。
    ///
    /// 用户 2026-09-24：「不跟手」的另一面 —— 此前 `c` 被夹在整行行程内，
    /// 拖到两端是「撞到墙」，手指还在动而条子已经不动了。现在改成**拖得动、但越拖越沉**：
    /// 端点外 0.5 档内是 1:1 跟手，再往外每多 0.5 档阻尼加 1 倍，
    /// 松手时 `snap` 把「弹回端点」和「吸附最近档」一起算进去（见 `snap` 的说明）。
    private func clampC(_ raw: CGFloat, lim: ClosedRange<CGFloat>, gap: CGFloat) -> CGFloat {
        let slack = pitch(gap) * 0.5
        // 越出端的「软」段：把超出量按指数衰减，越拖越沉（阻力 1 → 2 → 3 …）。
        // 正常行程内（lim 范围）1:1 跟手，端点外才衰减。
        func soften(_ v: CGFloat, _ bound: CGFloat, _ direction: CGFloat) -> CGFloat {
            let over = (v - bound) * direction
            if over <= 0 { return v }  // 还没出端，1:1
            // 指数衰减：0.5 档内几乎 1:1，1.5 档后只剩 1/8 跟手（「越拖越沉」）
            let damped = 0.5 * (1 - pow(0.5, over / slack))
            return bound + damped * direction
        }
        if raw > lim.upperBound { return soften(raw, lim.upperBound, 1) }
        if raw < lim.lowerBound { return soften(raw, lim.lowerBound, -1) }
        return raw
    }

    // =========================================================================
    // MARK: 视图
    // =========================================================================

    var body: some View {
        let width = max(120, availableWidth)
        // 间距只有一种算法：**全部档位都装下**（不够才压）。曾经那对
        //「静止按三档算 / 展开按全部算」的插值随「按住展开」一起删了（见文件头）——
        // 全宽横带里没有「只露三档」这种形态，于是间距也就不该有两个数。
        let gap = gap(for: width, shown: items.count)
        let lim = limits(width: width, gap: gap)
        let barW = barWidth(width: width)
        // 显示用的位置：即使 `c` 是上一次几何下的值，也先夹到合法范围再画 ——
        // 于是「宽度变了」只会表现为吸一下，而不是首帧停在错的地方。
        let cShown = clampC(c, lim: lim, gap: gap)
        ZStack(alignment: .leading) {
            bar(width: barW)
            capsule(barW: barW)
            labels(gap: gap, barW: barW, c: cShown)
        }
        // 条子**自己就是这个宽度**：它不再是「HStack 挤压出来的弹性视图」，
        // 所以「几何用的宽度」与「渲染出来的宽度」不可能两套（见文件头）。
        .frame(width: barW, height: barHeight)
        .contentShape(Rectangle())
        .highPriorityGesture(swipe(gap: gap, lim: lim, barW: barW))
        .onAppear { settle(animated: false, gap: gap, lim: lim) }
        .onChange(of: selectedID) { _, _ in settle(animated: true, gap: gap, lim: lim) }
        // 条外的整行拖动：只接收增量，位置与吸附仍在这里算（见 `rowDragChanged`）。
        .onChange(of: rowDrag) { _, new in rowDragChanged(new, gap: gap, lim: lim) }
        // 容器宽度变了（旋转 / iPad 分栏 / 首帧量到宽度）→ 按新间距重新落位。
        // 少了这一步，条子会按旧间距停在旧位置，直到用户碰它一下才归位。
        .onChange(of: availableWidth) { _, _ in settle(animated: false, gap: gap, lim: lim) }
        //  （这里曾有 `.onChange(of: expand)`：展开/收回改了间距，`c` 要按新间距重算一遍，
        //   否则滑动选档之后透镜会与那一档的字错开 —— 用户 2026-09-25 第 3 条报的正是这个。
        //   2026-09-26 删：间距不再随展开变，也就没有「变了之后要重算」这一步。
        //   那条时序的正面结论留在 `settle` 上：**改档位的地方必须同时把 `c` 放到位**。）
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("功能"))
    }

    // =========================================================================
    // MARK: 三层
    // =========================================================================

    private func bar(width: CGFloat) -> some View {
        // 胶囊（不是圆角矩形）：相机那条外轨的两端是**半圆**。
        //
        // 2026-09-25 材质审核：这里原本是 `Capsule().fill(fillSubtle).glassEffect(...)` ——
        // 玻璃底下垫了一块**不透明的扁平色**，于是折射与透光都被它挡掉，看起来是
        // 「磨砂色块 + 一圈高光」而不是玻璃。现在底下是一块透明的占位（`Color.clear`
        // 只为给出尺寸），材质本身就是那一层 —— 这正是 `dsGlass` 存在的理由。
        Color.clear
            .frame(width: width, height: barHeight)
            //  形状从**胶囊**改成**圆角矩形**（2026-09-26）：胶囊的两端是半圆，
            //  那是「一根浮着的条子」的形状；而相机贴在底边的那一条模式行是**横带**
            //  （两端几乎不回收）。五档全宽铺开之后，半圆的头会把首尾两档的字压得
            //  很紧，而圆角矩形与它同一高度下的可用宽度是一致的。
            .dsGlass(in: RoundedRectangle(cornerRadius: TokensRadius.large,
                                          style: .continuous))
            .allowsHitTesting(false)
    }

    /// 选中格（胶囊）。它**钉在条正中**，永远不动 —— 「选中谁」由 `c` 把哪个字送到正中决定。
    /// 第一版在这里用 `pvValue(c)` 反算位置，那是一个恒等变换（ideal(pvValue(c)) == c），
    /// 算出来的 x 永远等于 width/2；留着它只会让人以为透镜会动。
    private func capsule(barW: CGFloat) -> some View {
        // 选中格同样是胶囊 —— 相机里「选中」就是一枚住在轨道里的胶囊。
        let shape = Capsule()
        //  它随时可以被「不画」（见 `loupeVisible`）；那一下是状态的改变而不是手势，
        //  所以要自己把那股过渡接上（下面的 `.animation(value:)`）。
        //
        // 宽度也不能比条身还宽（很窄的容器里）：留 6pt，否则它会盖住条的两端圆头。
        let w = min(loupeWidth, max(slot, barW - 2 * TokensSpacing.xs))
        //  这枚胶囊现在是一块**真的玻璃**（用户 2026-09-25 第 4 条：
        //  「选中入口的选择效果需要一个玻璃胶囊」）。
        //  它此前是 `Capsule().fill(glassHighlight)` + 一圈发丝线 —— 一个不透明的白面，
        //  也就是「玻璃的假象」：没有折射、没有反射、不和底下的字发生关系，
        //  看起来就是一枚半透明的白胶囊（这正是用户看到的那一幕）。
        //
        //  它现在是**条子这个容器里的第二块形状**，不是叠上去的第二层材质：
        //  整条底条（左钮 / 模式条 / 右钮）由 `dsGlassLayer` 包成同一个 `GlassEffectContainer`
        //  （见 `MapSpineView.bottomBar`），所以系统知道它俩换得近 —— 选中格与轨道
        //  因此会互相折射，也正是 iOS 26 分段控件里「选中」的形态。
        //  它仍然不是按钮：点选由条子那唯一一个拖动手势判（见 `swipe`），
        //  所以 `interactive` 不传 —— 一个不会自己动的玻璃不该装成会动。
        return Color.clear
            .frame(width: w, height: loupeHeight)
            .dsGlass(in: shape)
            .opacity(loupeVisible ? 1 : 0)
            .animation(TokensMotion.fade, value: loupeVisible)
            .position(x: barW / 2, y: barHeight / 2)
            .allowsHitTesting(false)
    }

    private func labels(gap: CGFloat, barW: CGFloat, c: CGFloat) -> some View {
        ZStack {
            ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                let x = screenX(ideal(Double(i), gap: gap), barW: barW, c: c)
                // 只画条附近的两档：更远的字**直接不画**（遮罩会裁掉它们，
                // 但画出来再裁是白花的 GPU，而且远处的字会以半透明形式漏到条外）
                if x > -slot && x < barW + slot {
                    Text(item.title)
                        .font(TokensTypo.fixed(15, weight: .semibold))
                        .tracking(TokensTracking.label)
                        // 选中 = 主题强调色（相机里那一档是黄），其余 = 正文色。
                        // 两档字的字重与字号**一样** —— 相机也是用颜色而不是加粗区分，
                        // 而比较粗的字会让相邻两档的行宽不一致，条子会跟着抖一下。
                        //
                        //  未选中那一档此前走 `TokensInk.primary`（自适应色）。
                        //  用户 2026-09-25 第 4 条：「底部导航的字体颜色都太弱了」——
                        //  那句抱怨描述的正是 vibrancy 的本意：系统会**压低**材质上文字的
                        //  对比度，让它看起来「长在材质里」。对一段说明文字那是好事，
                        //  而对**导航**是坏事：这是全 App 唯一的入口，它必须第一眼看清。
                        //  所以这里回到实色标签（`TokensPalette.primary` = `.label`），
                        //  并用下面那层外发光补回「它坐在玻璃上」这个事实。
                        //  `index` 是 `nil`（车辆）时五个字全部走正文色 —— 见它的说明。
                        .foregroundStyle(i == index ? TokensPalette.accent
                                                    : TokensPalette.primary)
                        //  这里原本挂着一层逐处的 `.dsInkGlow()`（用户第 8 条）。
                        //  2026-09-25 第 2 条之后**文字不需要它了**：外壳现在是全局的
                        //  （`DSTextGlow` 挂在 App 根上，见 `Design/InkGlow.swift`）——
                        //  连这行字也在内。两处都挂等于同一圈壳画两遍，只会变浓。
                        .frame(width: slot)
                        .position(x: x, y: barHeight / 2)
                        .accessibilityLabel(Text(item.title))
                        .accessibilityAddTraits(i == index ? [.isSelected, .isButton] : [.isButton])
                        .accessibilityAction { pick(i) }
                }
            }
        }
        // 标签、透镜、手势同处**条内**坐标系（原点 = 条的左边缘，正中 = barW/2）——
        // 此前把标签装进「全屏宽」的容器再居中，坐标却按条宽算，所有字整体偏
        // (屏宽−条宽)/2，透镜永远压不到当前档的文字。
        .frame(width: barW, height: barHeight)
        // 条自己把越界的那半格裁掉：原型 `.strip{overflow:hidden}`。
        // 遮罩居中对齐，正好罩住条身 —— 与条同一个圆角矩形。
        // 少了这一步，半压在条边上的那个字会**漏到条外** ——
        // 而条是带圆角的，露出去的那半截正好把「静止只露三档」这个形态破掉。
        .mask {
            // 遮罩必须与条子**同一个形状**（上面 `bar` 那个圆角矩形），
            // 否则半压在条端的那个字会从圆角外面漏出来。
            RoundedRectangle(cornerRadius: TokensRadius.large, style: .continuous)
                .frame(width: barW, height: barHeight)
        }
        .allowsHitTesting(false)
    }

    // =========================================================================
    // MARK: 手势
    // =========================================================================

    /// `minimumDistance: 0` 是为了**按下就能拖**（手指落在条上任何一处都算）。
    /// 代价是点选要自己做 —— 位移小于 8pt 就当成「点了最近的那一档」，
    /// 而不是让每个标签各挂一个 `Button`（那样按下那一刻两条手势会打架）。
    ///
    /// （它此前还兼着「按下就展开、松手 620ms 后收回」那件事，共两个 620ms 计时器
    ///   与一个代号。2026-09-26 随展开一起删：条子一直是全宽的，没有收回去的形态。）
    private func swipe(gap: CGFloat, lim: ClosedRange<CGFloat>, barW: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                if cBase == nil {
                    cBase = c
                    moved = false
                }
                if abs(v.translation.width) > 8 { moved = true }
                // 行跟着手指走，透镜钉在正中（唯一的跟手形态，见文件头）
                let raw = (cBase ?? c) - v.translation.width
                c = clampC(raw, lim: lim, gap: gap)
                onPosition?(pvValue(c: c, gap: gap))
            }
            .onEnded { v in
                if !moved {
                    pick(nearest(to: v.location.x, gap: gap, barW: barW))
                } else {
                    snap(gap: gap, lim: lim, projected: projectedPV(v, gap: gap))
                }
                cBase = nil
            }
    }

    private func nearest(to x: CGFloat, gap: CGFloat, barW: CGFloat) -> Int {
        let rowX = x - barW / 2 + c
        let raw = (rowX - slot / 2) / pitch(gap)
        return min(max(Int(raw.rounded()), 0), max(0, items.count - 1))
    }

    /// 松手：吸附到最近一档。位置与档位用的是同一条 spring，所以看上去是「滑过去」。
    /// 条外的整行拖动（宿主转发进来，见 `RowDrag`）。
    ///
    /// `guard cBase == nil`：条子自己的手势正跟着这一根手指时，这条转发**整个作废** ——
    /// 两者算出来的值相同（都是从按下那一刻的 `c` 减去同一个绝对增量），
    /// 但没有必要让同一根手指有两个写 `c` 的人。
    private func rowDragChanged(_ e: RowDrag?, gap: CGFloat, lim: ClosedRange<CGFloat>) {
        guard cBase == nil else {
            // 条子自己的手势接管了这根手指（转发作废）—— 连同起点一起忘掉：
            // 否则松手时还会按一个过时的起点再吸附一次（两次算出来的档通常相同，
            // 但「通常」不是「一次」）。
            rowBase = nil
            rowMoved = false
            return
        }
        guard let e else {
            // 松手：按**预测落点**吸附（速度算进去），与条内拖动的松手同一条路。
            //
            //  ⚠️ 只有**真的拖过**（越过 8pt）才吸附：没拖过的那一下是「点」——
            //  点在某枚圆钮上、或点在条子上下的空白带里。混进来的话，
            //  点左臂那枚车钮会先换到车辆档，紧接着被这里按原地位置吸回某一档，
            //  看起来就是「点车钮没用、一下子弹回去」。
            if let base = rowBase {
                rowBase = nil
                if rowMoved {
                    snap(gap: gap, lim: lim,
                         projected: pvValue(c: base - rowPredicted, gap: gap))
                }
            }
            rowMoved = false
            return
        }
        if rowBase == nil { rowBase = c }
        guard let base = rowBase else { return }
        if e.moved { rowMoved = true }
        rowPredicted = e.predicted
        c = clampC(base - e.translation, lim: lim, gap: gap)
        onPosition?(pvValue(c: c, gap: gap))
    }

    /// 松手时的**预测落点**（连续档位，`pvValue` 的同一量纲）：
    /// 用系统给的 `predictedEndTranslation`，而不是松手那一刻的位置 —— 两者差的就是速度。
    ///
    /// 为什么必须看速度：iOS 的吸附（列表、翻页、选择器）都看它，轻甩一下就该走过去。
    /// 只看位置的话，「甩」和「停」结果一样 —— 手感只能是「不跟手」。
    /// 预测只有一处：跟手形态只有一种，「松手会到哪儿」因此也只有一种算法。
    /// （`Follow` 被删掉之前这里是一个 switch —— 两个分支就是两份预测，
    ///  而它们描述的是同一个量：`c` 减掉预测位移之后的连续档位。）
    private func projectedPV(_ v: DragGesture.Value, gap: CGFloat) -> Double {
        pvValue(c: (cBase ?? c) - v.predictedEndTranslation.width, gap: gap)
    }

    /// 松手时的吸附。`projected` = 按速度预测的连续档位；
    /// 给 `nil` 就按当前 `c` 算（点按 / 没有速度信息）。
    ///
    /// 动作用 `TokensMotion.settle`（**不过冲**）而不是 `count`：`c` 不只是条子自己的位置 ——
    /// 宿主每一帧拿它算六页的交叉过渡。用会弹的弹簧，就是让六页（含一张活地图）
    /// 的透明度跟着过冲，看起来是「颤抖」，代价是那一叠每一帧重画（用户 2026-09-25 第 2 条）。
    private func snap(gap: CGFloat, lim: ClosedRange<CGFloat>, projected: Double? = nil) {
        let last = Double(max(0, items.count - 1))
        // 先夹再四舍五入：拖动时可以越出端（`clampC` 的软段），而档位只有 0…last。
        let pv = min(max(projected ?? pvValue(c: c, gap: gap), 0), last)
        let i = min(max(Int(pv.rounded()), 0), max(0, items.count - 1))
        guard items.indices.contains(i) else { return }
        if items[i].id == selectedID {
            // 档位没变：只把位置吸回去（onChange 不会触发，所以自己走一次）
            withAnimation(TokensMotion.settle) {
                c = clampC(ideal(Double(i), gap: gap), lim: lim, gap: gap)
            }
            onPosition?(Double(i))
        } else {
            selectedID = items[i].id
            TokensHaptic.select()
        }
    }

    /// 外部改档位（深链 / 「我的」里的入口 / 上次停在哪一档）→ 滑过去
    ///
    /// 同样走 `settle`（不过冲）—— 点选一档与滑动吸附必须是**同一种**动效，
    /// 否则「点」与「滑」到同一档看起来是两件事（这是上文那条「同一个量只有一份算法」
    /// 在动效上的另一半）。
    private func settle(animated: Bool, gap: CGFloat, lim: ClosedRange<CGFloat>) {
        //  当前档不在条子上（车辆）时，停到**离当前位置最近的那一档**上（不高亮它）：
        //    · 平时（从某一档点车钮进来）：最近的那一档就是刚离开的那一档，
        //      条子一动不动 —— 而那正是之后从条子往下拖时要接上的位置；
        //    · 冷启动直接落在车辆档时：`c` 的初值 0 不是任何一档的中心
        //     （见 `ideal`），那次归位把它收到第 0 档上 —— 否则整行会向右偏一截。
        let nearest = min(max(Int(pvValue(c: c, gap: gap).rounded()), 0),
                          max(0, items.count - 1))
        let i = index ?? nearest
        let target = clampC(ideal(Double(i), gap: gap), lim: lim, gap: gap)
        if animated {
            withAnimation(TokensMotion.settle) { c = target }
        } else {
            c = target
        }
        onPosition?(Double(i))
    }

    private func pick(_ i: Int) {
        guard items.indices.contains(i), items[i].id != selectedID else { return }
        selectedID = items[i].id
        TokensHaptic.select()
    }
}
