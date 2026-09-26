import SwiftUI

// =============================================================================
//  DisplaySettings —— 「显示」这一组设置的唯一出处
// =============================================================================
//
//  用户 2026-09-26：
//    · 「设置文字的发光阴影程度」
//    · 「全局调整液态玻璃的通透度？（可行的话）」
//
//  两件事改的都是**全 App 的观感**，不是某一页的观感 —— 所以它们不是某一页的
//  `@State`，而是三个本机键 + 这一个 `ObservableObject`：
//
//    | 设置 | 谁读它 | 读到之后变成什么 |
//    |---|---|---|
//    | `glow` | `TokensHalo`（`Design/Tokens.swift`） | 文字外壳的半径与浓度（`DSTextGlow` 用） |
//    | `level` | `dsGlass`（`Design/DSGlass.swift`） | 用哪一档材质（更透 / 按底下是什么 / 更实） |
//    | `fill` | `TokensPalette.panel` / `fillSubtle` / `dsGlass` 的 tint | App 自己那几层半透明的底有多实 |
//
//  ── 为什么必须是一个 `ObservableObject`，而不是各处直接读 `UserDefaults` ──
//  `TokensPalette.panel` 是一个**计算属性**：它读 UserDefaults 也能读到新值 ——
//  但**没有任何东西会因此重画**（SwiftUI 不知道那三个键变了）。App 的根订阅这一个
//  单例（`CarKeeperApp.root` 的 `@ObservedObject`），任何一格改动都会让整棵树
//  重新求值。与 `wallpaper` / `phone` 那两处订阅同一个理由、同一种写法。
//
//  ⚠️ 三个键都写在这个文件里（**键名只有一个出处**，与 `HomeMode.storageKey`、
//  `MapSpineView.drawerKey` 同一条纪律）—— 设置界面只调这里的属性，不碰键名。
//
//  ⚠️ 它**不是** `@MainActor`：`TokensPalette.panel` 这类静态计算属性从非主线程的
//  求值里也会读到它（SwiftUI 的绘制路径），给类加主 actor 会让那一处变成跨 actor
//  访问。`@Published` 的写入本来就都发生在主线程（只有设置在写）。
// =============================================================================

final class DisplaySettings: ObservableObject {

    static let shared = DisplaySettings()

    // MARK: 玻璃的档

    /// 三档材质（用户 2026-09-26：「全局调整液态玻璃的通透度」）。
    ///
    /// 系统**没有**给「材质的透明度」一个旋钮 —— 能选的是**用哪一档材质**：
    /// `Glass.clear` 只折射、不磨砂（画面完整透过来），`.regular` 会磨砂，
    /// 而在 `.regular` 上加一层 `tint` 就是同一档材质**更实**的形态。
    /// 所以这个开关映射到那三件事，而不是去硬调一个不存在的数（见 `dsGlass`）。
    ///
    /// ⚠️ 「更透」那一档是**盖过**「按底下是什么选」这条规矩的（那条规矩见
    /// `DSGlassVariant`）：用户在设置里点名要更透，就不该有一个角落按自己的判断
    /// 用回磨砂 —— 一个开关按不同的地方给不同的结果，就不是一个全局开关。
    enum GlassLevel: String, CaseIterable, Identifiable {
        /// 更透：一律 `.clear`
        case clear
        /// 标准：按**底下是什么**选（2026-09-25 那一轮的规矩，也是默认值）
        case standard
        /// 更实：`.regular` + 一层 tint（压在花哨底图上也能看清字）
        case solid

        var id: String { rawValue }

        var title: String {
            switch self {
            case .clear: return "更透"
            case .standard: return "标准"
            case .solid: return "更实"
            }
        }
    }

    // MARK: 键（只有这一处）

    private static let glowKey = "carkeeper_display_glow"
    private static let levelKey = "carkeeper_glass_level"
    private static let fillKey = "carkeeper_glass_fill"

    // MARK: 值

    /// 文字外壳的**程度**（0…1）。0 = 不发光，1 = 最重。
    ///
    /// 默认 **0.5** 不是随手取的：它**正好等于** 2026-09-25 那一版定下的样子
    ///（外壳半径 3 / 4，浓度 0.45 / 0.65）。也就是说装上这一版，界面一处都不变 ——
    /// 用户往两边调的时候，起点是「他昨天看到的那张脸」（见 `TokensHalo`）。
    @Published var glow: Double {
        didSet { UserDefaults.standard.set(glow, forKey: Self.glowKey) }
    }

    /// 玻璃用哪一档材质。
    @Published var level: GlassLevel {
        didSet { UserDefaults.standard.set(level.rawValue, forKey: Self.levelKey) }
    }

    /// App 自己那几层半透明的底有多实（0…1）。默认 **1** = 今天的值。
    ///
    /// 它动的只有**我们画的**那些面（卡里的分组面、控件底、模式条的底，
    /// 以及「更实」那一档的 tint）。系统材质的磨砂强度不归它管 —— 那一件由
    /// `level` 决定（见上）。两件事分开，是为了让「更透的材质 + 更实的底」
    /// 这种组合也能调出来（它们是两个独立的问题：材质透不透、我们的面色厚不厚）。
    @Published var fill: Double {
        didSet { UserDefaults.standard.set(fill, forKey: Self.fillKey) }
    }

    private init() {
        let d = UserDefaults.standard
        // 初值都从本机取；没存过就是上面那三个默认值（`object(forKey:)` 而不是
        // `double(forKey:)`：后者在键不存在时返回 0 —— 那会让「没设过」看起来像
        // 「设成了最透/最不发光」）。
        glow = d.object(forKey: Self.glowKey) as? Double ?? 0.5
        //  不用 `Optional.flatMap(GlassLevel.init(rawValue:))`：`scan/scan.py` 的方法基线里
        //  没有 `flatMap`（全仓此前没有人用过它），而那道门对「基线里没有的名字」是报红
        //  而不是放行。写成两行同样清楚，且少一个要登记的 SDK 名字。
        let rawLevel = d.string(forKey: Self.levelKey) ?? ""
        level = GlassLevel(rawValue: rawLevel) ?? .standard
        fill = d.object(forKey: Self.fillKey) as? Double ?? 1
    }
}
