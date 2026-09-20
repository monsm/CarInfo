// =============================================================================
// SplashView.swift — 电影感启动
// Tesla 式极简 + 时间感知品牌光 + 呼吸动画
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
            Kansei.Color.background.ignoresSafeArea()

            // 品牌光晕
            Circle()
                .fill(Kansei.Color.ambient.opacity(0.3))
                .frame(width: 300, height: 300)
                .blur(radius: 60)
                .position(x: UIScreen.main.bounds.width / 2, y: UIScreen.main.bounds.height / 2 - 40)
                .opacity(brandGlow)

            VStack(spacing: Kansei.Spacing.xxl) {
                // 品牌标：呼吸光效
                ZStack {
                    Circle()
                        .fill(Kansei.Color.ambient)
                        .frame(width: 80, height: 80)
                        .blur(radius: 20)
                        .opacity(brandGlow * 0.5)

                    Image(systemName: "car.side.fill")
                        .font(.system(size: 36, weight: .medium))
                        .foregroundColor(Kansei.Color.primary)
                        .frame(width: 80, height: 80)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(Kansei.Color.ambient)
                        )
                }
                .kanseiBreathe(opacity: 0.4, scale: 1.05)

                VStack(spacing: Kansei.Spacing.sm) {
                    Text("长安车管家")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(Kansei.Color.primary)
                        .tracking(2)

                    Text("CHANGAN CONNECT")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Kansei.Color.tertiary)
                        .tracking(4)
                }

                // 进度条
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Kansei.Color.glassBorder)
                            .frame(height: 3)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Kansei.Color.ambient)
                            .frame(width: geo.size.width * progress, height: 3)
                    }
                }
                .frame(width: 160, height: 3)
                .padding(.top, Kansei.Spacing.md)
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
