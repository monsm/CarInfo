// =============================================================================
// Glass.swift — 玻璃组件
// 玻璃只出现在「浮在内容之上」的层：导航栏、Tab 栏、弹层
// iOS 15+ 支持 backdrop-filter，旧版本降级为纯色
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
        if #available(iOS 15, *) {
            content
                .background(
                    Material.thickMaterial
                        .blendMode(.overlay)
                )
                .background(Color.white.opacity(thickness / 100))
                .blur(radius: blur)
        } else {
            content
                .background(Color.black.opacity(0.3))
        }
    }
}

// MARK: - 玻璃卡片
struct GlassCard<Content: View>: View {
    let cornerRadius: CGFloat
    let showBorder: Bool
    let content: () -> Content

    init(cornerRadius: CGFloat = Kansei.Radius.large,
         showBorder: Bool = true,
         @ViewBuilder content: @escaping () -> Content) {
        self.cornerRadius = cornerRadius
        self.showBorder = showBorder
        self.content = content
    }

    var body: some View {
        if #available(iOS 15, *) {
            content()
                .padding(Kansei.Spacing.md)
                .background(
                    Material.ultraThinMaterial
                )
                .background(Color.white.opacity(0.05))
                .cornerRadius(cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Kansei.Color.glassBorder, lineWidth: 1)
                        .opacity(showBorder ? 1 : 0)
                )
        } else {
            content()
                .padding(Kansei.Spacing.md)
                .background(Color.white.opacity(0.08))
                .cornerRadius(cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Kansei.Color.glassBorder, lineWidth: 1)
                )
        }
    }
}

// MARK: - 玻璃导航栏
struct GlassNavBar: View {
    let title: String
    let subtitle: String?
    let trailing: (() -> AnyView)?

    init(title: String, subtitle: String? = nil, @ViewBuilder trailing: (() -> AnyView)? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
    }

    var body: some View {
        HStack {
            if #available(iOS 15, *) {
                Text(title)
                    .font(Kansei.Type.title).fontWeight(.semibold)
                    .foregroundColor(Kansei.Color.primary)

                if let subtitle {
                    Text(subtitle)
                        .font(Kansei.Type.caption)
                        .foregroundColor(Kansei.Color.tertiary)
                }

                Spacer()

                if let trailing = trailing {
                    trailing()
                }
            } else {
                Text(title)
                    .font(Kansei.Type.title).fontWeight(.semibold)
                    .foregroundColor(Kansei.Color.primary)

                Spacer()

                if let trailing = trailing {
                    trailing()
                }
            }
        }
        .padding(.horizontal, Kansei.Spacing.md)
        .padding(.vertical, Kansei.Spacing.sm)
        .background(
            Material.thickMaterial
                .blendMode(.overlay)
        )
        .background(Color.black.opacity(0.2))
        .overlay(alignment: .bottom) {
            DSDivider(inset: Kansei.Spacing.md)
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
        if #available(iOS 15, *) {
            content()
                .padding(.horizontal, Kansei.Spacing.md)
                .padding(.vertical, Kansei.Spacing.sm)
                .background(
                    Material.thickMaterial
                        .blendMode(.overlay)
                )
                .background(Color.black.opacity(0.15))
                .overlay(alignment: .top) {
                    DSDivider()
                }
        } else {
            content()
                .padding(.horizontal, Kansei.Spacing.md)
                .padding(.vertical, Kansei.Spacing.sm)
                .background(Color.black.opacity(0.3))
                .overlay(alignment: .top) {
                    DSDivider()
                }
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
            .animation(Kansei.Motion.tap, value: configuration.isPressed)
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
                .foregroundColor(Kansei.Color.primary)
                .padding(.vertical, Kansei.Spacing.md)
                .padding(.horizontal, Kansei.Spacing.lg)
                .background(
                    Kansei.Color.ambient
                        .cornerRadius(Kansei.Radius.medium)
                        .shadow(color: Kansei.Color.ambient.opacity(0.4), radius: 12, y: 4)
                )
        case .secondary:
            content
                .foregroundColor(Kansei.Color.primary)
                .padding(.vertical, Kansei.Spacing.md)
                .padding(.horizontal, Kansei.Spacing.lg)
                .background(
                    Kansei.Color.glassHighlight
                        .cornerRadius(Kansei.Radius.medium)
                )
        case .ghost:
            content
                .foregroundColor(Kansei.Color.secondary)
                .padding(.vertical, Kansei.Spacing.md)
                .padding(.horizontal, Kansei.Spacing.lg)
        }
    }
}
