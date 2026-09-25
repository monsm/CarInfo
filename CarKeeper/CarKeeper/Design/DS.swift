import SwiftUI
import UIKit

// =============================================================================
//  DS — CarKeeper Design System v4
// =============================================================================
//  设计语言：iOS 原生（Apple 的机制，不是 Apple 的仿制品）
//
//  四条硬规则（这一版存在的唯一理由）：
//   ① 不用卡片。内容直接落在画布上，靠「发丝分隔线」组织，分隔线内缩、不通栏。
//      需要分组的地方，用 iOS 的 inset-grouped 表面（二级分组背景 + 12pt 圆角），
//      它和画布同属一套系统色，因此永不会显得"卡片堆叠"。
//   ② 排版就是层级。字号用 iOS 的真实阶梯（34/700、22/600、17/400 字距 −.41 …），
//      不用自造的中庸字号，也不用容器（彩色底、描边、药丸）来分层。
//   ③ 颜色只来自系统。蓝 #007AFF/#0A84FF、绿、橙、红，加上 label 的三档不透明度。
//      界面里所有发光的东西都必须对应一个真实状态，不做装饰性彩色。
//   ④ 玻璃只出现在「浮在内容之上」的层：导航栏、弹层、底部操作条。
//      内容层一律不透明。
//
//  动效：只有两类 —— 状态变化的弹簧，以及一次性绘制（光条从 0 长到位）。
//        没有涟漪、没有光晕、没有扫光、没有呼吸、没有粒子、没有交错入场。
//
//  兼容：本文件同时提供 v2 时代的全部成员名（Palette/Typo/Space/… 与 DSCard 等），
//        但它们现在渲染的是 v4 语言。老页面无需逐个修改即可继承新观感。
// =============================================================================

//  这里原本有一段 `extension UIColor { static func dsDynamic(light:dark:) }`（动态色）。
//  2026-09-25 删：一个读者都没有，而且是**第二套实现** —— 全 App 真正在用的是
//  `ArtTheme.swift` 里的 `nativeDynamic(light:dark:)`（它的注释记着来历：原本由
//  WidgetTokens 的 `Palette.dynamic` 提供，那个文件删掉后内联进去）。
//  发现它的是 `scan/orphans.py` 判据 ②（系统类型扩展里没人读的成员）。

/// 设计系统组件（DSCard / DSRow / DSTile / DSSkeleton …）。
/// 令牌（颜色 / 字体 / 间距 / 圆角 / 动效 / 触觉）已全部合并到 `Tokens.swift`。
enum DS {
}

// =============================================================================
// MARK: - 画布
// =============================================================================

/// 页面画布：单一底色 + 统一 20pt 页面边距。
struct DSCanvas<Content: View>: View {
    var content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        ZStack {
            TokensPalette.background.ignoresSafeArea()
            content()
        }
    }
}

// =============================================================================
// MARK: - inset-grouped 表面（v4 唯一的"容器"）
// =============================================================================

/// 分组表面：iOS inset-grouped 的卡片面。**半透明**（`TokensPalette.panel`）、无描边、无阴影。
/// 只有需要"把一组行框在一起"时才用它；单条信息直接落在画布上用发丝线分隔。
///
///  为什么它不是不透明的（2026-09-25）：它铺在 `GlassCard` 里面，而卡片是玻璃。
///  一块不透明的面（`nightSurface`，深色 #1C1C1E）压在玻璃里，结果是「玻璃中间挖了一个黑洞」——
///  用户第 5 条说的「黑颜色太突兀」就是它。现在它读 `TokensPalette.panel`（同一色值的半透明版）——
///  那个透明度第九轮又从 0.5 收到 0.34（用户第 3 条：「我要通透」，列表尤甚）。
/// ⚠️ `glass` 与 `hero` 两个参数已于 2026-09-25 删除：它们**存下来就没再读过**
/// （`body` 永远填 `nightSurface`，也从不看 `hero`）。一个叫 `glass` 的参数不产生
/// 玻璃，是这个仓库最忌讳的那种谎 —— 谁写 `DSCard(glass: true)` 都会以为拿到了材质
/// 而其实什么都没发生。真玻璃只有一个入口：`dsGlass`（见 `Design/DSGlass.swift`）。
struct DSCard<Content: View>: View {
    var padding: CGFloat
    var radius: CGFloat
    var content: () -> Content

    init(padding: CGFloat = TokensSpacing.md,
         radius: CGFloat = TokensRadius.medium,
         @ViewBuilder content: @escaping () -> Content) {
        self.padding = padding
        self.radius = radius
        self.content = content
    }

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(TokensPalette.panel)
            }
            // 「艺术方向下给卡片一条发丝描边」这一块随艺术主题删掉了（2026-09-25）：
            // 那是「纸与墨」那套方向才有的做法，而它**只在那套主题下出现** ——
            // 主题只剩原生之后，这里的条件是恒假，留着就是一份永远不会执行的样式。
            // 现在全 App 的卡片只有一层底（`TokensPalette.panel`），没有描边。
    }
}

/// 可点击卡片
struct DSCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.55 : 1)
            .animation(TokensMotion.press, value: configuration.isPressed)
    }
}

// =============================================================================
// MARK: - 分隔线
// =============================================================================

/// 发丝分隔线。iOS 的真值：不与屏幕等宽，内缩 16pt（与行内容左对齐）。
struct DSDivider: View {
    var inset: CGFloat = 0
    var body: some View {
        Rectangle()
            .fill(TokensPalette.hairline)
            .frame(height: TokensHair.line)
            .padding(.leading, inset)
    }
}

/// 行内分隔线（内缩 16，与 DSRow 的内容左对齐）
struct DSSeparator: View {
    var inset: CGFloat = TokensHair.inset
    var body: some View {
        DSDivider(inset: inset)
    }
}

// =============================================================================
// MARK: - inset-grouped 分组（v4 唯一的分组形态）
// =============================================================================

/// iOS inset-grouped 分组：**分组标题在画布上，行在分组表面上**。
/// 这是 iOS 设置 / 健康 / 钱包的标准结构。
/// 规则：标题不进表面（那是旧版 CardBox 的做法，头部与内容混在一层里），
/// 　　　行与行之间用发丝线分隔，线内缩到与文字左对齐。
struct DSGroup<Content: View>: View {
    var title: String? = nil
    var trailing: String? = nil
    /// 不为 "na" 时，右侧那个值渲染成 `DSChip`（带语义色）而不是灰字。
    /// 「共 3 项故障」这类话是**状态**，不是计数：状态必须带颜色，计数只是灰字。
    var trailingCls: String = "na"
    var footer: String? = nil
    var onTrailingTap: (() -> Void)? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                DSSectionHeader(title: title, trailing: trailing,
                                trailingCls: trailingCls, action: onTrailingTap)
            }
            //  分组**不再自带一层底**。
            //
            //  2026-09-25（用户第 6 条：「指令和一键都降级到玻璃卡片上（其他子界面均降级到
            //  玻璃卡片上，尽量少的使用多级玻璃或层，容易导致玻璃不通透）」）。
            //  这里原来是 `RoundedRectangle.fill(TokensPalette.panel)` —— 一层半透明的扁面，
            //  每一组都叠在卡片自己的玻璃上。于是同一张卡里就有了**两层材质**：卡是玻璃，
            //  卡里的每一组又各是一块面色。用户看到的“不通透的灰”就是它（上一轮把它的
            //  不透明度从 0.5 降到 0.34，治不了根：只要是**多出一层**，玻璃的折射就断了）。
            //
            //  现在行直接坐在卡片的玻璃上，分组僭界由三件东西说：分组标题（`DSSectionHeader`）、
            //  行间的发丝线（`DSSeparator`）、以及卡片自己的圆角与内衬。
            //  代价如实写在这里：分组与卡片背景之间的对比变弱了 —— 而那一层对比是**拿玻璃
            //  换来的**，而用户这四轮反复要的就是玻璃。回退就是上面那三行（一个 `.background`）。
            VStack(spacing: 0) { content() }
                // 裁剪掉圆角：行的按压底色是矩形，不裁会在分组四角露出方角
                .clipShape(RoundedRectangle(cornerRadius: TokensRadius.medium, style: .continuous))
            if let footer {
                Text(footer)
                    .font(TokensTypo.footnote)
                    .foregroundStyle(TokensPalette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, TokensSpacing.sm)
            }
        }
    }
}

/// 分组内的一行：统一左右内缩（16pt）、最小高度 44pt、行尾一条内缩发丝线。
/// 行的内容可以是 DSRow / DSKeyValueRow / 任意视图。
struct DSGroupRow<Content: View>: View {
    var showsSeparator: Bool = true
    var separatorInset: CGFloat = 0
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            content()
                .padding(.horizontal, TokensSpacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: TokensSpacing.row)
            if showsSeparator { DSSeparator(inset: separatorInset) }
        }
    }
}

/// 原始报文行：左键右值。值走等宽数字，长值自动换行、不被键挤掉。
/// 用于「全量数据 / 车辆档案 / 检测明细」这类逐字段结构化排版。
struct DSKeyValueRow: View {
    var key: String
    var value: String
    var valueCls: String = "na"
    var mono: Bool = true

    var body: some View {
        //  2026-09-25（用户第 5 条：「内容放得下且不换行（全部页面都需要逐个控件审核）」）：
        //  这一行是**全站用得最多的一行**（车辆档案、充电明细、体检逐项、消息明细…）。
        //  它此前允许 key 折到两行、而 value 根本不限行数：值一长（VIN、故障码串、
        //  「3 条 · P0A80,P0A81…」）整行就变两行高，而它下面还有一条发丝线 ——
        //  一折行看上去就像“这一行没对齐”，不是“这一行内容多”。
        //  现在两边都是单行、**装不下就缩**（缩比行高变化便宜，也读得完）。
        HStack(alignment: .firstTextBaseline, spacing: TokensSpacing.md) {
            Text(key)
                .font(TokensTypo.subheadline)
                .foregroundStyle(TokensPalette.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: TokensSpacing.sm)
            Text(value)
                .font(mono ? TokensTypo.dataSmall : TokensTypo.subheadline)
                .foregroundStyle(valueCls == "na" ? TokensPalette.secondary : TokensPalette.statusColor(valueCls))
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                // 值优先占位（不够缩时先缩 key）—— 一条读数里值才是要看的东西。
                .layoutPriority(1)
        }
        .frame(minHeight: TokensSpacing.row)
        .accessibilityElement(children: .combine)
    }
}

// =============================================================================
// MARK: - 结构与排版
// =============================================================================

/// 分组标题：iOS 的 section header（13pt、二级灰、大写、不加容器）
struct DSSectionHeader: View {
    /// 标题。**可以为空** —— 卡片正文里那一行就是这种情况：卡头已经给这张卡
    /// 起过名（`GlassCardHead`），正文再写一遍就是同一个东西两个名字。
    /// 那时候这一行只剩下右侧那个动作（「全部已读」这类），标题留空即可。
    var title: String = ""
    var trailing: String? = nil
    /// 不为 "na" 时用 `DSChip`（一个语义圆点 + 颜色）代替灰字。
    var trailingCls: String = "na"
    var action: (() -> Void)? = nil

    var body: some View {
        // 分组标题是全 App 最密集的一行字（~28 屏都在用它）。
        // 它以前走 `TokensTypo.fixed(13)` —— 原生下返回的正是 `.system(size: 13)`，
        // 只有艺术方向下才换成宋体；主题删掉之后那个名字底下什么都不剩，
        // 所以这里直接写定尺字体（与原返回值逐值相同）。字距仍是 `TokensTracking.label`。
        HStack(alignment: .firstTextBaseline) {
            if !title.isEmpty {
                Text(title.uppercased())
                    .font(TokensTypo.fixed(13))
                    .tracking(TokensTracking.label)
                    .foregroundStyle(TokensPalette.secondary)
                    // 标题与右侧那个数挤在同一行（用户第 5 条）：先不许折，再允许缩。
                    // 分组标题折行会把下面那一组内容整体推下去一格，而它本来只是一行小字。
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: TokensSpacing.sm)
            if let trailing {
                if let action {
                    Button(trailing, action: action)
                        .font(TokensTypo.footnote)
                        .foregroundStyle(TokensPalette.ambient)
                        .buttonStyle(.plain)
                        // 命中区 44pt（HIG 最小触控目标）：文字只有 13pt 高，
                        // 而它旁边没有任何可点区域 —— 不给高度就只能碰运气点到。（2026-09-25）
                        .frame(minHeight: TokensSpacing.row)
                        .contentShape(Rectangle())
                } else if trailingCls != "na" {
                    DSChip(text: trailing, cls: trailingCls)
                } else {
                    Text(trailing)
                        .font(TokensTypo.footnote)
                        .foregroundStyle(TokensPalette.tertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
        .padding(.bottom, TokensSpacing.sm)
    }
}

/// 巨大数字：超细字重 + 负字距（Apple 的仪器感全靠字重差，不靠颜色）
struct DSBigNumber: View {
    var value: String
    var unit: String? = nil
    var caption: String? = nil
    var size: CGFloat = 96
    var tint: Color = TokensPalette.primary
    var alignment: HorizontalAlignment = .leading
    /// 字重。默认值 = 这个原语一直以来的写法（超细 —— 「仪器感」，见 `TokensTypo.display`）。
    /// 2026-09-25 加这一个参数的原因只有一处：地图抽屉头上那三个数压在通透玻璃上，
    /// 用户第 3 条要求「字体加粗」（超细的字在 `clear` 玻璃上会散）。
    /// 它必须放在最后 —— 带标签的实参在 Swift 里要按声明顺序写，
    /// 加在中间会让**已有**的调用点全部编译不过。
    var weight: Font.Weight = .ultraLight

    var body: some View {
        VStack(alignment: alignment, spacing: TokensSpacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: TokensSpacing.xs) {
                Text(value)
                    .font(TokensTypo.display(size, weight: weight))
                    // 字距 = 按字号算的基准（字号越大越要收紧，否则数字会散开）。
                    // 这里以前还加一项「主题的额外字距」（巨字方向靠它把超大数字
                    // 收成一整块），随艺术主题删除；原生那一项本来就是 0，
                    // 所以取值逐值不变。
                    .tracking(-size * 0.035)
                    .foregroundStyle(tint)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let unit {
                    Text(unit)
                        .font(TokensTypo.metric(size * 0.30))
                        .foregroundStyle(TokensPalette.secondary)
                }
            }
            if let caption {
                Text(caption)
                    .font(TokensTypo.footnote)
                    .foregroundStyle(TokensPalette.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// 【已删】`DSPageTitle`（页面大标题，艺术方向下画在内容里）。
//（2026-09-25）它的四个使用者（诊断 / 应急 / 体检 / 保养）**全部是卡里的正文**，
// 而它们嘴上那张卡自己已经写着名字（卡头 `GlassCardHead`）—— 于是同一屏出现两个名字
//（「诊断」+「设计令牌」、「应急」+「紧急求助」）。卡头就是标题，正文不再交一份。
extension View {
    /// 页面标题：iOS 大标题留在导航栏。
    ///
    /// 它以前有**两种活法** —— 艺术方向下把导航栏清空、大标题搬进版面（衬线 + 疏排）。
    /// 2026-09-25 艺术主题整份删除，于是只剩这一条；`inline: true` 保留，
    /// 因为有些页面本来就一直用行内标题，而「逐像素等于现状」是这里的硬要求。
    /// （艺术方向那一支的两个零件都已删：`DSPageTitle` 于同日删掉，
    ///  `TokensSerif` 随主题一起走。）
    func dsPageTitle(_ title: String, inline: Bool = false) -> some View {
        navigationTitle(title)
            .navigationBarTitleDisplayMode(inline ? .inline : .large)
    }

}

/// 关键指标（兼容旧名 DSMetric，渲染同 DSBigNumber）
struct DSMetric: View {
    var value: String
    var unit: String? = nil
    var caption: String? = nil
    var size: CGFloat = 72
    var tint: Color = TokensPalette.primary
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        DSBigNumber(value: value, unit: unit, caption: caption, size: size, tint: tint, alignment: alignment)
    }
}

/// 车灯光带 = 电量表（v4 的核心机制）。
/// 亮起的长度就是电量百分比；`glow` 是同一束光的溢出，不是装饰。
struct DSLightBar: View {
    var progress: Double                       // 0...1
    var height: CGFloat = 6
    var showsGlow: Bool = true
    var tint: LinearGradient? = nil
    @State private var revealed: Double = 0

    private var clamped: Double { max(0, min(1, progress)) }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width * revealed
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(TokensPalette.track)
                    .frame(height: height)
                if showsGlow && w > 1 {
                    Capsule()
                        .fill(tint ?? TokensPalette.lightBar)
                        .frame(width: w, height: height)
                        .blur(radius: 9)
                        .opacity(0.75)
                }
                Capsule()
                    .fill(tint ?? TokensPalette.lightBar)
                    .frame(width: w, height: height)
            }
            .frame(height: height)
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .frame(height: height)
        .onAppear {
            withAnimation(TokensMotion.draw) { revealed = clamped }
        }
        .onChange(of: clamped) { _, newValue in
            withAnimation(TokensMotion.value) { revealed = newValue }
        }
        .accessibilityElement()
        .accessibilityLabel(Text("电量比例"))
        .accessibilityValue(Text("\(Int(clamped * 100))%"))
    }
}

/// 环形读数：一圈轨道 + 一段弧 + 中心里的东西（健康评分用）。
///
/// 2026-09-25 新增（用户第 2 条：「车辆页的健康布局太不 iOS，太业余了」）。
/// 「百分比」在 iOS 上有一个通行的形态：**环**（活动 / 电量 / 健唐 App 都是它）。
/// 而它此前是「96pt 超细巨字 + 一条线性光带 + 一排行下的方块」三件东西说同一件事，
/// 其中超细那一支还是全 App 最细的字 —— 那几个字压在卡片上像未完成的排版，
/// 不像一个结论。环把「分数」与「占多少」合成**同一个图形**，中心那点地方刚好够写它。
///
/// 三条取自系统写法的细节，都不是装饰：
///   · 弧从**十二点**开始（`rotationEffect(-90°)`）—— 系统的表都是这么读的；
///   · 端点**圆头**（`lineCap: .round`）—— 方头在小进度时看起来像没开始；
///   · 球道用 `TokensPalette.track`（与光带同一条）。
/// 缩小不到 1 的进度也照画：环的“没满”本身就是读数的一部分（这一点与光带一致）。
struct DSRing<Content: View>: View {
    /// 0…1（超出的部分自己夹掉，调用点不必先夹）
    var progress: Double
    var tint: Color
    var size: CGFloat = 108
    var lineWidth: CGFloat = 12
    /// 环中心里的东西（怎么写由调用点决定：这里只保证它居中）
    @ViewBuilder var content: Content

    private var clamped: Double { max(0, min(1, progress)) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(TokensPalette.track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            content
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .contain)
    }
}

/// 三段事实条：竖向发丝线分隔的三个读数（v4 首屏用）
struct DSStatStrip: View {
    struct Item: Identifiable {
        let id = UUID()
        var label: String
        var value: String
        var cls: String = "na"
        var icon: String? = nil
        init(_ label: String, _ value: String, cls: String = "na", icon: String? = nil) {
            self.label = label
            self.value = value
            self.cls = cls
            self.icon = icon
        }
    }

    var items: [Item]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                if idx > 0 {
                    Rectangle()
                        .fill(TokensPalette.hairline)
                        .frame(width: TokensHair.line)
                        .frame(maxHeight: .infinity)
                }
                VStack(alignment: .leading, spacing: TokensSpacing.xs) {
                    HStack(spacing: TokensSpacing.xs) {
                        if let icon = item.icon {
                            Image(safeSymbol: icon, fallback: "circle")
                                .font(TokensTypo.fixed(10, weight: .semibold))
                        }
                        Text(item.label)
                            .lineLimit(1)
                    }
                    .font(TokensTypo.caption)
                    .foregroundStyle(TokensPalette.secondary)
                    Text(item.value)
                        .font(TokensTypo.data)
                        .foregroundStyle(item.cls == "na" ? TokensPalette.primary : TokensPalette.statusColor(item.cls))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, TokensSpacing.md)
                .padding(.vertical, TokensSpacing.md)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
    }
}

/// 状态：一个语义圆点 + 文案（不用彩色药丸底 —— 颜色只表达状态，不表达层级）
struct DSChip: View {
    var text: String
    var cls: String = "na"
    var icon: String? = nil

    private var color: Color { TokensPalette.statusColor(cls) }

    var body: some View {
        HStack(spacing: TokensSpacing.sm) {
            if let icon {
                Image(safeSymbol: icon, fallback: "circle.fill")
                    .font(TokensTypo.fixed(10, weight: .semibold))
                    .foregroundStyle(color)
            } else {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
            }
            Text(text)
                .font(TokensTypo.footnote)
                .foregroundStyle(cls == "na" ? TokensPalette.secondary : color)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

/// 标签 + 数值 行（iOS 行排版：左标题、右数值）
struct DSStatRow: View {
    var label: String
    var value: String
    var valueCls: String = "na"
    var icon: String? = nil

    var body: some View {
        HStack(spacing: TokensSpacing.sm) {
            if let icon {
                Image(safeSymbol: icon, fallback: "circle")
                    .font(.system(size: TokensSize.iconSm))
                    .foregroundStyle(TokensPalette.secondary)
                    .frame(width: 20)
            }
            // 与 `DSKeyValueRow` 同一条（用户第 5 条）：一行一个事实，不折行 ——
            // 装不下就缩，不把行高变成两行（那看起来是没对齐，不是内容多）。
            Text(label)
                .font(TokensTypo.body)
                .foregroundStyle(TokensPalette.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: TokensSpacing.md)
            Text(value)
                .font(TokensTypo.data)
                .foregroundStyle(valueCls == "na" ? TokensPalette.secondary : TokensPalette.statusColor(valueCls))
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(minHeight: TokensSpacing.row)
        .accessibilityElement(children: .combine)
    }
}


/// 设置式行：图标 + 标题/+ 副标题 + 右侧值 + 箭头（iOS 列表的标准行）
struct DSRow: View {
    var icon: String?
    var title: String
    var subtitle: String? = nil
    var value: String? = nil
    var valueCls: String = "na"
    var showsChevron: Bool = false
    var action: (() -> Void)? = nil

    var body: some View {
        Group {
            if let action {
                Button(action: action) { rowContent }.buttonStyle(DSRowButtonStyle())
            } else {
                rowContent
            }
        }
    }

    private var rowContent: some View {
        HStack(spacing: TokensSpacing.md) {
            if let icon {
                Image(safeSymbol: icon, fallback: "circle")
                    .font(.system(size: TokensSize.icon))
                    .foregroundStyle(TokensPalette.ambient)
                    .frame(width: TokensSize.iconColumn, alignment: .center)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(TokensTypo.body)
                    .foregroundStyle(TokensPalette.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(TokensTypo.footnote)
                        .foregroundStyle(TokensPalette.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: TokensSpacing.sm)
            if let value {
                Text(value)
                    .font(TokensTypo.data)
                    .foregroundStyle(valueCls == "na" ? TokensPalette.secondary : TokensPalette.statusColor(valueCls))
                    .multilineTextAlignment(.trailing)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(TokensTypo.fixed(13, weight: .semibold))
                    .foregroundStyle(TokensPalette.tertiary)
            }
        }
        .frame(minHeight: TokensSpacing.row)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct DSRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? TokensPalette.fillSubtle : Color.clear)
            .animation(TokensMotion.press, value: configuration.isPressed)
    }
}

/// 快捷操作：图标 + 标签（平铺表面，无图标砖、无描边、无阴影）
/// 只有"正在生效"的状态才用系统蓝，普通态是纯文字色。
struct DSTile: View {
    var icon: String
    var title: String
    var subtitle: String? = nil
    var isActive: Bool = false
    var cls: String = "acc"
    var isLoading: Bool = false
    var action: () -> Void

    private var accent: Color {
        isActive ? TokensPalette.statusColor(cls) : TokensPalette.primary
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: TokensSpacing.sm) {
                HStack(alignment: .center) {
                    Image(safeSymbol: icon, fallback: "circle")
                        .font(.system(size: TokensSize.tileIcon, weight: .regular))
                        .foregroundStyle(accent)
                    Spacer(minLength: 0)
                    if isLoading {
                        ProgressView().controlSize(.small)
                    }
                }
                Text(title)
                    .font(TokensTypo.body)
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let subtitle {
                    Text(subtitle)
                        .font(TokensTypo.footnote)
                        .foregroundStyle(TokensPalette.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(TokensSpacing.lg)
            .frame(minHeight: 84, alignment: .topLeading)
            .background {
                RoundedRectangle(cornerRadius: TokensRadius.medium, style: .continuous)
                    .fill(TokensPalette.panel)
            }
        }
        .buttonStyle(DSCardButtonStyle())
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(isActive ? "已开启" : "已关闭"))
    }
}

/// 主操作按钮（一屏最多一个）：实心胶囊
struct DSPrimaryButtonStyle: ButtonStyle {
    var tint: Color = TokensPalette.ambient

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TokensTypo.headline)
            .foregroundStyle(TokensPalette.labelOnTint)
            .frame(maxWidth: .infinity)
            .frame(height: TokensSize.button)
            .background(Capsule().fill(tint))
            .opacity(configuration.isPressed ? 0.82 : 1)
            //  `.scaleEffect(configuration.isPressed ? 0.985 : 1)` 2026-09-25 删除
            //（用户第 2 条：「全部页面不需要颤抖放大特效，太耗性能」）。
            //  它是全仓**唯一**一处「按下就缩放」—— 而按下的反馈已经由上面那行透明度
            //  给了。多那一层的代价是真的：这一条按钮是 `maxWidth: .infinity`，
            //  一次非整数缩放要让整条胶囊先渲染到离屏缓冲再合成。
            //  全 App 每一个主操作按钮都在这条路上。
            .animation(TokensMotion.press, value: configuration.isPressed)
    }
}

/// 次操作按钮：iOS 的"灰色胶囊"
struct DSSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TokensTypo.headline)
            // 这层底是**真玻璃**（下面那行 `dsGlassCapsule`）→ 字走 `TokensInk`：
            // 系统会按材质调它（vibrancy），而 `Color(uiColor: .label)` 是解析死的值
            // —— 在玻璃上它就是一层实字（见 `TokensInk` 的说明）。
            .foregroundStyle(TokensInk.primary)
            .frame(maxWidth: .infinity)
            .frame(height: TokensSize.button)
            // 次操作 = 玻璃胶囊（iOS 26 的次级按钮就是这层材质）。
            // 不再自己压透明度表现「按下」：玻璃的按压形态由系统演（`interactive`）。
            .dsGlassCapsule(interactive: true)
            .animation(TokensMotion.press, value: configuration.isPressed)
    }
}


/// 分段控件：系统分段控件的观感（填充底 + 白色滑块），不自造圆角
struct DSSegmented<T: Hashable>: View {
    var options: [(value: T, title: String)]
    @Binding var selection: T

    var body: some View {
        HStack(spacing: TokensSpacing.xxs) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let selected = option.value == selection
                Button {
                    withAnimation(TokensMotion.value) { selection = option.value }
                } label: {
                    Text(option.title)
                        .font(TokensTypo.subheadline.weight(selected ? .semibold : .regular))
                        .foregroundStyle(TokensPalette.primary)
                        //  固定高 32 的一格：这里的字**绝不能折行**（用户第 5 条）——
                        //  折了不是变成两行，而是被 32pt 的框**剪掉**（下一行看不见了）。
                        //  所以先不许折，再允许缩：宁可字小一点，不能出现半个字。
                        //  两段与三段都在用这个控件（车辆 / 我的那两个），段名都是两个字，
                        //  所以缩到 0.8 这一步在真机上大概用不着 —— 它是护栏，不是常态。
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    // 选中的滑块 = **玻璃里面那一层更亮的底**，与模式条上那枚透镜
                                    // 是同一个东西，所以用同一个令牌（`glassHighlight`）。
                                    // 它原来读 `nightSurface` —— 深色模式下那是 (28,28,30)，
                                    // 比它所在的凹槽（`fillSubtle`）还暗，于是「选中的那一格」
                                    // 看起来是一个黑洞（用户 2026-09-25 第 5 条截图的「全部 / 未读」）。
                                    // iOS 深色下选中段本来就该比凹槽**亮**，不是更暗。
                                    .fill(TokensPalette.glassHighlight)
                                    .shadow(color: TokensPalette.scrim.opacity(0.12), radius: 3, y: 1)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
        .padding(2)
        // 这一块在**卡里**（规则 ②：卡里不玻璃）——它是分段控件的凹槽，
        // 用「未选中的底」那个令牌。别名 `glassLight` 已删（见 `Tokens.swift`）：
        // 名字里带 glass 的扁平色，就是这一轮要找的那类谎。
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(TokensPalette.fillSubtle))
    }
}

/// 环形仪表：单色细环 + 轨道（保留给确实需要"环"的少数页面）
/// 迷你趋势曲线（Canvas 手绘）
/// 信息条（离线、失败、提示）：安静的提示，不用彩色块
struct DSNotice: View {
    enum Kind { case info, warning, error, success
        var cls: String {
            switch self {
            case .info: return "acc"
            case .warning: return "warn"
            case .error: return "bad"
            case .success: return "ok"
            }
        }
        var icon: String {
            switch self {
            case .info: return "info.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .error: return "xmark.octagon.fill"
            case .success: return "checkmark.circle.fill"
            }
        }
    }

    var kind: Kind
    var text: String
    var action: (title: String, run: () -> Void)? = nil

    var body: some View {
        HStack(spacing: TokensSpacing.sm) {
            Image(safeSymbol: kind.icon, fallback: "info.circle.fill")
                .font(TokensTypo.fixed(15))
                .foregroundStyle(TokensPalette.statusColor(kind.cls))
            Text(text)
                .font(TokensTypo.footnote)
                .foregroundStyle(TokensPalette.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: TokensSpacing.sm)
            if let action {
                Button(action.title, action: action.run)
                    .font(TokensTypo.footnote.weight(.semibold))
                    .foregroundStyle(TokensPalette.ambient)
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, TokensSpacing.md)
        .padding(.vertical, TokensSpacing.sm)
        .background(RoundedRectangle(cornerRadius: TokensRadius.small, style: .continuous)
            .fill(TokensPalette.panel))
        .accessibilityElement(children: .combine)
    }
}

/// 空状态 / 错误状态（页面级）
struct DSPlaceholder: View {
    var icon: String
    var title: String
    var message: String? = nil
    var actionTitle: String? = nil
    var cls: String = "na"
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: TokensSpacing.md) {
            Image(safeSymbol: icon, fallback: "questionmark.circle")
                .font(TokensTypo.fixed(40, weight: .light))
                .foregroundStyle(cls == "na" ? TokensPalette.tertiary : TokensPalette.statusColor(cls))
            Text(title)
                .font(TokensTypo.headline)
                .foregroundStyle(TokensPalette.primary)
                .multilineTextAlignment(.center)
            if let message {
                Text(message)
                    .font(TokensTypo.footnote)
                    .foregroundStyle(TokensPalette.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(DSSecondaryButtonStyle())
                    .frame(maxWidth: 220)
            }
        }
        .padding(.vertical, TokensSpacing.xxxl)
        .padding(.horizontal, TokensSpacing.xl)
        .frame(maxWidth: .infinity)
    }
}

/// 加载占位（静态：加载本身由 ProgressView 表达，占位块不做动画）
struct DSSkeleton: View {
    var height: CGFloat = 16
    var width: CGFloat? = nil

    var body: some View {
        RoundedRectangle(cornerRadius: TokensRadius.small, style: .continuous)
            .fill(TokensPalette.fillSubtle)
            .frame(width: width, height: height)
            .accessibilityHidden(true)
    }
}

// =============================================================================
// MARK: - 浮层材质（唯一允许用玻璃的地方）
// =============================================================================

/// 顶部导航栏容器（浮在内容之上 → 玻璃合法）
/// 底部悬浮操作条（浮在内容之上 → 玻璃合法）
// MARK: - Haptic feedback (backward compatibility alias)
// MARK: - 分组表面（inset-grouped 表面外观）

// =============================================================================
// MARK: - 可折叠分组（DS 语言里的唯一一种「折叠」）
// =============================================================================

/// 可折叠分组：标题行在画布上，行在分组表面上，**收起时标题行与 footer 仍然可见**。
///
/// 它取代旧的 `ExpandingCardBox`（那是第二套容器：标题行行内 padding 与自己的一层玻璃）。
/// 折叠本身是有用的功能（电池页的子系统 / 车控页的完整指令表默认收起），
/// 但它必须与 `DSGroup` **长得一样** —— 折叠只改变「展开还是收起」，不改变版式语言。
///
/// 收起状态下的 footer 是刻意的：像「这块只列 10 条」这种规则如果只在展开后可见，
/// 用户就永远不会去展开它。
struct DSExpandGroup<Content: View>: View {
    var title: String
    var trailing: String? = nil
    var trailingCls: String = "na"
    var footer: String? = nil
    var initiallyExpanded: Bool = false
    @ViewBuilder var content: () -> Content

    @State private var expanded: Bool

    init(title: String,
         trailing: String? = nil,
         trailingCls: String = "na",
         footer: String? = nil,
         initiallyExpanded: Bool = false,
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.trailing = trailing
        self.trailingCls = trailingCls
        self.footer = footer
        self.initiallyExpanded = initiallyExpanded
        self.content = content
        _expanded = State(initialValue: initiallyExpanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                TokensHaptic.select()
                withAnimation(TokensMotion.value) { expanded.toggle() }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: TokensSpacing.sm) {
                    Text(title.uppercased())
                        .font(TokensTypo.fixed(13))
                        .tracking(TokensTracking.label)
                        .foregroundStyle(TokensPalette.secondary)
                    Spacer(minLength: TokensSpacing.sm)
                    if let trailing, !trailing.isEmpty {
                        DSChip(text: trailing, cls: trailingCls)
                    }
                    Image(systemName: "chevron.down")
                        .font(TokensTypo.fixed(11, weight: .semibold))
                        .foregroundStyle(TokensPalette.tertiary)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .padding(.bottom, TokensSpacing.sm)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(title))
            .accessibilityValue(Text(expanded ? "已展开" : "已收起"))

            if expanded {
                VStack(spacing: 0) { content() }
                    .background {
                        RoundedRectangle(cornerRadius: TokensRadius.medium, style: .continuous)
                            .fill(TokensPalette.panel)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: TokensRadius.medium, style: .continuous))
            }

            if let footer {
                Text(footer)
                    .font(TokensTypo.footnote)
                    .foregroundStyle(TokensPalette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, TokensSpacing.sm)
            }
        }
    }
}

/// 与 DSExpandGroup 相同的标题行 + 折叠交互，但**不画背景表面**。
/// 用在「外层已有统一表面」的场景里，避免多层嵌套背景产生「框框套框框」的视觉垃圾。
struct DSSection<Content: View>: View {
    var title: String
    var trailing: String? = nil
    var trailingCls: String = "na"
    var footer: String? = nil
    @ViewBuilder var content: () -> Content

    @State private var expanded: Bool = false

    init(title: String,
         trailing: String? = nil,
         trailingCls: String = "na",
         footer: String? = nil,
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.trailing = trailing
        self.trailingCls = trailingCls
        self.footer = footer
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                TokensHaptic.select()
                withAnimation(TokensMotion.value) { expanded.toggle() }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: TokensSpacing.sm) {
                    Text(title.uppercased())
                        .font(TokensTypo.fixed(13))
                        .tracking(TokensTracking.label)
                        .foregroundStyle(TokensPalette.secondary)
                    Spacer(minLength: TokensSpacing.sm)
                    if let trailing, !trailing.isEmpty {
                        DSChip(text: trailing, cls: trailingCls)
                    }
                    Image(systemName: "chevron.down")
                        .font(TokensTypo.fixed(11, weight: .semibold))
                        .foregroundStyle(TokensPalette.tertiary)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .padding(.bottom, TokensSpacing.sm)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(title))
            .accessibilityValue(Text(expanded ? "已展开" : "已收起"))

            if expanded {
                VStack(spacing: 0) { content() }
            }

            if let footer {
                Text(footer)
                    .font(TokensTypo.footnote)
                    .foregroundStyle(TokensPalette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, TokensSpacing.sm)
            }
        }
    }
}

struct DSSurfaceModifier: ViewModifier {
    var padding: CGFloat
    var radius: CGFloat
    /// 要不要「更亮一点的底」。**这不是玻璃**（玻璃是 `dsGlass`）——
    /// 2026-09-25 材质审核把它从 `glass` 改名，因为那个名字会让调用点以为拿到了材质。
    /// 它照旧只在卡里用（规则 ②）。
    var subtle: Bool

    init(padding: CGFloat, radius: CGFloat, subtle: Bool) {
        self.padding = padding
        self.radius = radius
        self.subtle = subtle
    }

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    // 两档底：`subtle` = 更浅的那一档（输入框 / 未选中的底），否则是分组面。
                    // 「分组面」这一档已从 `nightSurface`（不透明）换成 `panel`（半透明），
                    // 理由见 `TokensPalette.panel` —— 卡里那层底不能是不透明的。
                    .fill(subtle ? TokensPalette.fillSubtle : TokensPalette.panel)
            }
    }
}

extension View {
    /// 分组表面外观
    func dsSurface(padding: CGFloat = TokensSpacing.md,
                   radius: CGFloat = TokensRadius.medium,
                   subtle: Bool = false) -> some View {
        modifier(DSSurfaceModifier(padding: padding, radius: radius, subtle: subtle))
    }
}

// 【已删】全页「纸」外壳三件套：`dsPaperPage()` / `DSPaperPageModifier` / `DSPaperPage`
//（2026-09-25）。它们的用法只有两个：「体检」与「保养」那两张卡的内容
//（`HealthDataView` / `MaintenanceMoneyView`）—— 那两个视图当初是页面，后来被挂进
// 车卡里，页面壳没拆。叠进卡里的代价是可算的，而且三样都看得见：
//   ① 第二层 `ScrollView`：里外两层都能滚时竖直拖动归内层，而内层拿到的是无限高，
//      它自己永远滚不动，只是把那一块区域的拖动吃掉（写这段话时叠叠乐还是自管手势，
//      现在是系统 `ScrollView` —— 结论不变：卡里再套一层滚动，这一块就滚不动了）；
//   ② 第二层纸面底 + 它自己的左右 16pt：叠在卡片的 18pt 上 = 内容距卡边 34pt；
//   ③ 一行页标题（「体检与数据」）：而卡片头已经写着「体检」。
// 拆完之后三件套零引用，所以整段删掉 —— 留着它就是「一件已经没有人用的东西」，
// 而下一个要写页面的人会拿它当模板。

