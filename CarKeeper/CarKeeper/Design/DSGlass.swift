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
//  ⚠️ 2026-09-26（用户：「全局调整液态玻璃的通透度」）：`dsGlass` 曾经还读
//  `DisplaySettings` 的两格；那一轮之后用户把话收紧了（「玻璃就默认选更透，
//  删除默认对应的设置入口」），于是 `DSGlass.swift` 又回到**只读形状与交互**：
//  材质固定 `.clear`，全局偏好这一层整个消失（见下面那一段）。
//  入口仍然只有这一个 —— 12 个调用点写的是同一句话。
//
//  ⚠️ 这里不留 `ViewModifier` 包装类型（2026-09-25 删过一次）：`DSGlassSurface` /
//  `DSGlassLayer` 只是搬运参数，而「搬运」不需要一个类型。文件里现在**一个类型都没有**
//  （`DSGlassVariant` 2026-09-26 随「更透」那一条一起删）—— 只有本文件自己的 `View` 扩展。
//
//  ⛔⛔ 2026-09-26 当天又试了一次包装类型，**把它拆掉了，别再试** ⛔⛔
//
//  为「降低透明度」这一档（下面那段）曾经引入过 `struct DSGlassSurface<S: InsettableShape>: View`
//  —— 理由看起来无可辩驳：`View` 扩展函数里读不到 `@Environment`，要读就得先是一个 `View`。
//  用户把它装到真机上，**启动约 1.9 秒即崩**（`bug_type 309`，`EXC_BAD_ACCESS` /
//  `SIGSEGV`，崩在栈保护区 = 栈溢出）：
//
//      栈顶  DSGlassSurface.body.getter                       ← 我们那个泛型 `View`
//            swift_getOpaqueTypeMetadataImpl                  ← 在建它 `some View` 的元数据
//            swift_getTypeByMangledName
//            swift::SubstGenericParametersFromMetadata::buildDescriptorPath   ← 这里自我递归
//            …（`recursionInfoArray`: depth 906 / originalLength 5572）
//      寄存器  anonymous descriptor View.glassEffect<A>(_:in:)
//
//  也就是说：**把 `glassEffect` 从「泛型 `View` 的 body」里调用**，在 iOS 27.2 上会让
//  运行时期解析那个扩展成员的元数据时无限递归。同一个调用从 `View` 扩展函数里发出
//  （`Self` 在调用点已经是具体类型）一直好好的 —— 这就是现在这一版仍然长这样的原因。
//  所以本文件**一个类型都没有**（`DSGlassVariant` 已于 2026-09-26 删）—— 只有 `View` 扩展。
// =============================================================================

//  ===========================================================================
//  2026-09-26（第二轮）：材质只剩一档 —— 「更透」
//  ===========================================================================
//  用户这一轮定了两件事，合起来把上一轮那套「全局通透度」整个收掉：
//    · 「玻璃就默认选更透」→ 材质一律 `.clear`（不再按底下是什么分两档）
//    · 「删除默认对应的设置入口」→ `DisplaySettings.GlassLevel` 那三档、它那个
//      分段控件、以及 `level` 这个键一起删；`.clear` 不再是「某一档设置」，
//      而是**唯一的材质**。
//  于是 `DSGlassVariant`（`.overMedia` / `.regular`）与 `dsGlass` 的 `variant:`
//  参数一起删掉：一个永远被忽略的参数正是这一仓反复删的那类东西
//  （「写进去了，没有任何读者」）。
//
//  ⚠️ 代价如实写在这里：`.clear` 不磨砂，卡里正文的对比度会跟着底下的照片走 ——
//  而卡片是这一档最大的用户。HIG 的原话是 clear 留给「压在连续画面上」的控件。
//  真机上若某张照片让某一行读不清，回退就是 `dsGlassMaterial` 里那一个词
//  （`.clear` → `.regular`）。
// ===========================================================================

//  ===========================================================================
//  「降低透明度」这一档由我们自己接
//  ===========================================================================
//  用户 2026-09-26：「我把系统的液态玻璃变成了最不通透（辅助功能 → 显示与文字大小 →
//  降低透明度），我们的 app 变成了这样，而相机的几乎没变 —— 你好好分析下相机的层结构」。
//
//  相机那条底条为什么几乎不变：**它底下没有系统材质** —— 那是一层自己画的半透明黑。
//  「降低透明度」能降的只有材质，没有材质就没有可降的东西。
//  （与本仓 2026-09-26 第一轮量到的那条一致：那条带子在像素上是一片均匀填充、
//    看不出底下的草地纹理。而它旁边的系统材质一眼就看得出变化。）
//
//  我们那一块相反：`.glassEffect` 在那一档下的表现是**把模糊拿掉、只留一层淡色**
//  （量用户那张截图：卡里能看出底下的地图纹理、亮度起伏 74…180，整块只比周围高 ~20/255），
//  而我们的字是白的实色（`TokensPalette.primary` = `.label`）—— 白字压在一块淡色上，
//  读不出来；同一屏里每一块玻璃都变成「一块浅色大方块」，远看像卡片变大了。
//
//  所以这一档不能交给系统：**用户要的是「少透一点」，系统的降法在这里恰好把可读性
//  也一起拿走了**。HIG 对同一件事的写法是 *「offer solid-fill alternatives at
//  component level」* —— 组件自己给一块实底。我们这块实底取 `TokensPalette.surface`
//  （不透明的系统面色）：深色下它是 #1C1C1E、亮色下是白，而字（`.label`）与发丝线都跟着
//  同一套明暗走 —— 两种明暗下都读得出来，这正是相机那条深色底子在同一档下保住的东西。
//
//  ⚠️ 读的是**系统那个开关本身**（`UIAccessibility.isReduceTransparencyEnabled`，
//  文档：*「A Boolean value that indicates whether the Reduce Transparency setting is in
//  an enabled state.」*），不是它的一个镜像：镜像要多一个类型（上面那段刚记过代价）+
//  一条挂在根上的写入。代价如实写着：这个值在**下一次求值**时才被读到 ——
//  用户去设置里翻这个开关时 App 在后台，回来时这一屏本来就会重画（刷新节拍 / 场景激活），
//  所以观感上是立刻生效的；真要「翻开关那一瞬间就重画」，得另接一条通知（那一档
//  曾经挂在 `DisplaySettings` 上，而那份设置已随「更透 / 50%」两条一起删）。
// ===========================================================================

extension View {
    /// 浮在内容之上的表面 —— 全 App 唯一的真玻璃入口（见本文件头注的三层规则）。
    ///
    /// - Parameters:
    ///   - shape: 玻璃的形状（`Capsule()` / `Circle()` / 圆角矩形）。形状是**物理**的一部分：
    ///     玻璃有厚度，形状决定光在哪儿拐弯。
    ///   - interactive: 这个表面可点就传 `true` —— 按下去的压缩与折射交给系统演，
    ///     别自己写 `.scaleEffect`（那只会让玻璃「硬」下去）。
    ///   - hairline: 要不要那圈发丝线。玻璃自己已经有边缘，多层叠在一起时少一圈更好。
    /// - Note: 形状约束是 `InsettableShape`（可内缩），不是任意 `Shape`。
    ///   那圈发丝线走的是 `strokeBorder`（线画在**里面**，玻璃才有厚度感），
    ///   而 `strokeBorder` 只在 `InsettableShape` 上。2026-09-25 的 CI 就是这条：
    ///   `value of type 'S' has no member 'strokeBorder'` —— 约束写宽了，
    ///   编译器要等到用法处才发现。三个便捷入口传的都是可内缩的形状，
    ///   所以把约束收窄**不损失任何调用点**（将来要传自定义形状，它会自己告诉你）。
    /// ⚠️ `@ViewBuilder` 是为了「降低透明度」那两支：它们画出的是两种不同的视图，
    /// 而一个 `some View` 函数的所有 `return` 必须是**同一个底层类型** —— 写成
    /// `if … return 面的视图` / `return 玻璃的视图` 根本编译不过（"the return statements
    /// in its body do not have matching underlying types"）。
    /// 再加一层保险：这一支是**函数**（`Self` 在调用点已是具体类型），
    /// 而不是上一版那个会崩的泛型 `View` 的 `body`（见文件头那段）。
    @ViewBuilder
    func dsGlass<S: InsettableShape>(in shape: S,
                                     interactive: Bool = false,
                                     hairline: Bool = true) -> some View {
        if UIAccessibility.isReduceTransparencyEnabled {
            //  「降低透明度」那一档：一块**不透明**的面色 + 同一圈发丝线（理由见文件上部）。
            //  发丝线留着：它是「这里有一块玻璃」这句话在无障碍那一档下的替身 ——
            //  少了它，卡片与它背后的界面就贴在一起了。
            //  这一支**不调用** `glassEffect`：那一档要的正是「没有材质」（也就不花那份合成）。
            shape.fill(TokensPalette.surface)
                .overlay {
                    if hairline {
                        shape.strokeBorder(TokensPalette.hairline, lineWidth: TokensHair.border)
                    }
                }
        } else {
            glassEffect(dsGlassMaterial(interactive: interactive), in: shape)
                .overlay {
                    if hairline {
                        shape.strokeBorder(TokensPalette.hairline, lineWidth: TokensHair.border)
                    }
                }
        }
    }

    /// 材质只有一种：`.clear`（用户这一轮定的「更透」）。
    ///
    /// 它不再是「一个开关的某一档」—— `DisplaySettings` 整份已删，所以这里
    /// 没有可读的设置。`interactive` 仍然要在这里合进去：`.interactive(true)`
    /// 是 `Glass` 自己的方法，而调用点传的是一个 `Bool`。
    private func dsGlassMaterial(interactive: Bool) -> Glass {
        let base: Glass = .clear
        // 写成 `interactive(true)` 而不是 `interactive()`：文档里那个默认值
        // （`_ isEnabled: Bool = true`）在 fragments 里看不到，写死实参就与它无关了。
        return interactive ? base.interactive(true) : base
    }

    /// 常用形状的便捷写法（胶囊：按钮 / 芯片 / 条子）
    func dsGlassCapsule(interactive: Bool = false,
                        hairline: Bool = true) -> some View {
        dsGlass(in: Capsule(), interactive: interactive, hairline: hairline)
    }

    /// 常用形状的便捷写法（圆角矩形：轻提示 / 面板）
    func dsGlassRounded(_ radius: CGFloat = TokensRadius.large,
                        interactive: Bool = false,
                        hairline: Bool = true) -> some View {
        dsGlass(in: RoundedRectangle(cornerRadius: radius, style: .continuous),
                interactive: interactive, hairline: hairline)
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
    //
    //  ⚠️ 2026-09-26：那个容器也是**「透明度 0 不等于不在场」**的原因 —— 它把子树里的
    //  玻璃合成成一个形状，于是子视图被淡到 0 时那块玻璃仍然算在这一层里。
    //  底条那两枚圆钮（`MapSpineView.arm`）与那条带子（`DSSwipeStrip.band`）因此改成
    //  由 `if` 决定在不在，而不是靠 `.opacity`。
    func dsGlassLayer(spacing: CGFloat = TokensSpacing.lg) -> some View {
        GlassEffectContainer(spacing: spacing) { self }
    }
}
