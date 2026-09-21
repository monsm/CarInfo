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
// 与小组件的关系：
//   WT.Palette 仍然是小组件 / 实时活动的唯一真源。艺术主题**只作用在 App 内**，
//   刻意不覆盖 WT —— 否则小组件会跟着 App 的临时主题一起漂移。
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
// 未做（如实说明，别以为已经做了）：
//   ① App 里仍有约 130 处直接写死的 `Color(uiColor:)` / `.white` / `.black`，
//      它们**不跟随主题**。要全部跟随，需要逐处迁移到令牌，属于下一轮的事。
//   ② 切换靠 root 上的 `.id` 重建整棵树 —— 副作用是那一瞬间**子树里的 @State 会重置**
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

    var id: String { rawValue }

    var title: String {
        switch self {
        case .nocturne: return "夜光"
        case .paper: return "纸上"
        case .typographic: return "巨字"
        case .native: return "原生"
        }
    }

    /// 一句话说明这套方向的**美从哪来**（不是形容词，是机制）
    var mechanism: String {
        switch self {
        case .nocturne: return "美来自光：黑底承担全部信息量，光只出现在车上与城市的光池里"
        case .paper: return "美来自印刷：纸面、墨线、红笔。红只给品牌与危险"
        case .typographic: return "美来自尺度：极细巨字对极小标注，网格即版面"
        case .native: return "美来自系统：语义色、分组表面、发丝线 —— iOS 原生语言"
        }
    }

    /// 这套方向在真 MapKit 上的处境（与 MAPKIT-FEASIBILITY.md 逐条对应）
    var mapKitVerdict: String {
        switch self {
        case .nocturne: return "最能落地：MapKit 压暗（emphasis .muted + 关 POI）+ 我们叠光层"
        case .paper: return "最贵：MapKit 没有任何 API 能画出纸与墨，要么自建地图样式，要么整层重画"
        case .typographic: return "最省：地图退成极淡网格，几乎不依赖地图 —— 但也最不像地图"
        case .native: return "现状：系统地图原样 + 我们自己的标注与折线"
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
                decor: .lightPool,
                allowsGlow: true,
                usesSerifTitles: false,
                displayWeight: .ultraLight,
                displayTracking: -0.3,
                preferredScheme: .dark
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
                decor: .paperGrain,
                allowsGlow: false,
                usesSerifTitles: true,
                displayWeight: .light,
                displayTracking: -0.2,
                preferredScheme: .light
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
                decor: .hairlineGrid,
                allowsGlow: false,
                usesSerifTitles: false,
                displayWeight: .ultraLight,
                displayTracking: -1.6,
                preferredScheme: .dark
            )
        // ---------------------------------------------------------------------
        case .native:
            return ArtTheme.nativeSpec
        }
    }

    /// 原生 = 切换前的 v4 取值（系统语义色）。**这里一个值都不许改**，
    /// 否则"原生"就不再等于现状，我们也失去一个可信的对照。
    private static var nativeSpec: ArtThemeSpec {
        ArtThemeSpec(
            canvas: WT.Palette.canvas,
            surface: WT.Palette.surface,
            raised: Color(uiColor: .tertiarySystemGroupedBackground),
            hairline: WT.Palette.hairline,
            track: WT.Palette.track,
            label: WT.Palette.label,
            labelSecondary: WT.Palette.labelSecondary,
            labelTertiary: WT.Palette.labelTertiary,
            accent: WT.Palette.tint,
            success: WT.Palette.ok,
            warning: WT.Palette.warn,
            error: WT.Palette.bad,
            info: WT.Palette.charge,
            onAccent: Color.white,
            lightBar: [Color.white, Color(red: 0.612, green: 0.776, blue: 1.000), WT.Palette.tint],
            decor: .none,
            allowsGlow: true,
            usesSerifTitles: false,
            displayWeight: .ultraLight,
            displayTracking: 0,
            preferredScheme: nil
        )
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
/// 顶层私有工具：0xRRGGBB + alpha → Color。
/// 用 `Color(.sRGB, ...)` 而不是 UIColor，是为了让取值在任何外观下都精确。
private func artHex(_ hex: UInt32, alpha: Double = 1) -> Color {
    Color(
        .sRGB,
        red: Double((hex >> 16) & 0xFF) / 255,
        green: Double((hex >> 8) & 0xFF) / 255,
        blue: Double(hex & 0xFF) / 255,
        opacity: alpha
    )
}
