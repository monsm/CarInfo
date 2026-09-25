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
            // 不再自铺不透明底，也不再自己画一团琥珀光晕：
            // 画布与光在根部只画一次（Design/Theme.swift 的 AppCanvas），启动画面吃同一束光。
            // 自己再画一个光源就是「光有两个来源」—— 而且它的方向还是编的。
            VStack(spacing: TokensSpacing.xxl) {
                // 品牌标：入场淡入（一次性，不是常驻呼吸）
                Image(safeSymbol: "car.side.fill", fallback: "car.side.fill")
                    .font(TokensTypo.fixed(34, weight: .light))
                    .foregroundStyle(TokensPalette.primary)
                    .frame(width: 80, height: 80)
                    .background(
                        RoundedRectangle(cornerRadius: TokensRadius.large, style: .continuous)
                            .fill(TokensPalette.ambient)
                    )
                    .opacity(brandGlow)

                VStack(spacing: TokensSpacing.sm) {
                    Text("长安车管家")
                        // 艺术方向下走衬线（原生下 TokensSerif.page 就是原来的系统字）
                        .font(TokensSerif.page(28))
                        .foregroundStyle(TokensPalette.primary)
                        .tracking(TokensTracking.title)

                    Text("CHANGAN CONNECT")
                        .font(TokensTypo.caption2)
                        .foregroundStyle(TokensPalette.tertiary)
                        .tracking(4)
                }

                // 进度：一条正在被画出来的线 —— 它对应一个真实状态（「正在启动」）
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(TokensPalette.track)
                            .frame(height: 2)
                        RoundedRectangle(cornerRadius: 1)
                            .fill(TokensPalette.ambient)
                            .frame(width: geo.size.width * progress, height: 2)
                    }
                }
                .frame(width: 160, height: 2)
                .padding(.top, TokensSpacing.md)
            }
            .padding(.horizontal, TokensSpacing.page)
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
