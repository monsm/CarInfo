import SwiftUI

// =============================================================================
//  GlassCard —— 叠叠乐里的一张玻璃卡
// =============================================================================
//
//  它取代了 `DSCard` 在「功能界面」里的位置。区别只有一处，但要紧：
//  `DSCard` 是**一块不透明的分组底**（iOS 的 inset-grouped），
//  而它是**一层真的玻璃** —— iOS 26 的 `.glassEffect` 是折射 + 反射的物理材质，
//  底下有东西（地图、上一张卡、页面的光）时它会透出来。
//
//  这就是「叠叠乐」能成立的前提：卡片彼此看得见对方，才叫叠。
//  全部不透明的话，不管错位多少，看起来都是一摞纸。
//
//  三条自我约束：
//    ① 颜色一律走令牌 —— 卡片不自己定义配色。每页的「个性色」由 `accent` 传进来，
//       而那个值本身也是令牌（TokensPalette.accent / info / success…）。
//    ② 圆角/内边距只从 `StackSpec.Card` 出。六页共用同一张卡，
//       卡片自己不合规格，别的再对也白搭。
//    ③ **不给卡加阴影**。玻璃的层次由系统材质产生；再叠一层自造的阴影，
//       在深色主题下会变成一圈脏边。
//
//  2026-09-25（第二轮）：那个 `glassy` 开关删了 —— 它是「离阅读线远的卡改用不透明底」
//  的性能妥协，而阅读线与消失带都不存在了（见 `ArcStack` 头注）。留着的后果比性能严重：
//  同一张卡会因为**滚动位置**换材质，滚过去那一瞬间正是最像贴图的一刻。
//  现在每张卡都是同一层玻璃，与它在哪儿无关。
//  ⚠️ 2026-09-26（第二轮）：`frosted` 与 `photoBackdrop` 两个参数一起删。
//  它们此前决定这张卡用 `Glass` 的哪个变体（`.clear` / `.regular`）——
//  而用户这一轮把材质定死了（「玻璃就默认选更透」），变体参数从 `dsGlass` 上
//  整个消失（见 `DSGlass.swift` 头部那一段）。
//  代价如实写：这张卡现在一律是 `.clear`（不磨砂），卡里正文的对比度会跟着
//  底下的照片走。真机上若某张照片让某一行读不清，回退是 `dsGlassMaterial` 里
//  那一个词（`.clear` → `.regular`），而**不是**在这里再开一个参数。
struct GlassCard<Content: View>: View {
    /// 这张卡的个性色（页面的艺术方向）。默认取全局强调色。
    var accent: Color = TokensPalette.accent
    /// 个性色的浓度。0 = 完全不要那一抹（纯玻璃）
    var accentWash: Double = 0.16
    @ViewBuilder var content: Content

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: StackSpec.Card.radius, style: .continuous)
    }

    var body: some View {
        content
            .padding(.horizontal, StackSpec.Card.padH)
            .padding(.top, StackSpec.Card.padTop)
            .padding(.bottom, StackSpec.Card.padBottom)
            .frame(maxWidth: .infinity, alignment: .leading)
            // 材质本身来自 `dsGlass`（`Design/DSGlass.swift`）——**全 App 唯一入口**。
            // 卡片是它最大的一位用户，但不是例外：玻璃在哪儿、用哪一档，只该有一个出处。
            //
            //  `hairline: false`：描边在下面那一条 `overlay` 里画，走令牌，不重复画两层。
            //  （这里此前还要按「底下是照片还是纯色」与「抽屉开着没」选变体，
            //   两点都已随「更透」那一条消失，见文件头上那一段。）
            .dsGlass(in: shape, hairline: false)
            .overlay { accentWashOverlay }
            .overlay { shape.strokeBorder(TokensPalette.hairline, lineWidth: TokensHair.border) }
            .clipShape(shape)
            // 卡是一片读得到的内容，语音不该把它拆成一句句散读
            .accessibilityElement(children: .contain)
    }

    /// 左上角那一抹个性色。用径向渐变（不是整面平涂）：
    /// 平涂会把玻璃的折射盖住，而径向只在角上留一层很淡的色，玻璃还在。
    private var accentWashOverlay: some View {
        RadialGradient(colors: [accent.opacity(accentWash), accent.opacity(0)],
                       center: .topLeading, startRadius: 0, endRadius: 260)
            .allowsHitTesting(false)
            .clipShape(shape)
    }
}

// =============================================================================
//  MARK: - 卡的头部：一个标题 + 一句可选的状态
// =============================================================================
//
//  「无数据」与「数据过期」是两种不同的东西，界面上必须长得不一样：
//    · 无数据  → 一句真话（"还没有体检记录"），**不摆 `--` 占位冒充数据**
//    · 过期    → 值照旧显示（它上次是真的），但右下角挂一个时间
//  这两条本来就是全站的规矩，卡片化之后多了一处风险：卡片的标题行很容易
//  被当成「一定有值」的地方，于是顺手写个 `?? "--"`。这里把它做成参数，
//  只有真的取值处才能决定。
struct GlassCardHead: View {
    let title: String
    var value: String? = nil
    var cls: String = "na"
    /// 数据时刻。给了就显示在右侧 —— 它是「这条读数是什么时候的」，
    /// 而不是「这张卡什么时候画的」。
    var at: Date? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: TokensSpacing.sm) {
            // 卡头坐在**卡片自己的玻璃**上 → 走 `TokensInk`（自适应色，
            // 用户 2026-09-25 第 10 条：玻璃上的字要看得到）。值那一个不走它：
            // 它是状态色，颜色本身就是信息。
            Text(title)
                .font(TokensTypo.sectionLabel)
                .foregroundStyle(TokensInk.secondary)
                .textCase(.uppercase)
            Spacer(minLength: TokensSpacing.sm)
            if let value {
                Text(value)
                    .font(TokensTypo.dataSmall)
                    .foregroundStyle(TokensPalette.statusColor(cls))
            }
            if let at {
                Text(at.formatted(date: .omitted, time: .shortened))
                    .font(TokensTypo.micro)
                    .foregroundStyle(TokensInk.tertiary)
            }
        }
    }
}

// =============================================================================
//  MARK: - 无数据 / 过期：两种状态各一句话
// =============================================================================

/// 卡片里的「没有这条数据」。`icon` 用 SF Symbol 名（调用点给，避免这里写死一堆符号）。
struct GlassCardEmpty: View {
    let text: String
    var icon: String = "tray"

    var body: some View {
        HStack(spacing: TokensSpacing.sm) {
            Image(safeSymbol: icon, fallback: icon)
                .font(TokensTypo.footnote)
                .foregroundStyle(TokensInk.tertiary)
            Text(text)
                .font(TokensTypo.footnote)
                .foregroundStyle(TokensInk.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, TokensSpacing.xs)
    }
}
