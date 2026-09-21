// =============================================================================
// SplashView.swift — 启动画面
// v4：只有一次性的入场 —— 品牌光淡入、进度条绘制。
// 没有呼吸、没有常驻发光：界面上会动的东西必须对应一个真实状态（这里是「正在启动」）。
// =============================================================================
import SwiftUI

struct SplashView: View {
    @State private var progress: CGFloat = 0
    @State private var showMain = false
    @State private var dissolved = false
    @State private var brandGlow: CGFloat = 0

    let duration: TimeInterval = 2.0

    var body: some View {
        ZStack {
            // 全屏背景
            TokensPalette.background.ignoresSafeArea()

            // 品牌光晕
            GeometryReader { geo in
                Circle()
                    .fill(TokensPalette.ambient.opacity(0.3))
                    .frame(width: 300, height: 300)
                    .blur(radius: 60)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2 - 40)
                    .opacity(brandGlow)
            }

            VStack(spacing: TokensSpacing.xxl) {
                // 品牌标：呼吸光效
                ZStack {
                    Circle()
                        .fill(TokensPalette.ambient)
                        .frame(width: 80, height: 80)
                        .blur(radius: 20)
                        .opacity(brandGlow * 0.5)

                    Image(systemName: "car.side.fill")
                        .font(.system(size: 36, weight: .medium))
                        .foregroundColor(TokensPalette.primary)
                        .frame(width: 80, height: 80)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(TokensPalette.ambient)
                        )
                }

                VStack(spacing: TokensSpacing.sm) {
                    Text("长安车管家")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(TokensPalette.primary)
                        .tracking(2)

                    Text("CHANGAN CONNECT")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(TokensPalette.tertiary)
                        .tracking(4)
                }

                // 进度条
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(TokensPalette.glassBorder)
                            .frame(height: 3)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(TokensPalette.ambient)
                            .frame(width: geo.size.width * progress, height: 3)
                    }
                }
                .frame(width: 160, height: 3)
                .padding(.top, TokensSpacing.md)
            }
        }
        .onAppear {
            withAnimation(.linear(duration: duration)) {
                progress = 1.0
            }
            brandGlow = 1.0

            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                withAnimation(.easeOut(duration: 0.4)) {
                    dissolved = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    showMain = true
                }
            }
        }
        .scaleEffect(dissolved ? 0.95 : 1)
        .opacity(dissolved ? 0 : 1)
    }
}
