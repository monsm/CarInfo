// =============================================================================
// #NEW-113 Onboarding 引导 — 首次使用 3 页引导流程
// =============================================================================

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
            // 页面内容
            TabView(selection: $currentPage) {
                ForEach(OnboardingPage.allCases) { page in
                    onboardingPage(page)
                        .tag(page.rawValue)
                }
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .always))
            .indexViewStyle(PageIndexViewStyle(backgroundDisplayMode: .always))

            // 底部操作区：直接坐在版面上（不再是一片带边的卡）
            // —— 引导页能做的事只有「下一步」和「跳过」，它们不需要一个容器来证明自己是一组。
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
        // 旧版：整屏三色渐变（主色 + 紫 + 蓝）+ 一枚彩色发光阴影。
        // 新版：单一画布（光在根上由真实太阳位置算），按钮用形状表达层级，不用光。
    }

    private func onboardingPage(_ page: OnboardingPage) -> some View {
        VStack(spacing: 24) {
            // 图标
            ZStack {
                // 旧版：渐变色圆 + 超大图标。新版：扁平色块（与登录页品牌标同一套语言）。
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(TokensPalette.ambient)
                    .frame(width: 96, height: 96)
                Image(safeSymbol: page.icon, fallback: "car.fill")
                    .font(.system(size: 40, weight: .regular))
                    .foregroundStyle(TokensPalette.ambient)
            }

            // 标题和描述（标题走衬线：艺术方向下「引导页」也是一页纸）
            VStack(spacing: 12) {
                Text(page.title)
                    .font(TokensSerif.page(28))
                    .foregroundStyle(TokensPalette.primary)

                Text(page.description)
                    .font(TokensTypo.body)
                    .foregroundStyle(TokensPalette.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            // 示例内容
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

/// 引导页上的「例子」：一行键值（例：示例车牌 / 京A·12345）。
/// 它用与「全量数据」同一套键值行 —— 同一个 App 里「左键右值」只该有一种写法。
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
