import SwiftUI
import UIKit

// =============================================================================
//  DS — CarKeeper Design System v2
// =============================================================================
//  设计语言：「Tesla 式结构 + iOS 27 Liquid Glass 材质」
//
//  取舍（与旧版最大的区别：旧版的视觉元素一个都不保留）：
//   • 结构上是 Tesla 的：单一画布、信息优先、巨大的数字、发丝分隔线、
//     4pt 网格、单一强调色、状态只靠语义色表达（绿/橙/红），不用渐变讲气氛。
//   • 材质上是 iOS 27 的：只有「浮在内容之上」的层（导航栏、底部操作条、弹层、
//     悬浮按钮）使用 Liquid Glass 材质；内容卡片一律不透明。
//   • 两条硬规则：
//     ① 动效只服务状态变化（数值变化、展开、推进），不做任何常驻播放的无限动画；
//     ② 点击只允许「内容自身形变」这一种反馈，不允许出现任何覆盖在内容上的图形。
//     ✗ emoji 当图标                        ✗ 满屏玻璃卡片（玻璃到处用=没有层级）
//
//  用法约定：新代码只用 DS.*；Theme 里的历史 token 已全部转接到 DS，
//  因此老页面也会立刻继承这套视觉，不需要逐个文件改。
// =============================================================================

// MARK: - 动态色（浅/深色两套，跟随系统外观）

extension UIColor {
    static func dsDynamic(light: UIColor, dark: UIColor) -> UIColor {
        UIColor { traits in traits.userInterfaceStyle == .dark ? dark : light }
    }
}

enum DS {

    // =========================================================================
    // MARK: 1. 色彩（Palette）
    // =========================================================================
    enum Palette {
        /// 页面画布：中性冷灰/近黑，不用系统蓝灰底（那是 iOS 默认，不是品牌）
        static let canvas = Color(uiColor: .dsDynamic(
            light: UIColor(white: 0.949, alpha: 1),          // #F2F2F3
            dark: UIColor(white: 0.043, alpha: 1)            // #0B0B0B
        ))
        /// 一级表面：内容卡片（不透明，保证文字对比度）
        static let surface = Color(uiColor: .dsDynamic(
            light: .white,
            dark: UIColor(white: 0.098, alpha: 1)            // #191919
        ))
        /// 二级表面：卡片内嵌的分组 / 可点击行
        static let surfaceRaised = Color(uiColor: .dsDynamic(
            light: UIColor(white: 0.965, alpha: 1),
            dark: UIColor(white: 0.137, alpha: 1)            // #232323
        ))
        /// 三级表面：输入框、进度槽
        static let surfaceSunken = Color(uiColor: .dsDynamic(
            light: UIColor(white: 0.925, alpha: 1),
            dark: UIColor(white: 0.078, alpha: 1)            // #141414
        ))
        /// 发丝线（0.5pt）：分隔线与卡片描边
        static let hairline = Color(uiColor: .dsDynamic(
            light: UIColor(white: 0, alpha: 0.10),
            dark: UIColor(white: 1, alpha: 0.10)
        ))
        static let hairlineStrong = Color(uiColor: .dsDynamic(
            light: UIColor(white: 0, alpha: 0.18),
            dark: UIColor(white: 1, alpha: 0.18)
        ))

        // ---- 文字（用系统语义色，保证 Dynamic Type / 对比度合规）----
        static let label = Color(uiColor: .label)
        static let labelSecondary = Color(uiColor: .secondaryLabel)
        static let labelTertiary = Color(uiColor: .tertiaryLabel)
        static let labelOnTint = Color.white

        // ---- 强调色（单一）：仅用于可交互主色与关键数据 ----
        static let tint = Color(uiColor: .dsDynamic(
            light: UIColor(red: 0.110, green: 0.298, blue: 0.839, alpha: 1),  // #1C4CD6
            dark: UIColor(red: 0.302, green: 0.549, blue: 1.000, alpha: 1)     // #4D8CFF
        ))
        static let tintSoft = Color(uiColor: .dsDynamic(
            light: UIColor(red: 0.110, green: 0.298, blue: 0.839, alpha: 0.10),
            dark: UIColor(red: 0.302, green: 0.549, blue: 1.000, alpha: 0.16)
        ))

        // ---- 语义状态色：唯一的"彩色"来源 ----
        static let ok = Color(uiColor: .dsDynamic(
            light: UIColor(red: 0.078, green: 0.588, blue: 0.278, alpha: 1),
            dark: UIColor(red: 0.204, green: 0.780, blue: 0.349, alpha: 1)
        ))
        static let warn = Color(uiColor: .dsDynamic(
            light: UIColor(red: 0.757, green: 0.459, blue: 0.000, alpha: 1),
            dark: UIColor(red: 1.000, green: 0.624, blue: 0.039, alpha: 1)
        ))
        static let bad = Color(uiColor: .dsDynamic(
            light: UIColor(red: 0.792, green: 0.126, blue: 0.130, alpha: 1),
            dark: UIColor(red: 1.000, green: 0.271, blue: 0.227, alpha: 1)
        ))
        /// 充电 / 电驱专属状态色（EV 语义，不等于 ok）
        static let charge = Color(uiColor: .dsDynamic(
            light: UIColor(red: 0.000, green: 0.514, blue: 0.478, alpha: 1),
            dark: UIColor(red: 0.196, green: 0.855, blue: 0.780, alpha: 1)
        ))

        /// 状态字符串 → 颜色（与旧 Theme.statusColor 同语义，供老代码继续调用）
        static func status(_ cls: String) -> Color {
            switch cls {
            case "ok", "normal": return ok
            case "warn", "warning": return warn
            case "bad", "fault", "abnormal", "danger": return bad
            case "charge", "charging": return charge
            case "acc", "accent": return tint
            default: return labelTertiary
            }
        }
    }

    // =========================================================================
    // MARK: 2. 字体（Typo）
    // =========================================================================
    //  两层策略：
    //   • 文本全部用系统语义样式 → 自动跟随 Dynamic Type（无障碍合规）
    //   • 仪表数字用固定尺寸 + monospacedDigit + 紧字距 → 视觉上像仪表盘，且换数不跳动
    enum Typo {
        // ---- 仪表数字 ----
        /// 超大数字（首页 SOC / 关键指标）
        static func display(_ size: CGFloat = 72) -> Font {
            .system(size: size, weight: .semibold, design: .rounded).monospacedDigit()
        }
        /// 中等数字（卡片主数值）
        static func metric(_ size: CGFloat = 34) -> Font {
            .system(size: size, weight: .semibold, design: .rounded).monospacedDigit()
        }
        /// 行内数字（列表里的数值，保证对齐）
        static let data = Font.system(size: 17, weight: .medium, design: .rounded).monospacedDigit()
        static let dataSmall = Font.system(size: 14, weight: .medium, design: .rounded).monospacedDigit()

        // ---- 文本（跟随 Dynamic Type）----
        static let largeTitle = Font.largeTitle.weight(.bold)
        static let title = Font.title.weight(.semibold)
        static let title2 = Font.title2.weight(.semibold)
        static let title3 = Font.title3.weight(.semibold)
        static let headline = Font.headline
        static let body = Font.body
        static let callout = Font.callout
        static let subheadline = Font.subheadline
        static let footnote = Font.footnote
        static let caption = Font.caption
        static let caption2 = Font.caption2

        /// 小写字母间距的分组标题（Tesla 的 section label：小、灰、加粗）
        static let sectionLabel = Font.footnote.weight(.semibold)
    }

    // =========================================================================
    // MARK: 3. 网格（4pt 基准）
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
        static let huge: CGFloat = 40
        /// 页面左右安全边距
        static let page: CGFloat = 16
        /// 卡片之间
        static let gap: CGFloat = 12
        /// 卡片内部
        static let cardPadding: CGFloat = 18
    }

    // =========================================================================
    // MARK: 4. 圆角（克制：只有三档）
    // =========================================================================
    enum Radius {
        static let small: CGFloat = 10   // 小控件、chip
        static let card: CGFloat = 18    // 卡片、行分组
        static let hero: CGFloat = 26    // Hero 卡片、弹层
        static let capsule: CGFloat = 999
    }

    enum Hair {
        static let line: CGFloat = 0.5
        static let border: CGFloat = 1
    }

    // =========================================================================
    // MARK: 5. 动效（只服务"状态变化"，不做装饰）
    // =========================================================================
    enum Motion {
        /// 交互反馈（按下、选中）
        static let press = Animation.spring(response: 0.28, dampingFraction: 0.86)
        /// 数值/状态变化
        static let value = Animation.spring(response: 0.42, dampingFraction: 0.9)
        /// 页面/弹层
        static let screen = Animation.spring(response: 0.42, dampingFraction: 0.92)
        static let fade = Animation.easeOut(duration: 0.22)
    }

    // =========================================================================
    // MARK: 6. 尺寸（触控目标 / 图标）
    // =========================================================================
    enum Size {
        /// 最小触控目标（HIG）
        static let tap: CGFloat = 44
        /// 主操作按钮高度
        static let button: CGFloat = 52
        static let iconSm: CGFloat = 15
        static let icon: CGFloat = 18
        static let iconLg: CGFloat = 22
        static let tileIcon: CGFloat = 26
        static let barHeight: CGFloat = 52
    }
}

// =============================================================================
// MARK: - 画布与表面
// =============================================================================

/// 页面画布：只有一层颜色。所有页面根部都应该用它。
struct DSCanvas<Content: View>: View {
    var content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        ZStack {
            DS.Palette.canvas.ignoresSafeArea()
            content()
        }
    }
}

/// 内容卡片：不透明表面 + 发丝描边。
/// `glass: true` 只在「浮在内容之上」的少数场景使用（弹层、浮层）。
struct DSCard<Content: View>: View {
    var padding: CGFloat
    var radius: CGFloat
    var glass: Bool
    var content: () -> Content

    init(padding: CGFloat = DS.Space.cardPadding,
         radius: CGFloat = DS.Radius.card,
         glass: Bool = false,
         @ViewBuilder content: @escaping () -> Content) {
        self.padding = padding
        self.radius = radius
        self.glass = glass
        self.content = content
    }

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if glass {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(.ultraThinMaterial)
                } else {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(DS.Palette.surface)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(DS.Palette.hairline, lineWidth: DS.Hair.line)
            }
    }
}

/// 可点击卡片（带按下反馈，不用缩放变形那种"果冻"效果）
struct DSTappableCard<Content: View>: View {
    var action: () -> Void
    var content: () -> Content

    init(action: @escaping () -> Void, @ViewBuilder content: @escaping () -> Content) {
        self.action = action
        self.content = content
    }

    var body: some View {
        Button(action: action) {
            DSCard(content: content)
        }
        .buttonStyle(DSCardButtonStyle())
    }
}

struct DSCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.72 : 1)
            .animation(DS.Motion.press, value: configuration.isPressed)
    }
}

/// 发丝分隔线
struct DSDivider: View {
    var inset: CGFloat = 0
    var body: some View {
        Rectangle()
            .fill(DS.Palette.hairline)
            .frame(height: DS.Hair.line)
            .padding(.leading, inset)
    }
}

// =============================================================================
// MARK: - 结构组件
// =============================================================================

/// 分组标题：小号灰字，左侧对齐，可选右侧动作（Tesla/Apple 通用的 section 语义）
struct DSSectionHeader: View {
    var title: String
    var trailing: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title.uppercased())
                .font(DS.Typo.sectionLabel)
                .tracking(0.6)
                .foregroundStyle(DS.Palette.labelSecondary)
            Spacer(minLength: DS.Space.sm)
            if let trailing {
                if let action {
                    Button(trailing, action: action)
                        .font(DS.Typo.footnote.weight(.semibold))
                        .foregroundStyle(DS.Palette.tint)
                        .buttonStyle(.plain)
                } else {
                    Text(trailing)
                        .font(DS.Typo.footnote)
                        .foregroundStyle(DS.Palette.labelTertiary)
                }
            }
        }
        .padding(.horizontal, DS.Space.xs)
        .padding(.bottom, DS.Space.sm)
    }
}

/// 关键指标：巨大数字 + 单位 + 说明（全 App 最重要的排版元素）
struct DSMetric: View {
    var value: String
    var unit: String? = nil
    var caption: String? = nil
    var size: CGFloat = 72
    var tint: Color = DS.Palette.label
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        VStack(alignment: alignment, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(DS.Typo.display(size))
                    .foregroundStyle(tint)
                    .contentTransition(.numericText())
                if let unit {
                    Text(unit)
                        .font(DS.Typo.metric(size * 0.34))
                        .foregroundStyle(DS.Palette.labelSecondary)
                }
            }
            if let caption {
                Text(caption)
                    .font(DS.Typo.footnote)
                    .foregroundStyle(DS.Palette.labelSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// 状态 chip：一个语义圆点 + 文案（状态只用这一种表达，不再用彩色圆角块堆叠）
struct DSChip: View {
    var text: String
    var cls: String = "na"
    var icon: String? = nil

    private var color: Color { DS.Palette.status(cls) }

    var body: some View {
        HStack(spacing: 6) {
            if let icon {
                Image(safeSymbol: icon, fallback: "circle.fill")
                    .font(.system(size: 11, weight: .semibold))
            } else {
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
            }
            Text(text)
                .font(DS.Typo.caption.weight(.medium))
                .lineLimit(1)
        }
        .foregroundStyle(cls == "na" ? DS.Palette.labelSecondary : color)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Capsule().fill(DS.Palette.status(cls).opacity(cls == "na" ? 0.06 : 0.12)))
        .overlay(Capsule().strokeBorder(DS.Palette.status(cls).opacity(0.22), lineWidth: DS.Hair.line))
        .accessibilityElement(children: .combine)
    }
}

/// 标签 + 数值 行（详情页主力排版：左标签灰、右数值白，等宽数字）
struct DSStatRow: View {
    var label: String
    var value: String
    var valueCls: String = "na"
    var icon: String? = nil

    var body: some View {
        HStack(spacing: DS.Space.sm) {
            if let icon {
                Image(safeSymbol: icon, fallback: "circle")
                    .font(.system(size: DS.Size.iconSm, weight: .medium))
                    .foregroundStyle(DS.Palette.labelTertiary)
                    .frame(width: 20)
            }
            Text(label)
                .font(DS.Typo.subheadline)
                .foregroundStyle(DS.Palette.labelSecondary)
            Spacer(minLength: DS.Space.md)
            Text(value)
                .font(DS.Typo.data)
                .foregroundStyle(valueCls == "na" ? DS.Palette.label : DS.Palette.status(valueCls))
                .multilineTextAlignment(.trailing)
        }
        .frame(minHeight: 34)
        .accessibilityElement(children: .combine)
    }
}

/// 紧凑指标格（两/三列栅格用）：上标签、下数值
struct DSStatTile: View {
    var label: String
    var value: String
    var unit: String? = nil
    var cls: String = "na"
    var icon: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                if let icon {
                    Image(safeSymbol: icon, fallback: "circle")
                        .font(.system(size: 11, weight: .medium))
                }
                Text(label)
                    .font(DS.Typo.caption2.weight(.medium))
                    .lineLimit(1)
            }
            .foregroundStyle(DS.Palette.labelTertiary)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(DS.Typo.metric(22))
                    .foregroundStyle(cls == "na" ? DS.Palette.label : DS.Palette.status(cls))
                    .contentTransition(.numericText())
                if let unit {
                    Text(unit)
                        .font(DS.Typo.caption)
                        .foregroundStyle(DS.Palette.labelSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// 可点击行：图标 + 标题/副标题 + 右侧值 + 箭头（设置、列表页统一用它）
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
                    .font(.system(size: DS.Size.icon, weight: .medium))
                    .foregroundStyle(DS.Palette.labelSecondary)
                    .frame(width: 26, alignment: .center)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DS.Typo.body)
                    .foregroundStyle(DS.Palette.label)
                if let subtitle {
                    Text(subtitle)
                        .font(DS.Typo.caption)
                        .foregroundStyle(DS.Palette.labelTertiary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: DS.Space.sm)
            if let value {
                Text(value)
                    .font(DS.Typo.data)
                    .foregroundStyle(valueCls == "na" ? DS.Palette.labelSecondary : DS.Palette.status(valueCls))
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.Palette.labelTertiary)
            }
        }
        .frame(minHeight: DS.Size.tap)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct DSRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? DS.Palette.surfaceRaised : Color.clear)
            .animation(DS.Motion.press, value: configuration.isPressed)
    }
}

/// 快捷操作磁贴：图标在上、文字在下，方阵排列（车控主力控件）
/// 只有"高亮态"才使用语义色，普通态是纯表面色 —— 一屏 8 个按钮也不会花。
struct DSTile: View {
    var icon: String
    var title: String
    var subtitle: String? = nil
    var isActive: Bool = false
    var cls: String = "acc"
    var isLoading: Bool = false
    var action: () -> Void

    private var accent: Color {
        isActive ? DS.Palette.status(cls) : DS.Palette.label
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: DS.Space.sm) {
                HStack {
                    Image(safeSymbol: icon, fallback: "circle")
                        .font(.system(size: DS.Size.tileIcon, weight: isActive ? .semibold : .regular))
                        .foregroundStyle(isActive ? DS.Palette.status(cls) : DS.Palette.label)
                        .frame(height: 30)
                    Spacer(minLength: 0)
                    if isLoading {
                        ProgressView().controlSize(.small)
                    }
                }
                Text(title)
                    .font(DS.Typo.subheadline.weight(.semibold))
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let subtitle {
                    Text(subtitle)
                        .font(DS.Typo.caption2)
                        .foregroundStyle(DS.Palette.labelTertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DS.Space.md)
            .frame(minHeight: 88)
            .background {
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .fill(isActive ? DS.Palette.status(cls).opacity(0.14) : DS.Palette.surface)
            }
            .overlay {
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .strokeBorder(isActive ? DS.Palette.status(cls).opacity(0.4) : DS.Palette.hairline,
                                  lineWidth: DS.Hair.line)
            }
        }
        .buttonStyle(DSCardButtonStyle())
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(isActive ? "已开启" : "已关闭"))
    }
}

/// 主操作按钮（锁车/解锁这类"一屏一个"的动作）
struct DSPrimaryButtonStyle: ButtonStyle {
    var tint: Color = DS.Palette.tint

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DS.Typo.headline)
            .foregroundStyle(DS.Palette.labelOnTint)
            .frame(maxWidth: .infinity)
            .frame(height: DS.Size.button)
            .background(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous).fill(tint))
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(DS.Motion.press, value: configuration.isPressed)
    }
}

/// 次操作按钮（描边式）
struct DSSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DS.Typo.headline)
            .foregroundStyle(DS.Palette.label)
            .frame(maxWidth: .infinity)
            .frame(height: DS.Size.button)
            .background(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous).fill(DS.Palette.surface))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .strokeBorder(DS.Palette.hairlineStrong, lineWidth: DS.Hair.line))
            .opacity(configuration.isPressed ? 0.72 : 1)
            .animation(DS.Motion.press, value: configuration.isPressed)
    }
}

/// 圆形图标按钮（导航栏、卡片角标）
struct DSIconButtonStyle: ButtonStyle {
    var size: CGFloat = DS.Size.tap
    var tint: Color = DS.Palette.label

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: DS.Size.icon, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(Circle().fill(configuration.isPressed ? DS.Palette.surfaceRaised : Color.clear))
            .contentShape(Circle())
            .animation(DS.Motion.press, value: configuration.isPressed)
    }
}

/// 分段控件（对齐系统的分段语义，但用 DS 的层级与圆角）
struct DSSegmented<T: Hashable>: View {
    var options: [(value: T, title: String)]
    @Binding var selection: T

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { option in
                let selected = option.value == selection
                Button {
                    withAnimation(DS.Motion.value) { selection = option.value }
                } label: {
                    Text(option.title)
                        .font(DS.Typo.subheadline.weight(selected ? .semibold : .regular))
                        .foregroundStyle(selected ? DS.Palette.label : DS.Palette.labelSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: DS.Radius.small - 2, style: .continuous)
                                    .fill(DS.Palette.surface)
                                    .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: DS.Radius.small, style: .continuous).fill(DS.Palette.surfaceSunken))
    }
}

/// 环形仪表（SOC / 健康分）：单色轨道 + 语义色进度。
struct DSGauge: View {
    var progress: Double            // 0...1
    var lineWidth: CGFloat = 12
    var tint: Color = DS.Palette.tint
    var value: String? = nil
    var unit: String? = nil
    var caption: String? = nil
    var size: CGFloat = 180

    var body: some View {
        ZStack {
            Circle()
                .stroke(DS.Palette.surfaceSunken, style: StrokeStyle(lineWidth: lineWidth))
            Circle()
                .trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(DS.Motion.value, value: progress)
            VStack(spacing: 2) {
                if let value {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(value)
                            .font(DS.Typo.display(46))
                            .foregroundStyle(DS.Palette.label)
                            .contentTransition(.numericText())
                        if let unit {
                            Text(unit)
                                .font(DS.Typo.metric(20))
                                .foregroundStyle(DS.Palette.labelSecondary)
                        }
                    }
                }
                if let caption {
                    Text(caption)
                        .font(DS.Typo.footnote)
                        .foregroundStyle(DS.Palette.labelSecondary)
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .combine)
    }
}

/// 迷你趋势曲线（Canvas 手绘，避免图表库依赖 + 保证在卡片里尺寸可控）
struct DSSparkline: View {
    var values: [Double]
    var tint: Color = DS.Palette.tint
    var height: CGFloat = 56
    var showsFill: Bool = true

    var body: some View {
        GeometryReader { geo in
            let pts = points(in: geo.size)
            ZStack {
                if showsFill, pts.count > 1 {
                    Path { p in
                        p.move(to: CGPoint(x: pts[0].x, y: geo.size.height))
                        pts.forEach { p.addLine(to: $0) }
                        p.addLine(to: CGPoint(x: pts[pts.count - 1].x, y: geo.size.height))
                        p.closeSubpath()
                    }
                    .fill(tint.opacity(0.12))
                }
                Path { p in
                    guard pts.count > 1 else { return }
                    p.move(to: pts[0])
                    pts.dropFirst().forEach { p.addLine(to: $0) }
                }
                .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }

    private func points(in size: CGSize) -> [CGPoint] {
        guard values.count > 1, let mn = values.min(), let mx = values.max() else { return [] }
        let span = max(0.0001, mx - mn)
        let stepX = size.width / CGFloat(values.count - 1)
        return values.enumerated().map { idx, v in
            let ratio = (v - mn) / span
            let y = size.height - CGFloat(ratio) * (size.height - 4) - 2
            return CGPoint(x: CGFloat(idx) * stepX, y: y)
        }
    }
}

/// 信息条（离线、失败、提示）：一条发丝线分隔的安静横幅，不用彩色渐变
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
                .font(.system(size: DS.Size.iconSm, weight: .semibold))
                .foregroundStyle(DS.Palette.status(kind.cls))
            Text(text)
                .font(DS.Typo.footnote)
                .foregroundStyle(DS.Palette.label)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: DS.Space.sm)
            if let action {
                Button(action.title, action: action.run)
                    .font(DS.Typo.footnote.weight(.semibold))
                    .foregroundStyle(DS.Palette.tint)
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, DS.Space.md)
        .padding(.vertical, DS.Space.sm)
        .background(RoundedRectangle(cornerRadius: DS.Radius.small, style: .continuous)
            .fill(DS.Palette.status(kind.cls).opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.small, style: .continuous)
            .strokeBorder(DS.Palette.status(kind.cls).opacity(0.25), lineWidth: DS.Hair.line))
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
            // 走 SafeSymbol：图标名写错时退回一个必定存在的图标，而不是渲染成空白
            Image(safeSymbol: icon, fallback: "questionmark.circle")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(DS.Palette.status(cls))
            Text(title)
                .font(DS.Typo.headline)
                .foregroundStyle(DS.Palette.label)
                .multilineTextAlignment(.center)
            if let message {
                Text(message)
                    .font(DS.Typo.footnote)
                    .foregroundStyle(DS.Palette.labelSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(DSSecondaryButtonStyle())
                    .frame(maxWidth: 220)
            }
        }
        .padding(DS.Space.xl)
        .frame(maxWidth: .infinity)
    }
}

/// 加载占位（骨架）。静态表面：加载本身由 ProgressView 表达，占位块不做任何动画。
struct DSSkeleton: View {
    var height: CGFloat = 16
    var width: CGFloat? = nil

    var body: some View {
        RoundedRectangle(cornerRadius: DS.Radius.small, style: .continuous)
            .fill(DS.Palette.surfaceRaised)
            .frame(width: width, height: height)
            .accessibilityHidden(true)
    }
}

// =============================================================================
// MARK: - 浮层材质（唯一允许用 Liquid Glass 的地方）
// =============================================================================

/// 顶部导航栏容器：iOS 27 液态玻璃，内容滚动时始终清晰可读
struct DSNavBar<Trailing: View>: View {
    var title: String
    var subtitle: String? = nil
    var showsBack: Bool = false
    var onBack: (() -> Void)? = nil
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: DS.Space.sm) {
            if showsBack, let onBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(DSIconButtonStyle(size: 36))
                .accessibilityLabel(Text("返回"))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(DS.Typo.title3)
                    .foregroundStyle(DS.Palette.label)
                if let subtitle {
                    Text(subtitle)
                        .font(DS.Typo.caption)
                        .foregroundStyle(DS.Palette.labelSecondary)
                }
            }
            Spacer(minLength: DS.Space.sm)
            trailing()
        }
        .padding(.horizontal, DS.Space.page)
        .padding(.vertical, DS.Space.sm)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) { DSDivider() }
    }
}

extension DSNavBar where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, showsBack: Bool = false, onBack: (() -> Void)? = nil) {
        self.init(title: title, subtitle: subtitle, showsBack: showsBack, onBack: onBack) { EmptyView() }
    }
}

/// 底部悬浮操作条（车窗/锁车这类高频动作）：液态玻璃 + 安全区跟随
struct DSBottomBar<Content: View>: View {
    var content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        content()
            .padding(.horizontal, DS.Space.md)
            .padding(.vertical, DS.Space.sm)
            .background(.ultraThinMaterial)
            .overlay(alignment: .top) { DSDivider() }
    }
}

// =============================================================================
// MARK: - 便捷修饰符（老代码 / 新代码都能用）
// =============================================================================

extension View {
    /// 卡片外观（等价 DSCard，但用于已有视图）
    func dsSurface(padding: CGFloat = DS.Space.cardPadding,
                   radius: CGFloat = DS.Radius.card,
                   glass: Bool = false) -> some View {
        modifier(DSSurfaceModifier(padding: padding, radius: radius, glass: glass))
    }

    /// 页面根部：单一画布底色 + 统一的 16pt 页面左右边距。
    /// 页面边距由设计系统提供（而非每个页面各自 padding），
    /// 这样所有页面的文本基线才会对齐 —— 这是「专业感」最直接的来源。
    func dsCanvas() -> some View {
        dsPageMargins()
            .background(DS.Palette.canvas.ignoresSafeArea())
    }

    /// 给页面根部的滚动容器统一左右安全边距（非滚动视图上是空操作）
    func dsPageMargins() -> some View {
        contentMargins(.horizontal, DS.Space.page, for: .scrollContent)
    }

    /// 组内行分隔（列表分组用）
    func dsRowInsets() -> some View {
        padding(.horizontal, DS.Space.md).padding(.vertical, DS.Space.xxs)
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
                    .fill(glass ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(DS.Palette.surface))
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(DS.Palette.hairline, lineWidth: DS.Hair.line)
            }
    }
}

// =============================================================================
// MARK: - 触觉反馈（极简：只保留两种，不堆叠）
// =============================================================================
enum DSHaptic {
    /// 轻触（按钮、切换）
    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    /// 结果反馈（指令下发成功/失败）
    static func result(_ success: Bool) {
        UINotificationFeedbackGenerator().notificationOccurred(success ? .success : .error)
    }
    /// 选中（分段、Tab）
    static func select() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
}
