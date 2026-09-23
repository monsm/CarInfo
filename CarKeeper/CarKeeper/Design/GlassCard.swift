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
//    ② 圆角/内边距只从 `StackSpec.Card` 出。七种叠法共用同一张卡，
//       卡片自己不合规格，叠法再对也白搭。
//    ③ **不给卡加阴影**。玻璃的层次由系统材质产生；再叠一层自造的阴影，
//       在深色主题下会变成一圈脏边。
struct GlassCard<Content: View>: View {
    /// 这张卡的个性色（页面的艺术方向）。默认取全局强调色。
    var accent: Color = TokensPalette.accent
    /// 个性色的浓度。0 = 完全不要那一抹（纯玻璃）
    var accentWash: Double = 0.16
    /// 要不要挂系统玻璃。
    ///
    /// 它是**性能开关**，不是风格开关：多张 glass 同时重绘很贵，而消失带里的卡
    /// 已经被遮罩淡到看不清了。关掉时用主题的不透明表面色 —— 在那些位置上
    /// 两者看不出区别（阈值由 `ArcStack` 给，见那里的说明）。
    var glassy: Bool = true
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
            .modifier(CardSurface(glassy: glassy, shape: shape))
            .overlay { accentWashOverlay }
            .overlay { shape.strokeBorder(TokensPalette.glassBorder, lineWidth: TokensHair.border) }
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

/// 卡的底：要么一层系统玻璃，要么主题的不透明表面色。
///
/// 两层共用**同一个 shape**，所以开关时轮廓不会变 —— 变的只有后面那层材质。
/// （`.regular` 是标准厚度：够透（看得见下一张卡），也够实（正文读得清）。
/// `.clear` 在浅色底图上会把字洗掉。）
private struct CardSurface: ViewModifier {
    let glassy: Bool
    let shape: RoundedRectangle

    @ViewBuilder
    func body(content: Content) -> some View {
        if glassy {
            content.glassEffect(.regular, in: shape)
        } else {
            content.background(TokensPalette.surface, in: shape)
        }
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
            Text(title)
                .font(TokensTypo.sectionLabel)
                .foregroundStyle(TokensPalette.secondary)
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
                    .foregroundStyle(TokensPalette.tertiary)
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
                .foregroundStyle(TokensPalette.tertiary)
            Text(text)
                .font(TokensTypo.footnote)
                .foregroundStyle(TokensPalette.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, TokensSpacing.xs)
    }
}
