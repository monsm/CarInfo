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

// MARK: - 动态色（浅/深色两套，跟随系统外观）

extension UIColor {
    static func dsDynamic(light: UIColor, dark: UIColor) -> UIColor {
        UIColor { traits in traits.userInterfaceStyle == .dark ? dark : light }
    }
}

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

/// 分组表面：iOS inset-grouped 的卡片面。不透明、无描边、无阴影。
/// 只有需要"把一组行框在一起"时才用它；单条信息直接落在画布上用发丝线分隔。
struct DSCard<Content: View>: View {
    var padding: CGFloat
    var radius: CGFloat
    var glass: Bool
    var hero: Bool
    var content: () -> Content

    init(padding: CGFloat = TokensSpacing.md,
         radius: CGFloat = TokensRadius.medium,
         glass: Bool = false,
         hero: Bool = false,
         @ViewBuilder content: @escaping () -> Content) {
        self.padding = padding
        self.radius = radius
        self.glass = glass
        self.hero = hero
        self.content = content
    }

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(TokensPalette.nightSurface)
            }
            // 艺术方向下给卡片一条发丝描边：纸与墨的语言里，「一块面」是靠线画出来的。
            // 原生主题不加（原生 = 现状）。这一处一改，全 App 的卡片同时变。
            .overlay {
                if TokensPalette.decor != .none {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(TokensPalette.hairline, lineWidth: TokensHair.line)
                }
            }
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
            .fill(TokensPalette.glassBorder)
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
            VStack(spacing: 0) { content() }
                .background {
                    RoundedRectangle(cornerRadius: TokensRadius.medium, style: .continuous)
                        .fill(TokensPalette.nightSurface)
                }
                // 裁剪掉圆角：行的按压底色是矩形，不裁会在分组四角露出方角
                .clipShape(RoundedRectangle(cornerRadius: TokensRadius.medium, style: .continuous))
                // 艺术方向下分组也要有线（与 DSCard 同一规则，原生不加）
                .overlay {
                    if TokensPalette.decor != .none {
                        RoundedRectangle(cornerRadius: TokensRadius.medium, style: .continuous)
                            .strokeBorder(TokensPalette.hairline, lineWidth: TokensHair.line)
                    }
                }
            if let footer {
                Text(footer)
                    .font(TokensTypo.footnote)
                    .foregroundStyle(TokensPalette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
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
        HStack(alignment: .firstTextBaseline, spacing: TokensSpacing.md) {
            Text(key)
                .font(TokensTypo.subheadline)
                .foregroundStyle(TokensPalette.primary)
                .lineLimit(2)
            Spacer(minLength: TokensSpacing.sm)
            Text(value)
                .font(mono ? TokensTypo.dataSmall : TokensTypo.subheadline)
                .foregroundStyle(valueCls == "na" ? TokensPalette.secondary : TokensPalette.statusColor(valueCls))
                .multilineTextAlignment(.trailing)
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
    var title: String
    var trailing: String? = nil
    /// 不为 "na" 时用 `DSChip`（一个语义圆点 + 颜色）代替灰字。
    var trailingCls: String = "na"
    var action: (() -> Void)? = nil

    var body: some View {
        // 分组标题是全 App 最密集的一行字（~28 屏都在用它）：
        // 它一换成衬线 + 疏排，整套界面的语气就从「App」变成「印刷物」。
        // 原生主题下 `TokensSerif.section` 返回系统字，所以原生 = 现状。
        HStack(alignment: .firstTextBaseline) {
            Text(title.uppercased())
                .font(TokensSerif.section(13))
                .tracking(TokensTracking.label)
                .foregroundStyle(TokensPalette.secondary)
            Spacer(minLength: TokensSpacing.sm)
            if let trailing {
                if let action {
                    Button(trailing, action: action)
                        .font(TokensTypo.footnote)
                        .foregroundStyle(TokensPalette.ambient)
                        .buttonStyle(.plain)
                } else if trailingCls != "na" {
                    DSChip(text: trailing, cls: trailingCls)
                } else {
                    Text(trailing)
                        .font(TokensTypo.footnote)
                        .foregroundStyle(TokensPalette.tertiary)
                }
            }
        }
        .padding(.bottom, 6)
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

    var body: some View {
        VStack(alignment: alignment, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(TokensTypo.display(size))
                    // 字距 = 按字号算的基准 + 主题的额外收紧。
                    // 原生主题的额外量为 0，所以切换前是什么样现在还是什么样；
                    // 「巨字」方向靠这一项把超大数字收成一整块（海报的做法）。
                    .tracking(-size * 0.035 + TokensTypo.displayTracking)
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

/// 页面大标题（**艺术方向下才有**）：导航栏的字体改不了（系统字体），
/// 所以「标题的字体」只能画在内容里 —— 这既是代价也是印刷物的做法：
/// 标题属于版面，不属于系统栏。
///
/// 它必须与 `dsPageTitle` **成套**：后者在艺术方向下把导航栏清空，这一支把标题补进版面。
/// 原生主题下这里什么也不画 —— 否则同一句话会说两遍
/// （导航栏的大标题 + 内容里的大标题），那不是「原生等于现状」。
struct DSPageTitle: View {
    var title: String
    var subtitle: String? = nil

    @ViewBuilder
    var body: some View {
        if TokensPalette.decor == .none {
            EmptyView()
        } else {
            artBody
        }
    }

    private var artBody: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(TokensSerif.page(30))
                .tracking(TokensTracking.title)
                .foregroundStyle(TokensPalette.primary)
            if let subtitle {
                Text(subtitle)
                    .font(TokensTypo.caption)
                    .tracking(TokensTracking.label)
                    .foregroundStyle(TokensPalette.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityAddTraits(.isHeader)
    }
}

extension View {
    /// 页面标题的两种活法：
    ///   原生      = iOS 大标题留在导航栏（逐像素等于切换前的现状）
    ///   艺术方向  = 导航栏清空，大标题搬进版面（衬线 + 疏排）
    /// 它必须与 `DSPageTitle` **成套**出现：只清导航栏不补内容，那一屏就没标题了。
    /// `inline: true` = 原生下也用行内标题（有些页面本来就一直用行内标题 ——
    /// 原生必须逐像素等于切换前的现状，所以那个选择要保留）。
    func dsPageTitle(_ title: String, inline: Bool = false) -> some View {
        if TokensPalette.decor == .none {
            return AnyView(navigationTitle(title)
                .navigationBarTitleDisplayMode(inline ? .inline : .large))
        }
        return AnyView(navigationTitle("").navigationBarTitleDisplayMode(.inline))
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
                        .fill(TokensPalette.glassBorder)
                        .frame(width: TokensHair.line)
                        .frame(maxHeight: .infinity)
                }
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 4) {
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
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
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
        HStack(spacing: 6) {
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
            Text(label)
                .font(TokensTypo.body)
                .foregroundStyle(TokensPalette.primary)
            Spacer(minLength: TokensSpacing.md)
            Text(value)
                .font(TokensTypo.data)
                .foregroundStyle(valueCls == "na" ? TokensPalette.secondary : TokensPalette.statusColor(valueCls))
                .multilineTextAlignment(.trailing)
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
                    .fill(TokensPalette.nightSurface)
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
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(TokensMotion.press, value: configuration.isPressed)
    }
}

/// 次操作按钮：iOS 的"灰色胶囊"
struct DSSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TokensTypo.headline)
            .foregroundStyle(TokensPalette.primary)
            .frame(maxWidth: .infinity)
            .frame(height: TokensSize.button)
            .background(Capsule().fill(TokensPalette.glassLight))
            .opacity(configuration.isPressed ? 0.65 : 1)
            .animation(TokensMotion.press, value: configuration.isPressed)
    }
}


/// 分段控件：系统分段控件的观感（填充底 + 白色滑块），不自造圆角
struct DSSegmented<T: Hashable>: View {
    var options: [(value: T, title: String)]
    @Binding var selection: T

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let selected = option.value == selection
                Button {
                    withAnimation(TokensMotion.value) { selection = option.value }
                } label: {
                    Text(option.title)
                        .font(TokensTypo.subheadline.weight(selected ? .semibold : .regular))
                        .foregroundStyle(TokensPalette.primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(TokensPalette.nightSurface)
                                    .shadow(color: TokensPalette.scrim.opacity(0.12), radius: 3, y: 1)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(TokensPalette.glassLight))
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
            .fill(TokensPalette.nightSurface))
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
                        .font(TokensSerif.section(13))
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
                .padding(.bottom, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(title))
            .accessibilityValue(Text(expanded ? "已展开" : "已收起"))

            if expanded {
                VStack(spacing: 0) { content() }
                    .background {
                        RoundedRectangle(cornerRadius: TokensRadius.medium, style: .continuous)
                            .fill(TokensPalette.nightSurface)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: TokensRadius.medium, style: .continuous))
                    .overlay {
                        if TokensPalette.decor != .none {
                            RoundedRectangle(cornerRadius: TokensRadius.medium, style: .continuous)
                                .strokeBorder(TokensPalette.hairline, lineWidth: TokensHair.line)
                        }
                    }
            }

            if let footer {
                Text(footer)
                    .font(TokensTypo.footnote)
                    .foregroundStyle(TokensPalette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
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
                        .font(TokensSerif.section(13))
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
                .padding(.bottom, 6)
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
                    .padding(.top, 6)
            }
        }
    }
}

struct DSSurfaceModifier: ViewModifier {
    var padding: CGFloat
    var radius: CGFloat
    var glass: Bool

    init(padding: CGFloat, radius: CGFloat, glass: Bool) {
        self.padding = padding
        self.radius = radius
        self.glass = glass
    }

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(glass ? TokensPalette.glassLight : TokensPalette.nightSurface)
            }
            .overlay {
                if TokensPalette.decor != .none {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(TokensPalette.hairline, lineWidth: TokensHair.line)
                }
            }
    }
}

extension View {
    /// 分组表面外观
    func dsSurface(padding: CGFloat = TokensSpacing.md,
                   radius: CGFloat = TokensRadius.medium,
                   glass: Bool = false) -> some View {
        modifier(DSSurfaceModifier(padding: padding, radius: radius, glass: glass))
    }

    /// 全页「纸」外壳：深潜页的统一容器，与地图主屏的 bottomPanel 视觉同源。
    ///
    /// 用法：把整页内容（ScrollView / VStack）包进 `DSPaperPage`，
    /// 顶部圆角 + 纸面填充 + hairline 顶边，和地图底部那张纸长得一样。
    /// 这是「地图是家、深潜页是从纸上抽出来展开的那张纸」的语言落地。
    func dsPaperPage() -> some View {
        modifier(DSPaperPageModifier())
    }
}

// 为什么不给这张纸做「已在大卡里就少画一层」的开关（曾经想用自定义 EnvironmentKey）：
//   ① 门禁 `scan.py` 只认显式核实过的 SDK 名字，`EnvironmentKey` 不在里面 ——
//      为一个视觉开关去扩白名单，是拿一个真实的编译验证换一个观感上的细节；
//   ② 而且没必要：大卡与这张纸**填的是同一个 `TokensPalette.surface`**，
//      两层叠在一起只会多出一条发丝线（就在模式条下方）—— 那条线反而有用，
//      它把「切换器」与「切换出来的内容」分开。
struct DSPaperPageModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, TokensSpacing.md)
            .padding(.top, TokensSpacing.md)
            .padding(.bottom, TokensSpacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                UnevenRoundedRectangle(
                    topLeadingRadius: TokensRadius.large,
                    topTrailingRadius: TokensRadius.large,
                    style: .continuous
                )
                .fill(TokensPalette.surface)
                .ignoresSafeArea(edges: .top)
            }
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(TokensPalette.hairline)
                    .frame(height: TokensHair.line)
            }
    }
}

/// 全页「纸」外壳的显式容器版本（比 modifier 更直观，也方便加标题）。
struct DSPaperPage<Content: View>: View {
    var content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) { content() }
                .dsPaperPage()
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

