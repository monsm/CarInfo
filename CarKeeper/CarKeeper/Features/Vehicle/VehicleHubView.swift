import SwiftUI

// =============================================================================
//  车辆档的外壳 —— 档案 / 健康 / 保养三段
// =============================================================================
//  它们此前是条子上的三档（车辆 / 健康 / 保养），可三档回答的是同一个问题：
//  **这辆车怎么了**。分成三档的代价是每次都要拨条子——而拨过去之后换的其实是
//  同一份报文（`control` 与 `carcheck`）。
//
//  现在它是一档里的三段：没有第二层返回按钮、没有 push，只有这一行分段控件。
//  深链落到哪一段由 `HomeMode.destination(for:)` 决定（`carkeeper://health`
//  → 车辆档 + 健康段），所以搜索里点「健康」不会落在「档案」上。
// =============================================================================

struct VehicleHubView: View {
    @EnvironmentObject private var nav: NavState
    @State private var tab: HomeSub = .profile

    var body: some View {
        StackPageView(accent: HomeMode.vehicle.accent, label: "车辆", cards: cards)
            .onAppear { consumeHint() }
            .onChange(of: nav.homeSub) { _, _ in consumeHint() }
    }

    /// 这一档的叠叠乐：巨字头 → 分段控件 → 当前那一段的内容。
    ///
    /// 三段（档案 / 健康 / 保养）共用**同一叠**，而不是各自一叠：
    /// 换段时巨字头与分段控件停在原地（它们是同一张卡），下面那一叠只换一个成员 ——
    /// 这样「换段」看起来是「下面那张卡换了」，而不是「又翻了一页」。
    @MainActor
    private var cards: [StackCard] {
        var out = HomeMode.vehicle.headCards
        out.append(StackCard(id: "tabs", content: AnyView(
            DSSegmented(options: HomeSub.vehicleTabs.map { (value: $0, title: $0.title) },
                        selection: $tab))))
        out.append(contentsOf: sectionCards)
        return out
    }

    /// 当前那一段自己的卡。能拆开的段自己拆（`VehicleView.cards`），
    /// 拆不开的（健康 / 保养是两张整表）包成一张 —— 两者的区别只是「卡有多高」，
    /// 不是两套排版。
    @MainActor
    private var sectionCards: [StackCard] {
        switch tab {
        case .health:
            return [StackCard(id: "health", title: "体检", content: AnyView(HealthDataView()))]
        case .service:
            return [StackCard(id: "service", title: "保养", content: AnyView(MaintenanceMoneyView()))]
        default:
            return VehicleView.sectionCards
        }
    }

    /// 消费深链带来的段落提示。消费掉（置 nil）是必须的：否则从别的档切回来时，
    /// 会被同一条旧提示再拉回那一段。
    private func consumeHint() {
        guard let hint = nav.homeSub, HomeSub.vehicleTabs.contains(hint) else { return }
        tab = hint
        nav.homeSub = nil
    }
}
