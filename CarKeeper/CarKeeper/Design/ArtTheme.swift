// =============================================================================
// ArtTheme.swift — 可切换的艺术主题（真机上一按就换，用眼睛挑）
// =============================================================================
//
// 为什么存在：三种艺术方向（夜光 / 纸上 / 巨字）光看截图挑不出来 —— 必须上真机。
//   所以方向不再是一份"稿子"，而是**一套可切换的取值**。切换点只有两个：
//     ① 令牌      —— TokensPalette 从当前主题读值（全 App ~340 处调用点一行不改）
//     ② 页面画布  —— pageBackground() 按主题叠一层装饰（光池 / 纸纹 / 网格）
//   换的是**值**，不是名字；所以任何一处用了令牌的界面都会立刻跟着变。
//
// 与小组件的关系（2026-09-23 已作废）：
//   这里曾写着「WT.Palette 是小组件 / 实时活动的唯一真源，艺术主题只作用在 App 内」。
//   小组件 / 表盘 / 灵动岛三个 target 已随免费账号清理全部删除（见 project.yml），
//   连那份 `Shared/WidgetTokens.swift` 也不在了 —— 现在**只有 App 一处界面**，
//   所以不再存在「App 的主题要不要外传」这个问题。
//
// 命名约定（历史教训，不是洁癖）：
//   一律用顶层类型（ArtTheme / ArtThemeSpec / ArtThemeStore / CanvasDecor）。
//   不再把泛用名（颜色、调色板、间距这类）嵌进另一个命名空间里 —— 历史上这样做过，
//   后果是 SwiftUI 的 `Color` 被整棵树劫持，编译报一堆“没有这个成员”。
//   `scan/shadowguard.py`（默认档 + --strict）专拦这种形状。
//
// 明暗：
//   .native 跟随系统（等于切换前的现状）；三个艺术方向自带明暗，由
//   CarKeeperApp 的 root 用 preferredColorScheme 施加 —— 纸上=亮，夜光/巨字=暗。
//
// 已做（2026-09-22 那一轮）：
//   ① 曾经散在全库的写死颜色 / 字号已全部迁到令牌 —— `TokensPalette.scrim`（遮罩与暗角）、
//      `labelOnTint`（彩色面上的文字）、`TokensTypo.fixed`（不跟随 Dynamic Type 的零件）
//      就是那一轮补的三个口子。**由 `scan/design.py` 长期把守**：字号与颜色字面量
//      只允许出现在 Tokens.swift / WidgetTokens.swift / 本文件里，
//      除此之外任何一处都要显式豁免并写明理由（未豁免就报错）。
//   ② 小组件与 App 曾共用 Shared/WidgetTokens.swift（同一份源文件）；Watch 那份
//      曾因 watchOS 上没有某些系统语义色而单独豁免 —— 这两份都已随扩展删除。
//      现在字号与颜色的字面量只允许出现在 Tokens.swift 与**本文件**里。
//
// 仍未做（如实说明，别以为已经做了）：
//   切换靠 root 上的 `.id` 重建整棵树 —— 副作用是那一瞬间**子树里的 @State 会重置**
//      （例如正在跑的下载进度条会归零；导航状态不受影响，它存在 NavState.shared 里）。
//      彻底解决要先把令牌改成可观察对象，那是一次涉及 ~340 处调用点的重构。
//      对"挑方向"这个用途而言，这是可接受的代价。
// =============================================================================
import SwiftUI

// MARK: - 画布装饰
/// 页面画布上的"艺术性"。不是颜色，是这套方向的做法。
enum CanvasDecor: String {
    /// 原生：只有一层中性画布（v4 规则：层级由表面色 + 发丝线 + 排版表达）
    case none
    /// 夜光：画布上有一束来自车所在地的光（暖，位置固定，不是动画）
    case lightPool
    /// 纸上：纸面颗粒 + 一点色温不均（印刷物在光下不会完全均匀）
    case paperGrain
    /// 巨字：极淡的网格 —— 版面本身就是内容
    case hairlineGrid

    /// 装饰强度（0 = 不画）。给视图层一个统一旋钮。
    var strength: Double {
        switch self {
        case .none: return 0
        case .lightPool: return 0.16
        case .paperGrain: return 0.05
        case .hairlineGrid: return 0.08
        }
    }
}

// MARK: - 一套主题的全部取值
/// **顶层 struct**，字段是属性不是嵌套类型 —— 不会与任何系统名撞。
struct ArtThemeSpec {
    // ---- 表面 ----
    var canvas: Color
    var surface: Color
    var raised: Color
    var hairline: Color
    var track: Color

    // ---- 文字三档 ----
    var label: Color
    var labelSecondary: Color
    var labelTertiary: Color

    // ---- 强调 + 语义（界面里唯一的"彩色"来源）----
    var accent: Color
    var success: Color
    var warning: Color
    var error: Color
    var info: Color
    /// 铺在强调色**之上**的文字色。
    /// 旧值写死 Color.white：系统蓝配白可以，但夜光的琥珀 #FFB26E 配白只有 1.9:1，
    /// 不可读 —— 所以它必须是主题的一部分，不是一个全局常量。
    var onAccent: Color

    // ---- 光条渐变：白 → 浅蓝 → 强调色 ----
    var lightBar: [Color]

    // ---- 上一版还写死在令牌层里的三处（现在它们也是主题的一部分）----
    /// 「光」的源头色：光条渐变的起点。
    /// 纸面上不允许发光（allowsGlow = false），所以那里它是墨色而不是白色 ——
    /// 否则纸主题会出现一条发光的白条，与「纸张没有发光」自相矛盾。
    var lightSource: Color
    /// 浅填充：输入框、未选中的底（`TokensPalette.fillSubtle` 读它）。
    var fillSubtle: Color
    /// 浮层 / 玻璃的高光边（暗底是白光，纸面是淡墨）
    var glassHighlight: Color
    /// 遮罩：弹层 / HUD 背后的一层、以及光照不到的暗角。
    /// 与 glassHighlight 同理 —— 它不是一个全局的「黑」：纸主题里遮罩是**墨**，
    /// 纯黑会在暖纸上发蓝。调用点只给不透明度。
    var scrim: Color

    // ---- 艺术规则（不是颜色）----
    /// 画布装饰
    var decor: CanvasDecor
    /// 允许"光"（发光/光晕）。纸上不允许 —— 纸张没有发光。
    var allowsGlow: Bool
    /// 标题走宋体（印刷物的做法）
    var usesSerifTitles: Bool
    /// 超大数字的字重（巨字方向靠**字重差**制造仪器感/海报感）
    var displayWeight: Font.Weight
    /// 超大数字的**额外**字距（不随 Dynamic Type 缩放的那一档）。
    /// 原生 = 0，即与切换前逐值相同（字距仍由 DSBigNumber 按字号算）。
    var displayTracking: CGFloat
    /// 主题自带的明暗；nil = 跟随系统（原生）
    var preferredScheme: ColorScheme?
    /// **每一页的个性色**，顺序与 `HomeMode.allCases` 一致：
    /// 出行 · 车辆 · 现在 · 充电 · 车控 · 我的。
    ///
    /// 为什么它是主题的一部分而不是六个新常量：六页的「个性」如果写死在页面里，
    /// 四套艺术主题下就都是同一套颜色 —— 而这一整套视觉的前提恰恰是「换主题 = 换值」。
    /// 它是**卡片左上角那一抹**与页内光晕的色，不是文字色，所以不参与对比度约定。
    var pageAccents: [Color]

    // MARK: - 全字段构造（老四套 + 原生的 spec 走它）
    ///
    /// 为什么它必须显式写出来：结构体一旦自己声明了任何 `init`，Swift 就不再合成
    /// 隐式的 memberwise init。下面那个「二十套主题」的便捷 init 是 `75c80ce` 加的，
    /// 它**顺手把当时四处照旧全字段写的 spec 弄红了**（夜光/纸张/字体/原生）：
    /// 每次调用都报 “extra arguments at positions #3, #4, #5, #7…”。
    ///
    /// 两套入口都是正当的，切不可为修编译而把四处调用改成便捷入口：
    ///   · 便捷入口 = 「我只告诉你我是什么」（色值由**同一套推导规则**算出来）；
    ///   · 全字段入口 = 「每一档我都量过」（那四处每个颜色旁边写着对比度实测值，
    ///     换成推导就等于把量过的值换成算出来的值 —— 那是设计变更，不是修 bug）。
    ///
    /// 参数顺序 = 下面存储属性的声明顺序，**不能改**：调用点按标签匹配、按顺序传参。
    init(canvas: Color,
         surface: Color,
         raised: Color,
         hairline: Color,
         track: Color,
         label: Color,
         labelSecondary: Color,
         labelTertiary: Color,
         accent: Color,
         success: Color,
         warning: Color,
         error: Color,
         info: Color,
         onAccent: Color,
         lightBar: [Color],
         lightSource: Color,
         fillSubtle: Color,
         glassHighlight: Color,
         scrim: Color,
         decor: CanvasDecor,
         allowsGlow: Bool,
         usesSerifTitles: Bool,
         displayWeight: Font.Weight,
         displayTracking: CGFloat,
         preferredScheme: ColorScheme?,
         pageAccents: [Color]) {
        self.canvas = canvas
        self.surface = surface
        self.raised = raised
        self.hairline = hairline
        self.track = track
        self.label = label
        self.labelSecondary = labelSecondary
        self.labelTertiary = labelTertiary
        self.accent = accent
        self.success = success
        self.warning = warning
        self.error = error
        self.info = info
        self.onAccent = onAccent
        self.lightBar = lightBar
        self.lightSource = lightSource
        self.fillSubtle = fillSubtle
        self.glassHighlight = glassHighlight
        self.scrim = scrim
        self.decor = decor
        self.allowsGlow = allowsGlow
        self.usesSerifTitles = usesSerifTitles
        self.displayWeight = displayWeight
        self.displayTracking = displayTracking
        self.preferredScheme = preferredScheme
        self.pageAccents = pageAccents
    }

    // MARK: - 便捷构造（20 套主题，2026-09-24 第八轮）
    ///
    /// 二十套主题全走这一个入口：每个主题**只给「它自己是什么」**（画布 / 表面 /
    /// 字 / 强调 / 装饰 / 字重 / 明暗 / 六页个性色），其余字段按**同一套规则推导**
    /// （发丝线 = 字色 ×12%、轨道 = 字色 ×15%、填充 = 字色 ×6%、高光 = 字色 ×15%、
    /// 遮罩 = 画布、光条 = 亮→中→强调 三段、语义色 = 四套固定取值、onAccent = 按
    /// 强调色亮度取深/浅）。规则写在一处 = 二十套主题不会各长一套习惯；
    /// 「完全不一样」体现在每个主题给的**核心色与装饰**上，不体现在推导规则上。
    init(canvas: Color,
         surface: Color,
         label: Color,
         accent: Color,
         decor: CanvasDecor = .none,
         allowsGlow: Bool = true,
         usesSerifTitles: Bool = false,
         displayWeight: Font.Weight = .ultraLight,
         displayTracking: CGFloat = -0.3,
         preferredScheme: ColorScheme? = nil,
         pageAccents: [Color]? = nil) {
        // 推导规则（全部是「同一个决定做一次」）：
        self.canvas = canvas
        self.surface = surface
        self.raised = surface
        self.hairline = label.opacity(0.12)
        self.track = label.opacity(0.15)
        self.label = label
        self.labelSecondary = label.opacity(0.62)   // 中间档：比正文淡，但要读得清
        self.labelTertiary = label.opacity(0.48)    // 第三档：说明文字（≥4.5:1 靠调用点字号兜）
        self.accent = accent
        // 语义色：四套固定取值（亮底用深一档，暗底用亮一档；跟着 preferredScheme 走）
        let dark = (preferredScheme ?? .dark) == .dark
        self.success = dark ? artHex(0x7FE0A0) : artHex(0x2E7D4F)
        self.warning = dark ? artHex(0xF0B24A) : artHex(0x9A6B15)
        self.error = dark ? artHex(0xFF6A55) : artHex(0xC0392B)
        self.info = dark ? artHex(0x78C8FF) : artHex(0x2F6B8F)
        self.onAccent = Self.onAccentText(for: accent, on: canvas)
        self.lightBar = [artHex(0xFFF6E8, alpha: dark ? 0.9 : 0.7),
                         accent.opacity(0.55), accent]
        self.lightSource = dark ? artHex(0xFFF6E8) : accent
        self.fillSubtle = label.opacity(0.06)
        self.glassHighlight = label.opacity(0.14)
        self.scrim = canvas
        self.decor = decor
        self.allowsGlow = allowsGlow
        self.usesSerifTitles = usesSerifTitles
        self.displayWeight = displayWeight
        self.displayTracking = displayTracking
        self.preferredScheme = preferredScheme
        self.pageAccents = pageAccents ?? Self.defaultPageAccents(dark: dark)
    }

    /// 六页默认个性色（不显式给的那一套）：暗底走六道冷光，亮底走六种墨。
    private static func defaultPageAccents(dark: Bool) -> [Color] {
        dark ? [artHex(0xB9A6FF), artHex(0x78C8FF), artHex(0x6FA8FF),
                artHex(0x5FD08A), artHex(0xA7C8EA), artHex(0xD9D2FF)]
             : [artHex(0x6A5F92), artHex(0x3F6E9E), artHex(0x2F5B8A),
                artHex(0x3F7A5A), artHex(0x4A6B87), artHex(0x5F5A80)]
    }

    /// 铺在强调色**之上**的文字色：强调色亮就铺深字，暗就铺浅字。
    /// 判据走 sRGB 分量（每个主题给的强调色都是 `artHex` 的定值，不可能是动态色）。
    ///
    /// 取分量不走 `UIColor`（SwiftUI 的 `Color` 没有可靠的公开 API 反解成 sRGB 分量；
    /// `getRed` 在动态色 / pattern 色上会失败）。`artHex` 构造的定值色直接读它的
    /// `CGColor` 分量 —— 同一套 sRGB 数值（`Color(.sRGB, ...)` 构造时就是这三个分量），
    /// 确定性成立；取不到（理论上不会发生）就铺白字。
    private static func onAccentText(for accent: Color, on canvas: Color) -> Color {
        guard let c = accent.cgColor, let comps = c.components, comps.count >= 3 else {
            return .white
        }
        // 分量顺序按 `colorSpace` 定：sRGB 是 [r,g,b,a]，但少数 CGColorSpace
        // 是 [gray,alpha]（只有 2 个分量）—— 定值色走 `Color(.sRGB,...)` 不会出现这种。
        let v: [Double] = Array(comps.prefix(3)).map { Double($0) }
        let l = 0.2126 * v[0] + 0.7152 * v[1] + 0.0722 * v[2]
        return l > 0.6 ? artHex(0x1A1614) : .white
    }
}

// MARK: - 四个方向
enum ArtTheme: String, CaseIterable, Identifiable {
    /// 夜光 —— 光就是秩序。黑底、暖金、只给车发光。
    case nocturne
    /// 纸上 —— 一张真的地图。纸与墨，红色只给品牌与危险。
    case paper
    /// 巨字 —— 尺度就是艺术。极细巨字 + 发丝网格。
    case typographic
    /// 原生 —— 切换前的 v4 语言（系统语义色）。默认值，切回来完全等于现状。
    case native
    // ---- 2026-09-24 第八轮新增 16 套（用户：「艺术主题有点欠缺，头脑风暴搞出 20 种
    //      完全不一样的」）：每套的美都来自**一个不同的机制**（材质 / 印刷 / 摄影 /
    //      玻璃 / 版画 / 仪表盘 / 胶片 …），不来自配色微调 —— 调色相不叫「完全不一样」。
    /// 玻璃 —— 一块起雾的玻璃窗。冷白、透明感、所有色都隔着一层水汽。
    case frost
    /// 青釉 —— 宋代瓷的青。低温青灰釉面，色温偏冷，光不发光、只折射。
    case celadon
    /// 胶片 —— 暗房里的红。冲印灯箱：暖红 + 黑，只有车那一颗星是亮的。
    case darkroom
    /// 墨绿 —— 军用的墨。旧仪器面板：深绿面、荧光绿读数，黑底上只有两个色。
    case phosphor
    /// 沙丘 —— 正午的沙漠。高对比暖沙色，字是晒干的赭墨，光是白得发烫的。
    case dune
    /// 雪夜 —— 雪地里的月光。深蓝黑底 + 冷白，只有车灯那一圈是暖的。
    case snowfield
    /// 蓝图 —— 工程蓝图。深蓝 + 白线，色温与「纸上」相反：那是暖纸，这是冷墨。
    case blueprint
    /// 琥珀 —— 树脂里封住的一帧。暖橙透明，光在色层里弯。
    case amber
    /// 银灰 —— 仪表盘的磨砂钢。中性灰阶，强调色只给「异常」那一格。
    case brushed
    /// 绛紫 —— 酒窖里的紫。深绛紫面 + 葡萄紫高光，光从瓶底透上来。
    case cellar
    /// 朱砂 —— 批红的印。暖白宣纸 + 朱砂一点，全 App 只有一个色是红的。
    case cinnabar
    /// 苔原 —— 冻土带。低饱和的青灰绿，光永远在雾后面。
    case tundra
    /// 玄墨 —— 水墨画留白。大面积近白，只有字是浓墨，装饰是极淡的墨晕。
    case inkwash
    /// 熔炉 —— 铸铁车间。近黑 + 铁橙，光像从缝隙里漏出来的。
    case forge
    /// 晨雾 —— 湖面的清晨。极淡的灰蓝渐变，字是雾前的远山色。
    case mist
    /// 赛博 —— 霓虹雨夜。深紫黑 + 品红与青的两道霓虹，只给车钉发光。
    case neon

    var id: String { rawValue }

    var title: String {
        switch self {
        case .nocturne: return "夜光"
        case .paper: return "纸上"
        case .typographic: return "巨字"
        case .native: return "原生"
        case .frost: return "玻璃"
        case .celadon: return "青釉"
        case .darkroom: return "胶片"
        case .phosphor: return "荧光"
        case .dune: return "沙丘"
        case .snowfield: return "雪夜"
        case .blueprint: return "蓝图"
        case .amber: return "琥珀"
        case .brushed: return "银灰"
        case .cellar: return "绛紫"
        case .cinnabar: return "朱砂"
        case .tundra: return "苔原"
        case .inkwash: return "玄墨"
        case .forge: return "熔炉"
        case .mist: return "晨雾"
        case .neon: return "霓虹"
        }
    }

    /// 一句话说明这套方向的**美从哪来**（不是形容词，是机制）
    var mechanism: String {
        switch self {
        case .nocturne: return "美来自光：黑底承担信息量，光只给车"
        case .paper: return "美来自印刷：纸面、墨线、红笔"
        case .typographic: return "美来自尺度：极细巨字对极小标注"
        case .native: return "美来自系统：语义色、分组表面、发丝线"
        case .frost: return "美来自水汽：所有色隔着起雾的玻璃"
        case .celadon: return "美来自釉：低温青灰，光只折不发"
        case .darkroom: return "美来自暗房：暖红灯箱，黑里一颗亮点"
        case .phosphor: return "美来自旧仪器：深绿面板、荧光读数"
        case .dune: return "美来自晒过：高对比暖沙色，墨是赭的"
        case .snowfield: return "美来自冷白：深蓝黑底，只留车灯暖圈"
        case .blueprint: return "美来自工程线：深蓝底、白线、冷墨"
        case .amber: return "美来自树脂：暖橙透明，光在色层里弯"
        case .brushed: return "美来自磨砂钢：中性灰阶，异常才用色"
        case .cellar: return "美来自瓶底透光：深绛紫面、葡萄紫高光"
        case .cinnabar: return "美来自钤印：暖白宣纸，只有红是朱砂"
        case .tundra: return "美来自冻土：低饱和青灰绿，光在雾后"
        case .inkwash: return "美来自留白：大面积近白，字是浓墨"
        case .forge: return "美来自缝隙透光：近黑底、铁橙从缝里漏出"
        case .mist: return "美来自远山：灰蓝渐变，字是雾前的色"
        case .neon: return "美来自雨夜霓虹：深紫黑，品红与青各一道"
        }
    }

    /// 这套方向在真 MapKit 上的处境（与 MAPKIT-FEASIBILITY.md 逐条对应）
    var mapKitVerdict: String {
        switch self {
        case .nocturne: return "最能落地：压暗 MapKit + 我们叠光层"
        case .paper: return "最贵：MapKit 画不出纸与墨，得自建地图样式"
        case .typographic: return "最省：地图退成极淡网格"
        case .native: return "现状：系统地图原样"
        case .frost: return "系统瓦片盖 20% 冷白雾（磨砂玻璃感）"
        case .celadon: return "瓦片盖 30% 青灰（釉色蒙版）"
        case .darkroom: return "瓦片压到 75% 暗 + 暖红罩（暗房灯箱）"
        case .phosphor: return "瓦片压到 80% 暗 + 深绿罩（旧仪器）"
        case .dune: return "瓦片盖 25% 暖沙（晒过色温）"
        case .snowfield: return "瓦片压到 70% 冷蓝黑（雪夜）"
        case .blueprint: return "瓦片盖 45% 深蓝（蓝图蒙版）"
        case .amber: return "瓦片盖 35% 暖橙（树脂色层）"
        case .brushed: return "瓦片盖 30% 中性灰（磨砂钢）"
        case .cellar: return "瓦片压到 75% 暗 + 深绛紫罩（瓶底光）"
        case .cinnabar: return "瓦片盖 20% 暖白（宣纸色温）"
        case .tundra: return "瓦片盖 40% 青灰绿（冻土雾）"
        case .inkwash: return "瓦片盖 30% 近白（留白）"
        case .forge: return "瓦片压到 85% 暗（铸铁车间）"
        case .mist: return "瓦片盖 45% 灰蓝（晨雾）"
        case .neon: return "瓦片压到 80% 暗 + 深紫黑罩（雨夜）"
        }
    }

    var spec: ArtThemeSpec {
        switch self {
        // ---------------------------------------------------------------------
        case .nocturne:
            return ArtThemeSpec(
                canvas: artHex(0x08070A),
                surface: artHex(0x141110),
                raised: artHex(0x1B1715),
                hairline: artHex(0xFFE8C8, alpha: 0.10),
                track: artHex(0xFFE8C8, alpha: 0.14),
                label: artHex(0xF6EFE4),
                labelSecondary: artHex(0xF6EFE4, alpha: 0.60),
                // 0.50：0.34 时实测对比度只有 2.76:1（canvas）—— 第三档文字也是正文，
                // 必须过 WCAG AA 的 4.5:1。0.50 实测 4.79 / 4.80 ✓
                labelTertiary: artHex(0xF6EFE4, alpha: 0.50),
                accent: artHex(0xFFB26E),
                success: artHex(0x7FE0A0),
                warning: artHex(0xF0B24A),
                error: artHex(0xFF6A55),
                info: artHex(0xFFB26E),
                onAccent: artHex(0x1A1614),
                lightBar: [artHex(0xFFF6E8), artHex(0xE7B27A), artHex(0xFFD9A8)],
                lightSource: artHex(0xFFF6E8),
                fillSubtle: artHex(0xF6EFE4, alpha: 0.06),
                glassHighlight: artHex(0xFFE8C8, alpha: 0.15),
                scrim: artHex(0x08070A),
                decor: .lightPool,
                allowsGlow: true,
                usesSerifTitles: false,
                displayWeight: .ultraLight,
                displayTracking: -0.3,
                preferredScheme: .dark,
                // 夜光：六页沿用原型里那六道冷光（它们本来就是为暗底调的）
                pageAccents: [artHex(0xB9A6FF), artHex(0x78C8FF), artHex(0x6FA8FF),
                              artHex(0x5FD08A), artHex(0xA7C8EA), artHex(0xD9D2FF)]
            )
        // ---------------------------------------------------------------------
        case .paper:
            return ArtThemeSpec(
                canvas: artHex(0xF4EEE1),
                surface: artHex(0xFBF7EE),
                raised: artHex(0xF1EBDE),
                hairline: artHex(0x1E1B16, alpha: 0.16),
                track: artHex(0x1E1B16, alpha: 0.14),
                label: artHex(0x1E1B16),
                // 原 #7C7466 在纸面上只有 3.99 / 4.32:1，不达标。
                // 这里要**同时**满足两件事：过得去 AND 第三档比它再淡一档。
                // #5C5648 → 6.31 / 6.82（中间档）
                labelSecondary: artHex(0x5C5648),
                // alpha 0.63 → 4.72 / 4.86 ✓（0.42 时只有 2.57）
                labelTertiary: artHex(0x1E1B16, alpha: 0.63),
                accent: artHex(0xB33325),
                success: artHex(0x2E7D4F),
                warning: artHex(0x9A6B15),
                error: artHex(0xB33325),
                info: artHex(0x2E7D4F),
                onAccent: artHex(0xFBF7EE),
                lightBar: [artHex(0x8E2A1E), artHex(0xC0392B), artHex(0xB33325)],
                lightSource: artHex(0x8E2A1E),
                fillSubtle: artHex(0x1E1B16, alpha: 0.05),
                glassHighlight: artHex(0x1E1B16, alpha: 0.08),
                scrim: artHex(0x1E1B16),
                decor: .paperGrain,
                allowsGlow: false,
                usesSerifTitles: true,
                displayWeight: .light,
                displayTracking: -0.2,
                preferredScheme: .light,
                // 纸上：不能有鲜艳的色块（纸没有发光），六页是六种**墨**
                pageAccents: [artHex(0x6A5F92), artHex(0x3F6E9E), artHex(0x2F5B8A),
                              artHex(0x3F7A5A), artHex(0x4A6B87), artHex(0x5F5A80)]
            )
        // ---------------------------------------------------------------------
        case .typographic:
            return ArtThemeSpec(
                canvas: artHex(0x08080A),
                surface: artHex(0x0D0D10),
                raised: artHex(0x141418),
                hairline: artHex(0xEDEAE4, alpha: 0.10),
                track: artHex(0xEDEAE4, alpha: 0.12),
                label: artHex(0xEDEAE4),
                labelSecondary: artHex(0xA8A2AE),
                // 原 #6E6874 只有 3.71 / 3.60:1。调亮到 #807A87 → 4.81 / 4.67 ✓
                labelTertiary: artHex(0x807A87),
                accent: artHex(0xF7F5F1),
                success: artHex(0x52B47A),
                warning: artHex(0xE8A33A),
                error: artHex(0xE8564A),
                info: artHex(0xEDEAE4),
                onAccent: artHex(0x08080A),
                lightBar: [artHex(0xF7F5F1), artHex(0xA8A2AE), artHex(0xEDEAE4)],
                lightSource: artHex(0xF7F5F1),
                fillSubtle: artHex(0xEDEAE4, alpha: 0.06),
                glassHighlight: artHex(0xEDEAE4, alpha: 0.10),
                scrim: artHex(0x08080A),
                decor: .hairlineGrid,
                allowsGlow: false,
                usesSerifTitles: false,
                displayWeight: .ultraLight,
                displayTracking: -1.6,
                preferredScheme: .dark,
                // 巨字：尺度就是艺术，色彩退到近白的一点点冷暖差别
                pageAccents: [artHex(0xE4DEEA), artHex(0xD4DCE8), artHex(0xCFD6E2),
                              artHex(0xC9E0D2), artHex(0xD2D8E0), artHex(0xE6E2EA)]
            )
        // ---------------------------------------------------------------------
        case .native:
            return ArtTheme.nativeSpec
        // -----------------------------------------------------------------
        // 2026-09-24 第八轮新增 16 套：全部走 `ArtThemeSpec` 的便捷构造
        //（只给核心色 + 装饰，其余字段按同一套规则推导 —— 见构造器头注）。
        case .frost:
            return ArtThemeSpec(canvas: artHex(0xE8F1F2), surface: artHex(0xF4F8F8),
                                label: artHex(0x3A4A4C), accent: artHex(0x3E8C95),
                                allowsGlow: true, displayWeight: .light,
                                preferredScheme: .light)
        case .celadon:
            return ArtThemeSpec(canvas: artHex(0xE6E8E2), surface: artHex(0xF2F1EC),
                                label: artHex(0x3C4A42), accent: artHex(0x4F7A68),
                                decor: .paperGrain, allowsGlow: false, usesSerifTitles: true,
                                displayWeight: .light, preferredScheme: .light)
        case .darkroom:
            return ArtThemeSpec(canvas: artHex(0x140806), surface: artHex(0x1E0E0A),
                                label: artHex(0xF0C8A8), accent: artHex(0xE85A3A),
                                decor: .lightPool, allowsGlow: true, preferredScheme: .dark)
        case .phosphor:
            return ArtThemeSpec(canvas: artHex(0x071008), surface: artHex(0x0D1A10),
                                label: artHex(0x8CE8A8), accent: artHex(0x5AE87A),
                                displayWeight: .light, preferredScheme: .dark)
        case .dune:
            return ArtThemeSpec(canvas: artHex(0xEDE3CE), surface: artHex(0xF6EEDC),
                                label: artHex(0x5A4A30), accent: artHex(0xB5651D),
                                usesSerifTitles: true, displayWeight: .light,
                                preferredScheme: .light)
        case .snowfield:
            return ArtThemeSpec(canvas: artHex(0x0B1220), surface: artHex(0x111B2E),
                                label: artHex(0xE8EEF6), accent: artHex(0x9FC8FF),
                                decor: .lightPool, allowsGlow: true, preferredScheme: .dark)
        case .blueprint:
            return ArtThemeSpec(canvas: artHex(0x10284A), surface: artHex(0x16325C),
                                label: artHex(0xDCE8F8), accent: artHex(0x7FB4E8),
                                decor: .hairlineGrid, allowsGlow: false, preferredScheme: .dark)
        case .amber:
            return ArtThemeSpec(canvas: artHex(0x1A1206), surface: artHex(0x241808),
                                label: artHex(0xF6E4C0), accent: artHex(0xE8A83A),
                                decor: .lightPool, allowsGlow: true, preferredScheme: .dark)
        case .brushed:
            return ArtThemeSpec(canvas: artHex(0xE4E4E6), surface: artHex(0xF2F2F4),
                                label: artHex(0x3A3A3E), accent: artHex(0x6A6A72),
                                displayWeight: .semibold, preferredScheme: .light)
        case .cellar:
            return ArtThemeSpec(canvas: artHex(0x180E18), surface: artHex(0x221424),
                                label: artHex(0xE8D8E8), accent: artHex(0x9A4E9A),
                                decor: .lightPool, allowsGlow: true, preferredScheme: .dark)
        case .cinnabar:
            return ArtThemeSpec(canvas: artHex(0xF6F1E6), surface: artHex(0xFBF7EE),
                                label: artHex(0x2A241C), accent: artHex(0xC0392B),
                                usesSerifTitles: true, displayWeight: .light,
                                preferredScheme: .light)
        case .tundra:
            return ArtThemeSpec(canvas: artHex(0xDDE4E2), surface: artHex(0xEAF0EE),
                                label: artHex(0x44524E), accent: artHex(0x5E7A70),
                                allowsGlow: false, preferredScheme: .light)
        case .inkwash:
            return ArtThemeSpec(canvas: artHex(0xF4F4F0), surface: artHex(0xFAFAF6),
                                label: artHex(0x242420), accent: artHex(0x30302C),
                                usesSerifTitles: true, displayWeight: .light,
                                preferredScheme: .light)
        case .forge:
            return ArtThemeSpec(canvas: artHex(0x0C0A0A), surface: artHex(0x161212),
                                label: artHex(0xE8DED4), accent: artHex(0xE86A2A),
                                decor: .lightPool, allowsGlow: true, preferredScheme: .dark)
        case .mist:
            return ArtThemeSpec(canvas: artHex(0xE8EDEF), surface: artHex(0xF2F5F6),
                                label: artHex(0x4A5A62), accent: artHex(0x6A8A94),
                                allowsGlow: false, preferredScheme: .light)
        case .neon:
            return ArtThemeSpec(canvas: artHex(0x0E0A1A), surface: artHex(0x161026),
                                label: artHex(0xE0D8F0), accent: artHex(0xE84AC8),
                                decor: .lightPool, allowsGlow: true, preferredScheme: .dark,
                                pageAccents: [artHex(0xE84AC8), artHex(0x4AE8C8), artHex(0x4A8AE8),
                                              artHex(0x5AE87A), artHex(0xB44AE8), artHex(0xE84A5A)])
        }
    }

    /// 原生 = 切换前的 v4 取值（系统语义色）。**这里一个值都不许改**，
    /// 否则"原生"就不再等于现状，我们也失去一个可信的对照。
    ///
    /// ⚠️ 这些值原先引用 `WT.Palette`（Shared/WidgetTokens.swift —— 小组件与实时活动那份
    /// 世界面令牌）。那个文件随小组件体系整份删除，于是这里的引用**逐个内联**，
    /// 字面量一个都没动（对照 git 历史里 `WidgetTokens.Palette` 的字面量）。
    ///
    /// ⚠️ **不能**改写成 `TokensPalette.canvas` 这类写法：`TokensPalette` 读的是
    /// `ArtThemeStore.spec`，而 `.native` 的 spec 就是本函数 —— 那会变成无限递归。
    private static var nativeSpec: ArtThemeSpec {
        ArtThemeSpec(
            canvas: Color(uiColor: UIColor.systemGroupedBackground),
            surface: Color(uiColor: UIColor.secondarySystemGroupedBackground),
            raised: Color(uiColor: .tertiarySystemGroupedBackground),
            hairline: Color(uiColor: UIColor.separator),
            track: Color(uiColor: .quaternaryLabel),
            label: Color(uiColor: .label),
            labelSecondary: Color(uiColor: .secondaryLabel),
            labelTertiary: Color(uiColor: .tertiaryLabel),
            accent: nativeDynamic(light: (0.000, 0.478, 1.000), dark: (0.039, 0.518, 1.000)),
            success: nativeDynamic(light: (0.204, 0.780, 0.349), dark: (0.188, 0.820, 0.345)),
            warning: nativeDynamic(light: (1.000, 0.584, 0.000), dark: (1.000, 0.624, 0.039)),
            error: nativeDynamic(light: (1.000, 0.231, 0.188), dark: (1.000, 0.271, 0.227)),
            info: nativeDynamic(light: (0.000, 0.780, 0.745), dark: (0.400, 0.839, 1.000)),
            onAccent: Color.white,
            lightBar: [Color.white, Color(red: 0.612, green: 0.776, blue: 1.000),
                       nativeDynamic(light: (0.000, 0.478, 1.000), dark: (0.039, 0.518, 1.000))],
            // 下面三个刻意保留原来的写死值 —— 「原生」必须逐值等于切换前的 v4。
            lightSource: Color.white,
            fillSubtle: Color(uiColor: .quaternarySystemFill),
            glassHighlight: Color.white.opacity(0.15),
            // 原生 = 切换前逐像素相同：遮罩就是纯黑 + 调用点给的不透明度。
            scrim: Color.black,
            decor: .none,
            allowsGlow: true,
            usesSerifTitles: false,
            displayWeight: .ultraLight,
            displayTracking: 0,
            preferredScheme: nil,
            // 原生：六个系统色（与系统语义色同一套取值）
            pageAccents: [artHex(0xAF52DE), artHex(0x5AC8FA), artHex(0x007AFF),
                          artHex(0x34C759), artHex(0x30B0C7), artHex(0x5856D6)]
        )
    }

    /// 明暗两套取值。
    /// 原先由 `WT.Palette.dynamic(light:dark:)` 提供；随 WidgetTokens 删除后内联在这里，
    /// 语义与取值完全一致（系统深色时取 dark，否则取 light）。
    private static func nativeDynamic(
        light: (CGFloat, CGFloat, CGFloat),
        dark: (CGFloat, CGFloat, CGFloat)
    ) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
            ? UIColor(red: dark.0, green: dark.1, blue: dark.2, alpha: 1)
            : UIColor(red: light.0, green: light.1, blue: light.2, alpha: 1)
        })
    }
}

// MARK: - 当前主题（唯一写入点）
enum ArtThemeStore {
    /// UserDefaults 键。视图侧用 `@AppStorage(ArtThemeStore.key)` 读取以获得重绘。
    static let key = "carkeeper_art_theme"

    /// 主题变化通知（需要在 App 之外也响应的对象可以订它）
    static let changed = Notification.Name("carkeeper_art_theme_changed")

    /// 当前主题。**计算属性，没有可变静态存储** —— 不引入并发风险。
    static var current: ArtTheme {
        ArtTheme(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .native
    }

    /// 当前取值。令牌层（TokensPalette）每次读值都从这里取。
    static var spec: ArtThemeSpec { current.spec }

    /// 切换主题。写 UserDefaults 并发通知；界面重绘由 root 上的 `.id` 负责。
    static func set(_ theme: ArtTheme) {
        guard theme != current else { return }
        UserDefaults.standard.set(theme.rawValue, forKey: key)
        NotificationCenter.default.post(name: changed, object: nil)
    }
}

// MARK: - 颜色构造
/// 顶层工具：0xRRGGBB + alpha → Color。
/// 用 `Color(.sRGB, ...)` 而不是 UIColor，是为了让取值在任何外观下都精确。
/// （2026-09-24 第八轮起不再 `private`：ArtThemeSpec 的便捷构造要用它。）
func artHex(_ hex: UInt32, alpha: Double = 1) -> Color {
    Color(
        .sRGB,
        red: Double((hex >> 16) & 0xFF) / 255,
        green: Double((hex >> 8) & 0xFF) / 255,
        blue: Double(hex & 0xFF) / 255,
        opacity: alpha
    )
}
