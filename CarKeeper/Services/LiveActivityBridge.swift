// =============================================================================
//  LiveActivityBridge — App 里唯一碰 WidgetKit / ActivityKit 的地方
// =============================================================================
//  App 只做两件事：把车况写成快照（SharedStore）、在充电状态变化时启动/更新/结束实时活动。
//  小组件与实时活动的**界面**全部在 Widgets/WidgetBundle.swift（扩展里），
//  数据契约在 Shared/ —— App 与扩展不共享界面代码，只共享令牌与模型。
//
//  ⚠️ 前置条件（缺一不可，缺任何一个实时活动都不会出现）：
//    1. App 的 Info.plist 里有 NSSupportsLiveActivities（project.yml 已加）
//    2. 系统设置里允许该 App 的实时活动（ActivityAuthorizationInfo）
//    3. 扩展里有一个 ActivityConfiguration（Widgets/WidgetBundle.swift 已实现）
// =============================================================================

import Foundation
import ActivityKit
import WidgetKit

@MainActor
enum LiveActivityBridge {

    /// 快照变化后调用：刷新小组件时间线 + 同步充电实时活动。
    /// 只在内容真的变了时才会被调用（SharedStore.write 返回 true），
    /// 否则车况每 60 秒轮询一次会把小组件的刷新预算烧光。
    static func sync(_ snapshot: VehicleSnapshot) {
        WidgetCenter.shared.reloadAllTimelines()
        Task { await syncChargingActivity(snapshot) }
    }

    /// 充电中 → 起一条实时活动；不充了 → 立刻收掉（不留一张"假充电中"的锁屏卡）
    private static func syncChargingActivity(_ snapshot: VehicleSnapshot) async {
        let running = Activity<ChargingActivityAttributes>.activities

        guard snapshot.charging else {
            for activity in running {
                await activity.end(nil, dismissalPolicy: .default)
            }
            return
        }

        // 用户在系统设置里关掉了实时活动：直接跳过，不报错
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let state = ChargingActivityAttributes.ContentState(
            soc: snapshot.soc,
            rangeKm: snapshot.rangeKm,
            powerKW: snapshot.chargePower ?? 0,
            timeToFull: snapshot.timeToFull,
            charging: true,
            cls: snapshot.chargeCls,
            updatedAt: snapshot.updatedAt
        )
        // 15 分钟没有新数据就标记为过期（锁屏上会变灰，而不是假装还是最新的）
        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(15 * 60))

        if let current = running.first {
            await current.update(content)
            // 意外多出来的活动（例如上次异常退出留下的）一并收掉
            for extra in running.dropFirst() {
                await extra.end(nil, dismissalPolicy: .immediate)
            }
            return
        }

        let attributes = ChargingActivityAttributes(plate: currentCarName(), startedAt: Date())
        // 失败不抛给上层：实时活动是"锦上添花"，不该影响车况刷新
        _ = try? Activity.request(attributes: attributes, content: content, pushType: nil)
    }

    /// 退出登录时收掉全部实时活动：
    /// 否则上一个账号的车牌和电量会留在锁屏上继续可见。
    static func endAll() {
        Task {
            for activity in Activity<ChargingActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// 车辆名（用于锁屏上的标题行）：与 App 首屏取的是同一个来源
    private static func currentCarName() -> String {
        let store = AppStore.shared
        let sel = VM.carSel(store.cars, store.carId)
        if sel.options.indices.contains(sel.index) { return sel.options[sel.index].name }
        return "车辆"
    }
}
