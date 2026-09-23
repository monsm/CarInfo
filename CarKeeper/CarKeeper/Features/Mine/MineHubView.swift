import SwiftUI

// =============================================================================
//  「我的」档的外壳 —— 设置 / 应急 / 诊断三段
// =============================================================================
//  应急与诊断此前各占条子上一整档（10 档里的两格），而它们是少数时刻才用的东西；
//  它们也不是「功能目录」的一员 —— 一个是出事时打给谁，一个是出问题时看什么。
//
//  应急被放进档内，是**明知代价**的选择（此前明确写过「紧急入口不该埋在目录里」）：
//  代价是从 1 次拖动变成 1 次拖动 + 1 次点击。换来的是条子上少两格低频内容，
//  以及「我的」这一档终于只有一个含义（我的账号 / 我的车 / 我的应急 / 我的工具）。
//  真出事时 SOS 也仍然在地图的操作条上不需要经过这一页。
// =============================================================================

struct MineHubView: View {
    @EnvironmentObject private var nav: NavState
    @State private var tab: HomeSub = .settings

    var body: some View {
        StackPageView(accent: HomeMode.mine.accent, label: "我的", cards: cards)
            .onAppear { consumeHint() }
            .onChange(of: nav.homeSub) { _, _ in consumeHint() }
    }

    /// 这一档的叠叠乐：巨字头 → 分段控件 → 当前那一段的卡。
    /// 与「车辆」同理：换段只换下面那一叠的一个成员，巨字头与分段控件不动。
    @MainActor
    private var cards: [StackCard] {
        var out = HomeMode.mine.headCards
        out.append(StackCard(id: "tabs", content: AnyView(
            DSSegmented(options: HomeSub.mineTabs.map { (value: $0, title: $0.title) },
                        selection: $tab))))
        switch tab {
        case .emergency:
            out.append(StackCard(id: "emergency", title: "应急",
                                 content: AnyView(EmergencyPanel())))
        case .dev:
            out.append(StackCard(id: "dev", title: "诊断", content: AnyView(DevView())))
        default:
            out.append(contentsOf: MineView.sectionCards)
        }
        return out
    }

    private func consumeHint() {
        guard let hint = nav.homeSub, HomeSub.mineTabs.contains(hint) else { return }
        tab = hint
        nav.homeSub = nil
    }
}
