// =============================================================================
// Tokens.swift — 设计令牌的唯一来源（Single Source of Truth）
// =============================================================================
//
// v4 · iOS 原生语言（最终方向）
//
// 三条取值原则（按优先级）：
//   1. 能用系统语义值的，绝不自造：颜色、字号、分隔线、圆角都取 iOS 真值。
//      这些值原来是 App 与小组件共用一份源文件（Shared/WidgetTokens.swift）保证不漂移；
//      小组件体系已删，现在只此一处，`ArtTheme` 的 native 取值与之逐值相同。
//   2. 强调色全局唯一（系统蓝）。旧的「时间感知琥珀金」已整体废弃：
//      一个 App 同时挂两套强调色，等于没有强调色。
//   3. 文字只有三档（label / 60% / 30%），且必须**跟随浅色/深色** ——
//      旧值把 primary/secondary/tertiary 写成固定白色，浅色模式下不可读。
//
// 结构约定：命名空间一律挂在顶层类型上（TokensXxx），不嵌套 ——
// 历史上把泛用名嵌进项目命名空间，结果把 SwiftUI 的 `Color` 劫持掉了；
// `scan/shadowguard.py`（默认档 + --strict）会拦下这类形状。
//
// 已废弃并删除（含各自的调用点迁移）：
//   TimeOfDay / ambient 时间感知色系、amber 家族、deepBlack / daySurface、
//   呼吸动效（TokensMotion.breathe / kanseiBreathe）—— v4 规定：
//   界面里所有会动、会发光的东西都必须对应一个真实状态。
//
// v5 · 可切换的艺术主题（2026-09-25 **已整份删除**）
//   v5 曾经把下面的颜色值改成「从当前主题读」（ArtTheme.swift 里有 20 套取值：
//   夜光 / 纸上 / 巨字 / 原生 + 后来加的 16 套）。用户 2026-09-25 定下**只用原生**，
//   其余 19 套与整套切换机制一起删掉 —— 于是这里又回到 v4 的样子：
//   **值直接写在这一处**，没有再往外转一层。
//   （连带删掉的还有：`CanvasDecor` 画布装饰、`TokensSerif` 衬线标题、
//    `preferredScheme` 主题自带明暗、地图的艺术蒙版与三种车钉样式、
//    以及那页「主题样张」。理由与其余几处一致：**只有一种取值的开关就是一层假的选择**。）
// =============================================================================
import SwiftUI
import UIKit

// MARK: - 颜色令牌（单一来源）
enum TokensPalette {
    // ---- 表面 ----
    /// 页面画布（systemGroupedBackground，亮 #F2F2F7 / 暗 #000）
    static let canvas: Color = Color(uiColor: UIColor.systemGroupedBackground)
    /// 一级分组表面（secondarySystemGroupedBackground）
    static let surface: Color = Color(uiColor: UIColor.secondarySystemGroupedBackground)
    /// 内凹 / 抬升表面（tertiarySystemGroupedBackground）
    static let raised: Color = Color(uiColor: .tertiarySystemGroupedBackground)
    /// 发丝分隔线（UIColor.separator）
    static let hairline: Color = Color(uiColor: UIColor.separator)
    /// 光条 / 进度轨道（quaternaryLabel）
    static let track: Color = Color(uiColor: .quaternaryLabel)
    /// 铺在强调色之上的文字色。系统蓝配白可以 —— 而这个 App 的强调色只有系统蓝一种。
    static let labelOnTint: Color = .white
    /// 遮罩：弹层 / HUD 背后的一层。**纯黑 + 调用点给的不透明度**。
    static let scrim: Color = .black
    /// 光从哪来（白）。用在「电量就是光」的光条起点、以及车灯的光晕。
    static let lightSource: Color = .white
    /// 系统蓝（= accent 的亮色那一档）。`lightBar` 的终点用它，
    /// 所以它必须是同一个值，而不是又写一遍三元组。
    private static let blue: Color = tokenDynamic(light: (0.000, 0.478, 1.000),
                                                  dark: (0.039, 0.518, 1.000))
    /// 车灯光带渐变（白 → 浅蓝 → 系统蓝）：只在「电量就是光」的地方出现
    static var lightBar: LinearGradient {
        LinearGradient(colors: [.white,
                                Color(red: 0.612, green: 0.776, blue: 1.000),
                                blue],
                       startPoint: .leading, endPoint: .trailing)
    }
    /// 平坦画布渐变（滚动背景用）。只有一个画布，没有氛围渐变。
    static var canvasGradient: LinearGradient {
        LinearGradient(colors: [canvas, canvas], startPoint: .top, endPoint: .bottom)
    }

    // ---- 文字三档 ----
    static let primary: Color = Color(uiColor: .label)
    static let secondary: Color = Color(uiColor: .secondaryLabel)
    static let tertiary: Color = Color(uiColor: .tertiaryLabel)

    //  上面这三个是**不透明的系统标签色**（`.label` 三档）—— 它们在卡片、分组面
    //  这类标准表面上是对的（那也正是它们 99% 的用法）。
    //
    //  而在**真玻璃**上（浮层：模式条、地图上的胶囊与圆钮、轻提示）它们少了一样东西：
    //  系统给材质上文字的「自适应」（vibrancy）。HIG「Materials」写的就是这件：
    //     · “Help ensure legibility by using vibrant colors on top of materials.”
    //     · “reserve clear Liquid Glass for components over visually rich backgrounds.”
    //  WWDC25「Build a SwiftUI app with the new design」把 SwiftUI 这一侧说死了：
    //  “SwiftUI automatically uses a vibrant text color that adapts to maintain legibility
    //   against colorful backgrounds.”
    //
    //  ⚠️ 而那个「自动」只作用于**系统语义的文字色**（`foregroundStyle(.primary)` /
    //  `.secondary` / `.tertiary` 这几个层级样式），**不作用于** `Color(uiColor: .label)`
    //  这种已经解析成固定值的颜色 —— 后者在玻璃上就是一层实字，底下再花也不会调自己。
    //  这就是用户 2026-09-25 第 10 条问的那件事（「是不是没开启自适应文字颜色」）：
    //  对，没开启 —— 因为我们一直在传具体颜色。
    //
    //  所以玻璃上的字走 **`TokensInk`**（同文件里的顶层类型，与这里的三个一一对应）。

    // ---- 强调色（只有一个）----
    static let accent: Color = tokenDynamic(light: (0.000, 0.478, 1.000),
                                            dark: (0.039, 0.518, 1.000))
    /// 兼容旧调用名的别名。**不再是时间感知色** —— 金色方案已整体废弃。
    static var ambient: Color { accent }

    // ---- 语义状态色（界面上唯一的「彩色」来源）----
    static let success: Color = tokenDynamic(light: (0.204, 0.780, 0.349),
                                             dark: (0.188, 0.820, 0.345))
    static let warning: Color = tokenDynamic(light: (1.000, 0.584, 0.000),
                                             dark: (1.000, 0.624, 0.039))
    static let error: Color = tokenDynamic(light: (1.000, 0.231, 0.188),
                                           dark: (1.000, 0.271, 0.227))
    /// 充电 / 电驱（EV 语义，不等于 success）
    static let info: Color = tokenDynamic(light: (0.000, 0.780, 0.745),
                                          dark: (0.400, 0.839, 1.000))

    // ---- 兼容名（历史调用点保留）----
    /// 旧名：夜间表面。只有「系统表面」一种，跟随深浅色。
    static var nightSurface: Color { surface }
    /// 页面底色（旧名）
    static var background: Color { canvas }
    /// 卡里的**控件底**（输入框 / 分段控件的凹槽 / 未选中的底 / 骨架 / 按压态）。
    ///
    /// 用户 2026-09-25 第 3 条：「所有子页面的卡片上面还是有这种控件显示着不通透的
    /// 灰色（列表尤甚），我要通透」。根因就是它：原来读的是 `quaternarySystemFill`
    /// —— 那是系统为**不透明背景**定的灰，压在玻璃卡上就是一块灰纱：
    /// 它不折射、不跟着底下的颜色变，于是卡片是透的、卡片里那块灰是“实”的。
    /// （同一条账在 `panel` 上已经算过一次，那次清的是分组面。）
    ///
    /// 现在它与 `panel` 同源：都从 `surface` 取，只是更淡。卡片、分组面、控件底
    /// 于是是**同一块材质的三个深浅**，而不是三种来路不同的灰。
    /// 数字化它就是系统动态色 `secondarySystemGroupedBackground` 的一层透明度。
    ///
    /// ⚠️ 为什么不干脆改成真材质（`.glassEffect`）：`Design/DSGlass.swift` 三层规则
    /// 第 ② 条 —— **卡里不玻璃**（卡片自己已经是玻璃，里面再摆一块是同一层放两次）。
    /// 这一仓要的「通透」是【半透明】，不是【多一层材质】。
    ///  2026-09-26 第二轮：它乘上**界面实度**，而那一档已固定为 50%
    ///  （用户：「界面实度 默认 50%，删除默认对应的设置入口」）。
    ///  所以它不再读任何设置（那个开关连同 `DisplaySettings` 一起删了），
    ///  只有一个写死的数 —— 「有多透」这件事又回到**只有一个答案**。
    ///  0.22 × 0.5 = 0.11：比原来那一版更透，而卡里的字仍有底
    ///  （文字令牌是不透明的 `label` 三档，所以这个数在明/暗 × 有色/无色底
    ///  这四套下都读得出来）。
    private static let faceFill: Double = 0.5
    static var fillSubtle: Color { surface.opacity(0.22 * faceFill) }

    /// 卡片**里面**那一层面：分组面、占位面、提示条、搜索框。
    ///
    /// ⚠️ 它**不是** `surface`，虽然它读的是同一个色值。`surface` 是**不透明**的分组底色
    ///（secondarySystemGroupedBackground，深色 #1C1C1E），而卡片本身是一层玻璃
    ///（`GlassCard` → `dsGlass`）。一块不透明的面压在玻璃里，等于「玻璃中间挖了一个黑洞」：
    /// 深色模式 + 彩色壁纸下，卡是半透明暖红、里面的面是 (28,28,30)，两者挨在一起就是断的 ——
    /// 用户 2026-09-25 第 5 条：「每个界面的控件都应该是玻璃质感 …… 黑颜色太突兀了」。
    ///
    /// 取值是 `surface` 的半透明版，而不是另写一个灰：卡片自己的玻璃与它底下的壁纸
    /// 因此能继续透上来 —— 它才像同一块材质的一层，而不是贴上去的一块板。
    /// **那个透明度是这里唯一的刻度**：调大就更实、调小就更透，全 App 的面一起变。
    ///
    /// 为什么不在这里用真材质（`.glassEffect`）：`Design/DSGlass.swift` 三层规则的第 ② 条 ——
    /// **卡里不玻璃**（玻璃叠玻璃会糊成一片，而卡片自己已经是玻璃）。这一层要的是
    /// 「玻璃里面那层更暗的底」，不是第二块材质。
    ///
    ///  2026-09-25 第 3 条把它从 0.5 调到 **0.34**：0.5 在深色模式 + 彩色壁纸下仍然
    ///  读得出「一块灰面」（用户：「控件显示着不通透的灰色（列表尤甚），我要通透」）。
    ///  往下调要盯的只有一件事：卡片里的字还有没有底 —— 而文字令牌是不透明的
    /// `label` 三档，所以同一个数在这四套（明/暗 × 有色/无色底）下都是安全的。
    ///
    ///  2026-09-26 第二轮：与 `fillSubtle` 一起乘上**那个固定的界面实度**（见那一行）。
    static var panel: Color { surface.opacity(0.34 * faceFill) }

    // 已删除：`glassBorder`（2026-09-25，与 `glassLight` 同一批）。
    // 它也是 `hairline` 的重复声明 —— 而 12 位用户里只有 4 位（`dsGlass` /
    // `GlassCard` / 模式条 / 卡片）真的在给玻璃描边，其余是图表的网格线、读数的
    // 分隔线、开发页的色板。**分隔线就叫 `hairline`**，它们现在读那个名字。
    // 于是「带 glass 的名字」只剩 `glassHighlight` 一个，而它是材质内部的高光面
    // （见下），不是拿来当底的扁平色。
    /// 玻璃**里面**那一层更亮的底：模式条上被选中的那一枚、透镜。
    ///
    /// ⚠️ 它**不是**玻璃，也不该拿去当「浮层」的底 —— 浮层走 `dsGlass`
    /// （`Design/DSGlass.swift`，那才是真材质）。这个值只用来在**已经是玻璃**的
    /// 表面上再压一层更亮的形状（规则 ②：一块表面里不再叠第二块玻璃）。
    static let glassHighlight: Color = .white.opacity(0.15)

    // ---- 底条自己画的那两层（相机那条横带的做法）----
    //
    //  用户 2026-09-26：「当系统玻璃变最不通透后，我们的底部导航也响应了，而相机的
    //  不会响应」。相机那条横带底下**没有系统材质** —— 它是自己画的一层半透明面。
    //  「降低透明度」能降的只有材质；没有材质，就没有可降的东西。
    //  底条照它做：`DSSwipeStrip.band` 与两枚圆钮的底都用下面这两个值 ——
    //  于是那个开关对底部导航**没有任何影响**（这正是量出来的差别：系统材质会变，
    //  自己画的面不会）。
    /// 底条那条底子。亮：白 55%（`.label` 的黑字压在上面读得出来）；
    /// 暗：近黑 55%（白字读得出来）。
    ///
    /// 2026-09-26（用户：「底部导航的带子稍微再透一个等级」）：0.72 → **0.55**。
    /// 相机那条带子的浓度不可直接读（它是叠在地图上的），所以这不是量出来的数 ——
    /// 用户上一版看着偏实，`0.72 → 0.55` 是**一档**（16 个百分点，与相机那条
    /// 半透明黑的量级一致）。再往下调要盯的只有一件事：带子上那三档字的对比度。
    static let barFill: Color = tokenDynamic(light: (1, 1, 1),
                                             dark: (0.11, 0.11, 0.12),
                                             alpha: 0.55)
    // ---- 玻璃底下那一层「对比底」（Apple 的 dimming layer）----
    //
    //  用户 2026-09-26 第 3 条：「再就是玻璃通透的情况下，文字怎么能看得清，
    //  苹果官方是怎么解决的」。官方的答案在两处，都是明文：
    //
    //   · HIG「Materials」（2025-09-09 按 Liquid Glass 更新）把两个变体的用途分开了：
    //     * `regular` —— “blurs and adjusts the luminosity of background content to
    //       maintain legibility of text and other foreground elements … Use the regular
    //       variant when background content might create legibility issues, or when
    //       components have a significant amount of text.”
    //     * `clear` —— “highly translucent … Use this variant for components that float
    //       above media backgrounds — such as photos and videos.”
    //     并且给 `clear` 补了一条：*“For optimal contrast and legibility, determine
    //     whether to add a **dimming layer** behind components with clear Liquid Glass:
    //     if the underlying content is bright, consider adding a **dark dimming layer of
    //     35% opacity**; if the underlying content is sufficiently dark … you don’t need
    //     to apply a dimming layer.”*
    //   · `Glass.clear` 的文档同一句话，并给了写法：
    //     `Label(…).glassEffect(.clear).background(.black.opacity(0.3))` ——
    //     **对比底在玻璃之下**（`.background` 挂在 `.glassEffect` 之后）。
    //
    //  所以「通透 + 字看得清」不是二选一：`.clear` 自己不带任何保证，
    //  保证来自它底下那一层。这一版就把它加上了（`Design/DSGlass.swift`，
    //  唯一入口，调用点不必各自垫面）。
    //
    //  ⚠️ 与 Apple 那一条**不一样的一点，是颜色**：他那个例子的字是白的（媒体控件），
    //  所以垫的是**黑**。我们这一仓的字是自适应的（亮色下近黑、暗色下纯白，
    //  见 `TokensPalette.primary`）—— 垫黑会在亮色模式下把**黑字**埋掉。
    //  于是这一层取「与字反相」：亮色下是白，暗色下是黑。
    //  35% 用的是他给的那个数（亮色下白 35% 比黑 35% 更“奶”一点 ——
    //  这是「更透」与「字读得出来」之间那一步的价钱，改这一个数就是改那个天平）。
    /// 玻璃底下那一层对比底。亮：白 35%；暗：黑 35%。
    /// 1 = 令牌这一档；0 = 不要这层（底下已经足够暗 / 已经有自己画的面，
    /// 例如底条那三块坐在 `barFill` 上，它们传 `dim: 0`）。
    static let glassDim: Color = tokenDynamic(light: (1, 1, 1),
                                              dark: (0, 0, 0),
                                              alpha: 0.35)

    // 已删除：`barSelection` / `barSelectionRim` / `barSelectionShadow`
    //（2026-09-26 第三批）。它们是我给「选中那一枚」自画的三层伪玻璃（底渐变 / 边 / 影子），
    // 而用户在下一秒就把话说清了：「准确的是 3 个液态玻璃：左右的球和中间的选中」——
    // 那三块要的是**真玻璃**（`dsGlass`），而真玻璃自己就带边缘与投影。
    // 三个令牌因此一个读者都不剩：留着它们，下一个读的人会以为选中那一枚还是自画的。
    // 唯一留在原地的是带子那一个（`barFill`）—— 它不是玻璃，理由写在 `DSSwipeStrip.band`。

    // 已删除：`glassLight`（2026-09-25）。
    // 它是 `fillSubtle` 的**重复声明**（同一个值、两个名字），而「名字里带 glass
    // 的扁平色」正是那一轮材质审核要找的那类谎：谁读到 `glassLight` 都会以为拿到了
    // 材质，实际拿到的是「未选中的底」那种系统灰。四处调用点已改成 `fillSubtle`，
    // 于是全仓再没有一个叫 glass 的扁平令牌。

    /// 状态类名（ok / warn / charge…）→ 颜色。
    static func statusColor(_ cls: String) -> Color {
        switch cls {
        case "ok", "normal": return success
        case "warn", "warning": return warning
        case "bad", "fault", "abnormal", "danger": return error
        case "charge", "charging": return info
        case "acc", "accent": return accent
        default: return secondary
        }
    }

    /// 每一页的个性色（顺序与 `HomeMode.allCases` 一致：
    /// 出行 · 现在 · 充电 · 车控 · 我的 · 车辆）。
    /// 它用在：卡片左上角那一抹、巨字下面一行光晕。**不是文字色**，
    /// 所以不参与对比度约定；需要文字对比度的地方一律用 primary/secondary/tertiary。
    /// 六个就是 iOS 系统调色板里那六个（紫 / 蓝 / 绿 / 青 / 靛 / 浅蓝）。
    ///
    /// ⚠️ 2026-09-25「车辆」从条子末尾删掉时（见 `HomeMode`），**这一排跟着换了位**：
    /// 按下标取色的规矩没变，但五个排在条子上的页保持了各自原来的颜色 ——
    /// 删一个入口不该把五页的配色也重排一遍（那是用户没要的一次改版）。
    /// 于是「浅蓝」从第二位搬到最后一位（它原来就是车辆那一档的）。
    static let pageAccents: [Color] = [tokenColor(0xAF52DE), tokenColor(0x007AFF),
                                       tokenColor(0x34C759), tokenColor(0x30B0C7),
                                       tokenColor(0x5856D6), tokenColor(0x5AC8FA)]
}

// MARK: - 玻璃上的文字（三档，自适应）
//
//  与 `TokensPalette` 的文字三档一一对应，区别只有一件事：它们是
//  `HierarchicalShapeStyle` —— 系统会跟着底下的材质调它们（vibrancy / 自适应亮暗），
//  而 `Color(uiColor: .label)` 是已经解析死的值（原因与引用见 `TokensPalette` 里
//  「文字三档」下面那一段）。
//
//  用在哪：**只有底下是真玻璃的地方**（`dsGlass` 的那些调用点：模式条、地图上的
//  胶囊与圆钮、轻提示、卡片自己的卡头）。卡片里的正文继续用那三个具体颜色 ——
//  卡片里的底是 `panel`（标准半透明面），那里要的是确定的对比度，不是自调。
//
//  写成 `static var`（计算属性）而不是 `static let`：`AnyShapeStyle` 是装箱值，
//  当成共享常量存起来会撞上 Swift 6 的并发检查（同一类账见 `TokensPalette.lightBar`）。
enum TokensInk {
    static var primary: AnyShapeStyle { AnyShapeStyle(HierarchicalShapeStyle.primary) }
    static var secondary: AnyShapeStyle { AnyShapeStyle(HierarchicalShapeStyle.secondary) }
    static var tertiary: AnyShapeStyle { AnyShapeStyle(HierarchicalShapeStyle.tertiary) }
}

//  `TokensHalo` 整份已删（2026-09-26）。
//
//  用户原话：「完全删除文字发光和文字发光功能」。它指的是同一件事的两种形态 ——
//  「文字发光」（挂在 App 根上、给每一行字画一圈反色外壳的 `DSTextGlow`）与
//  「文字发光功能」（设置里那格 0…100% 的滑杆 + `DisplaySettings.glow`）。
//  两者连同取值表（这个 enum：半径 3/4、浓度 0.45/0.65 的动态色对）与那 4 处
//  `dsInkGlow()`（图形一侧的外壳）一起删掉，全仓不再有任何一层壳。
//  `Design/InkGlow.swift` 整个文件、`DisplaySettings.swift` 里的 `glow` 也一并删。

// MARK: - 间距（4 的倍数，页面边距 20）
enum TokensSpacing {
    static let xxs = CGFloat(2)
    static let xs = CGFloat(4)
    static let sm = CGFloat(8)
    /// 12 —— iOS 里最常用的一档中间值（芯片内边、两行小字之间、图与字之间）。
    /// 原来的阶梯是 2/4/8/16/…，缺这一档，于是全 App 有十几处用字面量 `10/11/12`
    /// 去凑它 —— 2026-09-25 把它补进刻度（用户：「所有页面的间距布局都很不 iOS
    /// 的标准」）：**能叫出名字的值才是同一个决定**。
    static let snug = CGFloat(12)
    static let md = CGFloat(16)
    static let lg = CGFloat(24)
    static let xl = CGFloat(32)
    static let xxl = CGFloat(48)
    static let xxxl = CGFloat(64)
    static let huge = CGFloat(88)
    static let page = CGFloat(20)
    /// HIG 最小触控目标（不是间距刻度的一档，故不参与缩放）
    static let row = CGFloat(44)
}

// MARK: - 圆角（inset-grouped 的取值）
enum TokensRadius {
    static let small = CGFloat(8)
    /// inset-grouped 分组面
    static let medium = CGFloat(12)
    /// 大面（hero / sheet）
    static let large = CGFloat(20)
    static let pill = CGFloat(999)
}

// MARK: - 字号
//
// 两族并存是**有意的**：
//   • 系统语义阶梯（largeTitle/title/body/footnote…）跟随 Dynamic Type，是正文骨架
//   • 固定尺寸字体（hero/heading/subtitle/micro 与仪表数字 display/metric/data…）不随字号缩放，
//     用于「数字不跳动、版式不位移」的场景
enum TokensTypo {
    // ---- 系统语义阶梯（跟随 Dynamic Type）----
    static let largeTitle = Font.largeTitle.weight(.bold)      // 34 / 700
    static let title = Font.title.weight(.semibold)            // 28 / 600
    static let title2 = Font.title2.weight(.semibold)          // 22 / 600
    static let title3 = Font.title3.weight(.semibold)          // 20 / 600
    static let headline = Font.headline                        // 17 / 600
    static let body = Font.body                                // 17 / 400
    static let callout = Font.callout                          // 16
    static let subheadline = Font.subheadline                  // 15
    static let footnote = Font.footnote                        // 13
    static let caption = Font.caption                          // 12
    static let caption2 = Font.caption2                        // 11
    /// 分组标题（iOS 的 section header：13pt、二级灰、大写由视图层加）
    static let sectionLabel = Font.footnote

    // ---- 固定尺寸标题（不随 Dynamic Type）----
    static var hero: Font { Font.system(size: 48, weight: .light).monospacedDigit() }
    /// 24pt 半粗标题。旧名 `TokensTypo.heading` —— 让位给系统语义阶梯里的 `title`（28pt 且跟随字号）。
    static var heading: Font { Font.system(size: 24, weight: .semibold) }
    static var subtitle: Font { Font.system(size: 17, weight: .regular) }
    static var micro: Font { Font.system(size: 11, weight: .regular) }

    // ---- 仪表数字：等宽数字（换数不跳动）----
    /// 超大数字（首屏 SOC / 关键指标）：**字重差**是「仪器感」的来源 ——
    /// 超细字重 + 负字距（字距在 DSBigNumber 里按字号算），不靠颜色、不靠发光。
    ///
    /// `weight` 是 2026-09-25 加的**唯一一个**参数，默认值就是原来的超细。
    /// 加它的理由只有一处（写在这里免得它被当成「又多了一个旋钮」）：地图抽屉头上
    /// 那三个数（续航 / 电量 / 车速）压在瓦片与照片上，用户第 3 条原话是
    /// 「卡片的 3 个要素字体加粗」—— 超细的字在通透玻璃上会散掉。
    /// 「仪器感」那一套（超细 + 负字距）仍然是默认值，没有被动过。
    static func display(_ size: CGFloat = 72, weight: Font.Weight = .ultraLight) -> Font {
        .system(size: size, weight: weight).monospacedDigit()
    }
    /// 中等数字（页面头部大数值）
    static func metric(_ size: CGFloat = 34) -> Font {
        .system(size: size, weight: .light).monospacedDigit()
    }
    /// 行内数字（列表数值，iOS 正文尺寸）
    static let data = Font.system(size: 17).monospacedDigit()
    static let dataSmall = Font.system(size: 15).monospacedDigit()
    /// 定尺文字（**不随 Dynamic Type**）。
    /// 用在哪：画布本身是几何图形的地方 —— 地图图钉、药丸、环内的读数。
    /// 那些地方把字号放大就会撑破图形，所以尺寸必须固定；但固定尺寸也**只能从这一个
    /// 地方来**（`grep "fixed(" 就能看到全 App 到底用了几个尺寸），不写在调用点。
    static func fixed(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
    /// 指定尺寸的等宽数字：图例、次要读数这类「比 dataSmall 还要小但必须等宽」的地方。
    /// ⚠️ data / dataSmall 是**属性**（固定尺寸），digits 是**函数**（带尺寸参数）——
    /// 写成 TokensTypo.data(13) 会编译报错（cannot call value of non-function type 'Font'）。
    static func digits(_ size: CGFloat) -> Font {
        .system(size: size).monospacedDigit()
    }
}

// MARK: - 动效（只服务状态变化）
//
// v4 规则：没有涟漪、没有光晕、没有扫光、没有呼吸、没有粒子。
// 常驻运动只有一个 —— 充电时能量沿电缆流动（它本来就在流，见 DSLightBar 的 glow）。
// 其余全是一次性：入场（reveal）、数值变化（value）、绘制（draw）。
enum TokensMotion {
    static let tap = Animation.spring(response: 0.25, dampingFraction: 0.7)
    static let page = Animation.spring(response: 0.5, dampingFraction: 0.8)
    // `reveal`（抽屉展开那一下的弹簧）2026-09-25 删除：它的读者是卡里那道自画抽屉
    //（`moreDrawer`），而那个抽屉整块交给了系统 sheet（见 `MapSpineReadouts` 头注）。
    static let count = Animation.spring(response: 0.4, dampingFraction: 0.6)
    /// 归位：**不过冲**的弹簧（临界阻尼）。
    ///
    /// 用户 2026-09-25 第 2 条：「底部导航点选或滑动，全部页面不需要颤抖放大特效，
    /// 太耗性能」。`count`（dampingFraction 0.6）是有意会「弹一下」的 —— 对抽屉张开、
    /// 筛选条切换那类**离散**变化，那一点点过冲就是反馈。
    ///
    /// 但它不能用来推**模式条的位置**（`DSSwipeStrip.c`）：那一个数每一帧都被宿主拿去算
    /// 六页的交叉过渡 `opacity`，于是「弹簧过冲」变成「六页（含一张活地图）的透明度
    /// 来回摆」—— 视觉上正是那次抱怨里的「颤抖」，代价上是那一叠每一帧都被重画一遍，
    /// 而它做的事只是把条子滑回最近一档。阻尼收到 1.0（临界）之后，`c` 单调走到位，
    /// 没有回摆：既没有那一下抖，也没有多余的帧。
    static let settle = Animation.spring(response: 0.34, dampingFraction: 1.0)
    static let press = Animation.spring(response: 0.30, dampingFraction: 0.86)
    static let value = Animation.spring(response: 0.36, dampingFraction: 0.88)
    static let screen = Animation.spring(response: 0.42, dampingFraction: 0.90)
    static let fade = Animation.easeOut(duration: 0.20)
    /// 一次性绘制（光条从 0 长到位）
    static let draw = Animation.easeOut(duration: 1.1)
}

// MARK: - 触觉
enum TokensHaptic {
    static func select() { UISelectionFeedbackGenerator().selectionChanged() }
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func error() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    static func heavy() { UIImpactFeedbackGenerator(style: .heavy).impactOccurred() }
    /// 一个布尔决定成功/失败反馈。
    /// 参数命名避开 `success`，否则会遮蔽同名的静态方法。
    static func result(_ ok: Bool) {
        if ok { success() } else { error() }
    }
}

// MARK: - 发丝线（1px 级别的边框与内缩，不是间距刻度）
enum TokensHair {
    /// 发丝线（iOS 分隔线厚度）
    static let line: CGFloat = 0.5
    static let border: CGFloat = 1
    /// 分隔线内缩（与行内容左对齐）
    static let inset: CGFloat = 16
}

// MARK: - 尺寸（触控目标与图标，不是间距刻度）
enum TokensSize {
    static let tap: CGFloat = 44
    /// 主按钮（iOS 实心胶囊）
    static let button: CGFloat = 50
    static let iconSm: CGFloat = 13
    static let icon: CGFloat = 17
    //  `iconLg`（22）已于 2026-09-25 删除：它只有**一个**读者 ——「我的」里那张
    //  「去看车辆」的卡（用户第 7 条把它整张删了，因为模式条上就有「车辆」那一档）。
    //  删功能要跟着删它留下的孤儿，否则下一个读到这里的人会以为还有地方在用它。
    static let tileIcon: CGFloat = 22
    /// 行内图标列宽（iOS 设置行）
    static let iconColumn: CGFloat = 29
    //  已删除：`barHeight`（2026-09-26）。它是 56 —— 条高还在 54 那一族时留下的数，
    //  而真正的出处是 `DSSwipeStrip.barHeight`（47）：两个名字指同一件东西、
    //  其中一个还是旧值，下一个人拿到的就是错的那个（它本来**一个读者都没有**）。
}

// MARK: - 已删除：`TokensSerif`（2026-09-25，随艺术主题一起删）
//
//  它曾经是「标题与地名走宋体」的那一份字体表：原生主题下它返回系统字（所以原生 = 现状），
//  三个艺术方向下返回 Songti SC。主题只剩原生之后，它每一处调用拿到的都是系统字 ——
//  也就是说**这一个名字底下什么都不剩**，而那正是这个仓库一直在删的那类东西
//  （同一个决定被做了两次：字体该从 `TokensTypo` 出，衬线只是它的一种取值）。
//  八处调用点改成 `TokensTypo.fixed(...)`（与原返回值逐值相同：13 / 34 semibold /
//  28 semibold / 22），`place` 与 `label` 两个只有衬线才用得上的入口一并消失。
//
// MARK: - 字距
//
// 疏排是这套视觉的主要手段之一：中文小字一旦排得开，就从"说明文字"变成"地图注记"。
// 数值不随 Dynamic Type 变 —— 它是版面的度量，不是字号的一部分。
enum TokensTracking {
    /// 图上地名（字距就是它的排版）
    static let place: CGFloat = 6
    /// 小标注（药丸、图上标签）：约 0.06em
    static let label: CGFloat = 0.6
    /// 面板大标题：略收紧
    static let title: CGFloat = -0.2
}

// MARK: - 颜色构造（两个小工具）
/// 顶层工具：0xRRGGBB + alpha → Color。
/// 用 `Color(.sRGB, ...)` 而不是 UIColor，是为了让取值在任何外观下都精确。
/// （原 `ArtTheme.artHex`，随 ArtTheme.swift 一起搬来这里 —— 它的读者只剩 `pageAccents`。）
private func tokenColor(_ hex: UInt32, alpha: Double = 1) -> Color {
    Color(
        .sRGB,
        red: Double((hex >> 16) & 0xFF) / 255,
        green: Double((hex >> 8) & 0xFF) / 255,
        blue: Double(hex & 0xFF) / 255,
        opacity: alpha
    )
}

/// 明暗两套取值。系统深色时取 dark，否则取 light。
/// （原 `ArtTheme.nativeDynamic`，同一段实现、同一批取值。）
///
/// `alpha` 服务两个**半透明**的令牌：底条那一条带子（`barFill`，相机那条横带就是半透明）
/// 与玻璃底下那层对比底（`glassDim`，Apple 的 dimming layer 就是一层半透明）。
/// 其余每一个令牌都是不透明的系统语义值（三块形状现在走真玻璃，不靠扁平色）。
private func tokenDynamic(
    light: (CGFloat, CGFloat, CGFloat),
    dark: (CGFloat, CGFloat, CGFloat),
    alpha: CGFloat = 1
) -> Color {
    Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
        ? UIColor(red: dark.0, green: dark.1, blue: dark.2, alpha: alpha)
        : UIColor(red: light.0, green: light.1, blue: light.2, alpha: alpha)
    })
}
