import SwiftUI

// =============================================================================
// 长安车管家 — iOS 27 Apple Premium Design System
// ============================================================
// 规范文档：所有页面的字号、间距、圆角、色彩体系
// 原则：Apple HIG + Liquid Glass + 分层深度感 + 精确数值
// =============================================================================

// MARK: - Color(hex:) 工具
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 6: (r, g, b) = (int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        case 8: (r, g, b) = (int >> 24 & 0xFF, int >> 16 & 0xFF, int >> 8 & 0xFF)
        default: (r, g, b) = (255, 255, 255)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: 1)
    }
}

enum Theme {
    // MARK: - 品牌色（自适应浅色/深色模式）
    /// 主色调：长安品牌蓝，浅暗双模式
    static var brand: Color { .blue }                              // iOS 标准蓝
    static var brandLight: Color { Color(hex: "0A84FF") }          // 高亮蓝
    static var brandDark: Color { Color(hex: "0056CC") }           // 深色模式蓝

    // MARK: - 页面背景语义色
    /// 车况页（默认）
    static var pageAccent: Color { .accentColor }
    /// 电池/健康页 — 绿色调
    static var pageGreen: Color { Color.green }
    /// 车控页 — 蓝色调
    static var pageBlue: Color { Color.blue }
    /// 全量数据页 — 靛蓝调
    static var pageIndigo: Color { Color(.systemIndigo) }

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
    // 一、字号体系（Typography Scale）— iOS 27 Dynamic Type 兼容
    // =============================================================================
    // 基准字号：17pt（iOS 标准正文）
    // 比例：1.25（Major Third）
    //
    // Dynamic Type 策略：
    //   • Hero 数字（d1~d5）：Fixed，不受字号缩放影响（仪表盘视觉完整性）
    //   • 标题/正文：使用系统语义字体（.title/.headline/.body/.caption 等）
    //     自动跟随系统字号设置，确保 accessibility 合规
    //   • 等宽数字（mono/monoLg）：Fixed monospaced，保持数据对齐
    //   • 辅助文字（footnote/micro）：使用系统语义样式，允许缩放

    // ---- Hero 数字（固定大小，不参与 Dynamic Type 缩放）----
    // 仪表盘大数字：无论用户是否开启大字体，始终保持视觉冲击力
    static let d1 = Font.system(size: 80, weight: .bold, design: .rounded)
    static let d2 = Font.system(size: 52, weight: .semibold, design: .rounded)
    static let d3 = Font.system(size: 34, weight: .medium, design: .rounded)
    static let d4 = Font.system(size: 26, weight: .semibold, design: .monospaced)
    static let d5 = Font.system(size: 20, weight: .semibold, design: .rounded)

    // ---- 语义标题（跟随 Dynamic Type）----
    static var h1: Font { .largeTitle }                                       // 页面大标题
    static var h2: Font { .title }                                             // 卡片主标题
    static var h3: Font { .title3 }                                            // 子标题 / 分组名
    static var h4: Font { .headline }                                          // 微标题

    // ---- 正文（跟随 Dynamic Type）----
    static var body: Font { .body }                                            // 正文（基准）
    static var bodySm: Font { .subheadline }                                   // 小正文
    static var bodyMd: Font { .body }                                          // 中等正文
    static var bodyLg: Font { .callout }                                       // 大正文

    // ---- 辅助文字（跟随 Dynamic Type）----
    static var caption: Font { .caption }                                      // 说明文字
    static var captionBold: Font { .caption.bold() }                           // 说明文字（强调）
    static var footnote: Font { .footnote }                                    // 脚注 / 时间戳
    static var micro: Font { .caption2 }                                       // 超微文字

    // ---- 数字专用（等宽，固定大小保持对齐）----
    static let mono = Font.system(size: 14, weight: .medium, design: .monospaced)
    static let monoLg = Font.system(size: 17, weight: .semibold, design: .monospaced)

    // ---- 其他固定 Hero 尺寸（不受 Dynamic Type 影响）----
    static let d0 = Font.system(size: 42, weight: .bold, design: .rounded)    // 超大数字（AC温度）
    static let d0b = Font.system(size: 28, weight: .regular)                 // 地图坐标大数字

    // =============================================================================
    // Font 扩展：语义样式便捷方法
    // =============================================================================
    extension Font {
        /// 返回跟随 Dynamic Type 的语义字体
        static func headline(weight: Font.Weight = .semibold) -> Font {
            .headline.weight(weight)
        }
        static func body(weight: Font.Weight = .regular) -> Font {
            .body.weight(weight)
        }
        static func subheadline(weight: Font.Weight = .regular) -> Font {
            .subheadline.weight(weight)
        }
        static func caption(weight: Font.Weight = .regular) -> Font {
            .caption.weight(weight)
        }
        static func footnote(weight: Font.Weight = .regular) -> Font {
            .footnote.weight(weight)
        }
    }

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

    enum Spring {
        static let responseBase: Double = 0.45
        static let dampingFraction: Double = 0.8
        static let duration: Double = 0.5
        static var standard: Animation { Animation.spring(response: responseBase, dampingFraction: dampingFraction, blendDuration: duration) }
        static var quick: Animation { Animation.spring(response: 0.3, dampingFraction: 0.7, blendDuration: 0.25) }
        static var slow: Animation { Animation.spring(response: 0.6, dampingFraction: 0.9, blendDuration: 0.5) }
        static var smooth: Animation { Animation.easeInOut(duration: 0.35) }
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
            // 暗色模式提高 opacities 保证可见度
            LinearGradient(
                colors: [
                    tint.opacity(0.22),
                    tint.opacity(0.06),
                    .clear
                ],
                startPoint: .top,
                endPoint: UnitPoint(x: 0.5, y: 0.65)
            )
            // 顶层：径向光晕（右上角，模拟环境光）
            RadialGradient(
                colors: [tint.opacity(0.14), .clear],
                center: .topTrailing,
                startRadius: 30,
                endRadius: 400
            )
            // 暗色模式下增加微弱白色层提升卡片对比度
            Color.white.opacity(0.015)
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

    // MARK: - 导航栏样式：iOS 27 Liquid Glass
    // inline 标题 + 玻璃材质背景 + 白色高光描边 + 强调色图标
    func navBarStyle() -> some View {
        self
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigation)
            .toolbarBackgroundMaterial(.thin)
            .tint(.accentColor)
    }

    // ---- 玻璃卡片：深浅双模式自适应材质 + 高光描边 ----
    func glassCard(corner: CGFloat = Theme.Radius.card) -> some View {
        self
            .background(Material.thin, in: RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.28), .white.opacity(0.04)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.8
                    )
            )
            .shadow(color: .black.opacity(0.05), radius: 16, y: 6)
    }

    // ---- Hero 玻璃卡片：深浅双模式自适应 + 更强光晕 ----
    func glassHeroCard(corner: CGFloat = Theme.Radius.hero) -> some View {
        self
            .background(Material.thin, in: RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.34), .white.opacity(0.06)],
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

// MARK: - 浮动装饰粒子（SOC/评分圆环专用）
struct FloatingParticles: View {
    let size: CGFloat

    var body: some View {
        VStack {
            ForEach(0..<6, id: \.self) { i in
                particle(at: i, total: 6)
            }
        }
    }

    private func particle(at i: Int, total: Int) -> some View {
        let angle = (Double(i) / Double(total)) * 2 * .pi
        let radius = size / 2 + 14 + CGFloat(i % 3) * 5
        let baseX = radius * cos(angle)
        let baseY = radius * sin(angle)
        return Circle()
            .fill(floatingColor(i).opacity(0.32))
            .frame(width: 3.5, height: 3.5)
            .offset(x: baseX, y: baseY)
    }

    private func floatingColor(_ i: Int) -> Color {
        switch i % 5 {
        case 0: return .green
        case 1: return .teal
        case 2: return .blue
        case 3: return .yellow
        default: return .orange
        }
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
        .background(.thin, in: Capsule())
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
        .background(.thin,
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
        .background(.thin,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
    }
}

// MARK: - 快捷控制大圆钮（车控首页）
struct QuickControlButton: View {
    let icon: String
    let label: String
    let tint: Color
    let action: () -> Void
    @State private var isPressed = false

    var body: some View {
        Button {
            action()
        } label: {
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
        .scaleEffect(isPressed ? 0.88 : 1.0)
        .animation(Animation.spring(response: 0.35, dampingFraction: 0.6, blendDuration: 0.3), value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
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
