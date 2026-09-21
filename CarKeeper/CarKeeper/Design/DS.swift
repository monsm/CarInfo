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
//   ④ 玻璃只出现在「浮在内容之上」的层：导航栏、Tab 栏、弹层、底部操作条。
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

enum DS {

    // =========================================================================
    // MARK: 1. 色彩（Palette）— 全部使用 iOS 系统色真值
    // =========================================================================
    enum Palette {
        /// 页面画布：systemGroupedBackground（亮 #F2F2F7 / 暗 #000）
        /// ⚠️ 值与小组件/实时活动共用同一份（WT.Palette）——
        /// 见 Shared/WidgetTokens.swift 顶部：改一个数，App 与小组件同时改，不可能漂移。
        static let canvas = WT.Palette.canvas

        /// 一级分组表面：secondarySystemGroupedBackground（亮 #FFF / 暗 #1C1C1E）
        /// 这是 iOS inset-grouped 的卡片面，和画布永远成对出现。
        static let surface = WT.Palette.surface
        /// 二级表面：tertiarySystemGroupedBackground（暗 #2C2C2E）
        static let surfaceRaised = Color(uiColor: UIColor.tertiarySystemGroupedBackground)
        /// 下沉表面：输入框、分段控件底、进度槽
        static let surfaceSunken = Color(uiColor: UIColor.tertiarySystemFill)

        /// 发丝分隔线：UIColor.separator 的真值
        /// 亮色 rgba(60,60,67,.29) / 暗色 rgba(84,84,88,.65)
        static let hairline = WT.Palette.hairline
        /// 不透明分隔线：UIColor.opaqueSeparator（亮 #C6C6C8 / 暗 #38383A）
        static let hairlineStrong = Color(uiColor: UIColor.opaqueSeparator)
        /// 光条 / 进度轨道（quarterLabel）
        static let track = WT.Palette.track
        /// 通用填充（图标底、层高块）
        static let fill = Color(uiColor: UIColor.tertiarySystemFill)
        static let fillSubtle = Color(uiColor: UIColor.quaternarySystemFill)

        // ---- 文字：只有三档不透明度（label / 60% / 30%）----
        static let label = WT.Palette.label
        static let labelSecondary = WT.Palette.labelSecondary
        static let labelTertiary = WT.Palette.labelTertiary
        static let labelQuaternary = Color(uiColor: .quaternaryLabel)
        static let labelOnTint = Color.white

        // ---- 强调色（全局唯一）：iOS 系统蓝 ----
        static let tint = WT.Palette.tint
        static let tintSoft = Color(uiColor: UIColor.dsDynamic(
            light: UIColor(red: 0.000, green: 0.478, blue: 1.000, alpha: 0.12),
            dark: UIColor(red: 0.039, green: 0.518, blue: 1.000, alpha: 0.18)
        ))

        // ---- 语义状态色：唯一的"彩色"来源，全部系统色 ----
        static let ok = WT.Palette.ok          // #34C759 / #30D158
        static let warn = WT.Palette.warn      // #FF9500 / #FF9F0A
        static let bad = WT.Palette.bad        // #FF3B30 / #FF453A
        /// 充电 / 电驱状态（EV 语义，不等于 ok）
        static let charge = WT.Palette.charge

        // ---- 车灯光带用的渐变（白 → 浅蓝 → 系统蓝），只出现在"电量就是光"的地方 ----
        static let lightBar = WT.Palette.lightBar

        // ---- 兼容旧成员：现在是平坦画布（v4 只有一个画布，没有气氛渐变）----
        static let canvasGradient = LinearGradient(
            colors: [canvas, canvas], startPoint: .top, endPoint: .bottom
        )
        /// Hero 旧成员：不再是深色"驾驶舱"，回归分组表面（v4 没有 hero 卡片）
        static let heroFill = LinearGradient(
            colors: [surface, surface], startPoint: .topLeading, endPoint: .bottomTrailing
        )
        static let onHero = Color(uiColor: .label)
        static let onHeroSecondary = Color(uiColor: .secondaryLabel)
        static let onHeroTertiary = Color(uiColor: .tertiaryLabel)
        static let onHeroLine = Color(uiColor: UIColor.separator)

        /// 深色表面上的语义色版本（用在车灯/深色示意面上）
        static func statusOnDark(_ cls: String) -> Color {
            switch cls {
            case "ok", "normal": return Color(red: 0.290, green: 0.851, blue: 0.392)
            case "warn", "warning": return Color(red: 1.000, green: 0.722, blue: 0.192)
            case "bad", "fault", "abnormal", "danger": return Color(red: 1.000, green: 0.380, blue: 0.341)
            case "charge", "charging": return Color(red: 0.290, green: 0.898, blue: 0.831)
            case "na": return Color.white.opacity(0.55)
            default: return Color(red: 0.420, green: 0.651, blue: 1.000)
            }
        }

        /// 状态字符串 → 颜色
        static func status(_ cls: String) -> Color {
            switch cls {
            case "ok", "normal": return ok
            case "warn", "warning": return warn
            case "bad", "fault", "abnormal", "danger": return bad
            case "charge", "charging": return charge
            case "acc", "accent": return tint
            default: return labelSecondary
            }
        }
    }

    // =========================================================================
    // MARK: 2. 字体（Typo）— iOS 真实字号阶梯
    // =========================================================================
    enum Typo {
        // ---- 仪表数字：超细字重 + 等宽数字（换数不跳动）----
        /// 超大数字（首屏 SOC / 关键指标）：字重 100 是"仪器感"的来源
        static func display(_ size: CGFloat = 72) -> Font {
            .system(size: size, weight: .ultraLight).monospacedDigit()
        }
        /// 中等数字（页面头部大数值）
        static func metric(_ size: CGFloat = 34) -> Font {
            .system(size: size, weight: .light).monospacedDigit()
        }
        /// 行内数字（列表数值，iOS 正文尺寸）
        static let data = Font.system(size: 17).monospacedDigit()
        static let dataSmall = Font.system(size: 15).monospacedDigit()
        /// 指定尺寸的等宽数字：图例、次要读数这类"比 dataSmall 还要小但必须等宽"的地方。
        /// ⚠️ data / dataSmall 是**属性**（固定尺寸），digits 是**函数**（带尺寸参数）——
        /// 写成 DS.Typo.data(13) 会编译报错（cannot call value of non-function type 'Font'）。
        static func digits(_ size: CGFloat) -> Font {
            .system(size: size).monospacedDigit()
        }

        // ---- 文本：系统语义样式 → 自动跟随 Dynamic Type ----
        static let largeTitle = Font.largeTitle.weight(.bold)      // 34 / 700
        static let title = Font.title.weight(.semibold)            // 28 / 600
        static let title2 = Font.title2.weight(.semibold)          // 22 / 600
        static let title3 = Font.title3.weight(.semibold)          // 20 / 600
        static let headline = Font.headline                        // 17 / 600
        static let body = Font.body                                // 17 / 400
        static let callout = Font.callout                          // 16
        static let subheadline = Font.subheadline                  // 15
        static let footnote = Font.footnote                        // 13
        static let caption = Font.caption                          // 12
        static let caption2 = Font.caption2                        // 11

        /// 分组标题（iOS 的 section header：13pt、二级灰、大写由视图层加）
        static let sectionLabel = Font.footnote
    }

    // =========================================================================
    // MARK: 3. 网格
    // =========================================================================
    enum Space {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
        static let xxxl: CGFloat = 32
        static let huge: CGFloat = 44

        /// 页面左右边距（v4：20pt）
        static let page: CGFloat = 20
        /// 分组之间
        static let gap: CGFloat = 26
        /// 分组内部（inset-grouped 表面内边距）
        static let cardPadding: CGFloat = 16
        /// 行高（HIG 最小触控目标）
        static let row: CGFloat = 44
    }

    // =========================================================================
    // MARK: 4. 圆角（只有三档 + 胶囊）
    // =========================================================================
    enum Radius {
        static let small: CGFloat = 8     // 小控件、输入
        static let card: CGFloat = 12     // inset-grouped 表面
        static let hero: CGFloat = 20     // 弹层、大面板
        static let capsule: CGFloat = 999
    }

    enum Hair {
        /// 发丝线（iOS 分隔线厚度）
        static let line: CGFloat = 0.5
        static let border: CGFloat = 1
        /// 分隔线内缩（与行内容左对齐）
        static let inset: CGFloat = 16
    }

    // =========================================================================
    // MARK: 5. 动效（只服务状态变化）
    // =========================================================================
    enum Motion {
        static let press = Animation.spring(response: 0.30, dampingFraction: 0.86)
        static let value = Animation.spring(response: 0.36, dampingFraction: 0.88)
        static let screen = Animation.spring(response: 0.42, dampingFraction: 0.90)
        static let fade = Animation.easeOut(duration: 0.20)
        /// 一次性绘制（光条从 0 长到位）
        static let draw = Animation.easeOut(duration: 1.1)
    }

    // =========================================================================
    // MARK: 6. 尺寸
    // =========================================================================
    enum Size {
        static let tap: CGFloat = 44
        /// 主按钮（iOS 实心胶囊）
        static let button: CGFloat = 50
        static let iconSm: CGFloat = 13
        static let icon: CGFloat = 17
        static let iconLg: CGFloat = 22
        static let tileIcon: CGFloat = 22
        /// 行内图标列宽（iOS 设置行）
        static let iconColumn: CGFloat = 29
        static let barHeight: CGFloat = 56
    }

    // =========================================================================
    // MARK: 7. 阴影 —— v4 的内容层没有阴影（深度由系统表面色表达）
    // =========================================================================
    enum Elev {
        static let card = Color.clear
        static let cardFar = Color.clear
        static let hero = Color.clear
    }
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
            KanseiPalette.background.ignoresSafeArea()
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

    init(padding: CGFloat = DS.Space.cardPadding,
         radius: CGFloat = DS.Radius.card,
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
                    .fill(KanseiPalette.nightSurface)
            }
    }
}

/// 可点击卡片
struct DSCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.55 : 1)
            .animation(DS.Motion.press, value: configuration.isPressed)
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
            .fill(KanseiPalette.glassBorder)
            .frame(height: DS.Hair.line)
            .padding(.leading, inset)
    }
}

/// 行内分隔线（内缩 16，与 DSRow 的内容左对齐）
struct DSSeparator: View {
    var inset: CGFloat = DS.Hair.inset
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
    var footer: String? = nil
    var onTrailingTap: (() -> Void)? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                DSSectionHeader(title: title, trailing: trailing, action: onTrailingTap)
            }
            VStack(spacing: 0) { content() }
                .background {
                    RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                        .fill(KanseiPalette.nightSurface)
                }
                // 裁剪掉圆角：行的按压底色是矩形，不裁会在分组四角露出方角
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            if let footer {
                Text(footer)
                    .font(DS.Typo.footnote)
                    .foregroundStyle(KanseiPalette.secondary)
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
                .padding(.horizontal, DS.Space.cardPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: DS.Space.row)
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
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.md) {
            Text(key)
                .font(DS.Typo.subheadline)
                .foregroundStyle(KanseiPalette.primary)
                .lineLimit(2)
            Spacer(minLength: DS.Space.sm)
            Text(value)
                .font(mono ? DS.Typo.dataSmall : DS.Typo.subheadline)
                .foregroundStyle(valueCls == "na" ? KanseiPalette.secondary : KanseiPalette.statusColor(valueCls))
                .multilineTextAlignment(.trailing)
                .layoutPriority(1)
        }
        .frame(minHeight: DS.Space.row)
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
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title.uppercased())
                .font(DS.Typo.footnote)
                .tracking(0.2)
                .foregroundStyle(KanseiPalette.secondary)
            Spacer(minLength: DS.Space.sm)
            if let trailing {
                if let action {
                    Button(trailing, action: action)
                        .font(DS.Typo.footnote)
                        .foregroundStyle(KanseiPalette.ambient)
                        .buttonStyle(.plain)
                } else {
                    Text(trailing)
                        .font(DS.Typo.footnote)
                        .foregroundStyle(KanseiPalette.tertiary)
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
    var tint: Color = KanseiPalette.primary
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        VStack(alignment: alignment, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(DS.Typo.display(size))
                    .tracking(-size * 0.035)
                    .foregroundStyle(tint)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let unit {
                    Text(unit)
                        .font(DS.Typo.metric(size * 0.30))
                        .foregroundStyle(KanseiPalette.secondary)
                }
            }
            if let caption {
                Text(caption)
                    .font(DS.Typo.footnote)
                    .foregroundStyle(KanseiPalette.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// 关键指标（兼容旧名 DSMetric，渲染同 DSBigNumber）
struct DSMetric: View {
    var value: String
    var unit: String? = nil
    var caption: String? = nil
    var size: CGFloat = 72
    var tint: Color = KanseiPalette.primary
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
                    .fill(DS.Palette.track)
                    .frame(height: height)
                if showsGlow && w > 1 {
                    Capsule()
                        .fill(tint ?? DS.Palette.lightBar)
                        .frame(width: w, height: height)
                        .blur(radius: 9)
                        .opacity(0.75)
                }
                Capsule()
                    .fill(tint ?? DS.Palette.lightBar)
                    .frame(width: w, height: height)
            }
            .frame(height: height)
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .frame(height: height)
        .onAppear {
            withAnimation(DS.Motion.draw) { revealed = clamped }
        }
        .onChange(of: clamped) { _, newValue in
            withAnimation(DS.Motion.value) { revealed = newValue }
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
                        .fill(KanseiPalette.glassBorder)
                        .frame(width: DS.Hair.line)
                        .frame(maxHeight: .infinity)
                }
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 4) {
                        if let icon = item.icon {
                            Image(safeSymbol: icon, fallback: "circle")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        Text(item.label)
                            .lineLimit(1)
                    }
                    .font(DS.Typo.caption)
                    .foregroundStyle(KanseiPalette.secondary)
                    Text(item.value)
                        .font(DS.Typo.data)
                        .foregroundStyle(item.cls == "na" ? KanseiPalette.primary : KanseiPalette.statusColor(item.cls))
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

    private var color: Color { KanseiPalette.statusColor(cls) }

    var body: some View {
        HStack(spacing: 6) {
            if let icon {
                Image(safeSymbol: icon, fallback: "circle.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(color)
            } else {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
            }
            Text(text)
                .font(DS.Typo.footnote)
                .foregroundStyle(cls == "na" ? KanseiPalette.secondary : color)
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
        HStack(spacing: DS.Space.sm) {
            if let icon {
                Image(safeSymbol: icon, fallback: "circle")
                    .font(.system(size: DS.Size.iconSm))
                    .foregroundStyle(KanseiPalette.secondary)
                    .frame(width: 20)
            }
            Text(label)
                .font(DS.Typo.body)
                .foregroundStyle(KanseiPalette.primary)
            Spacer(minLength: DS.Space.md)
            Text(value)
                .font(DS.Typo.data)
                .foregroundStyle(valueCls == "na" ? KanseiPalette.secondary : KanseiPalette.statusColor(valueCls))
                .multilineTextAlignment(.trailing)
        }
        .frame(minHeight: DS.Space.row)
        .accessibilityElement(children: .combine)
    }
}

/// 紧凑指标（栏内两/三列）：大号超细数字在上、小号灰标签在下
struct DSStatTile: View {
    var label: String
    var value: String
    var unit: String? = nil
    var cls: String = "na"
    var icon: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(DS.Typo.metric(28))
                    .foregroundStyle(cls == "na" ? KanseiPalette.primary : KanseiPalette.statusColor(cls))
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let unit {
                    Text(unit)
                        .font(DS.Typo.caption)
                        .foregroundStyle(KanseiPalette.secondary)
                }
            }
            HStack(spacing: 4) {
                if let icon {
                    Image(safeSymbol: icon, fallback: "circle")
                        .font(.system(size: 10))
                }
                Text(label)
                    .lineLimit(1)
            }
            .font(DS.Typo.caption)
            .foregroundStyle(KanseiPalette.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        HStack(spacing: DS.Space.md) {
            if let icon {
                Image(safeSymbol: icon, fallback: "circle")
                    .font(.system(size: DS.Size.icon))
                    .foregroundStyle(KanseiPalette.ambient)
                    .frame(width: DS.Size.iconColumn, alignment: .center)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(DS.Typo.body)
                    .foregroundStyle(KanseiPalette.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(DS.Typo.footnote)
                        .foregroundStyle(KanseiPalette.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: DS.Space.sm)
            if let value {
                Text(value)
                    .font(DS.Typo.data)
                    .foregroundStyle(valueCls == "na" ? KanseiPalette.secondary : KanseiPalette.statusColor(valueCls))
                    .multilineTextAlignment(.trailing)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(KanseiPalette.tertiary)
            }
        }
        .frame(minHeight: DS.Space.row)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct DSRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? KanseiPalette.fillSubtle : Color.clear)
            .animation(DS.Motion.press, value: configuration.isPressed)
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
        isActive ? KanseiPalette.statusColor(cls) : KanseiPalette.primary
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: DS.Space.sm) {
                HStack(alignment: .center) {
                    Image(safeSymbol: icon, fallback: "circle")
                        .font(.system(size: DS.Size.tileIcon, weight: .regular))
                        .foregroundStyle(accent)
                    Spacer(minLength: 0)
                    if isLoading {
                        ProgressView().controlSize(.small)
                    }
                }
                Text(title)
                    .font(DS.Typo.body)
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let subtitle {
                    Text(subtitle)
                        .font(DS.Typo.footnote)
                        .foregroundStyle(KanseiPalette.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DS.Space.lg)
            .frame(minHeight: 84, alignment: .topLeading)
            .background {
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .fill(KanseiPalette.nightSurface)
            }
        }
        .buttonStyle(DSCardButtonStyle())
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(isActive ? "已开启" : "已关闭"))
    }
}

/// 主操作按钮（一屏最多一个）：实心胶囊
struct DSPrimaryButtonStyle: ButtonStyle {
    var tint: Color = KanseiPalette.ambient

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DS.Typo.headline)
            .foregroundStyle(DS.Palette.labelOnTint)
            .frame(maxWidth: .infinity)
            .frame(height: DS.Size.button)
            .background(Capsule().fill(tint))
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(DS.Motion.press, value: configuration.isPressed)
    }
}

/// 次操作按钮：iOS 的"灰色胶囊"
struct DSSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DS.Typo.headline)
            .foregroundStyle(KanseiPalette.primary)
            .frame(maxWidth: .infinity)
            .frame(height: DS.Size.button)
            .background(Capsule().fill(KanseiPalette.glassLight))
            .opacity(configuration.isPressed ? 0.65 : 1)
            .animation(DS.Motion.press, value: configuration.isPressed)
    }
}

/// 图标按钮（导航栏、行尾）
struct DSIconButtonStyle: ButtonStyle {
    var size: CGFloat = DS.Size.tap
    var tint: Color = KanseiPalette.primary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: DS.Size.iconLg))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(Circle().fill(configuration.isPressed ? KanseiPalette.glassLight : Color.clear))
            .contentShape(Circle())
            .animation(DS.Motion.press, value: configuration.isPressed)
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
                    withAnimation(DS.Motion.value) { selection = option.value }
                } label: {
                    Text(option.title)
                        .font(DS.Typo.subheadline.weight(selected ? .semibold : .regular))
                        .foregroundStyle(KanseiPalette.primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(KanseiPalette.nightSurface)
                                    .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(KanseiPalette.glassLight))
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
        HStack(spacing: DS.Space.sm) {
            Image(safeSymbol: kind.icon, fallback: "info.circle.fill")
                .font(.system(size: 15))
                .foregroundStyle(KanseiPalette.statusColor(kind.cls))
            Text(text)
                .font(DS.Typo.footnote)
                .foregroundStyle(KanseiPalette.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: DS.Space.sm)
            if let action {
                Button(action.title, action: action.run)
                    .font(DS.Typo.footnote.weight(.semibold))
                    .foregroundStyle(KanseiPalette.ambient)
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, DS.Space.md)
        .padding(.vertical, DS.Space.sm)
        .background(RoundedRectangle(cornerRadius: DS.Radius.small, style: .continuous)
            .fill(KanseiPalette.nightSurface))
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
        VStack(spacing: DS.Space.md) {
            Image(safeSymbol: icon, fallback: "questionmark.circle")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(cls == "na" ? KanseiPalette.tertiary : KanseiPalette.statusColor(cls))
            Text(title)
                .font(DS.Typo.headline)
                .foregroundStyle(KanseiPalette.primary)
                .multilineTextAlignment(.center)
            if let message {
                Text(message)
                    .font(DS.Typo.footnote)
                    .foregroundStyle(KanseiPalette.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(DSSecondaryButtonStyle())
                    .frame(maxWidth: 220)
            }
        }
        .padding(.vertical, DS.Space.xxxl)
        .padding(.horizontal, DS.Space.xl)
        .frame(maxWidth: .infinity)
    }
}

/// 加载占位（静态：加载本身由 ProgressView 表达，占位块不做动画）
struct DSSkeleton: View {
    var height: CGFloat = 16
    var width: CGFloat? = nil

    var body: some View {
        RoundedRectangle(cornerRadius: DS.Radius.small, style: .continuous)
            .fill(KanseiPalette.fillSubtle)
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

extension View {
    /// 分组表面外观
    func dsSurface(padding: CGFloat = DS.Space.cardPadding,
                   radius: CGFloat = DS.Radius.card,
                   glass: Bool = false) -> some View {
        modifier(DSSurfaceModifier(padding: padding, radius: radius, glass: glass))
    }
}

struct DSSurfaceModifier: ViewModifier {
    var padding: CGFloat
    var radius: CGFloat
    var glass: Bool

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(glass ? AnyShapeStyle(.ultraThinMaterial)
                                : AnyShapeStyle(DS.Palette.surface))
            }
    }
}

enum DSHaptic {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func result(_ success: Bool) { 
    UINotificationFeedbackGenerator().notificationOccurred(success ? .success : .error) }
    static func select() { UISelectionFeedbackGenerator().selectionChanged() }
}

