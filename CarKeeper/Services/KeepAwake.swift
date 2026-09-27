import UIKit

// =============================================================================
//  KeepAwake —— 车在动的时候**不让屏幕自己睡**
// =============================================================================
//
//  用户 2026-09-26：「再就是车移动的时候要保持屏幕唤醒不睡着」。
//
//  ── 机制只有一行 ──────────────────────────────────────────────────────
//
//  `UIApplication.shared.isIdleTimerDisabled` 就是系统给的那个开关
//（导航、视频播放器用的都是它）。不自己记时间、也不摆一块用来防熄屏的假视图 ——
//  那两种做法都会在别处多出一个「到底谁在管屏幕」的分支。
//
//  ── 「车在动」这件事只有一处出处 ────────────────────────────────────────
//
//  它就是 `AppStore.isCarMoving`（= 最近一份**定位报文**里的 `speed > 0`）——
//  刷新节律（`RefreshLoop`：地图页车在动 1s、停着那条递退曲线）用的也正是这一个布尔。
//  这里读同一处，**不另立**「多久没动就算停下」的判据 —— 两套判据管一件事，
//  等于两套都不可信（这一仓反复删的就是这一类）。
//
//  ⚠️ 观察方式用 Observation 框架的 `withObservationTracking`：`AppStore` 是
//  `@Observable`（不是 `ObservableObject`），所以没有 `$caches` 那样的 Combine
//  发布者可以订阅。它是**一次性**的观察 —— 每次回调都要重新装一次（`arm()`）。
//
//  ⚠️ 回调在**值改变之前**触发（willSet 语义，与 Combine 的 `@Published` 同一条），
//  所以真正落状态的那一步推到下一个主线程回合（`Task { @MainActor in … }`）：
//  那一刻新报文已经写进去了。 直接在回调里读会读到**上一份**报文 —— 那一版的
//  「车在动」永远晚一拍。
//
//  ⚠️ 只在**真的变了**才写 UIKit（`applied` 那个本机副本）：车在动时报文每 1 秒
//  来一份，每份都去写一遍系统属性没有意义（UIKit 会为此做一次跨进程的事）。
//
//  ⚠️ 边界，如实写两条：
//    · `isIdleTimerDisabled` 只在**前台**有意义 —— App 退到后台，系统照常锁屏。
//      那是系统的规矩，不是我们能关掉的开关（也没有为此加 scenePhase 分支：
//      那个分支只会让「谁在管屏幕」多一个入口）。
//    · 车在动 + 屏幕常亮 = 费电。这是用户明确要的取舍，所以**没有**再开一个开关
//      （这一仓的规矩：能定的事不留开关，见「显示」那一节整组被删的理由）。
// =============================================================================

@MainActor
final class KeepAwake {

    static let shared = KeepAwake()

    private init() {}

    /// 上一次写进 UIKit 的那个值（`nil` = 还没写过）。
    /// 它只为一件事存在：让「没变就不写」成立。
    private var applied: Bool? = nil

    /// 装上观察（启动时调一次；之后每次变化自己重装）。
    func start() {
        arm()
    }

    /// 装一次观察。
    private func arm() {
        withObservationTracking {
            //  读一次就够：`isCarMoving` 底下是那份缓存（`caches`），
            //  Observation 会把这条读路径经过的存储属性都记下来。
            _ = AppStore.shared.isCarMoving
        } onChange: { [weak self] in
            //  这一下发生在**写入之前**，所以推到下一个主线程回合再读（见文件头）。
            Task { @MainActor in
                self?.apply()
                self?.arm()
            }
        }
    }

    /// 按当前那一份读数落一次状态。
    private func apply() {
        let moving = AppStore.shared.isCarMoving
        guard applied != moving else { return }
        applied = moving
        UIApplication.shared.isIdleTimerDisabled = moving
    }
}
