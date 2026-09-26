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
//  ⚠️ 2026-09-26（用户：「全局调整液态玻璃的通透度」）：`dsGlass` 从此还读
//  `DisplaySettings` 的两格 —— 「用哪一档材质」与「更实那一档的 tint 多浓」。
//  它们**不**是第四个参数：参数说的是「这一块玻璃压在什么上」（几何与内容），
//  而那两格是**全 App 一致的观感**。把全局的偏好写成每个调用点都要传一遍的参数，
//  等于把「一致」寄托在 12 个调用点都记得传对（那正是这一仓反复吃过的那种账）。
//  于是入口仍然只有这一个，只是它现在多读两格设置。
//
//  ⚠️ `ViewModifier` 包装类型在 2026-09-25 删过一轮：那时的 `DSGlassSurface` 与
//  `DSGlassLayer` 只是搬运参数，而「搬运」不需要一个类型。
//  2026-09-26 `DSGlassSurface` 回来了，因为**这一版它有事要做**：读
//  `accessibilityReduceTransparency` 并换一块自己的实底（理由见下面那条类型）。
//  一条判据：包装类型只有在「它自己知道什么」时才成立 ——
//  `View` 扩展函数里读不到 `@Environment`，这就是那件事本身。
// =============================================================================

/// 玻璃的两种取用，按**底下是什么**选，不按好看选。
enum DSGlassVariant {
    /// 底下是 App 自己的界面（卡片、列表、画布）—— 常规玻璃。
    case regular
    /// 底下是**连续的画面**（地图、照片）：`.clear` 让画面保持可见，
    /// 只在边缘留一圈折射。文字多的控件别用它（对比度会跟着底下的画面走）。
    case overMedia
}

//  ===========================================================================
//  「降低透明度」这一档由我们自己接
//  ===========================================================================
//
//  用户 2026-09-26：「我把系统的液态玻璃变成了最不通透，我们的 app 变成了这样，
//  而相机的几乎没变 —— 你好好分析下相机的层结构」。
//
//  相机的底条为什么几乎不变：那条底子是**它自己画的深色面**（一层半透明黑），
//  底下没有系统材质 —— 一个「降低透明度」能降的只有材质，所以它没有可降的东西。
//  我们那一块则相反：`.glassEffect` 在那一档下的表现是**把模糊拿掉、只留一层淡色**
//  （截图量到的：卡里能看出底下的地图纹理，亮度只比周围高 ~20/255），
//  而我们的字是白的实色（`TokensPalette.primary` = `.label`）——
//  白字压在一块淡色上，读不出来；同一屏里每一块玻璃都变成「一块浅色大方块」，
//  远看像卡片变大了。
//
//  所以这一档不能交给系统：**用户要的是「少透一点」，系统的降法（去掉模糊、留淡色）
//  在这里恰好把文字的可读性也一起拿走了**。HIG 对同一件事的写法是
//  *「offer solid-fill alternatives at component level」* —— 组件自己给一块实底。
//  我们这块实底取 `TokensPalette.surface`（不透明的系统面色）：深色下它是 #1C1C1E、
//  亮色下是白，字与它一起随明暗走（`.label` 也是那套），于是两种明暗下都读得出来，
//  而这正是相机那条深色底子在同一档下保住的东西。
//
//  ⚠️ 为什么必须是一个 `View` 而不是 `dsGlass` 里的一句 `if`：函数里读不到
//  `@Environment`。玻璃得先是一个 `View`，才能知道用户开了没有。
//  （这一条与「玻璃是浮层的唯一入口」不冲突：它仍是同一条路的第一个落点，
//  调用点一个字都没变。）

/// 一块玻璃的本体。唯一的职责：在「降低透明度」开着时换一块**我们自己**的实底。
///
/// 参数与 `dsGlass` 一一对应，顺序也一致（本仓的成员初始化器按声明顺序传实参）。
struct DSGlassSurface<S: InsettableShape>: View {
    let shape: S
    let variant: DSGlassVariant
    let interactive: Bool
    let hairline: Bool

    /// 用户在「辅助功能 → 显示与文字大小 → 降低透明度」里要的那件事。
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if reduceTransparency {
            //  一块**不透明**的面色 + 同一圈发丝线。发丝线留着：它是「这里有一块玻璃」
            //  这句话在无障碍那一档下的替身，少了它，卡片与它背后的界面就贴在一起了。
            shape.fill(TokensPalette.surface)
                .overlay {
                    if hairline {
                        shape.strokeBorder(TokensPalette.hairline, lineWidth: TokensHair.border)
                    }
                }
        } else {
            glassEffect(material, in: shape)
                .overlay {
                    if hairline {
                        shape.strokeBorder(TokensPalette.hairline, lineWidth: TokensHair.border)
                    }
                }
        }
    }

    /// 用哪一档材质。
    ///
    ///  用户 2026-09-26：「全局调整液态玻璃的通透度」——设置里选的那一档
    ///  **盖过**「按底下是什么选」这条规矩（理由写在 `DisplaySettings.GlassLevel` 上：
    ///  一个全局开关按不同的地方给不同的结果，就不是一个全局开关）。
    ///  默认那一档是 `standard`，它走的正是这条规矩本身 —— 所以默认行为一字未改。
    private var material: Glass {
        let settings = DisplaySettings.shared
        let base: Glass
        switch settings.level {
        case .clear: base = .clear
        case .standard: base = variant == .overMedia ? .clear : .regular
        case .solid: base = .regular
        }
        // 「更实」那一档加一层**材质自己的** tint：那正是系统给的「同一档材质更实」
        // 的形态（`Glass.tint(_:)`），而**不是**在玻璃底下垫一块面 —— 垫面会把材质
        // 本身挡掉，那件事 `scan/glass.py` 的判据 ③ 正在拦。
        // 浓淡跟着「界面实度」一起走：两块调节钮说的是同一件观感，就不该各调各的。
        let tuned: Glass = settings.level == .solid
            ? base.tint(TokensPalette.surface.opacity(0.35 * settings.fill))
            : base
        // 写成 `interactive(true)` 而不是 `interactive()`：文档里那个默认值
        // （`_ isEnabled: Bool = true`）在 fragments 里看不到，写死实参就与它无关了。
        return interactive ? tuned.interactive(true) : tuned
    }
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
    /// - Note: 形状约束是 `InsettableShape`（可内缩），不是任意 `Shape`。
    ///   那圈发丝线走的是 `strokeBorder`（线画在**里面**，玻璃才有厚度感），
    ///   而 `strokeBorder` 只在 `InsettableShape` 上。2026-09-25 的 CI 就是这条：
    ///   `value of type 'S' has no member 'strokeBorder'` —— 约束写宽了，
    ///   编译器要等到用法处才发现。三个便捷入口传的都是可内缩的形状，
    ///   所以把约束收窄**不损失任何调用点**（将来要传自定义形状，它会自己告诉你）。
    func dsGlass<S: InsettableShape>(in shape: S,
                                     variant: DSGlassVariant = .regular,
                                     interactive: Bool = false,
                                     hairline: Bool = true) -> some View {
        //  这一句曾经就是整块玻璃（材质怎么选、tint 怎么调、发丝线画在哪）——
        //  2026-09-26 搬进 `DSGlassSurface`：函数里读不到 `@Environment`，
        //  而「降低透明度」那一档必须由我们自己接（理由写在那条类型上）。
        //  调用点一个字都没变，参数就是那里的参数。
        DSGlassSurface(shape: shape,
                       variant: variant,
                       interactive: interactive,
                       hairline: hairline)
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
