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
        VStack(spacing: 0) {
            DSSegmented(options: HomeSub.vehicleTabs.map { (value: $0, title: $0.title) },
                        selection: $tab)
                .padding(.horizontal, TokensSpacing.page)
                .padding(.vertical, TokensSpacing.sm)
                // 与下面的纸同色：视觉上仍是一张纸，分段控件只是纸的上沿
                .background(TokensPalette.surface)

            switch tab {
            case .health: HealthDataView()
            case .service: MaintenanceMoneyView()
            default: VehicleView()
            }
        }
        .onAppear { consumeHint() }
        .onChange(of: nav.homeSub) { _, _ in consumeHint() }
    }

    /// 消费深链带来的段落提示。消费掉（置 nil）是必须的：否则从别的档切回来时，
    /// 会被同一条旧提示再拉回那一段。
    private func consumeHint() {
        guard let hint = nav.homeSub, HomeSub.vehicleTabs.contains(hint) else { return }
        tab = hint
        nav.homeSub = nil
    }
}
