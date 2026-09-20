// =============================================================================
// Canvas.swift — 画布管理
// 全屏 LivingCar 舞台 + 时间感知氛围渐变 + 纯净内容区
// =============================================================================
import SwiftUI

struct DSCanvas<Content: View>: View {
    let content: () -> Content
    let ambient: Bool

    init(ambient: Bool = true, @ViewBuilder content: @escaping () -> Content) {
        self.content = content
        self.ambient = ambient
    }

    var body: some View {
        ZStack {
            canvasBackground
            content()
        }
        .ignoresSafeArea()
    }

    private var canvasBackground: some View {
        ZStack {
            // 主背景
            Rectangle()
                .fill(Kansei.Color.background)

            // 时间感知氛围光（仅在 ambient 模式启用）
            if ambient {
                ambientGlow
                    .ignoresSafeArea()
            }
        }
    }

    private var ambientGlow: some View {
        KanseiRadialGradient(
            colors: [
                Kansei.Color.ambient.opacity(0.15),
                Kansei.Color.ambient.opacity(0.05),
                Color.clear
            ],
            center: .bottom,
            startRadius: 0,
            endRadius: 1.2
        )
    }
}

// MARK: - 径向氛围渐变（性能优化版本）
struct KanseiRadialGradient: View {
    let colors: [Color]
    let center: UnitPoint
    let startRadius: CGFloat
    let endRadius: CGFloat

    var body: some View {
        LinearGradient(
            gradient: Gradient(colors: colors),
            startPoint: center,
            endPoint: center
        )
        .blur(radius: 60)
        .opacity(0.8)
    }
}

// MARK: - 内容容器
struct DSStage<Content: View>: View {
    let padding: CGFloat
    let content: () -> Content

    init(padding: CGFloat = Kansei.Spacing.page, @ViewBuilder content: @escaping () -> Content) {
        self.padding = padding
        self.content = content
    }

    var body: some View {
        content()
            .padding(.horizontal, padding)
            .padding(.vertical, Kansei.Spacing.lg)
    }
}

// MARK: - 分组卡片（发光边框版）
struct DSGroupedCard<Content: View>: View {
    let radius: CGFloat
    let glow: Bool
    let content: () -> Content

    init(radius: CGFloat = Kansei.Radius.medium, glow: Bool = true, @ViewBuilder content: @escaping () -> Content) {
        self.radius = radius
        self.glow = glow
        self.content = content
    }

    var body: some View {
        content()
            .padding(Kansei.Spacing.md)
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Kansei.Color.nightSurface.opacity(0.6))
                    .overlay(
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .stroke(Kansei.Color.glassBorder, lineWidth: 1)
                    )
                    .overlay {
                        if glow {
                            RoundedRectangle(cornerRadius: radius, style: .continuous)
                                .fill(Kansei.Color.ambient.opacity(0.03))
                                .blur(radius: 20)
                        }
                    }
            }
    }
}

// MARK: - 分割线（发丝线）
struct DSDivider: View {
    let inset: CGFloat
    let opacity: Double

    init(inset: CGFloat = Kansei.Spacing.md, opacity: Double = 0.15) {
        self.inset = inset
        self.opacity = opacity
    }

    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(opacity))
            .frame(height: 0.5)
            .padding(.leading, inset)
    }
}
