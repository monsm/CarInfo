// =============================================================================
// #NEW-112 启动画面 Splash
// 设计：Tesla 式 —— 纯色画布 + 扁平品牌标 + 细进度线。
// 品牌的第一秒应该安静、干净、可信。
// =============================================================================

import SwiftUI
import UIKit

struct SplashView: View {
    @State private var progress: CGFloat = 0
    @State private var showMain = false
    @State private var dissolved = false

    let duration: TimeInterval = 2.0

    var body: some View {
        ZStack {
            DS.Palette.canvasGradient.ignoresSafeArea()

            VStack(spacing: DS.Space.xxl) {
                // 品牌标：与登录页同一套视觉（主色方标 + 顶部高光 + 柔印）
                Image(systemName: "car.side.fill")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(DS.Palette.labelOnTint)
                    .frame(width: 72, height: 72)
                    .background(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(DS.Palette.tint)
                    )
                    // v4：与登录页同一块的平坦主色方标（无梯度描边、无柔印）

                VStack(spacing: DS.Space.sm) {
                    Text("长安车管家")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(DS.Palette.label)
                        .tracking(1.2)
                    Text("CHANGAN CONNECT")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DS.Palette.labelTertiary)
                        .tracking(3)
                }

                // 进度线：2pt，单一主色，宽度与内容区对齐
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(DS.Palette.surfaceSunken)
                        Capsule()
                            .fill(DS.Palette.tint)
                            .frame(width: max(2, geo.size.width * progress))
                    }
                }
                .frame(width: 180, height: 3)
                .clipShape(Capsule())
                .padding(.top, DS.Space.md)
                .accessibilityHidden(true)
            }
            .opacity(dissolved ? 0 : 1)
            .scaleEffect(dissolved ? 0.98 : 1)
            .animation(.easeOut(duration: 0.35), value: dissolved)
        }
        .onAppear {
            withAnimation(.linear(duration: duration)) {
                progress = 1.0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                dissolved = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    showMain = true
                }
            }
        }
    }
}

struct SplashView_Previews: PreviewProvider {
    static var previews: some View {
        SplashView()
    }
}
