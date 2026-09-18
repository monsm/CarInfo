import SwiftUI

// =============================================================================
// 长安车管家 — iOS 27 Apple Premium Design System
// ============================================================
// 规范文档：所有页面的字号、间距、圆角、色彩体系
// 原则：Apple HIG + Liquid Glass + 分层深度感 + 精确数值
// =============================================================================

enum Theme {
    // MARK: - 品牌色（自适应浅色/深色模式）
    /// 主色调：长安品牌蓝，浅暗双模式
    static var brand: Color { Color(hex: "007AFF") }          // iOS 标准蓝
    static var brandLight: Color { Color(hex: "0A84FF") }     // 高亮蓝
    static var brandDark: Color { Color(hex: "0056CC") }      // 深色模式蓝

    // MARK: - 语义色（系统自适应）
    static var ok: Color { Color.green }
    static var warn: Color { Color.orange }
    static var bad: Color { Color.red }
    static var acc: Color { Color.accentColor }
    static var na: Color { Color.secondary }

    // MARK: - 状态 → 语义色
    static func statusColor(_ cls: String) -> Color {
        switch cls {
        case "ok", "normal": return .green
        case "warn", "warning": return .orange
        case "bad", "fault", "abnormal": return .red
        case "acc": return .accentColor
        case "idle", "off": return Color(.systemGray4)
        default: return Color(.systemGray4)
        }
    }

    // =============================================================================
    // 一、字号体系（Typography Scale）
    // =============================================================================
    // 基准字号：17pt（iOS 标准正文）
    // 比例：1.25（Major Third）

    // ---- 数字字体（SF Pro Rounded 专用）----
    static let d1 = Font.system(size: 80, weight: .bold, design: .rounded)    // Hero 大数字（SOC/评分）
    static let d2 = Font.system(size: 52, weight: .semibold, design: .rounded) // 二级数字（胎压/温度）
    static let d3 = Font.system(size: 34, weight: .medium, design: .rounded)  // 三级数字（电压/电流）
    static let d4 = Font.system(size: 26, weight: .semibold, design: .monospaced) // 数据面板数字
    static let d5 = Font.system(size: 20, weight: .semibold, design: .rounded)  // 小数字徽章

    // ---- 标题字体（SF Pro）----
    static let h1 = Font.system(size: 28, weight: .bold)                        // 页面大标题
    static let h2 = Font.system(size: 20, weight: .semibold)                    // 卡片主标题
    static let h3 = Font.system(size: 17, weight: .semibold)                    // 子标题 / 分组名
    static let h4 = Font.system(size: 15, weight: .semibold)                    // 微标题

    // ---- 正文字体----
    static let body = Font.system(size: 17, weight: .regular)                   // 正文（基准）
    static let bodySm = Font.system(size: 15, weight: .regular)                 // 小正文
    static let bodyMd = Font.system(size: 16, weight: .regular)                 // 中等正文
    static let bodyLg = Font.system(size: 19, weight: .regular)                 // 大正文

    // ---- 辅助文字----
    static let caption = Font.system(size: 13, weight: .regular)                // 说明文字
    static let captionBold = Font.system(size: 13, weight: .semibold)           // 说明文字（强调）
    static let footnote = Font.system(size: 11, weight: .regular)               // 脚注 / 时间戳
    static let micro = Font.system(size: 10, weight: .regular)                  // 超微文字

    // ---- 数字专用（等宽）----
    static let mono = Font.system(size: 14, weight: .medium, design: .monospaced)
    static let monoLg = Font.system(size: 17, weight: .semibold, design: .monospaced)

    // =============================================================================
    // 二、间距体系（Spacing Scale）
    // =============================================================================
    // 基准：4pt，所有间距为 4 的倍数
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
        static let xxxl: CGFloat = 32
        static let hero: CGFloat = 40
        static let page: CGFloat = 16   // 页面水平内边距
        static let cardSpacing: CGFloat = 16 // 卡片垂直间距
        static let cardPadding: CGFloat = 20 // 卡片内边距
        static let gridGap: CGFloat = 12 // 网格间距
    }

    // =============================================================================
    // 三、圆角体系（Corner Radius Scale）
    // =============================================================================
    enum Radius {
        static let tiny: CGFloat = 8    // 图标按钮、tag
        static let small: CGFloat = 12  // Pill、小卡片
        static let medium: CGFloat = 16 // StatTile、普通卡片
        static let large: CGFloat = 20  // 消息卡片
        static let card: CGFloat = 24   // 标准玻璃卡片
        static let hero: CGFloat = 28   // Hero 区域卡片
        static let ultra: CGFloat = 32  // 超大 Hero 卡片
        static let full: CGFloat = 50   // 圆形元素
    }

    // =============================================================================
    // 四、色彩体系（Color System）
    // =============================================================================
    enum ColorSystem {
        // ---- 表面色（Surface）----
        static let background: Color = Color(.systemGroupedBackground)
        static let cardBg: Color = Color(.secondarySystemGroupedBackground)
        static let overlay: Color = Color(.thinMaterial)
        static let glass: Color = Color(.ultraThinMaterial)

        // ---- 文字色（Text）----
        static let primary: Color = Color(.label)
        static let secondary: Color = Color(.secondaryLabel)
        static let tertiary: Color = Color(.tertiaryLabel)
        static let quaternary: Color = Color(.quaternaryLabel)

        // ---- 边框色（Border）----
        static let border: Color = Color(.separator)
        static let borderSubtle: Color = Color(.separator).opacity(0.5)

        // ---- 填充色（Fill）----
        static let fill: Color = Color(.secondarySystemFill)
        static let fillSubtle: Color = Color(.tertiarySystemFill)
        static let fillHighlighted: Color = Color(.quaternarySystemFill)

        // ---- 阴影色----
        static let shadowLight: Color = Color.black.opacity(0.04)
        static let shadowMedium: Color = Color.black.opacity(0.08)
        static let shadowStrong: Color = Color.black.opacity(0.12)
    }

    // =============================================================================
    // 五、阴影体系（Shadow Scale）
    // =============================================================================
    enum Shadow {
        static let none: ShadowStyle = .init(color: .clear, radius: 0, x: 0, y: 0)
        static let light = ShadowStyle(color: ColorSystem.shadowLight, radius: 8, x: 0, y: 2)
        static let medium = ShadowStyle(color: ColorSystem.shadowMedium, radius: 16, x: 0, y: 4)
        static let strong = ShadowStyle(color: ColorSystem.shadowStrong, radius: 24, x: 0, y: 8)
        static let glow = GlowStyle(color: .accentColor, radius: 12, offset: 4)
    }

    // =============================================================================
    // 六、动画时长（Animation Duration）
    // =============================================================================
    enum Duration {
        static let instant: Double = 0.1
        static let fast: Double = 0.2
        static let normal: Double = 0.3
        static let slow: Double = 0.5
        static let springFast = Spring(response: 0.3, dampingFraction: 0.7)
        static let springNormal = Spring(response: 0.45, dampingFraction: 0.8)
        static let springSlow = Spring(response: 0.6, dampingFraction: 0.9)
    }

    // MARK: - 辅助工具
    static func font(_ size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        .system(size: size, weight: weight, design: design)
    }

    static func lineHeight(_ size: CGFloat) -> CGFloat {
        switch size {
        case 80, 52: return size * 1.1
        case 34, 28: return size * 1.15
        case 20, 17: return size * 1.29
        default: return size * 1.4
        }
    }
}

// MARK: - 阴影样式
struct ShadowStyle {
    var color: Color
    var radius: CGFloat
    var x: CGFloat
    var y: CGFloat
}

struct GlowStyle {
    var color: Color
    var radius: CGFloat
    var offset: CGFloat
}

// MARK: - 页面底色：多层次渐变光晕（Apple Premium）
struct PageBackground: View {
    var tint: Color = .accentColor
    var body: some View {
        ZStack {
            // 底层：系统分组背景
            Color(.systemGroupedBackground)
            // 中层：主题色渐变光晕（大面积、柔和）
            LinearGradient(
                colors: [tint.opacity(0.18), tint.opacity(0.04), .clear],
                startPoint: .top,
                endPoint: UnitPoint(x: 0.5, y: 0.65)
            )
            // 顶层：径向光晕（右上角，模拟环境光）
            RadialGradient(
                colors: [tint.opacity(0.10), .clear],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 400
            )
        }
        .ignoresSafeArea()
    }
}

// MARK: - View Extensions：Apple Premium 组件
extension View {
    // 页面底色
    func pageBackground(_ tint: Color = .accentColor) -> some View {
        background(PageBackground(tint: tint))
    }

    // ---- 玻璃卡片：薄材质 + 顶部高光描边 + 大圆角 + 柔和投影 ----
    func glassCard(corner: CGFloat = Theme.Radius.card) -> some View {
        self
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.38), .white.opacity(0.06)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.8
                    )
            )
            .shadow(color: .black.opacity(0.05), radius: 16, y: 6)
    }

    // ---- Hero 玻璃卡片：更大的圆角 + 更强的光晕 ----
    func glassHeroCard(corner: CGFloat = Theme.Radius.hero) -> some View {
        self
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.42), .white.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.0
                    )
            )
            .shadow(color: .black.opacity(0.07), radius: 20, y: 8)
    }

    // ---- 通用圆角卡片（可选圆角值）----
    func premiumCard(corner: CGFloat = Theme.Radius.card) -> some View {
        self
            .background(Color(.secondarySystemGroupedBackground).opacity(0.85),
                        in: RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(Color(.separator).opacity(0.4), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
    }

    // ---- 应用阴影 ----
    func applyShadow(_ s: ShadowStyle) -> some View {
        shadow(color: s.color, radius: s.radius, x: s.x, y: s.y)
    }

    // ---- 应用光晕 ----
    func applyGlow(_ g: GlowStyle) -> some View {
        self
            .shadow(color: g.color.opacity(0.3), radius: g.radius, y: g.offset)
            .shadow(color: g.color.opacity(0.15), radius: g.radius * 1.5, y: g.offset * 2)
    }
}

// MARK: - 状态点（带同色光晕）
struct StatusDot: View {
    let cls: String
    var size: CGFloat = 8
    var body: some View {
        Circle()
            .fill(Theme.statusColor(cls))
            .frame(width: size, height: size)
            .opacity(cls == "na" ? 0.35 : 1)
            .shadow(color: Theme.statusColor(cls).opacity(cls == "na" ? 0 : 0.5), radius: 3)
    }
}

// MARK: - 语义色玻璃胶囊
struct Pill: View {
    let text: String
    let cls: String
    var dot: Bool = true

    var body: some View {
        HStack(spacing: 5) {
            if dot { StatusDot(cls: cls, size: 6) }
            Text(text)
                .font(Theme.micro)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.statusColor(cls))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.statusColor(cls).opacity(0.28), lineWidth: 0.8))
    }
}

// MARK: - 键值行（详情 / 明细）
struct KVRow: View {
    let k: String
    let v: String
    var mono: Bool = false
    var strong: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.md) {
            Text(k)
                .font(Theme.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: Theme.Spacing.lg)
            Text(v)
                .font(Theme.font(14, weight: strong ? .semibold : .medium,
                                 design: mono ? .monospaced : .rounded))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 玻璃分组卡片（全局容器：标题 + 状态胶囊 + 内容）
struct CardBox<Content: View>: View {
    let title: String
    var side: String? = nil
    var sideCls: String = ""
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(Theme.h4)
                    .foregroundStyle(.secondary)
                Spacer()
                if let side, !side.isEmpty {
                    Pill(text: side, cls: sideCls.isEmpty ? "na" : sideCls, dot: false)
                }
            }
            content()
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(corner: Theme.Radius.card)
    }
}

// MARK: - 统计小磁贴
struct StatTile: View {
    let icon: String
    let label: String
    let value: String
    var unit: String = ""
    var tint: Color = .accentColor

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .font(Theme.font(14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(Theme.caption)
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(value)
                        .font(Theme.font(15, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    if !unit.isEmpty {
                        Text(unit).font(Theme.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .background(.ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
    }
}

// MARK: - 列表分隔行
struct ListDivider: View {
    var body: some View {
        Divider().opacity(0.5)
    }
}

// MARK: - 分区标题
struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(Theme.captionBold)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Spacing.sm)
    }
}

// MARK: - 指标徽章（用于车速/里程/充电等）
struct MetricPill: View {
    let icon: String
    let value: String
    let unit: String
    var tint: Color = .accentColor

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(Theme.micro)
                .foregroundStyle(tint.opacity(0.85))
            Text(value)
                .font(Theme.mono)
                .foregroundStyle(.primary)
            if !unit.isEmpty {
                Text(unit).font(Theme.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(.ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
    }
}

// MARK: - 快捷控制大圆钮（车控首页）
struct QuickControlButton: View {
    let icon: String
    let label: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: Theme.Spacing.sm) {
                Image(systemName: icon)
                    .font(Theme.font(24, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 56, height: 56)
                    .background(tint.opacity(0.12), in: Circle())
                Text(label)
                    .font(Theme.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 轮胎单元格（Apple CarKey 风格）
struct TyreCell: View {
    let label: String
    let kpa: String
    let temp: String
    let cls: String
    let minSafePressure: Double

    var body: some View {
        let pressurePercent = min(1.0, max(0.0,
            (Double(kpa) ?? 220) - minSafePressure) / (280 - minSafePressure))
        let barColor: Color = cls == "bad" ? .red : (pressurePercent > 0.5 ? .green : .orange)

        VStack(spacing: 6) {
            // 位置标签
            HStack {
                Image(systemName: "tire")
                    .font(Theme.micro)
                    .foregroundStyle(.secondary)
                Text(label)
                    .font(Theme.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            // 压力数字（大）
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(kpa)
                    .font(Theme.d4)
                    .foregroundStyle(cls == "bad" ? .red : .primary)
                Text("kPa")
                    .font(Theme.micro)
                    .foregroundStyle(.secondary)
            }

            // 压力色带（可视化进度条）
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color.systemGray5)
                        .frame(height: 4)
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(barColor.opacity(0.8))
                        .frame(width: geo.size.width * pressurePercent, height: 4)
                }
            }
            .frame(height: 4)

            // 温度
            Text(temp + "°C")
                .font(Theme.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, Theme.Spacing.sm)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                .fill(cls == "bad"
                      ? Color.red.opacity(0.06)
                      : Color.green.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                        .strokeBorder(barColor.opacity(0.25), lineWidth: 0.8)
                )
        )
    }
}
