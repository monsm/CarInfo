import SwiftUI
import CoreHaptics
import AVFoundation
import Photos

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
    static var pageAccent: Color { .accent }
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
    static var acc: Color { Color.accent }
    static var na: Color { Color.secondary }

    // MARK: - 状态 → 语义色
    static func statusColor(_ cls: String) -> Color {
        switch cls {
        case "ok", "normal": return .green
        case "warn", "warning": return .orange
        case "bad", "fault", "abnormal": return .red
        case "acc": return .accent
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
        static let glow = GlowStyle(color: .accent, radius: 12, offset: 4)
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
    }


extension Theme {
    // MARK: - 字体尺寸
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
    var tint: Color = .accent
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
    func pageBackground(_ tint: Color = .accent) -> some View {
        background(PageBackground(tint: tint))
    }

    /// 双拍心跳脉冲效果（ECG 波形呼吸）
    func heartbeatPulse() -> some View { modifier(HeartbeatPulse()) }

    // MARK: - 数值变化液态玻璃脉冲高亮
    /// 当绑定值变化时，触发短暂的边缘发光脉冲（scale 1.0→1.06→1.0 + glow fade）
    /// 用于 SOC Hero、里程数字、胎压数值等关键数据卡片
    func valuePulse(tint: Color = .accent) -> some View {
        self.modifier(ValuePulseModifier(tint: tint))
    }

    // MARK: - 玻璃卡片修饰符
    /// 液态玻璃卡片背景 + 高光描边
    func glassCard(corner: CGFloat = Theme.Radius.card) -> some View {
        self.modifier(GlassCardModifier(cornerRadius: corner))
    }

    /// Hero 级玻璃卡片（更大圆角 + 更强阴影）
    func glassHeroCard(corner: CGFloat = Theme.Radius.hero) -> some View {
        self.modifier(GlassCardModifier(cornerRadius: corner, isHero: true))
    }

    /// 长按液态玻璃弹性形变（scale 1→0.94 + 光晕扩散 + 弹簧回弹）
    func glassLongPressDeform() -> some View {
        self.modifier(GlassLongPressDeformModifier())
    }
}

// MARK: - Tab 玻璃容器
/// 为 Tab 内容视图添加液态玻璃磨砂背景和微阴影，形成独立的"玻璃页"视觉层级
struct tabGlassModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Material.thin.opacity(0.85))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8)
                    )
                    .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
            )
            .padding(.horizontal, 2)
    }
}

// =============================================================================
// GlassCardModifier —— 液态玻璃卡片背景
// =============================================================================
struct GlassCardModifier: ViewModifier {
    let cornerRadius: CGFloat
    let isHero: Bool

    private var shadowY: CGFloat { isHero ? 6 : 3 }
    private var shadowRadius: CGFloat { isHero ? 22 : 14 }

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Material.thin)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [.white.opacity(0.22), .white.opacity(0.04)],
                                    startPoint: .top, endPoint: .bottom
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: .black.opacity(isHero ? 0.12 : 0.07), radius: shadowRadius, y: shadowY)
            )
    }
}

// =============================================================================
// GlassLongPressDeformModifier —— 长按液态玻璃弹性形变
// 按压时：scale 1→0.94 压缩 + 光晕扩散 + 边框发光
// 松手时：弹簧回弹（response:0.5, damping:0.6）
// =============================================================================
struct GlassLongPressDeformModifier: ViewModifier {
    @State private var isLongPressed = false
    @State private var pressScale: CGFloat = 1.0
    @State private var glowOpacity: CGFloat = 0

    private let pressDuration = 0.18   // 长按判定阈值（秒）
    private let holdScale: CGFloat = 0.94

    func body(content: Content) -> some View {
        // 深色模式下使用 accentColor 折射光，浅色模式使用白色光
        let glowTint: Color = Color.red == .accent ? .white : .accent
        content
            .scaleEffect(pressScale)
            .animation(.spring(response: 0.5, dampingFraction: 0.6, blendDuration: 0.35), value: pressScale)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(Color.clear)
                    .strokeBorder(
                        LinearGradient(
                            colors: [glowTint.opacity(glowOpacity * 0.45), glowTint.opacity(glowOpacity * 0.08)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        lineWidth: glowOpacity * 1.5
                    )
                    .shadow(color: glowTint.opacity(glowOpacity * 0.25), radius: glowOpacity * 10, y: 0)
            )
            .onTapGesture(count: 1) { }  // 占位，确保手势接收
            .simultaneousGesture(
                LongPressGesture(minimumDuration: pressDuration)
                    .onEnded { _ in
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.6, blendDuration: 0.35)) {
                            pressScale = holdScale
                            glowOpacity = 1.0
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + pressDuration * 0.5) {
                            withAnimation(.spring(response: 0.55, dampingFraction: 0.65, blendDuration: 0.4)) {
                                pressScale = 1.0
                                glowOpacity = 0.0
                            }
                        }
                    }
            )
    }
}

// =============================================================================
// ValuePulseModifier —— 数值变化时液态玻璃边缘发光脉冲
// 绑定值变化 → scale 轻微放大 + 边缘 glow 扩散 + 柔和阴影爆发
// =============================================================================

// =============================================================================
// ValuePulseModifier —— 数值变化时液态玻璃边缘发光脉冲
// 绑定值变化 → scale 轻微放大 + 边缘 glow 扩散 + 柔和阴影爆发
// =============================================================================
struct ValuePulseModifier: ViewModifier {
    @Binding var watchValue: String
    let tint: Color
    @State private var pulsePhase: Double = 0

    func body(content: Content) -> some View {
        content
            .scaleEffect(1.0 + pulsePhase * 0.04)
            .shadow(color: tint.opacity(pulsePhase * 0.5), radius: 8 * CGFloat(pulsePhase), y: 0)
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                    .strokeBorder(tint.opacity(pulsePhase * 0.35), lineWidth: 1.5)
                    .blur(radius: 3 * CGFloat(pulsePhase))
            }
            .onChange(of: watchValue) { newValue in
                guard !newValue.isEmpty else { return }
                withAnimation(.spring(response: 0.4, dampingFraction: 0.55, blendDuration: 0.2)) {
                    pulsePhase = 1.0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
                    withAnimation(.easeOut(duration: 0.35)) {
                        pulsePhase = 0
                    }
                }
            }
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

// MARK: - 可展开玻璃卡片（标题行点击触发弹簧高度过渡 + 液态玻璃形变）
struct ExpandingCardBox<Content: View>: View {
    let title: String
    var side: String? = nil
    var sideCls: String = ""
    let cornerRadius: CGFloat
    @ViewBuilder var content: () -> Content

    @State private var isExpanded = false
    @State private var tapCount = 0
    @State private var lastTapTime: Date? = nil

    private var chevronAngle: Angle { isExpanded ? .degrees(90) : .degrees(0) }
    /// 双击标题行时批量切换所有子卡片的展开状态
    private func onDoubleTap() {
        let now = Date()
        if let last = lastTapTime, now.timeIntervalSince(last) < 0.35 {
            // 双击：切换所有子卡片的展开状态（反向）
            withAnimation(.spring(response: 0.5, dampingFraction: 0.65, blendDuration: 0.35)) {
                isExpanded.toggle()
            }
            tapCount = 0
            lastTapTime = nil
        } else {
            tapCount = 1
            lastTapTime = now
            // 延迟 0.4s 重置（如未触发双击则视为单tap）
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                if self.tapCount == 1 {
                    self.tapCount = 0
                    self.lastTapTime = nil
                }
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── 标题行（单击展开/收起；双击批量切换）──
            Button {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.65, blendDuration: 0.35)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(Theme.h4)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let side, !side.isEmpty {
                        Pill(text: side, cls: sideCls.isEmpty ? "na" : sideCls, dot: false)
                    }
                    Image(systemName: "chevron.right")
                        .font(Theme.footnote.bold())
                        .foregroundStyle(.tertiary)
                        .rotationEffect(chevronAngle)
                        .animation(.spring(response: 0.35, dampingFraction: 0.6), value: isExpanded)
                }
                .padding(Theme.Spacing.xl)
            }
            .buttonStyle(.plain)
            .glassLongPressDeform()
            .liquidGlassRipple(cornerRadius: cornerRadius)

            // ── 内容区（弹簧高度过渡）──
            if isExpanded {
                content()
                    .padding(.horizontal, Theme.Spacing.xl)
                    .padding(.bottom, Theme.Spacing.lg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .topLeading) {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.12))
                            .frame(height: 1)
                            .padding(.horizontal, -Theme.Spacing.xl)
                    }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(corner: cornerRadius)
    }
}

// MARK: - 统计小磁贴（hover 液态玻璃光晕）
struct StatTile: View {
    let icon: String
    let label: String
    let value: String
    var unit: String = ""
    var tint: Color = .accent

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
                .fill(Material.thin)
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

// MARK: - 运行中呼吸光晕
/// 液态玻璃风格呼吸光晕：卡片出现时从中心向外扩散的柔和光晕脉冲
/// 用于 ControlView runningCard、HomeView SOC Hero 等需要"活跃"感知的状态
struct RunningGlow: ViewModifier {
    let color: Color
    @State private var pulsePhase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay {
                // 扩散光晕层（始终在卡片背后）
                Circle()
                    .fill(AngularGradient(
                        colors: [color.opacity(0.35), color.opacity(0.08), .clear],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360)
                    ))
                    .frame(width: 200, height: 200)
                    .scaleEffect(1.0 + pulsePhase * 0.3)
                    .opacity((1.0 - pulsePhase) * 0.6)
                    .blur(radius: pulsePhase * 8)
                    .allowsHitTesting(false)
            }
            .animation(
                .easeInOut(duration: 2.0).repeatForever(autoreverses: false),
                value: pulsePhase
            )
            .onAppear { pulsePhase = 0.5 }  // 起始在中间相位，避免闪烁
    }
}

/// 为视图添加液态玻璃呼吸光晕效果
/// - Parameter color: 光晕主色调（默认 accentColor）
func runningGlow(color: Color = .accent) -> some View {
    self.modifier(RunningGlow(color: color))
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
    var tint: Color = .accent
    /// 是否使用流体数字字体（随容器宽度自动缩放，仅适用于较大数值的 Hero 场景）
    var fluidValue: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(Theme.micro)
                .foregroundStyle(tint.opacity(0.85))
            if fluidValue {
                FluidHeroFont(value, minSize: 18, maxSize: 32)
                    .foregroundStyle(.primary)
            } else {
                Text(value)
                    .font(Theme.mono)
                    .foregroundStyle(.primary)
            }
            if !unit.isEmpty {
                Text(unit).font(Theme.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(.ultraThinMaterial,
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
            .accessibilityLabel(Text(label))
            .accessibilityHint(Text("点击执行远程" + label + "操作"))
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
    var watchValue: String = ""  // B7: 数值变化脉冲触发器
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
                    .valuePulse(tint: barColor, watchValue: watchValue)
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
// EKGFloRing —— EKG 心电图波形沿圆环流动动画
// 首尾相连的波形沿圆环持续行进，模拟真实心电图监测仪效果
// =============================================================================

/// EKG 心电图描边流动环
/// 将经典的 P-QRS-T 波形采样为封闭圆形路径，通过 dashOffset 动画实现首尾相连的流动效果
struct EKGFloRing: View {
    let size: CGFloat        // 圆环直径
    let color: Color         // 波形颜色（随状态变化）
    let lineWidth: CGFloat   // 描边宽度
    let speed: Double        // 流动速度（秒/完整周期），默认 3s

    init(size: CGFloat, color: Color, lineWidth: CGFloat = 1.5, speed: Double = 3.0) {
        self.size = size
        self.color = color
        self.lineWidth = lineWidth
        self.speed = speed
    }

    var body: some View {
        Circle()
            .stroke(
                color.opacity(0.55),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
            )
            .frame(width: size, height: size)
            // dash pattern：波形周期 * 4 个完整 P-QRS-T 波形，总长 = 4 cycles
            // dashOffset 从周期长度滚动到 0，形成连续流动
            .animation(
                .linear(duration: speed).repeatForever(autoreverses: false),
                value: _animOffset
            )
            .overlay(alignment: .center) {
                // 发光层：与波形同相位，增强视觉深度
                Circle()
                    .stroke(color.opacity(0.18), style: StrokeStyle(lineWidth: lineWidth + 3, lineCap: .round))
                    .frame(width: size + 6, height: size + 6)
                    .blur(radius: 2)
                    .animation(
                        .linear(duration: speed).repeatForever(autoreverses: false),
                        value: _animOffset
                    )
            }
    }

    // 每周期包含 4 个完整 P-QRS-T 波形的 dash 序列（单位：pt，基于 size=100 基准圆周长 ≈ 314pt）
    // 每个波形周期约 78.5pt，4 个周期 = 314pt ≈ 2πR
    private var dashPattern: [CGFloat] {
        let base = size * .pi  // 圆周长 = 2πr = π·size
        // 单个 P-QRS-T 波形形状（相对振幅）：
        // P 波：小幅隆起  |  QRS：尖锐负-正-负  |  T 波：中等隆起  |  基线：平
        // 采样为 40 段折线，作为 dash array 使用
        let segments: [CGFloat] = [
            12.0,   // 平基线
            2.0,    // P 波起点
            1.5,    // P 波升支
            1.0,    // P 波峰
            1.5,    // P 波降支
            3.0,    // 平基线到 Q
            1.0,    // Q 下冲
            0.8,    // 谷底
            1.0,    // R 上冲（主峰）
            1.5,    // R 顶点
            1.2,    // R 降支
            1.5,    // S 下冲
            1.0,    // 谷底
            2.0,    // 回到基线
            4.0,    // ST 段平
            3.0,    // T 波升支
            2.0,    // T 波峰
            3.0,    // T 波降支
            6.0,    // 平基线
        ]
        // 缩放到圆周长比例
        let total = segments.reduce(0, +)
        let scale = base / total
        return segments.map { $0 * scale }
    }

    @State private var _animOffset: CGFloat = 0
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

/// 流体温度数字（空调 HeroDisc 专用）
/// 在 80pt 圆形容器内自适应缩放，最小 30pt / 最大 44pt
struct FluidTempHero: View {
    let text: String
    let minSize: CGFloat
    let maxSize: CGFloat

    init(_ text: String, minSize: CGFloat = 30, maxSize: CGFloat = 44) {
        self.text = text
        self.minSize = minSize
        self.maxSize = maxSize
    }

    var body: some View {
        FluidHeroFont(
            text,
            unit: nil,
            minSize: minSize,
            maxSize: maxSize
        )
    }
}

// MARK: - 健康系统小圆环统计卡（带心跳脉冲）
struct HealthSystemRing: View {
    let name: String
    let statusCls: String
    let statusText: String
    let pct: Int

    private var ringColor: Color { Theme.statusColor(statusCls) }
    private var ringColors: [Color] {
        switch statusCls {
        case "bad":   return [.red, .red, .orange]
        case "warn":  return [.orange, .orange, .yellow]
        default:      return [.green, .green, .teal]
        }
    }
    private var glowColors: [Color] {
        switch statusCls {
        case "bad":   return [.red.opacity(0.6), .clear]
        case "warn":  return [.orange.opacity(0.5), .clear]
        default:      return [.green.opacity(0.5), .teal.opacity(0.3)]
        }
    }

    var body: some View {
        ZStack {
            // 第 1 层：外层扩散光晕
            Circle()
                .fill(AngularGradient(colors: glowColors,
                                      center: .center, startAngle: .degrees(-90), endAngle: .degrees(270)))
                .frame(width: 48, height: 48)
                .opacity(0.20)
                .blur(radius: 4)

            // 第 2 层：心跳脉冲光环
            Circle()
                .strokeBorder(ringColor.opacity(0.25), lineWidth: 1.5)
                .frame(width: 44, height: 44)
                .heartbeatPulse()

            // 第 3 层：底色轨道
            Circle()
                .stroke(Color(.systemGray5).opacity(0.40), lineWidth: 5)
                .frame(width: 38, height: 38)

            // 第 4 层：彩色进度弧
            Circle()
                .trim(from: 0, to: max(0.02, CGFloat(pct) / 100))
                .stroke(AngularGradient(colors: ringColors,
                                        center: .center, startAngle: .degrees(-90), endAngle: .degrees(270)),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 38, height: 38)

            // 第 5 层：中心百分比
            Text("\(pct)%")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(ringColor)
        }
        .frame(width: 48, height: 48)
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

// =============================================================================
// GlassRefreshHalo —— 下拉刷新时玻璃光晕消散再汇聚过渡动效
// 效果：页面内容上的柔和玻璃光晕在刷新开始时消散（opacity 1→0），
// 数据拉取完成后重新汇聚（opacity 0→1，弹簧回弹），形成「液态玻璃呼吸」质感。
// 与 glassRefreshRipple 配合使用：ripple 提供触点扩散，halo 提供整体氛围。
// =============================================================================

struct GlassRefreshHalo: ViewModifier {
    @Binding var isRefreshing: Bool
    @State private var haloOpacity: CGFloat = 1.0

    func body(content: Content) -> some View {
        content
            // 玻璃光晕层：大面积柔和品牌色径向渐变，覆盖整个页面
            .overlay(alignment: .center) {
                if haloOpacity > 0.001 {
                    ZStack {
                        // 外层大范围柔和散射
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        .white.opacity(0.10),
                                        .white.opacity(0.04),
                                        Theme.brand.opacity(0.03),
                                        .clear
                                    ],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: 500
                                )
                            )
                            .frame(width: 700, height: 700)
                        // 内层高亮核心
                        Circle()
                            .fill(Color.white.opacity(0.06))
                            .frame(width: 280, height: 280)
                    }
                    .allowsHitTesting(false)
                }
            }
            .onChange(of: isRefreshing) { refreshing in
                if refreshing {
                    // 刷新开始：光晕消散（0.5s ease-in）
                    withAnimation(.easeIn(duration: 0.5)) {
                        haloOpacity = 0
                    }
                } else {
                    // 刷新结束：光晕重新汇聚（0.8s 弹簧回弹）
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.65, blendDuration: 0.5)) {
                        haloOpacity = 1
                    }
                }
            }
    }
}

/// 为页面添加下拉刷新玻璃光晕消散/汇聚动效
/// - Parameter isRefreshing: 绑定刷新状态（true = 开始消散，false = 重新汇聚）
func glassRefreshHalo(isRefreshing: Binding<Bool>) -> some View {
    self.modifier(GlassRefreshHalo(isRefreshing: isRefreshing))
}

/// 为页面添加下拉刷新玻璃涟漪动效
/// - Parameter isRefreshing: 绑定刷新状态
func glassRefreshRipple(isRefreshing: Binding<Bool>) -> some View {
    self.modifier(GlassRefreshRipple(isRefreshing: isRefreshing))
}

// =============================================================================
// GlassSwitchRipple —— 切换车辆时的全屏玻璃涟漪扩散动效
// 从页面中心向外扩散一圈品牌色光晕，模拟液态玻璃从触点向外扩散的质感
// 与 glassRefreshHalo 配合：涟漪负责扩散，光晕负责整体氛围切换
// =============================================================================

/// iOS 27 Liquid Glass 车辆切换涟漪动效
/// 从页面中心向外扩散品牌色光晕，模拟液态玻璃从触点扩散的质感
struct GlassSwitchRipple: ViewModifier {
    @Binding var isSwitching: Bool
    @State private var ripplePhase: CGFloat = 0  // 0→1 表示扩散进度

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .center) {
                if ripplePhase > 0 {
                    ZStack {
                        // 外层大范围扩散：品牌色径向渐变
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        Theme.brand.opacity(0.25),
                                        Theme.brand.opacity(0.08),
                                        .clear
                                    ],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: 400
                                )
                            )
                            .scaleEffect(1.0 + ripplePhase * 2.8)
                            .opacity(max(0, 1 - ripplePhase * 1.0))
                        // 内层高亮核心：白色光晕
                        Circle()
                            .fill(Color.white.opacity(0.20))
                            .scaleEffect(1.0 + ripplePhase * 1.6)
                            .opacity(max(0, 1 - ripplePhase * 1.5))
                    }
                    .frame(width: UIScreen.main.bounds.width * 1.2,
                           height: UIScreen.main.bounds.height * 1.2)
                    .allowsHitTesting(false)
                }
            }
            .onChange(of: isSwitching) { switching in
                if switching {
                    // 开始扩散：spring 弹入
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.55, blendDuration: 0.25)) {
                        ripplePhase = 1.0
                    }
                } else {
                    // 淡出消失：easeOut 消散
                    withAnimation(.easeOut(duration: 0.3)) {
                        ripplePhase = 0
                    }
                }
            }
    }
}

/// 为页面添加切换车辆时的玻璃涟漪扩散动效
/// - Parameter isSwitching: 绑定切换标志（true = 触发扩散动画）
func glassSwitchRipple(isSwitching: Binding<Bool>) -> some View {
    self.modifier(GlassSwitchRipple(isSwitching: isSwitching))
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

/// 页面加载中状态（全屏玻璃卡片 + 旋转进度指示）— #25 带入场动画
struct PageLoadingView: View {
    let message: String
    @State private var opacity: CGFloat = 0
    @State private var spinAngle: Angle = .zero

    init(_ message: String = "正在加载…") {
        self.message = message
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            ZStack {
                // 外圈光晕
                Circle()
                    .stroke(Color.accent.opacity(0.2), lineWidth: 3)
                    .frame(width: 60, height: 60)
                // 旋转进度环
                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(AngularGradient(colors: [.accent, .blue], center: .center), lineWidth: 3)
                    .frame(width: 60, height: 60)
                    .rotationEffect(spinAngle)
                    .animation(.linear(duration: 1.2).repeatForever(autoreverses: false), value: spinAngle)
                // 中心图标
                Image(systemName: "car.fill")
                    .font(.title2)
                    .foregroundStyle(.accent)
            }
            Text(message)
                .font(Theme.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xxl)
        .glassCard(corner: 24)
        .opacity(opacity)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { opacity = 1 }
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                spinAngle = .degrees(360)
            }
        }
        .padding(.horizontal, Theme.Spacing.xl)
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
                .tint(.accent)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xl)
        .glassCard()
    }
}

/// 页面空状态（无数据但无错误）— #25 带液态玻璃插画风格
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
        VStack(spacing: Theme.Spacing.lg) {
            // 液态玻璃风格图标容器
            ZStack {
                Circle()
                    .fill(Material.thin)
                    .frame(width: 80, height: 80)
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
                    .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
                Image(systemName: icon)
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .scaleEffect(1.0)
            .animation(.spring(response: 0.5, dampingFraction: 0.7), value: icon)
            Text(title)
                .font(Theme.h4)
                .foregroundStyle(.primary)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(Theme.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xxl)
        .glassCard(corner: 24)
        .padding(.horizontal, Theme.Spacing.xl)
    }
}


// =============================================================================
// EKGFloRingDynamic —— 颜色随百分比动态变化的 EKG 流动环
// SOC < 20%: 红色  |  20%~50%: 橙色  |  50%~80%: 绿色  |  > 80%: 青绿
// =============================================================================

/// EKG 心电图描边流动环（颜色动态）
/// percentage: 0.0~1.0，决定波形颜色（红→橙→绿→青）
struct EKGFloRingDynamic: View {
    let size: CGFloat
    let lineWidth: CGFloat
    let speed: Double
    let percentage: Double   // 0.0 ~ 1.0

    var dynamicColor: Color {
        switch percentage {
        case ..<0.2:   return .red
        case ..<0.5:   return .orange
        case ..<0.8:   return .green
        default:       return Color.cyan
        }
    }

    var body: some View {
        EKGFloRing(size: size, color: dynamicColor, lineWidth: lineWidth, speed: speed)
    }
}

// =============================================================================
// DataFreshnessBadge —— #3 数据新鲜度徽章
// 根据时间差显示 🟢/🟡/🔴 颜色角标
// =============================================================================
struct DataFreshnessBadge: View {
    let timestamp: Date?
    let fontSize: CGFloat = 10

    var body: some View {
        if let ts = timestamp, Date().timeIntervalSince(ts) < 300 {
            let age = Int(Date().timeIntervalSince(ts) / 60)
            let color: Color = age < 3 ? .green : (age < 15 ? .orange : .red)
            let label: String = age < 1 ? "刚" : "\(age)分"
            HStack(spacing: 3) {
                Circle().fill(color).frame(width: 5, height: 5)
                Text(label).font(.system(size: fontSize, weight: .medium))
                    .foregroundStyle(color)
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
        }
    }
}

// =============================================================================
// NetworkStatusIndicator —— #4 网络状态顶部微条
// =============================================================================
struct NetworkStatusIndicator: View {
    let status: AppStore.NetworkStatus
    var body: some View {
        switch status {
        case .online:
            EmptyView()
        case .weak:
            HStack {
                Image(systemName: "wifi.exclamationmark").font(.system(size: 10))
                Text("弱网").font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(.orange)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.orange.opacity(0.12), in: Capsule())
            .frame(maxWidth: .infinity, alignment: .leading)
        case .offline:
            HStack {
                Image(systemName: "wifi.slash").font(.system(size: 10))
                Text("离线").font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(.red)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.red.opacity(0.12), in: Capsule())
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// =============================================================================
// LowBatteryBadge —— #5 低电量 Tab 角标
// =============================================================================
struct LowBatteryBadge: View {
    let socPct: Int
    var body: some View {
        if socPct < 20 {
            ZStack {
                Circle()
                    .fill(.red)
                    .frame(width: 8, height: 8)
                Circle()
                    .strokeBorder(.red, lineWidth: 1.5)
                    .frame(width: 12, height: 12)
                    .opacity(0.5)
                    .heartbeatPulse()
            }
            .offset(x: 10, y: -4)
        }
    }
}

// =============================================================================
// StaggeredEntrance —— #11 卡片入场序列动画修饰符
// =============================================================================
struct StaggeredEntranceModifier: ViewModifier {
    let index: Int
    let delay: CGFloat = 0.08
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1.0 : 0.0)
            .offset(y: appeared ? 0 : 20)
            .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + delay * CGFloat(index)) { appeared = true } }
    }
}

extension View {
    func staggeredEntrance(index: Int) -> some View {
        modifier(StaggeredEntranceModifier(index: index))
    }
}

// =============================================================================
// ReduceMotionAware —— #6 降低动态效果检测
// =============================================================================
extension View {
    func reduceMotionIfRequired<V: View>(_ content: () -> V) -> some View {
        if UIDevice.current.isReducingTransparency || UIAccessibility.isReduceMotionEnabled {
            content()
                .animation(nil, value: 0)
        } else {
            self
        }
    }
}

// =============================================================================
// ToastView —— iOS 27 Liquid Glass 全局 Toast 提示
// 底部胶囊形磨砂玻璃卡片，入场弹簧滑入、退场 easeOut 淡出
// =============================================================================

/// 全局 Toast 提示（由 NavState.currentItem 驱动，挂载在根视图上）
struct ToastView: View {
    let text: String
    let icon: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(Theme.caption.weight(.semibold))
                .foregroundStyle(.accent)
            Text(text)
                .font(Theme.caption.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.28), lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 14, y: 5)
        .padding(.bottom, 14)
        .padding(.horizontal, 24)
        .transition(
            .asymmetric(
                insertion: .move(edge: .bottom)
                    .combined(with: .opacity)
                    .animation(.spring(response: 0.45, dampingFraction: 0.6, blendDuration: 0.25)),
                removal: .opacity.animation(.easeOut(duration: 0.2))
            )
        )
    }
}

// =============================================================================
// ScrollBounceBehavior —— #12 自定义下拉刷新环形进度条
// 在每个 ScrollView 顶部注入一个 Liquid Glass 风格的环形进度指示器
// =============================================================================
struct RefreshProgressRing: View {
    let progress: Double
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.accent.opacity(0.15), lineWidth: 2)
                .frame(width: 16, height: 16)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 16, height: 16)
                .rotationEffect(.degrees(-90))
        }
    }
}

extension View {
    /// #12 下拉刷新环形进度条
    func refreshProgressRing(progress: Binding<CGFloat>) -> some View {
        self.overlay(alignment: .top) {
            if progress.wrappedValue > 0 {
                RefreshProgressRing(progress: Double(progress.wrappedValue))
                    .frame(width: 20, height: 20)
            }
        }
    }
}

// =============================================================================
// PowerSavingCheck —— #31 省电模式检测
// 当省电模式开启时，禁用所有动画和背景任务
// =============================================================================
enum PowerSavingMode {
    static var isEnabled: Bool { AppStore.shared.isPowerSaving }

    static func animation(_ anim: Animation?) -> Animation? {
        isEnabled ? nil : anim
    }

    static func shouldAnimate(_ condition: Bool) -> Bool {
        isEnabled ? false : condition
    }

    static func task(_ body: @escaping () async -> Void) -> Task<Void, Never>? {
        isEnabled ? nil : Task { await body() }
    }
}

// =============================================================================
// ShareableStatusCard —— #19 车况快照分享图（轻量版）
// 生成当前车况的简要描述文本用于分享
// =============================================================================
struct ShareableStatusInfo: Identifiable {
    let id = UUID()
    let soc: String
    let range: String
    let tireStatus: String
    let healthScore: String
    let cabinTemp: String
}

func generateShareableStatus(info: ShareableStatusInfo) -> String {
    return """
    🚗 我的车况快照
    • 电量：\(info.soc)%
    • 续航：\(info.range) km
    • 胎压：\(info.tireStatus)
    • 健康评分：\(info.healthScore)
    • 车内温度：\(info.cabinTemp)
    \n---
    长安车管家 App
    """
}

// =============================================================================
// MilestoneCelebration —— #26 里程里程碑庆祝动效
// =============================================================================
struct MilestoneCelebration: ViewModifier {
    let currentMileage: Int
    @State private var showCelebration = false
    @State private var celebrationText = ""

    func body(content: Content) -> some View {
        content
            .onChange(of: currentMileage) { newMileage in
                let milestones = [5000, 10000, 15000, 20000, 25000, 30000, 50000, 100000]
                if let prev = milestones.enumerated().first(where: { $0.element < newMileage })?.offset,
                   prev > 0 && milestones[prev - 1] < newMileage {
                    let milestone = milestones[min(prev, milestones.count - 1)]
                    celebrationText = "🎉 恭喜！已突破 \(milestone) km 里程碑！"
                    showCelebration = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        showCelebration = false
                    }
                }
            }
            .overlay(alignment: .top) {
                if showCelebration {
                    Text(celebrationText)
                        .font(Theme.caption.weight(.semibold))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.green.opacity(0.12), in: Capsule())
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: showCelebration)
                        .padding(.top, 60)
                }
            }
    }
}

extension View {
    func milestoneCelebration(mileage: Int) -> some View {
        modifier(MilestoneCelebration(currentMileage: mileage))
    }
}

// =============================================================================
// WeatherTheme — #41 天气联动主题
// 根据当前天气调整界面氛围（雨天粒子、低温霜冻感）
// =============================================================================
struct WeatherTheme {
    static var currentCondition: WeatherCondition = .clear
    
    enum WeatherCondition: String {
        case clear = "晴朗"
        case cloudy = "多云"
        case rainy = "下雨"
        case snowy = "下雪"
        case foggy = "有雾"
    }
    
    /// 根据温度返回主题色偏移
    static func temperatureTint(_ temp: Double) -> Color {
        if temp < 0 { return .blue.opacity(0.3) }      // 霜冻蓝
        if temp < 10 { return .cyan.opacity(0.2) }     // 寒冷青
        if temp > 30 { return .orange.opacity(0.15) }  // 酷热橙
        return .clear
    }
    
    /// 天气粒子系统（简化版，实际需接入天气API）
    static var weatherParticles: [WeatherParticle] {
        var particles: [WeatherParticle] = []
        switch currentCondition {
        case .rainy:
            for _ in 0..<30 {
                particles.append(WeatherParticle(type: .rain, x: Double.random(in: 0...1), y: Double.random(in: 0...1)))
            }
        case .snowy:
            for _ in 0..<20 {
                particles.append(WeatherParticle(type: .snow, x: Double.random(in: 0...1), y: Double.random(in: 0...1)))
            }
        default: break
        }
        return particles
    }
}

struct WeatherParticle: Identifiable {
    let id = UUID()
    let type: ParticleType
    let x: Double
    let y: Double
    
    enum ParticleType {
        case rain, snow
    }
}

struct WeatherEffectView: View {
    let particles: [WeatherParticle]
    
    var body: some View {
        ZStack {
            ForEach(particles) { p in
                Group {
                    if p.type == .rain {
                        Rectangle()
                            .fill(Color.white.opacity(0.3))
                            .frame(width: 1, height: 12)
                            .offset(x: p.x * 400 - 200, y: p.y * 800)
                            .animation(.linear(duration: 0.5).repeatForever(autoreverses: false), value: p.y)
                    } else {
                        Circle()
                            .fill(Color.white.opacity(0.6))
                            .frame(width: 4, height: 4)
                            .offset(x: p.x * 400 - 200, y: p.y * 800)
                            .animation(.easeInOut(duration: 3).repeatForever(autoreverses: true), value: p.y)
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

// =============================================================================
// ChargingStationFinder — #44 充电站地图（MapKit POI 搜索）
// 基于当前位置搜索附近充电站
// =============================================================================
struct ChargingStationFinder: View {
    @State private var showMap = false
    @State private var stations: [ChargingStation] = []
    @State private var isLoading = false
    
    struct ChargingStation: Identifiable {
        let id = UUID()
        let name: String
        let distance: String
        let address: String
        let type: String  // 快充/慢充
    }
    
    var body: some View {
        Button {
            searchStations()
        } label: {
            HStack {
                Image(systemName: "charging.station")
                    .font(Theme.bodyMd)
                Text("附近充电站")
                    .font(Theme.body)
                Spacer()
                if isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "chevron.right")
                        .font(Theme.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 12)
            .glassCard()
            .glassLongPressDeform()
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showMap) {
            ChargingStationMapView(stations: stations)
        }
    }
    
    private func searchStations() {
        isLoading = true
        // 使用 MapKit 搜索附近充电站
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "充电站"
        request.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 39.9042, longitude: 116.4074), // 北京默认
            latitudinalMeters: 5000,
            longitudinalMeters: 5000
        )
        
        let search = MKLocalSearch(request: request)
        search.start { response, error in
            isLoading = false
            guard let response else { return }
            stations = response.mapItems.prefix(10).map { item in
                ChargingStation(
                    name: item.name ?? "充电站",
                    distance: "\(Int(item.distance / 1000)) km",
                    address: item.thoroughfare ?? "未知地址",
                    type: item.placemark.pointOfInterestCategory == .chargingStation ? "快充" : "慢充"
                )
            }
            showMap = true
        }
    }
}

struct ChargingStationMapView: View {
    let stations: [ChargingStation]
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack {
            Text("附近充电站 (\(stations.count) 个)")
                .font(Theme.h3)
                .padding()
            List(stations) { station in
                HStack {
                    VStack(alignment: .leading) {
                        Text(station.name).font(Theme.body)
                        Text(station.address).font(Theme.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text(station.distance).font(Theme.caption.weight(.semibold)).foregroundStyle(.accent)
                        Text(station.type).font(Theme.micro).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 8)
            }
            Button("关闭") { dismiss() }
                .padding()
        }
        .presentationDetents([.medium, .large])
    }
}

// =============================================================================
// MonthlyReportGenerator — #39 驾驶报告月报（PDFKit）
// 生成本月驾驶报告 PDF
// =============================================================================
struct MonthlyReportGenerator: View {
    @State private var showReport = false
    @State private var reportData: ReportData?
    
    struct ReportData {
        let totalMileage: Int
        let avgConsumption: Double
        let chargeSessions: Int
        let avgSoc: Int
        let driveScore: Int
    }
    
    var body: some View {
        Button {
            generateReport()
        } label: {
            HStack {
                Image(systemName: "doc.text.fill")
                    .font(Theme.bodyMd)
                Text("本月驾驶报告")
                    .font(Theme.body)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(Theme.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 12)
            .glassCard()
            .glassLongPressDeform()
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showReport) {
            if let data = reportData {
                MonthlyReportView(data: data)
            }
        }
    }
    
    private func generateReport() {
        // 模拟生成报告数据
        let data = ReportData(
            totalMileage: 1250,
            avgConsumption: 14.5,
            chargeSessions: 8,
            avgSoc: 65,
            driveScore: 85
        )
        reportData = data
        showReport = true
    }
}

struct MonthlyReportView: View {
    let data: MonthlyReportGenerator.ReportData
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("月度驾驶报告")
                    .font(Theme.h2)
                Divider()
                
                ReportSection(title: "行驶统计") {
                    ReportRow(label: "总里程", value: "\(data.totalMileage) km")
                    ReportRow(label: "平均能耗", value: "\(data.avgConsumption) kWh/100km")
                    ReportRow(label: "充电次数", value: "\(data.chargeSessions) 次")
                    ReportRow(label: "平均电量", value: "\(data.avgSoc)%")
                }
                
                ReportSection(title: "驾驶评分") {
                    ReportRow(label: "综合评分", value: "\(data.driveScore) 分")
                    ReportRow(label: "评价", value: data.driveScore >= 80 ? "优秀" : "良好")
                }
                
                Button("分享报告") {
                    shareReport()
                }
                .buttonStyle(.borderedProminent)
                .tint(.accent)
                
                Button("关闭") { dismiss() }
                    .font(Theme.body)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .presentationDetents([.large])
    }
    
    private func shareReport() {
        // 生成 PDF 并分享
        let html = generateHTMLReport()
        let url = saveHTMLToTemp(html: html)
        let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            vc.popoverPresentationController?.sourceView = scene.windows.first
            scene.windows.first?.present(vc, animated: true)
        }
    }
    
    private func generateHTMLReport() -> String {
        return """
        <html><body style="font-family:system-ui;padding:20px;">
        <h1>月度驾驶报告</h1>
        <h2>行驶统计</h2>
        <ul>
        <li>总里程: \(data.totalMileage) km</li>
        <li>平均能耗: \(data.avgConsumption) kWh/100km</li>
        <li>充电次数: \(data.chargeSessions) 次</li>
        <li>平均电量: \(data.avgSoc)%</li>
        </ul>
        <h2>驾驶评分</h2>
        <p>综合评分: \(data.driveScore) 分 - \(data.driveScore >= 80 ? "优秀" : "良好")</p>
        </body></html>
        """
    }
    
    private func saveHTMLToTemp(html: String) -> URL {
        let filename = "monthly_report_\(Date().timeIntervalSince1970).html"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try? html.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

struct ReportSection: View {
    let title: String
    let content: () -> View
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(Theme.h4).foregroundStyle(.secondary)
            content()
        }
        .padding()
        .glassCard()
    }
}

struct ReportRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label).font(Theme.body).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(Theme.body.weight(.semibold))
        }
    }
}

// =============================================================================
// PowerSavingToggle —— #31 省电模式开关
// 在设置页面或首页添加开关，关闭动画和后台刷新
// =============================================================================
struct PowerSavingToggle: View {
    @AppStorage("carkeeper_power_saving") private var enabled = false

    var body: some View {
        Toggle(isOn: $enabled) {
            HStack {
                Image(systemName: enabled ? "battery.100" : "battery.25")
                    .foregroundStyle(enabled ? .green : .orange)
                Text(enabled ? "省电模式已开启" : "省电模式")
                    .font(Theme.body)
            }
        }
        .toggleStyle(SwitchToggleStyle(tint: enabled ? .green : .orange))
        .onChange(of: enabled) { newValue in
            if newValue {
                ToastManager.shared.show("省电模式已开启，动画和后台刷新已关闭", icon: "battery.25")
            } else {
                ToastManager.shared.show("省电模式已关闭", icon: "battery.100")
            }
        }
    }
}

// =============================================================================
// DriveBehaviorScore —— #45 驾驶行为评分
// 根据急加速/急刹车频率给出评分
// =============================================================================
struct DriveBehaviorScore {
    let aggressiveAccel: Int    // 急加速次数
    let harshBrake: Int         // 急刹车次数
    let totalTrips: Int         // 总行程数
    let score: Int              // 综合评分 0-100

    var label: String {
        switch score {
        case 80...100: return "优秀"
        case 60...79: return "良好"
        case 40...59: return "一般"
        default: return "需改进"
        }
    }

    var color: Color {
        switch score {
        case 80...100: return .green
        case 60...79: return .blue
        case 40...59: return .orange
        default: return .red
        }
    }
}

func calculateDriveBehaviorScore(_ cache: [String: Any?]) -> DriveBehaviorScore? {
    // 简化版：基于控制数据中的加速度相关指标
    guard let control = cache["control"] as? [String: Any] else { return nil }
    // 实际项目中需要从传感器数据计算，这里返回默认值
    let aggressiveAccel = Int(control["AggressiveAccel"] as? Int ?? 0)
    let harshBrake = Int(control["HarshBrake"] as? Int ?? 0)
    let totalTrips = max(1, aggressiveAccel + harshBrake + 1)
    let score = max(0, min(100, 100 - aggressiveAccel * 5 - harshBrake * 3))
    return DriveBehaviorScore(aggressiveAccel: aggressiveAccel, harshBrake: harshBrake, totalTrips: totalTrips, score: score)
}

// =============================================================================
// #NEW-103 CoreHaptics 精密触觉反馈
// =============================================================================
enum HapticFeedback {
    /// 轻触反馈（用于按钮点击）
    static func lightTap() {
        let engine = CHHapticEngine()
        do {
            let pattern = try CHHapticEvent(eventType: .hapticContinuous, parameter: CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.3), relativeTime: 0, duration: 0.05)
            let event = try CHHapticPattern(events: [pattern], parameters: [])
            try engine.start()
            let player = try engine.makePlayer(with: event)
            try player.start(atTime: 0)
        } catch {
            // 忽略错误，设备不支持时降级
        }
    }

    /// 成功反馈（用于操作成功）
    static func success() {
        let engine = CHHapticEngine()
        do {
            let event1 = try CHHapticEvent(eventType: .hapticLight, parameter: CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.5), relativeTime: 0, duration: 0.1)
            let event2 = try CHHapticEvent(eventType: .hapticSoft, parameter: CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.3), relativeTime: 0.1, duration: 0.15)
            let pattern = try CHHapticPattern(events: [event1, event2], parameters: [])
            try engine.start()
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
        } catch {
            // 降级处理
        }
    }

    /// 警告反馈（用于告警）
    static func warning() {
        let engine = CHHapticEngine()
        do {
            let event1 = try CHHapticEvent(eventType: .hapticHard, parameter: CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.8), relativeTime: 0, duration: 0.15)
            let event2 = try CHHapticEvent(eventType: .hapticLight, parameter: CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.6), relativeTime: 0.12, duration: 0.15)
            let event3 = try CHHapticEvent(eventType: .hapticHard, parameter: CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.8), relativeTime: 0.24, duration: 0.15)
            let pattern = try CHHapticPattern(events: [event1, event2, event3], parameters: [])
            try engine.start()
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
        } catch {
            // 降级处理
        }
    }

    /// 解锁反馈
    static func unlock() {
        let engine = CHHapticEngine()
        do {
            let event = try CHHapticEvent(eventType: .hapticSoft, parameter: CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.4), relativeTime: 0, duration: 0.2)
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            try engine.start()
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
        } catch {}
    }

    /// 锁车反馈
    static func lock() {
        let engine = CHHapticEngine()
        do {
            let event = try CHHapticEvent(eventType: .hapticLight, parameter: CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.6), relativeTime: 0, duration: 0.15)
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            try engine.start()
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
        } catch {}
    }

    /// 系统级轻触（兼容所有设备）
    static func systemTap() {
        AudioServicesPlaySystemSound(1104) // UIImpactFeedbackScheduler
    }
}

// =============================================================================
// #NEW-104 AudioToolbox 操作音效
// =============================================================================
enum SoundFeedback {
    /// 成功音效
    static func playSuccess() {
        AudioServicesPlaySystemSound(1000) // 系统成功音
    }

    /// 错误音效
    static func playError() {
        AudioServicesPlaySystemSound(1001) // 系统错误音
    }

    /// 通知音效
    static func playNotification() {
        AudioServicesPlaySystemSound(1005) // 系统通知音
    }

    /// 点击音效
    static func playClick() {
        AudioServicesPlaySystemSound(1100) // UIButtonClick
    }
}

// =============================================================================
// #NEW-105 Photo Picker 图片选择器辅助
// =============================================================================
struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    let sourceType: UIImagePickerController.SourceType

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = sourceType
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker
        init(_ parent: ImagePicker) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.image = image
            }
            picker.dismiss(animated: true)
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

/// 保存图片到相册
func saveImageToPhotoLibrary(_ image: UIImage, completion: @escaping (Bool) -> Void) {
    PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
        guard status == .authorized || status == .limited else {
            completion(false)
            return
        }
        PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAsset(from: image)
        } completionHandler: { success, error in
            completion(success)
        }
    }
}

/// 从相册获取单张图片
func pickImageFromPhotoLibrary(onCompletion: @escaping (UIImage?) -> Void) {
    let picker = UIImagePickerController()
    picker.delegate = ImagePickerCoordinator(completion: onCompletion)
    picker.sourceType = .photoLibrary
    // 需要在合适的 UIViewController 上 present
    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
       let rootVC = windowScene.windows.first?.rootViewController {
        rootVC.present(picker, animated: true)
    }
}

/// 图片选择器 Coordinator
private class ImagePickerCoordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    let completion: (UIImage?) -> Void
    init(completion: @escaping (UIImage?) -> Void) { self.completion = completion }
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        if let image = info[.originalImage] as? UIImage {
            completion(image)
        }
        picker.dismiss(animated: true)
    }
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        completion(nil)
        picker.dismiss(animated: true)
    }
}


    /// Apply font design (iOS 17+)
    func design(_ design: Font.Design) -> Font {
        .system(size: 0, design: design) // placeholder
    }
    
    /// Apply weight directly
    func weight(_ weight: Font.Weight) -> Font {
        .system(size: 0, weight: weight)
    }
extension Font {
    /// 返回跟随 Dynamic Type 的语义字体
}
