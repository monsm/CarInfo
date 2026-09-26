import SwiftUI

// =============================================================================
//  DSSwipeStrip —— 相机 App 的模式条（可手拖、带吸附、透镜钉在正中）
// =============================================================================
//
//  这是全套界面**唯一**的入口控件：地图是取景框，模式条决定取景框里此刻
//  在回答哪个问题。它不是「导航」，因为它**不换屏** —— 换的是同一块画布上
//  同一张纸里的内容。
//
//  形态是量出来的（用户 2026-09-23 / 2026-09-24 / 2026-09-26 三次提供相机截图，
//  每次都是按像素量过再落成）。**2026-09-26 第三批裁图（干净底，能量准）定的形**：
//    · 底玻璃 = **两枚圆钮之间那一条胶囊**（660×144px = 215×47pt，两端半圆）——
//      不是通铺全宽的横带。关键的一步是发现 **215pt 恰好等于两钮之间那一段**：
//      相机的带子宽度不是一个常量，它**就是那一段**，所以这里也把它画在自己身上
//      （`band`），宿主的行宽减去两枚圆钮与两条中缝就是它。
//    · 静止只画**当前档 ±1**。这一步是量出来的：同一台机器有六档（影效果 视频 照片
//      人像 空间 全景），而静态那张只有三行字；两图的**字距一样**（190px = 62pt，
//      1.32 × 带高），变的只是「露出多少」。
//    · 选中指示是一枚**胶囊**：静止 219×124px = 71×40pt（**0.86 × 带高**），
//      拖动时 237×144px = 77×47pt（**1.0 × 带高**）—— 它静止时比带子矮一截，
//      手指一拖就长到满高。宽 71 = 1.15 × 字距、77 = 1.24 × 字距。
//    · **拖动态**（相机图 2 / 图 3）：带子**溶解**（干净的黑底里量不到它）、
//      两枚圆钮**不在场**、字铺满整屏且两端渐隐（最外那档暗到 ~57%），
//      而胶囊**仍在正中** —— 跟手的是字，不是胶囊。
//    · 选中那一档的字是**主题强调色**（相机里是黄），其余是正文色 —— 相机用「颜色」
//      而不是「加粗」标出当前那一档，玻璃胶囊已经把「位置」说清楚了
//    · 相邻标签间距恒定 0.73 × 条高
//
//  ⚠️ 2026-09-26（用户两轮：①「你并没有按照相机 app 来设计底部导航，重新仔细研究
//  相机 app 的逻辑」②「你并没有仔细看相机底部导航静态和动态时的结构」）：
//  这一轮**量了两遍**，第一版是错的，两处都错在同一个地方 —— 把「后果」当成了「选择」：
//    · 相机静态**只露当前档 ±1 共三档**。最硬的证据是两张图放一起：同一台机器有六档
//      （影效果 视频 照片 人像 空间 全景），而静态那张只画得出 视频 照片 人像；
//      两图的**字距一样**（190px ≈ 62pt），变的只是「露出多少」。第一版把静态改成
//      「五档等距铺满整行」，那正是相机没有的形态。
//    · 相机那两枚圆钮**就在这一行**、在带子两端（左下缩略图、右下翻转镜头）。
//      第一版把它们挪到条子上面另起一行，理由是「条子只剩 240pt，所以只露得下三档」——
//      那条推理是反的：**正因为两枚钮在这一行，条子才放得下三档**。
//  其余量到的数（都写进 `MapSpineView.bottomBar`）：静态带子顶边距屏幕底 ≈81pt、
//  字心 ≈57pt；动态那张（手指拖到一半）带子顶边抬到 ≈97pt 且更实（白墙 255 → 95，
//  约 60% 黑）、可见档数从三涨到五档半（最左那档被屏幕边缘切掉）。
//
//  于是现在的形态是：**两枚圆钮之间那一段就是条子自己的宽**（`availableWidth`），
//  带子、字号、节距全从它推出来 —— 静止看得见三档是那个宽度的后果，不是输入。
//
//  ⚠️ 2026-09-26（第二次改）：带子与选中胶囊都从 `.dsGlass` 换成**自己画的面**
//（`TokensPalette.barFill` / `barSelection`）。两个原因都量过：
//    · 相机那条横带底下没有系统材质，所以「降低透明度」对它无效，而系统材质会变
//      （用户：「我们的底部导航也响应了，而相机的不会响应」）；
//    · 真材质必须住在一个 `GlassEffectContainer` 里，而那个容器把**同层的字与
//      选中胶囊一起吞掉了** —— 真机上量到的就是「带子里一个字都没有」。
//
//  「按下展开」仍然没有：那是相机**上一个版本**的做法（按下→条子长到全宽→620ms 后收回），
//  而它的替代品现在有了 —— 相机真正的动态态是下面这一条，它不是「展开」而是「溶解」。
//  `expand` / `onExpand` / `retractToken` / `ArmSlot` 仍留在历史里：
//  本条的目的不是抢宽度，所以那套插值时序没有一个是需要的。
//
//  两枚圆钮的让位归宿主（`MapSpineView.arm` 的 `if barDragging`）：它们不在条子里，
//  所以让位**不改变条子的宽**；而占位用的是一块同尺寸的空视图（`armPlaceholder`），
//  布局因此一个字也不动（这条账在 `arm` 上写着）。
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
//  现在宽度由外壳按**屏幕宽**算出这一段（见 `MapSpineView.barRowWidth(_:)`），
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
    /// 条子**能动用多宽** = 两侧圆钮之间那一段（宿主算好传进来的，
    /// 见 `MapSpineView.stripLaneWidth(_:)`）—— 不是整行宽度。
    ///
    /// ⚠️ 它必须是「容器给的宽度」，**不能**是条子自己被布局分到的宽度（见文件头）。
    /// 兜底 212 = 390 的屏宽减去两侧各 33 的留白、两枚 47 的圆钮与两条 9 的中缝 ——
    /// 让「暂时量不到宽度」的那一帧也算得下去（兜底服务的是首帧，不是某一个调用点）。
    ///
    /// 它也是**这一条胶囊的全部宽度**（相机量到的那 215pt 正是它这个量，只差屏宽）：
    /// 条子的 frame 就是它，而条子不再是自己画一根窄的坐在一条宽的里。
    var availableWidth: CGFloat = 212
    /// 拖动时字可以画到多宽（相机那张拖动态：六档铺满屏幕、两端被屏幕边切）。
    /// 宿主给的是整屏宽（`MapSpineView.bottomBar` 传的 `pageWidth`）—— 它比 `availableWidth`
    /// 宽，所以拖动时字会**溢出条子**：`frame` 不变（布局不动），变的是遮罩的宽。
    var spillWidth: CGFloat = 212
    /// 拖动中（相机的动态态）—— 宿主据此让两枚圆钮让位（它们不在这条子里）。
    /// 它只报「这一次触摸算不算拖」：轻点不抬，越过 8pt 才抬。
    var onDragging: ((Bool) -> Void)?
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
    ///     下一次碰条子才归位。而那条离底的空白带正是拇指自然停放的位置
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
    /// 条高 —— **相机那个数**（裁图 144px = 47pt）。条子这一族几何全由它推出来，
    /// 而宿主那两枚圆钮的直径**就是它**（`MapSpineView.armSize` 直接读这个常量）：
    /// 相机里圆钮与带子等高，两处各写一个数就是两个数。
    ///
    /// ⚠️ 2026-09-26（用户：「左右 2 个圆球太贴着边框了，和相机的尺寸距离大小不匹配」）：
    /// 2026-09-25 用户说过「滑动区变高」，于是条高 46 → 54。**那一次把整族数一起放大了
    /// 15%**：节距 62 → 71、选中胶囊 71×40 → 82×46、圆钮 47 → 54 —— 因为这几条式子的
    /// **比例是照相机定的**（节距 = 1.32 × 带高、胶囊 = 1.15 × 节距 与 0.86 × 带高），
    /// 带高一换，它们就一起漂。回到 47 之后，四条式子**同时**落回相机量到的绝对值
    ///（节距 62、胶囊 71×40、圆钮 47、带子 ≈215）—— 那是这组比例本来要给出的答案。
    /// 而「滑动区」一点没小：整行（含条下那 33pt）仍是滑动区，触摸高度还是 80pt，
    /// 与条高 54 那一版**逐点相同**。
    /// 它写成 `static` 是因为宿主也要读它（`MapSpineView.armSize`），而里面每一处都用
    /// `Self.barHeight` —— 一个数只能有一个出处（同名再声明一份实例属性会让这个名字
    /// 在实例上下文里指两个东西，读的人每次都得先判断是哪一种）。
    static let barHeight: CGFloat = 47
    /// 一档的宽度（定宽，见文件头）。它只当**标签的排版格**用（字号 13 的两个汉字
    /// 约 27pt），不再决定条子多宽 —— 条宽现在是 `availableWidth`（见 `barWidth`）。
    /// 它比字宽宽出那几 pt 就是相机量到的「字到透镜边 32pt 空气」里属于格的那一份。
    private let slot: CGFloat = 36
    /// 标签在透镜里左右各留多少（只在「档位太多、得压间距」时用）
    private var pillPad: CGFloat { Self.barHeight * 0.37 }
    /// 相邻标签的最大间距。相机量到的是 **1.32 × 带高**（190px 字距 ÷ 144px 带高），
    /// 而节距 = 格宽 + 间距 —— 所以这里写**减法**：间距 = 1.32 × 带高 − 格宽。
    ///
    /// ⚠️ 它曾经写成「0.65 × 带高」（两个式子在带高 54 时给出同一个值，看不出差别）。
    /// 带高回到相机那个 47 之后两者分开了：0.65 × 47 给出节距 66.6，而相机是 62 ——
    /// 也就是说那个 0.65 是**凑出来的系数**（为 54 凑的），1.32 才是量到的比例。
    ///
    /// ⚠️ 这个间距**两个状态下是同一个数**：量两张图时字距一样（都是 190px），
    /// 变的只是「露出多少」，所以它不能随形态变。
    private var gapMax: CGFloat { Self.barHeight * 1.32 - slot }

    /// 选中格（透镜）的尺寸。**它不再由节距推出来** —— 那是上一版的病根：
    /// 静止时整行只露三档、但 `gap` 是按「六档能不能装下」算的（节距只有 40），
    /// 于是透镜被封顶成 38：几乎就是字的宽度，看起来「没有玻璃」。
    /// 用户 2026-09-24：「首页 选中的玻璃体太小了，大 50%」。
    ///
    /// 2026-09-26 第三批裁图量到的是**两个数**（不再是「一个定值」）：
    ///   静止 71×40pt（宽 = 1.15 × 字距、高 = 0.86 × 带高）
    ///   拖动 77×47pt（宽 = 1.24 × 字距、高 = **1.0 × 带高**）
    /// 也就是「手指一碰到，胶囊长到满行高」—— 那一下是相机拖动镜头那个轨道的样子。
    ///
    /// 注：「选中的那一格更宽」与 HIG 那条「各段等宽」不矛盾 —— 等宽说的是**分段**
    ///（它们仍然是同一个 `slot`，所以吸附不会飘），而透镜是**选中指示**，
    /// 指示器比它盖住的那一段宽，正是 iOS 26/27 玻璃控件里选中态的做法。
    private func loupeWidth(_ pitch: CGFloat) -> CGFloat { pitch * (dragging ? 1.24 : 1.15) }
    private var loupeHeight: CGFloat { Self.barHeight * (dragging ? 1 : 0.86) }

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
    private var loupeVisible: Bool { index != nil || dragging }

    /// 相机的拖动态要不要上（见文件头）：手指按住、并且**越过 8pt** 才算 ——
    /// 轻点是选档，不该让整条底子闪一下。两条拖动通道各报各的那一半。
    private var dragging: Bool {
        if cBase != nil { return moved }
        if rowBase != nil { return rowMoved }
        return false
    }

    // =========================================================================
    // MARK: 行几何（全部是纯函数，宽度是参数）
    // =========================================================================

    /// 行内坐标：第 i 档的中心（i 可以是小数）
    private func ideal(_ i: Double, gap: CGFloat) -> CGFloat {
        CGFloat(i) * (slot + gap) + slot / 2
    }

    /// 一档的节距
    private func pitch(_ gap: CGFloat) -> CGFloat { slot + gap }

    /// 一条字离正中多远开始变暗、暗到多少。
    ///
    /// 锚点是量出来的**一处**：相机拖动态里最外那一档约 0.57（同一张图里另一档
    /// 被屏幕边切掉）。规则按几何写、不按像素：一档**整整跑出可见带一格**时降到 0.55，
    /// 之前一直是 1，之后不再更暗（再暗就读不出来了，而它仍然是一档可点的字）。
    ///
    /// 静止态根本碰不到它：只露 ±1 时最远的字距正中就是一格，而可见带的半宽是它两倍。
    private func fade(x: CGFloat, barW: CGFloat, pitch: CGFloat) -> Double {
        let visible = dragging ? max(barW, spillWidth) : barW
        let over = abs(x - barW / 2) - max(0, (visible - slot) / 2)
        guard over > 0 else { return 1 }
        return max(0.55, 1 - Double(over / max(1, pitch)) * 0.45)
    }

    /// 装下 `shown` 档需要的间距：装不下就把**间距**压到刚好（压间距，而不是让字互相盖住）。
    ///
    /// `shown` 由调用点给（现在是「全部档位」），而**宽度不再由它推** —— 上一版用它算
    /// 「三档多宽」，那仍然是把观察结果当输入。它现在只当一道安全网：
    /// 窄容器里字不许互相盖住（那个病在 2026-09-24 真实发生过：节距 40、透镜 38）。
    private func gap(for width: CGFloat, shown: Int) -> CGFloat {
        let n = max(1, shown)
        if n == 1 { return gapMax }
        let fits = (width - 2 * pillPad - CGFloat(n) * slot) / CGFloat(n - 1)
        return min(gapMax, max(6, fits))
    }

    /// 条子画出来的宽度 = **两枚圆钮之间那一段**（宿主量好传进来）。
    ///
    /// ⚠️ 它走过的三个形态，每一步都是把「后果」当成了「选择」被纠回来：
    ///   ① 插值（静止三档宽 → 按住长开到全宽）：`rowWidth` / `restWidth` / `openWidth`
    ///      就是为它存在的，2026-09-26 随「按住展开」一起删。
    ///   ② 「三档 + 两条间距」当宽度：那仍然是把观察到的结果（静止看见三档）当成了输入。
    ///      现在宽度归两枚圆钮（它就是那一段，见文件头），**三档是几何自己算出来的**：
    ///      带宽 ≈212、节距 62 → 212 ÷ 62 = 3.4，所以当前档 ±1 各自整格在带里、
    ///      ±2 整个在带外。要挪就挪节距，而节距是从带高推出来的，不是为「装几档」挑的。
    private func barWidth() -> CGFloat {
        max(120, availableWidth)
    }

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
        let barW = barWidth()
        // 间距只有一种算法：**全部档位都能铺开**（不够就把间距压到刚好）。
        // 它按 `spillWidth` 算而不是按带宽：拖动时字要铺到整屏（相机的拖动态），
        // 而两张图量到的字距一样 —— 所以这个数不能跟带宽挂在一起。
        let gap = gap(for: max(barW, spillWidth), shown: items.count)
        let lim = limits(width: barW, gap: gap)
        // 显示用的位置：即使 `c` 是上一次几何下的值，也先夹到合法范围再画 ——
        // 于是「宽度变了」只会表现为吸一下，而不是首帧停在错的地方。
        let cShown = clampC(c, lim: lim, gap: gap)
        ZStack(alignment: .leading) {
            //  拖动中它不在场（见 `band` 的说明）。
            if !dragging {
                band(barW: barW)
                    .transition(.opacity)
            }
            capsule(barW: barW, gap: gap)
            labels(gap: gap, barW: barW, c: cShown)
        }
        // 溶解 / 回来那一下的过渡（`if` 拿掉的东西要有人接住，否则是硬闪）。
        .animation(TokensMotion.fade, value: dragging)
        // 条子**自己就是这个宽度**：它不再是「HStack 挤压出来的弹性视图」，
        // 所以「几何用的宽度」与「渲染出来的宽度」不可能两套（见文件头）。
        .frame(width: barW, height: Self.barHeight)
        .contentShape(Rectangle())
        .highPriorityGesture(swipe(gap: gap, lim: lim, barW: barW))
        .onAppear { settle(animated: false, gap: gap, lim: lim) }
        .onChange(of: selectedID) { _, _ in settle(animated: true, gap: gap, lim: lim) }
        // 条外的整行拖动：只接收增量，位置与吸附仍在这里算（见 `rowDragChanged`）。
        .onChange(of: rowDrag) { _, new in rowDragChanged(new, gap: gap, lim: lim) }
        // 拖动开始 / 结束报给宿主：两枚圆钮靠它让位（它们不在这一条里，见文件头）。
        .onChange(of: dragging) { _, now in onDragging?(now) }
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

    /// 底子：**两枚圆钮之间那一条胶囊**（相机量到的形态，见文件头）。
    ///
    /// 它在这里而不是在宿主里 —— 它的宽度就是条子自己的宽度，两处各画一次就会有
    /// 两个数（2026-09-26 的上一版正是「宿主画一条通铺的、条子在里头又画一条窄的」）。
    ///
    /// 拖动时它**溶解掉**（相机图 2 / 图 3 的黑底里量不到它）：这是那个动态态的第一步。
    ///
    ///  ⚠️ 2026-09-26 第三批：三块形状（两枚圆钮 + 选中那一枚）回到了真玻璃，
    ///  而**它不跟着回去**（用户自己的两个直觉都对：「带子尽量保持一个液态玻璃试试，
    ///  但应该不是液态玻璃，要不然又看不到文字了」）：
    ///    · 它底下没有系统材质 —— 量出来的（相机那条横带就是画的，所以「降低透明度」
    ///      对它无效）；
    ///    · 它是选中那一枚**下面**那一层：它变成玻璃，就是「一块表面里叠两块玻璃」
    ///      （`DSGlass.swift` 规则的 ②），而那条路上一轮把整条的内容吞过一次；
    ///    · 字压在材质上时，对比度就由材质说了算 —— 那正是「又看不到文字了」，
    ///      而这条带子上的字是全 App 唯一入口的名字。
    ///
    ///  ⚠️ 2026-09-26（第二次改）：它从 `.dsGlass` 换成**自己画的面**（`barFill`）。
    ///  三条依据都是量出来的：
    ///    · 相机那条横带底下没有系统材质，所以「降低透明度」对它无效 —— 而我们的
    ///     会变（用户：「我们的底部导航也响应了，而相机的不会响应」）；
    ///    · 真材质必须住在一个 `GlassEffectContainer` 里，而**那个容器把同层的字与
    ///      选中胶囊一起吞掉了**（带子里一个字都没有）；
    ///    · 半透明的面本身就该带一圈发丝线：少了它，一条半透明的底子会和底下的照片
    ///      糊在一起（相机那条横带也有一道边缘）。
    ///  它曾经是 `.opacity(dragging ? 0 : 1)`（透明度 0 在容器眼里只是「内容不见了」）；
    ///  现在它由 `body` 里的 `if` 决定在不在，淡出交给 `.transition(.opacity)`。
    private func band(barW: CGFloat) -> some View {
        Capsule()
            .fill(TokensPalette.barFill)
            .overlay {
                Capsule().strokeBorder(TokensPalette.hairline, lineWidth: TokensHair.border)
            }
            .frame(width: barW, height: Self.barHeight)
            .allowsHitTesting(false)
    }

    /// 选中格（胶囊）。它**钉在条正中**，永远不动 —— 「选中谁」由 `c` 把哪个字送到正中决定。
    /// 第一版在这里用 `pvValue(c)` 反算位置，那是一个恒等变换（ideal(pvValue(c)) == c），
    /// 算出来的 x 永远等于 width/2；留着它只会让人以为透镜会动。
    private func capsule(barW: CGFloat, gap: CGFloat) -> some View {
        // 选中格同样是胶囊 —— 相机里「选中」就是一枚住在轨道里的胶囊。
        let shape = Capsule()
        //  它随时可以被「不画」（见 `loupeVisible`）；那一下是状态的改变而不是手势，
        //  所以要自己把那股过渡接上（下面的 `.animation(value:)`）。
        //
        // 宽度也不能比条身还宽（很窄的容器里）：留 6pt，否则它会盖住条的两端圆头。
        let w = min(loupeWidth(pitch(gap)), max(slot, barW - 2 * TokensSpacing.xs))
        //  ⚠️ 2026-09-26 第三批（用户：「准确的是 3 个液态玻璃，左右的球和中间的选中」）：
        //  它现在是**真玻璃**（`dsGlass`），与两枚圆钮同一套。
        //
        //  为什么这一次可以、上一次不行：上一次的障碍是「玻璃必须住在容器里」，
        //  而那时**带子也是玻璃** —— 两块玻璃叠在一个容器里才需要合成，也才会
        //  把同层的内容一起吞掉。现在带子是**自己画的面**（`band`，相机就是那样），
        //  所以这一枚坐在一块**不是玻璃**的面上：一块表面里没有第二块玻璃，
        //  也就不需要容器。
        //
        //  三代写法各自的账（留着，因为每一代都是被一个真实故障否掉的）：
        //    · 第一代 `Capsule().fill(TokensPalette.glassHighlight)` —— 一个半透明白面，
        //      也就是「玻璃的假象」；
        //    · 第二代真材质（那一版带子也是玻璃）—— 真机上量到「带子里一个字都没有」；
        //    · 第三代数层自画的伪玻璃（底渐变 / 边 / 影子）—— 质感仍差得远（用户）。
        //
        //  阴影不另加：系统玻璃自带边缘与投影，再加一层就是两层影子。
        return Color.clear
            .frame(width: w, height: loupeHeight)
            .dsGlass(in: shape, variant: .regular, interactive: false)
            .opacity(loupeVisible ? 1 : 0)
            .animation(TokensMotion.fade, value: loupeVisible)
            //  拖动时长到满行高（相机量到 40 → 47pt，0.86 → 1.0 × 带高）。
            .animation(TokensMotion.settle, value: dragging)
            .position(x: barW / 2, y: Self.barHeight / 2)
            .allowsHitTesting(false)
    }

    private func labels(gap: CGFloat, barW: CGFloat, c: CGFloat) -> some View {
        ZStack {
            ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                let x = screenX(ideal(Double(i), gap: gap), barW: barW, c: c)
                //  ⚠️ 这里曾经有一道裁剪判据（`if x > -slot && x < barW + slot`，
                //  「只画条附近的两档」）。**2026-09-26 删**：用户报「条子里一个字都
                //  没有」时，值得怀疑的正是「位置算错」这一类 —— 而窗口里一共只有五个字，
                //  画出来再裁的代价可以忽略。少一条判据就少一整类「什么都不显示」的可能，
                //  裁切本来就有遮罩在做（见本函数末尾的 `.mask`）。
                Text(item.title)
                    //  字号也回到相机那个数（裁图：glyph 40px = 13pt；带高 47 → 3.6 × 字高，
                    //  与相机逐字相同）。它此前是 15 —— 条高 54 那一族里的数；只换条高、
                    //  不换字号，静止形态就比相机大一圈（同一条子里的字占的份量）。
                    .font(TokensTypo.fixed(13, weight: .semibold))
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
                    //  所以这里走实色标签（`TokensPalette.primary` = `.label`），
                    //  并用全局那层外发光补回「它坐在玻璃上」这个事实。
                    //
                    //  ⚠️ 2026-09-26：底条上的字与图形**一律实色**，没有例外 ——
                    //  左边那枚圆钮里的车图形当月从 `TokensInk.primary` 换成实色，
                    //  依据是量出来的（截图里那一枚内部整片平坦 68…69、起伏 0，
                    //  而同一行右边那枚实色的钥匙是 251）。两处是同一个决定，见 `armGlyph`。
                    //  `index` 是 `nil`（车辆）时五个字全部走正文色 —— 见它的说明。
                    .foregroundStyle(i == index ? TokensPalette.accent
                                                : TokensPalette.primary)
                    //  这里原本挂着一层逐处的 `.dsInkGlow()`（用户第 8 条）。
                    //  2026-09-25 第 2 条之后**文字不需要它了**：外壳现在是全局的
                    //  （`DSTextGlow` 挂在 App 根上，见 `Design/InkGlow.swift`）——
                    //  连这行字也在内。两处都挂等于同一圈壳画两遍，只会变浓。
                    //  相机那张拖动态里，最外那一档暗到 ~57%（白墙被屏幕边切掉那一下）——
                    //  这里按「它离开可见带有多远」做同一条渐变：整整跑出一格 = 0.55，
                    //  不再更暗（再暗就读不出来了，而它仍然是可点的一档）。
                    .opacity(fade(x: x, barW: barW, pitch: pitch(gap)))
                    .frame(width: slot)
                    .position(x: x, y: Self.barHeight / 2)
                    .accessibilityLabel(Text(item.title))
                    .accessibilityAddTraits(i == index ? [.isSelected, .isButton] : [.isButton])
                    .accessibilityAction { pick(i) }
            }
        }
        // 标签、透镜、手势同处**条内**坐标系（原点 = 条的左边缘，正中 = barW/2）——
        // 此前把标签装进「全屏宽」的容器再居中，坐标却按条宽算，所有字整体偏
        // (屏宽−条宽)/2，透镜永远压不到当前档的文字。
        .frame(width: barW, height: Self.barHeight)
        // 窗口把越界的那半格裁掉（原型 `.strip{overflow:hidden}`）。
        //
        //  遮罩是一个**矩形**（2026-09-26 从圆角矩形改回）：窗口本身不可见，遮罩在这里
        //  只决定「字在哪里被切」。宽是**两个数**：静止 = **三档宽**（相机静态那张
        //  只画得出当前 ±1，两端各留一段空气）——不是条宽：带宽 ≈212、节距 62，
        //  按条宽裁（±106）会让 ±2 从窗口边缘露出 18pt 的一条边，而 `pitch × 3` = 186
        //  （±93）则 ±1 带 13pt 空气、±2 完全在窗外。
        //  拖动 = `spillWidth`（相机那张拖动态：六档铺满屏幕、切在屏幕边上）。
        //  字画到条子外面是故意的：`frame` 不动，所以布局不抖 —— 变的只是这块遮罩。
        .mask {
            Rectangle()
                .frame(width: dragging ? max(barW, spillWidth) : min(barW, pitch(gap) * 3),
                       height: Self.barHeight)
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
                    //  这一根手指归条子 —— 条外那条通道的**残留**一起清掉。
                    //  ⚠️ 2026-09-26：`rowBase` 原先只在 `rowDragChanged` 里清，而条外那条
                    //  手势被接管 / 被系统取消时**不会走 `onEnded`**，`rowBase` 就留下上一次
                    //  触摸的起点。下一次触摸若先到的是条外那条通道，它算出的 `c` 是
                    //  「过时的起点 − 本次增量」—— 松手吸附到的就是错的那一档（用户看到的
                    //  是「放手就去相邻的入口」）。起点与这一根手指的同一条通道绑定。
                    rowBase = nil
                    rowMoved = false
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

    /// 松手时**用哪一档**：位置说了算，速度只买一步。
    ///
    /// ⚠️ 2026-09-26（用户：「滑动到 A，放手就容易去相邻的入口」）：此前松手直接拿
    /// `predictedEndTranslation` 去换档位。它是系统按速度算出的「松手后手指将到的地方」，
    /// 在**一次普通拖动**里通常比手指多走 20–60pt（0.3–0.9 档，节距 62）——
    /// 用户把 A 对到透镜正中时手上还剩一点速度，那多出来的一截正好把他推过 0.5 档，
    /// 于是落到邻居。而用户对的是**眼睛看到的**那一档，不是速度预测出来的位置。
    ///
    /// 现在：投影比停手的位置多出不到半档 → 完全按位置吸附（速度只是噪声）；超过半档
    /// 才算「甩」，而甩**最多多走一档** —— 一路甩过三档不是这个控件的手感，
    /// 相机那条模式条也是「甩一下，走一格」。
    ///
    /// 两条通道（条内 / 条外整行）都走这一个函数：松手的结果只能有一个算法。
    private func landingPV(_ projected: Double?, gap: CGFloat) -> Double {
        let pos = pvValue(c: c, gap: gap)
        guard let projected else { return pos }
        let extra = projected - pos
        guard abs(extra) > 0.5 else { return pos }
        return pos + min(max(extra, -1), 1)
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
        // 先折算（速度只买一步，见 `landingPV`）再夹、再四舍五入：拖动时可以越出端
        //（`clampC` 的软段），而档位只有 0…last。
        let pv = min(max(landingPV(projected, gap: gap), 0), last)
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
