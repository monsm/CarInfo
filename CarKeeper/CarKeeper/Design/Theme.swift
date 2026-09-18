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
        static let glass: Color = Color(.thinMaterial)      // 与 overlay 统一，深色模式可见度更好

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
    /// iOS 27 Liquid Glass Tab 切换过渡动画：
    /// 每个 Tab 内容以弹簧回弹 + 淡入方式滑入，配合 TabView.transaction 使用。
    func liquidGlassTabTransition() -> some View {
        self
            .scaleEffect(1.0)
            .opacity(1.0)
            .offset(y: 0)
    }

    /// iOS 27 Liquid Glass 深潜页面滑入转场
    /// 从右侧滑入 + 淡入 + 轻微弹簧回弹，配合 navigationDestination 的 transition 使用
    func liquidGlassSlideIn() -> some View {
        self
            .transition(
                .asymmetric(
                    insertion: .move(edge: .trailing)
                        .combined(with: .opacity)
                        .animation(.spring(response: 0.45, dampingFraction: 0.6, blendDuration: 0.3)),
                    removal: .move(edge: .leading)
                        .combined(with: .opacity)
                        .animation(.easeInOut(duration: 0.25))
                )
            )
    }

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

    // ---- 玻璃卡片：深浅双模式自适应材质 + 高光描边 + 水波纹涟漪 ----
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
            .liquidGlassRipple(cornerRadius: corner)
    }

    // ---- Hero 玻璃卡片：深浅双模式自适应 + 更强光晕 + 水波纹涟漪 ----
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
            .liquidGlassRipple(cornerRadius: corner)
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

// MARK: - 统计小磁贴（hover 液态玻璃光晕）
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
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                .fill(.thin)
        )
        .modifier(PressFeedback(pressScale: 0.93,
                                glowColor: tint,
                                glowIntensity: 0.6,
                                springResponse: 0.4,
                                springDamping: 0.65))
        .liquidGlassRipple(cornerRadius: Theme.Radius.medium)
    }
}

// MARK: - Liquid Glass Press Feedback（统一按压/悬停动效）
/// 所有 Button 组件共享的液态玻璃按压反馈修饰符：scale 压缩 + glow 光晕
/// 按压光晕跟随位置 —— 可复用的子视图
private struct PressGlow: View {
    let color: Color?
    let intensity: CGFloat
    let isPressed: Bool
    let isHovered: Bool
    let glowCenter: CGPoint  // 归一化坐标 0~1（几何读者传入）
    let size: CGSize

    private var active: Bool { isPressed || isHovered }
    private var glowOpacity: CGFloat {
        isPressed ? intensity * 0.65 : isHovered ? intensity * 0.20 : 0
    }
    private var blurRadius: CGFloat { isPressed ? 12 : 8 }

    var body: some View {
        ZStack {
            // 柔和光晕圆：跟随触摸点，尺寸随 press 状态放大
            Circle()
                .fill(color?.opacity(glowOpacity).scaledToWidth(80 + (isPressed ? 40 : 0), of: size))
                .blur(radius: blurRadius)
                .offset(x: glowCenter.x * size.width - size.width / 2,
                        y: glowCenter.y * size.height - size.height / 2)
            // 边缘高光描边（跟随手指，press 时更亮）
            Circle()
                .stroke(color?.opacity(isPressed ? intensity : isHovered ? intensity * 0.45 : 0),
                        lineWidth: isPressed ? 2.2 : isHovered ? 1.4 : 0)
                .frame(width: isPressed ? 72 : 56, height: isPressed ? 72 : 56)
                .offset(x: glowCenter.x * size.width - size.width / 2,
                        y: glowCenter.y * size.height - size.height / 2)
        }
    }
}

struct PressFeedback: ViewModifier {
    /// 按下时的缩放比例（0.88 = 明显压缩，0.93 = 轻微压缩）
    let pressScale: CGFloat
    /// 发光颜色（nil 时自动取内容前景色/ accentColor）
    let glowColor: Color?
    /// 发光强度（0~1）
    let glowIntensity: CGFloat
    /// 弹簧响应（越大越慢）
    let springResponse: CGFloat
    /// 弹簧阻尼（越小回弹越快）
    let springDamping: CGFloat

    @State private var isPressed  = false
    @State private var isHovered  = false
    @State private var touchPoint = CGPoint.zero   // 触摸点（几何空间坐标）
    @State private var geoSize    = CGSize.zero    // 容器尺寸

    func body(content: Content) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let cx = touchPoint.x / max(w, 1)
            let cy = touchPoint.y / max(h, 1)
            content
                // 缩放：按下压缩 / 悬停微放大
                .scaleEffect(isPressed ? pressScale : (isHovered ? 1.02 : 1.0))
                .animation(.spring(response: springResponse, dampingFraction: springDamping, blendDuration: 0.2),
                           value: isPressed)
                .animation(.spring(response: springResponse, dampingFraction: springDamping, blendDuration: 0.2),
                           value: isHovered)
                // 跟随手指的光晕叠加层
                .overlay(alignment: .center) {
                    PressGlow(color: glowColor, intensity: glowIntensity,
                              isPressed: isPressed, isHovered: isHovered,
                              glowCenter: CGPoint(x: cx, y: cy),
                              size: geo.size)
                }
                // 整体边框（静态）
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            glowColor?.opacity(isPressed ? glowIntensity * 0.5 : isHovered ? glowIntensity * 0.25 : 0),
                            lineWidth: isPressed ? 1.5 : isHovered ? 1.0 : 0
                        )
                )
                // 手势追踪：记录触摸位置 + press 状态
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .local)
                        .onChanged { v in
                            touchPoint = v.location
                            isPressed  = true
                        }
                        .onEnded   { _ in isPressed = false }
                )
                // 悬停（iPad / 桌面）
                .onHover { hovered in isHovered = hovered }
                // 记录容器尺寸
                .onAppear { geoSize = geo.size }
                .onChange(of: geo.size) { geoSize = $0 }
        }
    }
}

/// 带液态玻璃按压反馈的 Button 包装器
/// - Parameters:
///   - action: 点击回调
///   - scale: 按压缩放比例，默认 0.93（轻微）；0.88（明显）
///   - glowColor: 发光颜色，nil 时取 AccentColor
///   - label: 按钮内容
@ViewBuilder
func GlowButton<T: View>(
    scale: CGFloat = 0.93,
    glowColor: Color? = nil,
    @ViewBuilder label: () -> T
) -> some View {
    label()
        .modifier(PressFeedback(
            pressScale:      scale,
            glowColor:       glowColor,
            glowIntensity:   1.0,
            springResponse:  0.4,
            springDamping:   0.65
        ))
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
        .modifier(PressFeedback(pressScale: 0.90,
                                glowColor: tint,
                                glowIntensity: 0.5,
                                springResponse: 0.35,
                                springDamping: 0.60))
        .liquidGlassRipple(cornerRadius: Theme.Radius.small)
    }
}

// MARK: - 快捷控制大圆钮（车控首页）
struct QuickControlButton: View {
    let icon: String
    let label: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        GlowButton(scale: 0.88, glowColor: tint) {
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
        }
        .liquidGlassRipple(cornerRadius: Theme.Radius.hero)
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
        )
        .modifier(PressFeedback(pressScale: 0.93, glowColor: barColor, glowIntensity: 1.0,
                                springResponse: 0.4, springDamping: 0.65))
        .liquidGlassRipple(cornerRadius: Theme.Radius.small)
    }
}

// =============================================================================
// HeartbeatPulse —— 双拍心跳脉冲效果 ViewModifier
// 模拟真实心电图（ECG）波形：快速收缩（systole）→ 舒张（diastole）→ 短暂停顿
// 用于 SOC / 健康评分圆环的实时脉冲光环，替代无效的 easeInOut repeatForever。
// =============================================================================

struct HeartbeatPulse: ViewModifier {
    @State private var t: CGFloat = 0

    /// 双拍心跳波形（0→1 周期），返回当前脉冲强度
    /// T 在 0～5s 循环，形成「咚-咚」→ 回弹 → 短暂停顿的经典心率形态
    private static func beatIntensity(t: CGFloat) -> CGFloat {
        // 每 5s 一个完整心跳周期
        let cycle = t * 2 * .pi / 5.0
        // 双峰：主峰（systole）+ 次峰（dicrotic notch）
        let peak1 = exp(-pow(sin(cycle * 0.5), 2) * 8.0)
        let peak2 = exp(-pow(sin(cycle * 0.5 + 0.9), 2) * 12.0)
        let raw = peak1 + peak2 * 0.55
        return min(1.0, raw * 1.8)
    }

    func body(content: Content) -> some View {
        let intensity = HeartbeatPulse.beatIntensity(t: t)
        content
            .scaleEffect(1.0 + intensity * 0.06)
            .opacity(0.6 + intensity * 0.4)
            .blur(radius: intensity * 3)
            .animation(.linear(duration: 5.0).repeatForever(autoreverses: false), value: t)
            .onAppear { t = 0 }
    }
}

// =============================================================================
// FluidHeroFont —— iOS 27 流体数字字体
// 根据容器宽度动态计算字号，确保数字在不同屏幕尺寸上始终占据最佳视觉比例
// 同时保持设计令牌驱动，方便统一调整基础参数
// =============================================================================

/// 流体 Hero 数字字体组件
/// - Parameters:
///   - text: 要显示的文字内容（如 "85"、"92"）
///   - unit: 单位文字（如 "%"、"分"）
///   - baseSize: 基准字号（默认 80pt，对应 iPhone 标准屏宽）
///   - minSize: 最小字号（默认 56pt，防止小屏字号过小）
///   - maxSize: 最大字号（默认 96pt，防止大屏字号过大）
///   - weight: 字重（默认 bold）
///   - design: 字体设计（默认 rounded，符合 iOS 27 风格）
struct FluidHeroFont: View {
    let text: String
    let unit: String?
    let baseSize: CGFloat
    let minSize: CGFloat
    let maxSize: CGFloat
    let weight: Font.Weight
    let design: Font.Design?

    init(
        _ text: String,
        unit: String? = nil,
        baseSize: CGFloat = 80,
        minSize: CGFloat = 56,
        maxSize: CGFloat = 96,
        weight: Font.Weight = .bold,
        design: Font.Design? = .rounded
    ) {
        self.text = text
        self.unit = unit
        self.baseSize = baseSize
        self.minSize = minSize
        self.maxSize = maxSize
        self.weight = weight
        self.design = design
    }

    var body: some View {
        GeometryReader { geo in
            let containerWidth = geo.size.width
            // 流体比例：以 baseSize 为基准，根据容器宽度按比例缩放
            // 设计令牌：默认基准宽度 390pt（iPhone 14 Pro 标准屏宽）
            let fluidScale = max(minSize / baseSize, min(containerWidth / 390.0, maxSize / baseSize))
            let fontSize = baseSize * fluidScale

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(text)
                    .font(.system(size: fontSize, weight: weight, design: design))
                if let unit {
                    Text(unit)
                        .font(.system(size: fontSize * 0.45, weight: weight, design: design))
                        .offset(y: -fontSize * 0.05)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.5)
        }
        .frame(maxWidth: .infinity)
    }
}

/// 流体百分比数字（SOC / 健康评分专用）
struct FluidPercentHero: View {
    let text: String
    let minSize: CGFloat
    let maxSize: CGFloat

    init(_ text: String, minSize: CGFloat = 56, maxSize: CGFloat = 96) {
        self.text = text
        self.minSize = minSize
        self.maxSize = maxSize
    }

    var body: some View {
        FluidHeroFont(
            text,
            unit: "%",
            minSize: minSize,
            maxSize: maxSize
        )
    }
}

/// 流体评分数字（健康报告专用）
struct FluidScoreHero: View {
    let text: String
    let minSize: CGFloat
    let maxSize: CGFloat

    init(_ text: String, minSize: CGFloat = 56, maxSize: CGFloat = 96) {
        self.text = text
        self.minSize = minSize
        self.maxSize = maxSize
    }

    var body: some View {
        FluidHeroFont(
            text,
            unit: "分",
            minSize: minSize,
            maxSize: maxSize
        )
    }
}

// =============================================================================
// LiquidRipple —— iOS 27 液态玻璃水波纹点击反馈
// 三层同心涟漪：中心白色高光 + 中层蓝色光晕 + 外层扩散淡出
// 所有涟漪严格约束在卡片圆角内，不溢出边界
// =============================================================================

/// iOS 27 Liquid Glass 水波纹点击反馈（三层同心涟漪）
struct LiquidRipple: ViewModifier {
    @State private var rippleCenter: CGPoint = .zero
    @State private var rippleActive = false
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        // 先 clip 到圆角，再叠加涟漪
        content
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            // 手势层（在 clip 之外，保证触摸坐标准确）
            .simultaneousGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { v in
                        rippleCenter = v.location
                    }
                    .onEnded { _ in
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.55, blendDuration: 0.2)) {
                            rippleActive = true
                        }
                    }
            )
            // 三层同心涟漪叠加层
            .overlay {
                if rippleActive {
                    ZStack {
                        // 外层扩散环：最大半径，最淡，最先消失
                        Circle()
                            .fill(Color.white.opacity(0.18))
                            .scaleEffect(rippleActive ? 6.0 : 0.0)
                            .frame(width: 50, height: 50)
                            .position(rippleCenter)
                        // 中层蓝色光晕：中等半径，蓝色 tint，模拟液体折射
                        Circle()
                            .fill(Color.blue.opacity(0.12))
                            .scaleEffect(rippleActive ? 4.0 : 0.0)
                            .frame(width: 50, height: 50)
                            .position(rippleCenter)
                        // 内层白色高光：最小半径，最亮，模拟接触点
                        Circle()
                            .fill(Color.white.opacity(0.45))
                            .scaleEffect(rippleActive ? 2.5 : 0.0)
                            .frame(width: 50, height: 50)
                            .position(rippleCenter)
                    }
                }
            }
            // 0.7s 后自动清除状态
            .onChange(of: rippleActive) { active in
                if !active { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
                    withAnimation(.easeOut(duration: 0.15)) {
                        rippleActive = false
                    }
                }
            }
    }
}

/// 为玻璃卡片添加水波纹涟漪效果
/// - Parameter cornerRadius: 圆角半径，涟漪将严格约束在此范围内
func liquidGlassRipple(cornerRadius: CGFloat = Theme.Radius.card) -> some View {
    self.modifier(LiquidRipple(cornerRadius: cornerRadius))
}

// =============================================================================
// GlassRefreshRipple —— 下拉刷新时的全屏玻璃涟漪扩散动效
// 绑定 isRefreshing 状态：true 时从中心扩散一圈半透明光晕，false 时淡出
// =============================================================================

/// iOS 27 Liquid Glass 下拉刷新涟漪动效
/// - Parameter isRefreshing: 绑定刷新状态（true = 正在刷新，触发扩散动画）
struct GlassRefreshRipple: ViewModifier {
    @Binding var isRefreshing: Bool
    @State private var ripplePhase: CGFloat = 0  // 0→1 表示扩散进度

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .center) {
                if isRefreshing || ripplePhase > 0 {
                    ZStack {
                        // 背景光晕：大面积柔和扩散
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [.white.opacity(0.12), .clear],
                                    startPoint: .center,
                                    endPoint: .bottom
                                )
                            )
                            .scaleEffect(ripplePhase * 3.5)
                            .opacity(max(0, 1 - ripplePhase * 0.8))
                        // 核心光晕：中心高亮扩散
                        Circle()
                            .fill(Color.white.opacity(0.18))
                            .scaleEffect(ripplePhase * 1.8)
                            .opacity(max(0, 1 - ripplePhase * 1.2))
                    }
                    .frame(width: UIScreen.main.bounds.width * 1.5,
                           height: UIScreen.main.bounds.width * 1.5)
                }
            }
            .onChange(of: isRefreshing) { refreshing in
                if refreshing {
                    // 开始扩散
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.55, blendDuration: 0.3)) {
                        ripplePhase = 1.0
                    }
                } else {
                    // 淡出消失
                    withAnimation(.easeOut(duration: 0.35)) {
                        ripplePhase = 0
                    }
                }
            }
    }
}

/// 为页面添加下拉刷新玻璃涟漪动效
/// - Parameter isRefreshing: 绑定刷新状态
func glassRefreshRipple(isRefreshing: Binding<Bool>) -> some View {
    self.modifier(GlassRefreshRipple(isRefreshing: isRefreshing))
}

// =============================================================================
// Dynamic Type —— 大字体模式自适应工具
// 根据系统动态类型设置自动缩放间距、边距和字体，确保可读性和布局完整性
// =============================================================================

/// Dynamic Type 缩放因子（根据 ContentSizeCategory 返回倍数）
enum DynamicTypeScale {
    static func factor(for size: ContentSizeCategory) -> CGFloat {
        switch size {
        case .xxLarge, .large, .extraLarge, .medium, .small, .accessibilityMedium:
            return 1.0
        case .accessibilityExtraLarge:
            return 1.15
        case .accessibilityHuge:
            return 1.3
        case .accessibilityExtraExtraHuge:
            return 1.5
        case .accessibilityExtraExtraExtraHuge:
            return 1.7
        case .accessibilityExtraExtraExtraExtraHuge:
            return 2.0
        @unknown default:
            return 1.0
        }
    }

    /// 将基准间距乘以当前 Dynamic Type 缩放因子
    static func spacing(_ base: CGFloat, for size: ContentSizeCategory) -> CGFloat {
        base * factor(for: size)
    }

    /// 将基准 padding 乘以当前 Dynamic Type 缩放因子
    static func padding(_ base: CGFloat, for size: ContentSizeCategory) -> CGFloat {
        base * factor(for: size)
    }
}

// MARK: - Dynamic Type View 扩展
extension View {
    /// 应用 Dynamic Type 感知的水平内边距（自适应页面左右留白）
    func adaptivePagePadding(_ size: ContentSizeCategory) -> some View {
        self.padding(.horizontal, DynamicTypeScale.padding(Theme.Spacing.page, for: size))
    }

    /// 应用 Dynamic Type 感知的 VStack/HStack 间距
    func adaptiveSpacing(_ base: CGFloat, _ size: ContentSizeCategory) -> some View {
        self.spacing(DynamicTypeScale.spacing(base, for: size))
    }

    /// 应用 Dynamic Type 感知的安全区域底部 padding
    func adaptiveSafeAreaBottom(_ base: CGFloat, _ size: ContentSizeCategory) -> some View {
        self.safeAreaPadding(.bottom, DynamicTypeScale.padding(base, for: size))
    }

    /// 动态类型字号限制：大字体模式下限制行数，防止溢出
    func dynamicTypeLineLimit(_ limit: Int = 3) -> some View {
        self.lineLimit(limit)
    }
}

// MARK: - DynamicTypeCompressModifier
/// 玻璃卡片内容压缩：大字体模式下自动缩减间距、限制行数、压缩内边距
struct DynamicTypeCompressModifier: ViewModifier {
    @Environment(\.dynamicTypeSize) private var size

    private var isCompressThreshold: Bool { size.isLargeOrBigger }

    private var compressRatio: CGFloat {
        guard isCompressThreshold else { return 1.0 }
        switch size {
        case .accessibilityMedium, .large, .extraLarge:
            return 0.75
        case .accessibilityLarge:
            return 0.60
        default:
            return 0.45
        }
    }

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, compressRatio * Theme.Spacing.page)
            .padding(.vertical, compressRatio * Theme.Spacing.md)
    }
}

// MARK: - DynamicTypeTextCompressModifier
/// 文字行限制压缩：大字体模式下自动限制文本行数
struct DynamicTypeTextCompressModifier: ViewModifier {
    @Environment(\.dynamicTypeSize) private var size
    let isTitle: Bool

    private var lineLimit: Int {
        guard size.isLargeOrBigger else { return 3 }
        if isTitle {
            switch size {
            case .accessibilityMedium, .large, .extraLarge:
                return 2
            default:
                return 1
            }
        } else {
            return 3
        }
    }

    func body(content: Content) -> some View {
        content.lineLimit(lineLimit)
    }
}

// MARK: - DynamicType 扩展
extension View {
    /// 应用玻璃卡片内容压缩（间距+padding）
    func dynamicTypeCompress() -> some View {
        self.modifier(DynamicTypeCompressModifier())
    }

    /// 应用文字行限制压缩
    func dynamicTypeTextCompress(isTitle: Bool = false) -> some View {
        self.modifier(DynamicTypeTextCompressModifier(isTitle: isTitle))
    }
}

// MARK: - ContentSizeCategory 辅助扩展
extension ContentSizeCategory {
    /// 判断是否为大字体模式（.extraLarge 及以上）
    var isLargeOrBigger: Bool {
        switch self {
        case .large, .extraLarge,
             .accessibilityMedium, .accessibilityLarge,
             .accessibilityExtraLarge, .accessibilityExtraExtraLarge,
             .accessibilityExtraExtraExtraLarge, .accessibilityExtraExtraExtraExtraLarge:
            return true
        default:
            return false
        }
    }

    /// 获取当前字号对应的行限制（1=标题紧凑，2=正文，3=默认）
    var lineLimitForTitle: Int {
        guard isLargeOrBigger else { return 3 }
        switch self {
        case .accessibilityMedium, .large, .extraLarge:
            return 2
        default:  // accessibilityLarge 及以上
            return 1
        }
    }

    /// 获取当前字号对应的内边距压缩比例
    var paddingCompression: CGFloat {
        guard isLargeOrBigger else { return 1.0 }
        switch self {
        case .accessibilityMedium, .large, .extraLarge:
            return 0.80   // 压缩 20%
        case .accessibilityLarge:
            return 0.65   // 压缩 35%
        default:  // accessibilityExtraLarge 及以上
            return 0.50   // 压缩 50%
        }
    }
}


// =============================================================================
// Page State Views —— 统一的加载 / 错误 / 空状态展示组件
// 所有 Feature 页面统一使用，确保深浅双模式下视觉一致
// =============================================================================

/// 页面加载中状态（全屏玻璃卡片 + 旋转进度指示）
struct PageLoadingView: View {
    let message: String

    init(_ message: String = "正在加载…") {
        self.message = message
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            ProgressView()
                .controlSize(.large)
                .tint(.accentColor)
                .scaleEffect(1.1)
            Text(message)
                .font(Theme.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xxl)
        .glassCard()
    }
}

/// 页面加载失败状态（玻璃卡片 + 重试按钮）
struct PageErrorView: View {
    let message: String
    let retryAction: () -> Void

    init(_ message: String, retry: @escaping () -> Void) {
        self.message = message
        self.retryAction = retry
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
                .foregroundStyle(Theme.warn)
                .padding(.bottom, 4)
            Text(message)
                .font(Theme.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Spacing.lg)
            Button("重新加载") { retryAction() }
                .buttonStyle(.borderedProminent)
                .tint(.accentColor)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xl)
        .glassCard()
    }
}

/// 页面空状态（无数据但无错误）
struct PageEmptyView: View {
    let title: String
    let subtitle: String
    let icon: String

    init(_ title: String, subtitle: String = "", icon: String = "doc.text") {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 36, weight: .medium))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(Theme.h4)
                .foregroundStyle(.primary)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(Theme.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xxl)
        .glassCard()
    }
}

