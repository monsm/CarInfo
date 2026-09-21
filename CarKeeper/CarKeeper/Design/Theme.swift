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
    // 令牌已全部合并到 `Tokens.swift`：
    //   TokensPalette / TokensTypo / TokensSpacing / TokensRadius / TokensMotion / TokensHaptic
    // 这里只保留非令牌工具函数，见下方 extension：font(_:weight:design:) / lineHeight(_:)。
}

extension Theme {
    // MARK: - 字体尺寸
    static func font(_ size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        .system(size: size, weight: weight, design: design)
    }
    /// Overload accepting an already-constructed font (e.g. TokensTypo.caption, TokensTypo.subheadline)
    static func font(_ f: Font) -> Font { f }

    static func lineHeight(_ size: CGFloat) -> CGFloat {
        switch size {
        case 80, 52: return size * 1.1
        case 34, 28: return size * 1.15
        case 20, 17: return size * 1.29
        default: return size * 1.4
        }
    }
}

// MARK: - 页面底色：单一画布
// 规则：背景只有一层中性画布色。层级由「表面色 + 发丝线 + 排版」表达，
// 页面之间的差异也来自内容与排版，不来自背景本身。
// MARK: - View Extensions：Apple Premium 组件
extension View {
    // 页面底色 + 统一页面边距
    // 刻意不接受任何颜色参数：页面底色只能是 TokensPalette.background 这一层。
    //
    // v5：画布之上再叠一层**主题装饰**（CanvasDecorLayer）。
    // 它永远在内容之下（写在 background 里，不是 overlay），所以不遮挡、不吃点击。
    // 装饰不是“氛围背景”的回归：它只表达这套艺术方向的做法 ——
    //   夜光 = 一束来自车所在地的光；纸上 = 纸面在光下的不均；巨字 = 发丝网格。
    func pageBackground() -> some View {
        contentMargins(.horizontal, TokensSpacing.page, for: .scrollContent)
            .background {
                ZStack {
                    TokensPalette.canvasGradient
                    CanvasDecorLayer()
                        // 装饰层不吃点击：它只是画布，不是控件
                        .allowsHitTesting(false)
                }
                .ignoresSafeArea()
            }
    }

    // MARK: - 卡片修饰符
    /// 液态玻璃卡片背景 + 高光描边
    func glassCard(corner: CGFloat = TokensRadius.medium) -> some View {
        self.modifier(GlassCardModifier(cornerRadius: corner, isHero: false))
    }

    /// Hero 级玻璃卡片（更大圆角 + 更强阴影）
    func glassHeroCard(corner: CGFloat = TokensRadius.large) -> some View {
        self.modifier(GlassCardModifier(cornerRadius: corner, isHero: true))
    }

}

// =============================================================================
// CanvasDecorLayer —— 按当前主题给画布叠一层装饰
// =============================================================================
// 三种装饰各对应一种艺术方向的做法，不是随机氛围：
//   lightPool    夜光：一束来自车所在地的光（暖色、位置固定、不是动画）
//   paperGrain   纸上：纸面在光下的色温不均（印刷物不会完全均匀）
//   hairlineGrid 巨字：发丝网格 —— 版面本身就是内容
//
// 它只出现在 pageBackground() 的 background 里（内容之下），并且关闭命中测试，
// 所以不会遮挡、不会吃掉任何点击。
struct CanvasDecorLayer: View {
    private var decor: CanvasDecor { TokensPalette.decor }

    var body: some View {
        switch decor {
        case .none:
            Color.clear

        case .lightPool:
            GeometryReader { geo in
                RadialGradient(
                    colors: [TokensPalette.accent.opacity(0.16), TokensPalette.accent.opacity(0)],
                    center: UnitPoint(x: 0.78, y: 0.12),
                    startRadius: 0,
                    endRadius: max(geo.size.width, geo.size.height) * 0.72
                )
            }

        case .paperGrain:
            ZStack {
                RadialGradient(
                    colors: [Color(red: 0.78, green: 0.68, blue: 0.50).opacity(0.10), .clear],
                    center: UnitPoint(x: 0.18, y: 0.08),
                    startRadius: 0,
                    endRadius: 420
                )
                RadialGradient(
                    colors: [Color(red: 0.55, green: 0.46, blue: 0.32).opacity(0.06), .clear],
                    center: UnitPoint(x: 0.90, y: 0.85),
                    startRadius: 0,
                    endRadius: 520
                )
            }

        case .hairlineGrid:
            GeometryReader { geo in
                Path { p in
                    let step: CGFloat = 44
                    var x: CGFloat = 0
                    while x <= geo.size.width {
                        p.move(to: CGPoint(x: x, y: 0))
                        p.addLine(to: CGPoint(x: x, y: geo.size.height))
                        x += step
                    }
                    var y: CGFloat = 0
                    while y <= geo.size.height {
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: geo.size.width, y: y))
                        y += step
                    }
                }
                .stroke(TokensPalette.primary.opacity(CanvasDecor.hairlineGrid.strength), lineWidth: 0.5)
            }
        }
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
                    .fill(TokensPalette.nightSurface)
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
            .fill(TokensPalette.statusColor(cls))
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
        HStack(alignment: .firstTextBaseline, spacing: TokensSpacing.md) {
            Text(k)
                .font(TokensTypo.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: TokensSpacing.lg)
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
    var cornerRadius: CGFloat = TokensRadius.medium
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: TokensSpacing.lg) {
            HStack(alignment: .firstTextBaseline) {
                Text(title.uppercased())
                    .font(TokensTypo.sectionLabel)
                    .tracking(0.6)
                    .foregroundStyle(TokensPalette.secondary)
                Spacer(minLength: TokensSpacing.sm)
                if let side, !side.isEmpty {
                    DSChip(text: side, cls: sideCls.isEmpty ? "na" : sideCls)
                }
            }
            content()
        }
        .padding(TokensSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(corner: cornerRadius)
    }
}

// MARK: - 可展开玻璃卡片（标题行点击触发弹簧高度过渡 + 液态玻璃形变）
struct ExpandingCardBox<Content: View>: View {
    let title: String
    var side: String? = nil
    var sideCls: String = ""
    var cornerRadius: CGFloat = TokensRadius.medium
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
                HStack(alignment: .firstTextBaseline, spacing: TokensSpacing.sm) {
                    Text(title.uppercased())
                        .font(TokensTypo.sectionLabel)
                        .tracking(0.6)
                        .foregroundStyle(TokensPalette.secondary)
                    Spacer(minLength: TokensSpacing.sm)
                    if let side, !side.isEmpty {
                        DSChip(text: side, cls: sideCls.isEmpty ? "na" : sideCls)
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(TokensPalette.tertiary)
                        .rotationEffect(isExpanded ? .degrees(180) : .degrees(0))
                        .animation(TokensMotion.press, value: isExpanded)
                }
                .padding(.horizontal, TokensSpacing.md)
                .padding(.vertical, TokensSpacing.lg)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))

            // ── 内容区（弹簧高度过渡）──
            if isExpanded {
                content()
                    .padding(.horizontal, TokensSpacing.xl)
                    .padding(.bottom, TokensSpacing.lg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .topLeading) {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.12))
                            .frame(height: 1)
                            .padding(.horizontal, -TokensSpacing.xl)
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
        self.padding(.horizontal, DynamicTypeScale.padding(TokensSpacing.page, for: size))
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
            .padding(.horizontal, compressRatio * TokensSpacing.page)
            .padding(.vertical, compressRatio * TokensSpacing.md)
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
        VStack(alignment: .leading, spacing: TokensSpacing.md) {
            HStack(spacing: TokensSpacing.sm) {
                ProgressView().controlSize(.small)
                Text(message)
                    .font(TokensTypo.footnote)
                    .foregroundStyle(TokensPalette.secondary)
            }
            DSSkeleton(height: 88, width: nil)
            DSSkeleton(height: 142, width: nil)
            DSSkeleton(height: 64, width: nil)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, TokensSpacing.page)
        .padding(.vertical, TokensSpacing.lg)
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
        VStack(spacing: TokensSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(TokensPalette.warning)
            Text(message)
                .font(TokensTypo.subheadline)
                .foregroundStyle(TokensPalette.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("重新加载") { retryAction() }
                .buttonStyle(DSSecondaryButtonStyle())
                .frame(maxWidth: 200)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, TokensSpacing.xl)
        .padding(.horizontal, TokensSpacing.page)
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
// MARK: - 从 63decaa 被误删的实现（月报 / 省电开关）
// 注意：这一节原来还包括"充电站地图"与"驾驶评分"，两者已删 ——
// 它们各自是第二、第三套实现：充电站搜的是写死的北京坐标，评分用报文里
// 根本不存在的急加速/急刹车键名（永远 0 次 + 100 分）。现在两者都归到
// 地图主屏的「充电」层与评分页，那里才是唯一那份实现。
// =============================================================================

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
                    .font(TokensTypo.body)
                Text("本月驾驶报告")
                    .font(TokensTypo.body)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(TokensTypo.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, TokensSpacing.md)
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
                    .font(TokensTypo.title)
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
                .tint(TokensPalette.ambient)
                
                Button("关闭") { dismiss() }
                    .font(TokensTypo.body)
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
            Text(title).font(TokensTypo.headline).foregroundStyle(.secondary)
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
            Text(label).font(TokensTypo.body).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(TokensTypo.body.weight(.semibold))
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
                    .font(TokensTypo.body)
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
