import Foundation

// =============================================================================
//  RefreshLoop —— 全 App 唯一一处决定「多久取一次数」的地方
// =============================================================================
//
//  用户 2026-09-25：
//    「地图页如果车正在移动则每 2 秒刷新一次地图页所需数据 api，静止则 1 分钟刷新一次，
//      其他页面均采取 5 分钟一次，地图页的全局刷新可以刷新全部 api」。
//
//  为什么不是「每个页面自己开一个定时器」：六页是**同时建出来**的（`MapSpineView.pageDeck`
//  一次搭好六档，换档只是淡出淡入）。每页一个 `Timer` 就等于六个循环各按自己的节律取数，
//  而它们问的是同一个服务端、同一辆车 —— 一次「换档」会同时把六份请求都点着。
//  这个仓库上一次删掉的东西正是这一类（同一件事有好几套实现）。
//
//  所以：**一个循环**，节律由三个输入算出来，而这三个输入都只有一处出：
//    · 在哪一档 —— `HomeMode.storageKey`（模式条自己写的那一个键，DSSwipeStrip → @AppStorage）
//    · 车在不在动 —— 最近一次取到的报文里的 `VehicleSpeed`（`AppStore.isCarMoving`）
//    · 手动刷新 —— 由人点（`refreshAll()`），不参与节律
//
//  ── 节律本身（照用户原话，一个数一个理由） ──
//
//  | 何时 | 间隔 | 取什么 | 为什么 |
//  |---|---|---|---|
//  | 地图页 · 车在动 | **2 s** | `fetchCore()` | 车速、电量、位置正在变，这一页的读数就是「现在」 |
//  | 地图页 · 车停着 | **60 s** | `fetchCore()` | 停着的车几乎不变；一分钟够快，也不至于空转 |
//  | 其他五档 | **300 s** | `fetchVehicleData()` | 那几页要的是**全量**（含消息与体检），而它们不是「此刻」的读数 |
//
//  `fetchCore` 与 `fetchVehicleData` 的分工不是这里定的，是 `AppStore` 既有的两条路：
//  前者只取车况那四项（快、轻，适合 2 秒一次），后者多取消息与体检（重，适合 5 分钟一次）。
//  地图页的**手动**「全局刷新」走全量 —— 用户原话：「地图页的全局刷新可以刷新全部 api」。
//
//  ── 三条自我约束 ──
//
//   ① **不并发**：一次取数没回来之前不开始下一次（`await` 完再睡）。2 秒的节律下，
//      弱网里一次请求可能比间隔还长 —— 那正是「同一秒点着两趟」最容易发生的地方。
//   ② **没登录 / 没车就不取**：`carId` 为空时那几个接口本来就会 400，白白打一趟。
//   ③ **进后台不需要特殊处理**：iOS 会挂起进程，`Task.sleep` 随之停摆，回前台继续。
//      自己写后台观察者只会多一条要在两处维护的分支。
//
//  ⚠️ 它读 `HomeMode.storageKey` —— 一个 `Features/` 里的枚举常量，而本文件在 `Services/`。
//  这是**故意**的方向：导航词表（六档叫什么、存在哪个键）只有那一处，
//  让服务自己再记一份「哪一档是地图」的字符串，就是把同一个决定写了两遍。
//
//  ⚠️ 它**不在** `LaunchFence` 的四个开关里：那四个是「启动期做了哪些事」的二分实验，
//  而这个循环是 App 正常形态的一部分（第一次取数在 2/60/300 秒之后，与「载入不到
//  10 秒就退」不在同一个时间窗）。这一条写在 `LaunchFence.mapFetches` 的注里了。
// =============================================================================

@MainActor
final class RefreshLoop {

    static let shared = RefreshLoop()

    private init() {}

    /// 三档节律（秒）。**它们只在这里出现一次** —— 别处再写一个 2 或 300 就是第二份节律。
    enum Cadence {
        /// 地图页 · 车在动
        static let moving: Double = 2
        /// 地图页 · 车停着
        static let parked: Double = 60
        /// 其他五档
        static let page: Double = 300
    }

    private var task: Task<Void, Never>? = nil

    /// 最近一次取数的时刻。给界面回答「这份读数有多新」用（也让人一眼看出循环在不在跑）。
    private(set) var lastTickAt: Date? = nil

    // MARK: 节律

    /// 现在这一档在不在**地图主屏**。
    ///
    /// 读的是 `HomeMode.storageKey` —— 模式条写的那**同一个常量**（键名不在这儿重写一遍，
    /// 见 `keys.py` 的纪律）。没有存过值时当作地图页（默认档就是它）。
    private var isOnMap: Bool {
        let raw = UserDefaults.standard.string(forKey: HomeMode.storageKey) ?? HomeMode.now.rawValue
        return raw == HomeMode.now.rawValue
    }

    /// 下一次该等多久（秒）。**整个节律表就是这三个分支**。
    var interval: Double {
        guard isOnMap else { return Cadence.page }
        return AppStore.shared.isCarMoving ? Cadence.moving : Cadence.parked
    }

    // MARK: 生命周期

    /// 起循环。**幂等**：调两次不会变成两条循环（第二条直接返回）。
    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while let self, !Task.isCancelled {
                let wait = self.interval
                // 先睡再取：启动那一趟由 `store.bootstrap()` 负责，
                // 这里不该在 App 刚起来、网络还没热的时候再压一趟上去。
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                if Task.isCancelled { return }
                await self.tick()
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    // MARK: 取数

    /// 一次自动取数。**按当前档位选轻重**：地图页要「此刻」（轻），其余页要全量（重）。
    private func tick() async {
        let store = AppStore.shared
        guard store.isLoggedIn, !store.carId.isEmpty else { return }
        if isOnMap {
            await store.fetchCore()
        } else {
            await store.fetchVehicleData()
        }
        lastTickAt = Date()
    }

    /// 手动「全局刷新」：**全部 API**（车况 + 消息 + 体检）。
    /// 地图页那颗「全局刷新」走它 —— 用户按下去要的是「所有东西都给我重取一遍」，
    /// 而不是「比自动那次多一点点」。
    func refreshAll() async {
        let store = AppStore.shared
        guard store.isLoggedIn, !store.carId.isEmpty else { return }
        await store.fetchVehicleData()
        lastTickAt = Date()
        // 一颗按下去就没有回音的按钮，用户只会怀疑它没生效 —— 而它其实取完了。
        // 所以刷完说一句：全取到就是一句「好了」，有缺项就**如实说几项**
        //（缺项不是失败：`saveCache` 已经把没取到的源清空，界面自己会显示「没取到」）。
        let missed = store.lastMissedSources
        ToastManager.shared.show(
            missed.isEmpty ? "已取到最新数据" : "有 \(missed.count) 项没取到",
            icon: missed.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
    }
}
