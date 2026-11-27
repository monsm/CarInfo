import SwiftUI

struct SplashView: View {
    @State private var progress: CGFloat = 0
    @State private var showMain = false
    @State private var dissolved = false
    @State private var brandGlow: CGFloat = 0

    let duration: TimeInterval = 2.0

    var body: some View {
        ZStack {
            VStack(spacing: TokensSpacing.xxl) {
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
                        .font(TokensTypo.fixed(28, weight: .semibold))
                        .foregroundStyle(TokensPalette.primary)
                        .tracking(TokensTracking.title)

                    Text("CHANGAN CONNECT")
                        .font(TokensTypo.caption2)
                        .foregroundStyle(TokensPalette.tertiary)
                        .tracking(4)
                }

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
