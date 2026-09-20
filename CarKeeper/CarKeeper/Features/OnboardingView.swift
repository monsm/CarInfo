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
    @State private var isLastPage = false
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

            // 底部操作区
            VStack(spacing: 20) {
                Text(isLastPage ? "准备好了吗？" : "")
                    .font(Theme.h3)
                    .foregroundStyle(.primary)

                if isLastPage {
                    Button("开始使用") {
                        onboardingSeen = true
                    }
                    .font(Theme.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Kansei.Color.ambient, in: RoundedRectangle(cornerRadius: Kansei.Radius.medium))
                    .shadow(color: Kansei.Color.ambient.opacity(0.3), radius: 8, y: 4)

                    Button("跳过引导") {
                        onboardingSeen = true
                    }
                    .font(Theme.caption)
                    .foregroundStyle(.secondary)
                } else {
                    HStack {
                        Button("跳过") {
                            onboardingSeen = true
                        }
                        .font(Theme.caption)
                        .foregroundStyle(.secondary)

                        Spacer()

                        Button(currentPage < OnboardingPage.allCases.count - 1 ? "下一步" : "完成") {
                            withAnimation(.spring(response: 0.3)) {
                                if currentPage < OnboardingPage.allCases.count - 1 {
                                    currentPage += 1
                                } else {
                                    onboardingSeen = true
                                }
                            }
                        }
                        .font(Theme.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Kansei.Color.ambient, in: RoundedRectangle(cornerRadius: Kansei.Radius.medium))
                    }
                }
            }
            .padding(.horizontal, DS.Space.xxxl)
            .padding(.vertical, DS.Space.xxl)
            .background(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .fill(Kansei.Color.nightSurface))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .strokeBorder(Kansei.Color.glassBorder, lineWidth: DS.Hair.line))
            .padding(.top, DS.Space.xl)
        }
        // 旧版：整屏三色渐变（主色 + 紫 + 蓝）。新版：单一画布色。
        .background(Kansei.Color.background)
    }

    private func onboardingPage(_ page: OnboardingPage) -> some View {
        VStack(spacing: 24) {
            // 图标
            ZStack {
                // 旧版：渐变色圆 + 超大图标。新版：扁平色块（与登录页品牌标同一套语言）。
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Kansei.Color.ambient)
                    .frame(width: 96, height: 96)
                Image(safeSymbol: page.icon, fallback: "car.fill")
                    .font(.system(size: 40, weight: .regular))
                    .foregroundStyle(Kansei.Color.ambient)
            }

            // 标题和描述
            VStack(spacing: 12) {
                Text(page.title)
                    .font(Theme.h2)
                    .foregroundStyle(.primary)

                Text(page.description)
                    .font(KanseiTypo.body)
                    .foregroundStyle(.secondary)
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

struct ExampleCard: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .font(Theme.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(KanseiTypo.body.monospaced())
                .foregroundStyle(Kansei.Color.ambient)
        }
        .padding()
        .background(Kansei.Color.fillSubtle, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 40)
    }
}

struct OnboardingView_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingView()
    }
}
