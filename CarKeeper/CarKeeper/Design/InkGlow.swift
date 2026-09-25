import SwiftUI

// =============================================================================
//  玻璃上那行字的「轻微反色发光外壳」—— 两条路
// =============================================================================
//
//  用户 2026-09-25 第 8 条（原话）：
//    「是不是想让通透玻璃的文字看得清，给文字加上一个轻微反色玻璃的发光外壳就解决了？
//      可以试试」
//
//  他指出的正是 `.clear` 玻璃的固有代价：那一版玻璃**不磨砂**（HIG：clear 只给压在
//  连续画面上的控件用），于是字底下直接是瓦片或照片 —— 底色深浅一变，同一行字就有
//  时候看不清。系统给材质文字的 vibrancy（`TokensInk`）解决的是「跟着材质调亮暗」，
//  它解决不了「底下那张照片的那一块正好和字的亮度一样」。而**反色的外发光**解决的
//  恰好是这一种：字是亮的，就在它周围压一圈暗的；字是暗的，就围一圈亮的。
//  两种底色都不吃亏，而外壳只有 3pt，不改变字本身的颜色与粗细。
//
//  ── 为什么是「反色」而不是「同色」 ──
//  同色外发光（给白字加白色 shadow）在深底上等于没加，因为一圈白光里那行字反而不清楚；
//  真正起作用的永远是**与字相反的那一侧**。所以那个颜色是**动态色令牌**
//  （`TokensHalo.ink`：暗色主题压黑、亮色主题提白）—— 深浅色由系统告诉我们，
//  不是我们挑的审美；而调用点因此连一个三元都不用写。
//
//  ── 两条路：全局（`DSTextGlow`）与逐处（`dsInkGlow()`）────────────────────
//  第一版只有逐处的 `dsInkGlow()`（用户第 8 条），点名了四处：模式条的字、地图读数、
//  地图圆钮、图层胶囊。它的问题是**它是一张名单**：`.clear` 玻璃的代价是普遍的，
//  名单外的任何一行字（卡片正文、列表、按钮）照样会糊 —— 而那是我漏它、不是它不糊。
//
//  用户 2026-09-25 的第 2 条把它变成了全局的：「全局全部字体都加层发光阴影 看看能不能
//  在液态玻璃中看清」。做法是 `TextRenderer`：`View.textRenderer(_:)` 的原文是
//    「Returns a new view such that any text views **within it** will use renderer
//     to draw themselves」——「within it」就是关键：挂在 App 根上，全 App 的
//  `Text` 都从这条路画，名单从此不存在（见 `CarKeeperApp.swift` 的 `root`）。
//
//  ⚠️ 于是分工是清楚的，**不要互相代替**：
//    · `Text`（文字）→ `DSTextGlow`（全局，绘字那一步做的）
//    · `Image`（图形、SF Symbol）→ `dsInkGlow()`（它画的不是字，渲染器管不着）
//  两件都在这个文件里，因为它们是同一个决定（外壳的颜色、半径）在两个绘制管线上的形态。
//
//  ⚠️ 代价如实写在这里（用户 2026-09-25 刚要求过「全局优化性能流畅性」）：
//  每一条文字的 run 都要多一遍离屏模糊。它买的是「瓦片 / 照片上的字看得清」，
//  而它在**卡片正文上什么也看不见**（那里的底是 `panel`，一圈同深度的壳被它吸收了）。
//  关掉它的方法只有一行：把 `CarKeeperApp.swift` 里那个 `.dsTextGlow()` 删掉
//  （删掉之后逐处的 `dsInkGlow()` 仍在，图形不会失去外壳）。
// =============================================================================

/// 全局文字外壳：把「轻微反色外发光」铺到每一个 `Text` 上。
///
/// 它是 `TextRenderer`（协议 iOS 17+；挂它的那个修饰符 `View.textRenderer(_:)` 是 iOS 18+，
/// 而本 App 的 target 是 iOS 26）——SwiftUI 在**绘字**这一步把 layout 交给我们，
/// 我们照着画第二遍光。文档里那个协议的原文是
/// *「A value that can replace the default text view rendering behavior.」*
///
/// 半径按**这一行字自己的高度**选（`run.typographicBounds`）：13pt 的正文与 96pt 的
/// 巨字不能用同一圈壳 —— 后者一圈 3pt 的光在 40pt 高的笔画旁等于没加。这一条是
/// 逐处版本那个 `strong:` 参数的全局版（它就是为「大数 / 标题」开的第二档）。
struct DSTextGlow: TextRenderer {
    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        // `layout` → 行 → run（run = 同一段样式的连续字）。两层嵌套是协议自己的形状
        // （`Text.Layout` / `.Line` / `.Run` 都是 `RandomAccessCollection`）。
        for line in layout {
            for run in line {
                // 第一遍**只画影子**（`options: .shadowOnly`）：文档原话是
                // 「draw only the shadow, and omit the source object」。
                // 少了这个选项就得把字画两遍，而半透明的字画两遍会变浓 —— 那不是外壳，
                // 那是把字换了颜色（这一仓的正文大量用 `.opacity`，所以这里必须干净）。
                var glow = context
                glow.addFilter(.shadow(color: TokensHalo.ink,
                                       radius: haloRadius(for: run),
                                       options: .shadowOnly))
                glow.draw(run)
                // 第二遍才是字本身：原样、原色、原不透明度。
                context.draw(run)
            }
        }
    }

    /// 外壳比字宽出去一圈，不告诉 SwiftUI 就会被裁掉。文档给这个属性写的用途正是这一句：
    /// *「when drawing the text with a shadow this may be used to extend the drawing bounds
    /// to avoid clipping the shadow」*。四面各留一格（= 半径）。
    var displayPadding: EdgeInsets {
        EdgeInsets(top: TokensHalo.radius,
                   leading: TokensHalo.radius,
                   bottom: TokensHalo.radius,
                   trailing: TokensHalo.radius)
    }

    /// 笔画高了，壳要跟着撑开一点 —— 否则大数旁那一圈光看起来像没加（见类型注释）。
    private func haloRadius(for run: Text.Layout.Run) -> CGFloat {
        run.typographicBounds.rect.height >= 22 ? TokensHalo.radiusWide : TokensHalo.radius
    }
}

extension View {
    /// 给压在连续画面上的玻璃文字加一圈轻微反色外发光。
    ///
    /// - Parameter strong: 字号在 20pt 以上（标题、大数字）时传 `true` ——
    ///   笔画粗了，壳要跟着撑开一点，否则看着像没加。
    ///
    /// ⚠️ 文字现在走全局的 `DSTextGlow`（挂在 App 根上），所以这个方法只剩**图形**在用
    ///（`Image`：SF Symbol 不是字，渲染器碰不到）。文字上**不要**再挂它：两层壳叠在
    /// 一起会变浓，而第二次那一层什么也没多买。
    func dsInkGlow(strong: Bool = false) -> some View {
        shadow(color: TokensHalo.ink, radius: strong ? TokensHalo.radiusWide : TokensHalo.radius)
    }

    /// 全局文字外壳的开关。**只该挂在 App 的根上**（`CarKeeperApp.root`）——
    /// 它是一条包住整棵树的线，挂两次不会更清楚，只会把每一行字画两遍。
    func dsTextGlow() -> some View {
        textRenderer(DSTextGlow())
    }
}
