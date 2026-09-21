import SwiftUI
import MapKit
import CoreHaptics
import AVFoundation
import Photos

// =============================================================================
// SafeSymbol —— SF Symbol 名称兜底
// 背景：历史代码里散落着若干并不存在的图标名（例如 "tire"、"gauge.full"、
//      "battery.3quarter.fill"），而 Image(systemName:) 遇到不存在的名字会渲染成
//      空白 —— 在界面上看起来就是「这个位置的图标缺失了」。
// 约定：凡是「图标名字是变量 / 拼出来的」地方，一律走 Image(safeSymbol:)，
//      名字无效时退回一个一定存在的图标，保证界面永不出现空白图标。
// =============================================================================
enum SafeSymbol {
    private static var cache: [String: String] = [:]

    /// 返回一个可用的 symbol 名：请求的名字不存在时返回 fallback
    static func name(_ requested: String, fallback: String = "questionmark.circle.fill") -> String {
        if let hit = cache[requested] { return hit }
        let resolved = UIImage(systemName: requested) != nil ? requested : fallback
        cache[requested] = resolved
        return resolved
    }
}

extension Image {
    /// 构造 systemName 图标，但名字无效时自动退回 fallback（避免图标凭空消失）
    init(safeSymbol name: String, fallback: String = "questionmark.circle.fill") {
        self.init(systemName: SafeSymbol.name(name, fallback: fallback))
    }
}

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
    // MARK: - 颜色别名（兼容旧代码 Theme.Colors.*）
    enum Colors {
        static var accent: Color { KanseiPalette.ambient }
        static var brand: Color { KanseiPalette.ambient }
        static var brandLight: Color { KanseiPalette.ambient }
        static var brandDark: Color { KanseiPalette.ambient }
        static var background: Color { ColorSystem.background }
        static var cardBg: Color { ColorSystem.cardBg }
        static var primary: Color { ColorSystem.primary }
        static var secondary: Color { ColorSystem.secondary }
        static var tertiary: Color { ColorSystem.tertiary }
        static var border: Color { ColorSystem.border }
        static var fill: Color { ColorSystem.fill }
        static var ok: Color { KanseiPalette.success }
        static var warn: Color { KanseiPalette.warning }
        static var bad: Color { KanseiPalette.error }
        static var tint: Color { KanseiPalette.ambient }
        static var charge: Color { KanseiPalette.info }
    }

    // MARK: - 品牌色（自适应浅色/深色模式）

    /// 主色调：全 App 只有一个强调色（KanseiPalette.ambient）。
    /// 各页面不设自己的色相，页面之间的差异由排版与内容表达。
    static var brand: Color { KanseiPalette.ambient }
    static var brandLight: Color { KanseiPalette.ambient }
    static var brandDark: Color { KanseiPalette.ambient }

    // MARK: - 语义色（全局唯一来源：DS.Palette）
    static var ok: Color { KanseiPalette.success }
    static var warn: Color { KanseiPalette.warning }
    static var bad: Color { KanseiPalette.error }
    static var charge: Color { KanseiPalette.info }
    static var acc: Color { KanseiPalette.ambient }
    static var na: Color { KanseiPalette.tertiary }

    // MARK: - 状态 → 语义色
    static func statusColor(_ cls: String) -> Color {
        KanseiPalette.statusColor(cls)
    }

    // =============================================================================
    // 一、字号体系（Typography Scale）— 适配 Dynamic Type
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
    // 全部数字改成「等宽数字 + 圆润字形」：换数时不再抖动，读数像仪表盘。
    static var d1: Font { DS.Typo.display(72) }
    static var d2: Font { DS.Typo.display(52) }
    static var d3: Font { DS.Typo.metric(34) }
    /// Hero 数字（行程/统计大数值）
    static var heroNum: Font { DS.Typo.metric(22) }

    static var d4: Font { DS.Typo.metric(26) }
    static var d5: Font { DS.Typo.metric(20) }

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

    // ---- 数字专用（等宽数字，固定大小保持对齐）----
    static var mono: Font { DS.Typo.dataSmall }
    static var monoLg: Font { DS.Typo.data }

    // ---- 其他固定 Hero 尺寸（不受 Dynamic Type 影响）----
    static var d0: Font { DS.Typo.display(42) }    // 超大数字（AC 温度）
    static var d0b: Font { DS.Typo.metric(28) }    // 地图坐标大数字

    // =============================================================================
    // Font 扩展：语义样式便捷方法
    // =============================================================================
    enum FontSize {
        static var headline: Font { .headline.weight(.semibold) }
        static var body: Font { .body }
        static var subheadline: Font { .subheadline }
        static var caption: Font { .caption }
        static var footnote: Font { .footnote }
    }

    // =============================================================================
    // 二、间距体系（Spacing Scale）
    // =============================================================================
    // 基准：4pt，所有间距为 4 的倍数
    /// 间距令牌。`Tokens` 后缀是刻意保留的：通用词一旦成为嵌套类型名，就会在本作用域内
    /// 遮蔽将来可能出现的同名 SDK 类型（`Kansei.Color` 事故的同款；scan/shadowguard.py --strict 拦这种形状）。
    enum SpacingTokens {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
        static let xxxl: CGFloat = 32
        static let hero: CGFloat = 40
        static let page: CGFloat = DS.Space.page        // 页面水平内边距
        static let cardSpacing: CGFloat = DS.Space.gap  // 卡片垂直间距
        static let cardPadding: CGFloat = DS.Space.cardPadding // 卡片内边距
        static let gridGap: CGFloat = DS.Space.md       // 网格间距
    }

    // =============================================================================
    // 三、圆角体系（Corner Radius Scale）
    // =============================================================================
    /// 圆角令牌。`Tokens` 后缀是刻意保留的：通用词一旦成为嵌套类型名，就会在本作用域内
    /// 遮蔽将来可能出现的同名 SDK 类型（`Kansei.Color` 事故的同款；scan/shadowguard.py --strict 拦这种形状）。
    enum RadiusTokens {
        // 全部对齐 DS 的三档圆角（10 / 18 / 26）：卡片圆角在全 App 只有这三档，
        // 圆角档位一多，界面立刻显出「拼凑感」。
        static let tiny: CGFloat = DS.RadiusTokens.small   // 图标按钮、tag
        static let sm: CGFloat = DS.RadiusTokens.small     // tiny 别名
        static let small: CGFloat = DS.RadiusTokens.small
        static let medium: CGFloat = DS.RadiusTokens.card
        static let large: CGFloat = DS.RadiusTokens.card
        static let lg: CGFloat = DS.RadiusTokens.card
        static let md: CGFloat = DS.RadiusTokens.card
        static let card: CGFloat = DS.RadiusTokens.card
        static let hero: CGFloat = DS.RadiusTokens.hero
        static let ultra: CGFloat = DS.RadiusTokens.hero
        static let full: CGFloat = 50   // 圆形元素
    }

    // =============================================================================
    // 四、色彩体系（Color System）
    // =============================================================================
    enum ColorSystem {
        // ---- 表面色（Surface）：来源统一为 DS.Palette，保证与 DS 组件同色 ----
        static let background: Color = KanseiPalette.background
        static let cardBg: Color = KanseiPalette.nightSurface
        static let surfaceRaised: Color = KanseiPalette.nightSurface
        static let overlay: Color = KanseiPalette.nightSurface
        static let glass: Color = KanseiPalette.nightSurface   // 旧版的半透明页面底已取消，避免“满屏玻璃”

        // ---- 文字色（Text）----
        static let primary: Color = KanseiPalette.primary
        static let secondary: Color = KanseiPalette.secondary
        static let tertiary: Color = KanseiPalette.tertiary
        static let quaternary: Color = KanseiPalette.tertiary.opacity(0.6)

        // ---- 边框色（Border）：发丝线 ----
        static let border: Color = KanseiPalette.glassBorder
        static let borderSubtle: Color = KanseiPalette.glassBorder.opacity(0.6)

        // ---- 填充色（Fill）----
        static let fill: Color = KanseiPalette.nightSurface
        static let fillSubtle: Color = KanseiPalette.glassLight
        static let fillHighlighted: Color = KanseiPalette.nightSurface

        // ---- 阴影色（Tesla 式：极弱，只用于“浮层”）----
        static let shadowLight: Color = Color.black.opacity(0.05)
        static let shadowMedium: Color = Color.black.opacity(0.08)
        static let shadowStrong: Color = Color.black.opacity(0.12)
    }

    // =============================================================================
    // 五、阴影体系（Shadow Scale）
    // =============================================================================
    /// 阴影令牌。`Tokens` 后缀是刻意保留的：通用词一旦成为嵌套类型名，就会在本作用域内
    /// 遮蔽将来可能出现的同名 SDK 类型（`Kansei.Color` 事故的同款；scan/shadowguard.py --strict 拦这种形状）。
    enum ShadowTokens {
        // 新视觉里卡片靠发丝描边分层，阴影只给浮层用，且都压到极弱。
        static let none: ShadowStyle = .init(color: .clear, radius: 0, x: 0, y: 0)
        static let light = ShadowStyle(color: ColorSystem.shadowLight, radius: 4, x: 0, y: 1)
        static let medium = ShadowStyle(color: ColorSystem.shadowMedium, radius: 10, x: 0, y: 3)
        static let strong = ShadowStyle(color: ColorSystem.shadowStrong, radius: 18, x: 0, y: 6)
    }

    enum Spring {
        static let responseBase: Double = 0.45
        static let dampingFraction: Double = 0.8
        static let duration: Double = 0.5
        static var standard: Animation { Animation.spring(response: responseBase, dampingFraction: dampingFraction,
 blendDuration: duration) }
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
        // 动效曲线统一收敛到 DS.MotionTokens：反馈快、状态变化稳、不过冲。
        static let springFast: Animation = DS.MotionTokens.press
        static let springNormal: Animation = DS.MotionTokens.value
        static let springSlow: Animation = DS.MotionTokens.screen
    }
}

extension Theme {
    // MARK: - 字体尺寸
    static func font(_ size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        .system(size: size, weight: weight, design: design)
    }
    /// Overload accepting an already-constructed font (e.g. Theme.caption, Theme.subheadline)
    static func font(_ f: Font) -> Font { f }
    static var subheadline: Font { .subheadline }

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

// MARK: - 页面底色：单一画布
// 规则：背景只有一层中性画布色。层级由「表面色 + 发丝线 + 排版」表达，
// 页面之间的差异也来自内容与排版，不来自背景本身。
// MARK: - View Extensions：Apple Premium 组件
extension View {
    // 页面底色 + 统一页面边距
    // 刻意不接受任何颜色参数：页面底色只能是 KanseiPalette.background 这一层。
    func pageBackground() -> some View {
        contentMargins(.horizontal, DS.Space.page, for: .scrollContent)
            .background(DS.Palette.canvasGradient.ignoresSafeArea())
    }

    // MARK: - 卡片修饰符
    /// 液态玻璃卡片背景 + 高光描边
    func glassCard(corner: CGFloat = Theme.RadiusTokens.card) -> some View {
        self.modifier(GlassCardModifier(cornerRadius: corner, isHero: false))
    }

    /// Hero 级玻璃卡片（更大圆角 + 更强阴影）
    func glassHeroCard(corner: CGFloat = Theme.RadiusTokens.hero) -> some View {
        self.modifier(GlassCardModifier(cornerRadius: corner, isHero: true))
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

    // 新版：内容卡片一律「不透明表面 + 发丝描边」，去掉玻璃与渐变描边。
    // 理由：玻璃卡片一多，层级就没了 —— 这也是旧版最“廉价”的地方。
    // 只有浮层（弹层、悬浮操作）才用 glassCard(isHero:) 的玻璃材质。
    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    // 内容一律不透明（hero 也一样）：玻璃只允许出现在浮层。
                    .fill(KanseiPalette.nightSurface)
            }
            // v4：内容层没有描边、没有阴影 —— 深度只由系统表面色表达。
            // （它们曾经是“卡片感”的来源，也是界面显廉价的主因。）
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

// MARK: - 状态点（纯色圆点，无附加效果）
struct StatusDot: View {
    let cls: String
    var size: CGFloat = 8
    var body: some View {
        Circle()
            .fill(Theme.statusColor(cls))
            .frame(width: size, height: size)
            .opacity(cls == "na" ? 0.35 : 1)
    }
}

// MARK: - 语义色玻璃胶囊
struct Pill: View {
    let text: String
    let cls: String
    var dot: Bool = true

    var body: some View {
        DSChip(text: text, cls: cls)
    }
}

// MARK: - 键值行（详情 / 明细）
struct KVRow: View {
    let k: String
    let v: String
    var mono: Bool = false
    var strong: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.SpacingTokens.md) {
            Text(k)
                .font(Theme.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: Theme.SpacingTokens.lg)
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
    var cornerRadius: CGFloat = Theme.RadiusTokens.card
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            HStack(alignment: .firstTextBaseline) {
                Text(title.uppercased())
                    .font(DS.Typo.sectionLabel)
                    .tracking(0.6)
                    .foregroundStyle(KanseiPalette.secondary)
                Spacer(minLength: DS.Space.sm)
                if let side, !side.isEmpty {
                    DSChip(text: side, cls: sideCls.isEmpty ? "na" : sideCls)
                }
            }
            content()
        }
        .padding(DS.Space.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(corner: cornerRadius)
    }
}

// MARK: - 可展开玻璃卡片（标题行点击触发弹簧高度过渡 + 液态玻璃形变）
struct ExpandingCardBox<Content: View>: View {
    let title: String
    var side: String? = nil
    var sideCls: String = ""
    var cornerRadius: CGFloat = Theme.RadiusTokens.card
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
                // 标题行 = DS 的分组标题（小号、灰、加粗、字距微开），
                // 不再用大号标题 + 旋转箭头：折叠区的标题应当比内容轻，而不是更重。
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.sm) {
                    Text(title.uppercased())
                        .font(DS.Typo.sectionLabel)
                        .tracking(0.6)
                        .foregroundStyle(KanseiPalette.secondary)
                    Spacer(minLength: DS.Space.sm)
                    if let side, !side.isEmpty {
                        DSChip(text: side, cls: sideCls.isEmpty ? "na" : sideCls)
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(KanseiPalette.tertiary)
                        .rotationEffect(isExpanded ? .degrees(180) : .degrees(0))
                        .animation(DS.MotionTokens.press, value: isExpanded)
                }
                .padding(.horizontal, DS.Space.cardPadding)
                .padding(.vertical, DS.Space.lg)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))

            // ── 内容区（弹簧高度过渡）──
            if isExpanded {
                content()
                    .padding(.horizontal, Theme.SpacingTokens.xl)
                    .padding(.bottom, Theme.SpacingTokens.lg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .topLeading) {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.12))
                            .frame(height: 1)
                            .padding(.horizontal, -Theme.SpacingTokens.xl)
                    }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(corner: cornerRadius)
    }
}

// MARK: - Press Feedback（统一按压/悬停动效）
/// 所有可点组件共享的按压反馈修饰符：只有 scale 压缩。
/// 规则：点击只允许「内容自身形变」这一种反馈 —— 不加描边、不叠任何覆盖层，
/// 因此也不存在任何跟随手指或扩散的图形。
struct PressFeedback: ViewModifier {
    /// 按下时的缩放比例（0.88 = 明显压缩，0.93 = 轻微压缩）
    let pressScale: CGFloat
    /// 弹簧响应（越大越慢）
    let springResponse: CGFloat
    /// 弹簧阻尼（越小回弹越快）
    let springDamping: CGFloat

    @State private var isPressed  = false
    @State private var isHovered  = false

    func body(content: Content) -> some View {
        content
            // 缩放：按下压缩 / 悬停微放大
            .scaleEffect(isPressed ? pressScale : (isHovered ? 1.02 : 1.0))
            .animation(.spring(response: springResponse, dampingFraction: springDamping, blendDuration: 0.2),
                       value: isPressed)
            .animation(.spring(response: springResponse, dampingFraction: springDamping, blendDuration: 0.2),
                       value: isHovered)
            // 只记录按压状态：不记录触摸点，也不绘制任何覆盖图形
            .simultaneousGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { _ in isPressed = true }
                    .onEnded   { _ in isPressed = false }
            )
            // 悬停（iPad / 桌面）
            .onHover { hovered in isHovered = hovered }
    }
}

// MARK: - 列表分隔行
struct ListDivider: View {
    var body: some View {
        Divider().opacity(0.5)
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

// =============================================================================
// Dynamic Type —— 大字体模式自适应工具
// 根据系统动态类型设置自动缩放间距、边距和字体，确保可读性和布局完整性
// =============================================================================

/// Dynamic Type 缩放因子（根据 ContentSizeCategory 返回倍数）
enum DynamicTypeScale {
    static func factor(for size: ContentSizeCategory) -> CGFloat {
        switch size {
        case .extraSmall, .small, .medium, .large, .extraLarge,
             .extraExtraLarge, .extraExtraExtraLarge,
             .accessibilityMedium, .accessibilityLarge:
            return 1.0
        case .accessibilityExtraLarge:
            return 1.15
        case .accessibilityExtraExtraLarge:
            return 1.3
        case .accessibilityExtraExtraExtraLarge:
            return 1.5
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
        self.padding(.horizontal, DynamicTypeScale.padding(Theme.SpacingTokens.page, for: size))
    }

    /// 应用 Dynamic Type 感知的 VStack/HStack 间距
    @ViewBuilder func adaptiveSpacing(_ base: CGFloat, _ size: ContentSizeCategory) -> some View {
        // Note: spacing() is a layout modifier; callers should apply it directly to VStack/HStack
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
        case .accessibility1, .large, .xLarge:
            return 0.75
        case .accessibility2:
            return 0.60
        default:
            return 0.45
        }
    }

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, compressRatio * Theme.SpacingTokens.page)
            .padding(.vertical, compressRatio * Theme.SpacingTokens.md)
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
            case .accessibility1, .large, .xLarge:
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
             .accessibilityExtraExtraExtraLarge:
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

// MARK: - DynamicTypeSize 辅助判断（基线 iOS 26 / Swift 6，无需版本分支）
extension DynamicTypeSize {
    var isLargeOrBigger: Bool {
        self != .xSmall && self != .small
    }
}

// =============================================================================
// Page State Views —— 统一的加载 / 错误 / 空状态展示组件
// 所有 Feature 页面统一使用，确保深浅双模式下视觉一致
// =============================================================================

/// 页面加载中状态
/// 新版：安静的骨架 + 一行说明文字。不再有旋转彩色渐变环、不再有玻璃卡片 ——
/// Tesla 式的加载态是「内容位置的占位」，不是一段装饰动画。
struct PageLoadingView: View {
    let message: String

    init(_ message: String = "正在加载…") {
        self.message = message
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            HStack(spacing: DS.Space.sm) {
                ProgressView().controlSize(.small)
                Text(message)
                    .font(DS.Typo.footnote)
                    .foregroundStyle(KanseiPalette.secondary)
            }
            DSSkeleton(height: 88, width: nil)
            DSSkeleton(height: 142, width: nil)
            DSSkeleton(height: 64, width: nil)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DS.Space.page)
        .padding(.vertical, DS.Space.lg)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(message))
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
        VStack(spacing: DS.Space.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(KanseiPalette.warning)
            Text(message)
                .font(DS.Typo.subheadline)
                .foregroundStyle(KanseiPalette.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("重新加载") { retryAction() }
                .buttonStyle(DSSecondaryButtonStyle())
                .frame(maxWidth: 200)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Space.xl)
        .padding(.horizontal, DS.Space.page)
    }
}

/// 页面空状态（无数据但无错误）— #25 带液态玻璃插画风格
// =============================================================================
/// 网络状态条：一整行、发丝线分隔、左对齐 —— 像车内状态灯，而不是飘在顶部的彩色胶囊。
/// 全局 Toast 提示（由 NavState.currentItem 驱动，挂载在根视图上）
// =============================================================================
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
                Image(safeSymbol: "ev.charger", fallback: "bolt.fill")
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
            .padding(.vertical, DS.Space.md)
            .glassCard()
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
            let origin = CLLocation(latitude: 39.9042, longitude: 116.4074)
            stations = response.mapItems.prefix(10).map { item in
                let meters = item.location.distance(from: origin)
                let coord = item.location.coordinate
                return ChargingStation(
                    name: item.name ?? "充电站",
                    distance: "\(Int(meters / 1000)) km",
                    address: String(format: "%.4f, %.4f", coord.latitude, coord.longitude),
                    type: item.pointOfInterestCategory == .evCharger ? "快充" : "慢充"
                )
            }
            showMap = true
        }
    }
}



// =============================================================================
// =============================================================================
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
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info:
 [UIImagePickerController.InfoKey : Any]) {
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
    // UIImagePickerController.delegate 是 weak 引用：必须由外部强引用持有 coordinator，
    // 否则临时构造的对象会在 present 之前就被释放，选中照片的回调永远不会触发。
    let coordinator = ImagePickerCoordinator(completion: { image in
        ImagePickerDelegateStore.current = nil
        onCompletion(image)
    })
    ImagePickerDelegateStore.current = coordinator
    picker.delegate = coordinator
    picker.sourceType = .photoLibrary
    // 需要在合适的 UIViewController 上 present
    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
       let rootVC = windowScene.windows.first?.rootViewController {
        rootVC.present(picker, animated: true)
    }
}

/// 强引用持有相册选择器的 delegate（delegate 属性本身是 weak）。
private enum ImagePickerDelegateStore {
    static var current: ImagePickerCoordinator?
}

/// 图片选择器 Coordinator
private class ImagePickerCoordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    let completion: (UIImage?) -> Void
    init(completion: @escaping (UIImage?) -> Void) { self.completion = completion }
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info:
 [UIImagePickerController.InfoKey : Any]) {
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

// MARK: - View extensions
extension View {
    /// 统一按压反馈（弹簧响应 0.4 / 阻尼 0.65）
    func pressFeedback() -> some View {
        self.modifier(PressFeedback(pressScale: 0.93,
                                    springResponse: 0.4,
                                    springDamping: 0.65))
    }
}

// =============================================================================
// MARK: - 从 63decaa 被误删的实现（充电站地图 / 月报 / 省电开关 / 驾驶评分）
// =============================================================================

struct ChargingStationMapView: View {
    let stations: [ChargingStationFinder.ChargingStation]
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
                        Text(station.distance)
                            .font(Theme.caption.weight(.semibold))
                            .foregroundStyle(Theme.Colors.accent)
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
            .padding(.vertical, DS.Space.md)
            .glassCard()
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
                .tint(Theme.Colors.accent)
                
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
            scene.windows.first?.rootViewController?.present(vc, animated: true)
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

struct ReportSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(Theme.h4).foregroundStyle(.secondary)
            content
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
        .onChange(of: enabled) { _, newValue in
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
    return DriveBehaviorScore(aggressiveAccel: aggressiveAccel,
                              harshBrake: harshBrake,
                              totalTrips: totalTrips,
                              score: score)
}
