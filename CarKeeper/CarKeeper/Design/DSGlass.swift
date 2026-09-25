import SwiftUI

// =============================================================================
//  DSGlass —— 「浮在内容之上」那一层的唯一材质
// =============================================================================
//
//  用户 2026-09-25：「全局液态玻璃的质感全项目每个犄角旮旯方方面面都做到位了吗」。
//  查下来的答案是**没有**，而且问题不在细节，在名字：
//
//    · 真正的液态玻璃（`.glassEffect`）当年只出现在 **3 处** —— 卡片（`GlassCard`）、
//      底部模式条（`DSSwipeStrip`）、地图那颗圆形机械按钮（`MapSpineView`）。
//    · 其余每一处「浮在内容之上」的表面 —— 轻提示（Toast）、次操作按钮、地图上的
//      图层胶囊、分段控件、芯片、搜索框 —— 用的都是 `TokensPalette.glassLight`，
//      而那个令牌**就是 `fillSubtle`**（同一个值、两个名字）。那一轮已把它删掉：
//      现在全仓没有一个叫 glass 的扁平令牌，读到 glass 就一定是真材质。
//    · 还有两处把玻璃**垫在不透明的面底下**（`Capsule().fill(fillSubtle)` 再接
//      `.glassEffect(...)`；`Circle().fill(glassHighlight)` 再接玻璃）—— 材质本身
//      被那块面挡掉了，看起来是「磨砂色块 + 一圈高光」。
//
//  这不是审美问题，是「物理材质的四个性质」一件都没发生：
//    ① 折射（把底下的内容推一点）② 反射（边缘的高光与内部暗部）
//    ③ 厚度（形状自带的边缘）④ 与底下内容联动的模糊
//  自己用「半透明色 + 一圈发丝线」拼出来的是这四件事的**假象**。
//
//  ── 三层规则（照抄 Apple「Applying Liquid Glass to custom views」的判据） ──
//
//   ① **浮在内容之上**（导航/工具/悬浮按钮/轻提示/地图上的控件）→ 真玻璃：`dsGlass`
//   ② **卡片里**（芯片、键值行、分段控件、说明块）→ **不**玻璃。玻璃叠玻璃会糊成一片，
//      而且卡片自己已经是玻璃了 —— 里面再摆材质等于同一层放两次。
//   ③ **真正的内容表面**（画布、地图本身、图表）→ 不玻璃（玻璃是控件语言，不是内容语言）
//
//  `dsGlass` 是这三层里第 ① 层的**唯一入口**。`scan/glass.py` 在 CI 上拦四件事：
//  别处直连 `.glassEffect`、别处直连 `GlassEffectContainer`、玻璃底下垫不透明的面、
//  再引入旧材质语言（`…Material`）—— 否则「哪儿是玻璃」又会开始各写各的。
//
//  ⚠️ 为什么材质只能有一个来源：`Glass` 的两个变体（`.regular` / `.clear`）是系统按
//  **底下内容**选的，不是按审美选的。而 `.interactive` 会把「这个控件会动」这件事交给
//  系统去演（按下去的压缩与折射变化）—— 自己用 `.scaleEffect` + `opacity` 模拟的
//  那一套，永远差在「玻璃不被压」。
//
//  ⚠️ 这里不留 `ViewModifier` 包装类型（2026-09-25 同日删）：`DSGlassSurface` /
//  `DSGlassLayer` 只是搬运参数，删掉之后本文件只剩 `DSGlassVariant` 一个类型，
//  而它是 `dsGlass` 的**参数类型**（调用点写 `.overMedia`，是隐式成员表达式）——
//  「声明了却没有别人按名字提到」在 `scan/orphans.py` 眼里是孤儿，已在那边登记理由。
// =============================================================================

/// 玻璃的两种取用，按**底下是什么**选，不按好看选。
enum DSGlassVariant {
    /// 底下是 App 自己的界面（卡片、列表、画布）—— 常规玻璃。
    case regular
    /// 底下是**连续的画面**（地图、照片）：`.clear` 让画面保持可见，
    /// 只在边缘留一圈折射。文字多的控件别用它（对比度会跟着底下的画面走）。
    case overMedia
}

extension View {
    /// 浮在内容之上的表面 —— 全 App 唯一的真玻璃入口（见本文件头注的三层规则）。
    ///
    /// - Parameters:
    ///   - shape: 玻璃的形状（`Capsule()` / `Circle()` / 圆角矩形）。形状是**物理**的一部分：
    ///     玻璃有厚度，形状决定光在哪儿拐弯。
    ///   - variant: 按底下是什么选，见 `DSGlassVariant`。
    ///   - interactive: 这个表面可点就传 `true` —— 按下去的压缩与折射交给系统演，
    ///     别自己写 `.scaleEffect`（那只会让玻璃「硬」下去）。
    ///   - hairline: 要不要那圈发丝线。玻璃自己已经有边缘，多层叠在一起时少一圈更好。
    func dsGlass<S: Shape>(in shape: S,
                           variant: DSGlassVariant = .regular,
                           interactive: Bool = false,
                           hairline: Bool = true) -> some View {
        let base: Glass = variant == .overMedia ? .clear : .regular
        // 写成 `interactive(true)` 而不是 `interactive()`：文档里那个默认值
        // （`_ isEnabled: Bool = true`）在 fragments 里看不到，写死实参就与它无关了。
        let material: Glass = interactive ? base.interactive(true) : base
        return glassEffect(material, in: shape)
            .overlay {
                if hairline {
                    shape.strokeBorder(TokensPalette.hairline, lineWidth: TokensHair.border)
                }
            }
    }

    /// 常用形状的便捷写法（胶囊：按钮 / 芯片 / 条子）
    func dsGlassCapsule(variant: DSGlassVariant = .regular,
                        interactive: Bool = false,
                        hairline: Bool = true) -> some View {
        dsGlass(in: Capsule(), variant: variant, interactive: interactive, hairline: hairline)
    }

    /// 常用形状的便捷写法（圆角矩形：轻提示 / 面板）
    func dsGlassRounded(_ radius: CGFloat = TokensRadius.large,
                        variant: DSGlassVariant = .regular,
                        interactive: Bool = false,
                        hairline: Bool = true) -> some View {
        dsGlass(in: RoundedRectangle(cornerRadius: radius, style: .continuous),
                variant: variant, interactive: interactive, hairline: hairline)
    }

    // =========================================================================
    //  GlassEffectContainer —— 一片区域里有多块玻璃时要用的那个容器
    // =========================================================================
    //
    //  系统要知道「哪几块玻璃挨得近」，才能让它们互相折射、并在出现/消失时变形接上。
    //  没有它，多块玻璃各自按自己的边界算 —— 挨在一起时边缘会互相打架（看起来像两块
    //  贴纸，而不是同一层材质上的两个形状）。
    //  地图那一屏是这个问题最明显的地方：底条 + 那颗圆形按钮 + 图层胶囊同屏，
    //  由 `MapSpineView` 用 `dsGlassLayer` 包成**一层**。
    func dsGlassLayer(spacing: CGFloat = TokensSpacing.lg) -> some View {
        GlassEffectContainer(spacing: spacing) { self }
    }
}
