
import SwiftUI

enum OnboardingPage: String, CaseIterable, Identifiable {
    case connect = "connect"
    case location = "location"
    case pin = "pin"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .connect: return "绑定车辆"
        case .location: return "开启定位"
        case .pin: return "设置密码"
        }
    }
    var description: String {
        switch self {
        case .connect: return "输入车牌号绑定您的爱车"
        case .location: return "开启定位以查看车辆位置"
        case .pin: return "设置 PIN 码保护车辆控制"
        }
    }
    var icon: String {
        switch self {
        case .connect: return "car.fill"
        case .location: return "location.fill"
        case .pin: return "lock.fill"
        }
    }
}

struct OnboardingView: View {
    @State private var currentPage = 0
    @AppStorage("carkeeper_onboarding_seen") private var onboardingSeen = false

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $currentPage) {
                ForEach(OnboardingPage.allCases) { page in
                    onboardingPage(page)
                        .tag(page.rawValue)
                }
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .always))
            .indexViewStyle(PageIndexViewStyle(backgroundDisplayMode: .always))

            HStack {
                Button("跳过") {
                    onboardingSeen = true
                }
                .font(TokensTypo.footnote)
                .foregroundStyle(TokensPalette.secondary)

                Spacer(minLength: TokensSpacing.md)

                Button(currentPage < OnboardingPage.allCases.count - 1 ? "下一步" : "完成") {
                    withAnimation(.spring(response: 0.3)) {
                        if currentPage < OnboardingPage.allCases.count - 1 {
                            currentPage += 1
                        } else {
                            onboardingSeen = true
                        }
                    }
                }
                .font(TokensTypo.body.weight(.semibold))
                .foregroundStyle(TokensPalette.labelOnTint)
                .padding(.horizontal, TokensSpacing.lg)
                .padding(.vertical, TokensSpacing.sm + 4)
                .background(TokensPalette.ambient,
                            in: RoundedRectangle(cornerRadius: TokensRadius.pill, style: .continuous))
            }
            .padding(.horizontal, TokensSpacing.page)
            .padding(.vertical, TokensSpacing.lg)
        }
    }

    private func onboardingPage(_ page: OnboardingPage) -> some View {
        VStack(spacing: TokensSpacing.lg) {
            ZStack {
                RoundedRectangle(cornerRadius: TokensRadius.large, style: .continuous)
                    .fill(TokensPalette.ambient)
                    .frame(width: 96, height: 96)
                Image(safeSymbol: page.icon, fallback: "car.fill")
                    .font(TokensTypo.fixed(40))
                    .foregroundStyle(TokensPalette.ambient)
            }

            VStack(spacing: TokensSpacing.snug) {
                Text(page.title)
                    .font(TokensTypo.fixed(28, weight: .semibold))
                    .foregroundStyle(TokensPalette.primary)

                Text(page.description)
                    .font(TokensTypo.body)
                    .foregroundStyle(TokensPalette.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            if page == .connect {
                ExampleCard(title: "示例车牌", value: "京A·12345")
            } else if page == .location {
                ExampleCard(title: "定位权限", value: "用于显示车辆位置")
            } else {
                ExampleCard(title: "PIN 码长度", value: "4-6 位数字")
            }
        }
        .padding()
    }
}

struct ExampleCard: View {
    let title: String
    let value: String

    var body: some View {
        DSGroup {
            DSGroupRow {
                DSKeyValueRow(key: title, value: value, mono: false)
            }
        }
        .padding(.horizontal, TokensSpacing.xxxl)
    }
}

struct OnboardingView_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingView()
    }
}
