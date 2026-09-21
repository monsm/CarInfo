// =============================================================================
// Glass.swift — 玻璃组件
// 玻璃只出现在「浮在内容之上」的层：导航栏、Tab 栏、弹层
// 基线 iOS 26：直接使用 Material（无需 backdrop-filter 降级分支）
// =============================================================================
import SwiftUI

// MARK: - 玻璃背景修饰符
struct GlassBackground: ViewModifier {
    let thickness: CGFloat
    let blur: CGFloat

    init(thickness: CGFloat = 20, blur: CGFloat = 30) {
        self.thickness = thickness
        self.blur = blur
    }

    func body(content: Content) -> some View {
        content
            .background(
                Material.thickMaterial
                    .blendMode(.overlay)
            )
            .background(Color.white.opacity(thickness / 100))
            .blur(radius: blur)
    }
}

// MARK: - 玻璃卡片
struct GlassCard<Content: View>: View {
    let cornerRadius: CGFloat
    let showBorder: Bool
    let content: () -> Content

    init(cornerRadius: CGFloat = TokensRadius.large,
         showBorder: Bool = true,
         @ViewBuilder content: @escaping () -> Content) {
        self.cornerRadius = cornerRadius
        self.showBorder = showBorder
        self.content = content
    }

    var body: some View {
        content()
            .padding(TokensSpacing.md)
            .background(
                Material.ultraThinMaterial
            )
            .background(Color.white.opacity(0.05))
            .cornerRadius(cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(TokensPalette.glassBorder, lineWidth: 1)
                    .opacity(showBorder ? 1 : 0)
            )
    }
}

// MARK: - 玻璃导航栏
struct GlassNavBar: View {
    let title: String
    let subtitle: String?
    let trailing: (() -> AnyView)?

    init(title: String, subtitle: String? = nil, trailing: (() -> AnyView)? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
    }

    var body: some View {
        HStack {
            Text(title)
                .font(TokensTypo.heading).fontWeight(.semibold)
                .foregroundColor(TokensPalette.primary)

            if let subtitle {
                Text(subtitle)
                    .font(TokensTypo.caption)
                    .foregroundColor(TokensPalette.tertiary)
            }

            Spacer()

            if let trailing = trailing {
                trailing()
            }
        }
        .padding(.horizontal, TokensSpacing.md)
        .padding(.vertical, TokensSpacing.sm)
        .background(
            Material.thickMaterial
                .blendMode(.overlay)
        )
        .background(Color.black.opacity(0.2))
        .overlay(alignment: .bottom) {
            DSDivider(inset: TokensSpacing.md)
        }
    }
}

// MARK: - 玻璃底部栏
struct GlassBottomBar<Content: View>: View {
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        content()
            .padding(.horizontal, TokensSpacing.md)
            .padding(.vertical, TokensSpacing.sm)
            .background(
                Material.thickMaterial
                    .blendMode(.overlay)
            )
            .background(Color.black.opacity(0.15))
            .overlay(alignment: .top) {
                DSDivider()
            }
    }
}

// MARK: - 按钮样式
struct KanseiButtonStyle: ButtonStyle {
    let variant: Variant

    enum Variant {
        case primary, secondary, ghost
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .fontWeight(.semibold)
            .animation(TokensMotion.tap, value: configuration.isPressed)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .modifier(ButtonBackground(variant: variant))
    }
}

struct ButtonBackground: ViewModifier {
    let variant: KanseiButtonStyle.Variant

    func body(content: Content) -> some View {
        switch variant {
        case .primary:
            content
                .foregroundColor(TokensPalette.primary)
                .padding(.vertical, TokensSpacing.md)
                .padding(.horizontal, TokensSpacing.lg)
                .background(
                    TokensPalette.ambient
                        .cornerRadius(TokensRadius.medium)
                        .shadow(color: TokensPalette.ambient.opacity(0.4), radius: 12, y: 4)
                )
        case .secondary:
            content
                .foregroundColor(TokensPalette.primary)
                .padding(.vertical, TokensSpacing.md)
                .padding(.horizontal, TokensSpacing.lg)
                .background(
                    TokensPalette.glassHighlight
                        .cornerRadius(TokensRadius.medium)
                )
        case .ghost:
            content
                .foregroundColor(TokensPalette.secondary)
                .padding(.vertical, TokensSpacing.md)
                .padding(.horizontal, TokensSpacing.lg)
        }
    }
}
