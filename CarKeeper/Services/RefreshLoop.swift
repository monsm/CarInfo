import Foundation

// =============================================================================
//  RefreshLoop —— 全 App 唯一一处决定「多久取一次数」的地方
// =============================================================================
//
//  用户 2026-09-25（这一稿的底子）：
//    「地图页如果车正在移动则每 2 秒刷新一次地图页所需数据 api，静止则 1 分钟刷新一次，
//      其他页面均采取 5 分钟一次，地图页的全局刷新可以刷新全部 api」。
//
//  用户 2026-09-26（这一轮改的四条）：
//    ① 「地图页并没有实时刷新 …… 连续 10 次读到 0 速度就每隔 15 秒刷新一次地图页」
//    ② 「有速度就 2 秒刷新一次地图页（自动刷新 api）」
//    ③ 「其他页面每 1 分钟刷新一次」
//    ④ 「对于 api 压力大的可采取用户查看时再加载 api 数据，或每 5 分钟一次」
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
//  ── 节律本身（一个数一个理由） ──
//
//  | 何时 | 间隔 | 取什么 | 为什么 |
//  |---|---|---|---|
//  | 地图页 · 车在动 | **2 s** | `fetchCore()` | 车速、电量、位置正在变，这一页的读数就是「现在」 |
//  | 地图页 · 刚停下 | **60 s** | `fetchCore()` | 还在确认它是不是真停了；一分钟够快，也不至于空转 |
//  | 地图页 · 连着 10 次 0 速度 | **15 s** | `fetchCore()` | 见下（这一条是**变快**的那一条） |
//  | 其他五档 · 轻 | **60 s** | `fetchCore()` | 那几页的骨架是车况四项 |
//  | 其他五档 · 重 | **300 s** 或**翻到这一页时** | `fetchVehicleData()` | 消息 + 体检是两路重接口，见下 |
//
//  ⚠️ 「连着 10 次读到 0 速度 → 15 秒」的方向容易读反：它是**变快**，不是变慢。
//  60 秒那一档是「刚停下来、还在确认」；连着 10 次都是 0 之后，这一页要回答的问题
//  变成了「它什么时候再动」—— 而那个时刻只能靠问出来。停着的车多问几次很便宜
//  （它没有在动、报文也一样），而**漏掉起步**的代价是地图留在原地不动。
//  数的是**读数**（每一次取数算一次），不是时间 —— 所以它和「多久取一次」是同一个变量的两面。
//
//  ⚠️ 「重的两路」为什么不跟轻的一起 60 秒一次：`fetchVehicleData()` 多取**消息**与**体检**
//  两个大接口（`AppStore.gather` 的两个开关），而这两份数据回答的不是「此刻」——
//  用户 2026-09-26 给的办法正是这一条：「用户查看时再加载，或每 5 分钟一次」。
//  所以：**翻到这一页时当场取一次**（`modeChanged`），之后 5 分钟一次。
//  地图页不管重的那两路：它要的是「现在」。
//
//  ── 三条自我约束 ──
//
//   ① **不并发**：一次取数没回来之前不开始下一次（`await` 完再睡）。2 秒的节律下，
//      弱网里一次请求可能比间隔还长 —— 那正是「同一秒点着两趟」最容易发生的地方。
//   ② **没登录 / 没车就不取**：`carId` 为空时那几个接口本来就会 400，白白打一趟。
//   ③ **进后台不需要特殊处理**：iOS 会挂起进程，`Task.sleep` 随之停摆，回前台继续。
//      自己写后台观察者只会多一条要在两处维护的分支。
//
//  ⚠️ 一次睡眠是**一秒一格**的（见 `start()`）：节律会变，而「一口气睡完」的那个写法
//  会让变化等到这一觉睡完才生效 —— 换档要等整整一分钟，2 秒那一档醒来时车已经开走了。
//  一格一秒的代价只是一次 `Task.sleep`，没有网络、没有分配。
//
//  ⚠️ 它读 `HomeMode.storageKey` —— 一个 `Features/` 里的枚举常量，而本文件在 `Services/`。
//  这是**故意**的方向：导航词表（六档叫什么、存在哪个键）只有那一处，
//  让服务自己再记一份「哪一档是地图」的字符串，就是把同一个决定写了两遍。
//
//  ⚠️ 它**不在** `LaunchFence` 的四个开关里：那四个是「启动期做了哪些事」的二分实验，
//  而这个循环是 App 正常形态的一部分（第一次取数在 2/15/60/300 秒之后，与「载入不到
//  10 秒就退」不在同一个时间窗）。这一条写在 `LaunchFence.mapFetches` 的注里了。
// =============================================================================

@MainActor
final class RefreshLoop {

    static let shared = RefreshLoop()

    private init() {}

    /// 全部节律（秒）。**它们只在这里出现一次** —— 别处再写一个 2 或 300 就是第二份节律。
    enum Cadence {
        /// 地图页 · 车在动
        static let moving: Double = 2
        /// 地图页 · 刚停下（还在确认）
        static let parked: Double = 60
        /// 地图页 · **连着读到 10 次 0 速度之后**（见文件头那一段：这一条是变快的那一条）
        static let parkedConfirmed: Double = 15
        /// 其他五档的**轻**取数（车况四项）
        static let page: Double = 60
        /// 其他五档的**重**取数（消息 + 体检）
        static let heavy: Double = 300
        /// 「连着读到 10 次 0 速度」里的那个 10
        static let zeroStreak: Int = 10
    }

    private var task: Task<Void, Never>? = nil

    /// 最近一次取数的时刻。给界面回答「这份读数有多新」用（也让人一眼看出循环在不在跑）。
    private(set) var lastTickAt: Date? = nil

    /// 连着读到**几次 0 速度**（只数地图页的读数）。车在动就归零。
    private var zeroStreak = 0

    /// 上一次取「重的那两路」（消息 + 体检）的时刻。
    private var lastHeavyAt: Date? = nil

    /// 上一拍看到的是哪一档。它一变就是「用户翻到了另一页」—— 那一页的重数据当场取一次。
    private var lastModeRaw: String? = nil

    // MARK: 节律

    /// 现在这一档的 raw 值。
    ///
    /// 读的是 `HomeMode.storageKey` —— 模式条写的那**同一个常量**（键名不在这儿重写一遍，
    /// 见 `keys.py` 的纪律）。没有存过值时当作地图页（默认档就是它）。
    private var currentModeRaw: String {
        UserDefaults.standard.string(forKey: HomeMode.storageKey) ?? HomeMode.now.rawValue
    }

    /// 现在这一档在不在**地图主屏**。
    private var isOnMap: Bool { currentModeRaw == HomeMode.now.rawValue }

    /// 这一档与上一拍看到的是不是同一个。**一次 tick 只读一次**（读到的那个值当场记下）。
    private var modeChanged: Bool { currentModeRaw != lastModeRaw }

    /// 下一次该等多久（秒）。**整个节律表就是这两个分支**。
    var interval: Double {
        guard isOnMap else { return Cadence.page }
        if AppStore.shared.isCarMoving { return Cadence.moving }
        return zeroStreak >= Cadence.zeroStreak ? Cadence.parkedConfirmed : Cadence.parked
    }

    // MARK: 生命周期

    /// 起循环。**幂等**：调两次不会变成两条循环（第二条直接返回）。
    func start() {
        guard task == nil else { return }
        lastModeRaw = currentModeRaw
        task = Task { [weak self] in
            while let self, !Task.isCancelled {
                // 先睡再取：启动那一趟由 `store.bootstrap()` 负责，
                // 这里不该在 App 刚起来、网络还没热的时候再压一趟上去。
                var waited: Double = 0
                let wait = self.interval
                while waited < wait {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    if Task.isCancelled { return }
                    waited += 1
                    // 换档就立刻醒：那一页的重数据要**当场**取（见文件头的 ④）。
                    if self.modeChanged { break }
                }
                if Task.isCancelled { return }
                await self.tick(pageArrived: self.modeChanged)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    // MARK: 取数

    /// 一次自动取数。**按当前档位选轻重**：地图页要「此刻」（轻），其余页要全量（重）。
    /// - Parameter pageArrived: 这一拍是不是「用户刚翻到这一页」（是就把重的那两路一起取）。
    private func tick(pageArrived: Bool) async {
        let store = AppStore.shared
        lastModeRaw = currentModeRaw
        guard store.isLoggedIn, !store.carId.isEmpty else { return }
        if isOnMap {
            await store.fetchCore()
            // 「连着 10 次读到 0 速度」数的是读数，不是时间：每一次取数算一次。
            if store.isCarMoving { zeroStreak = 0 } else { zeroStreak += 1 }
        } else {
            // 翻到这一页 / 距上次重取满 5 分钟 → 重的那两路（它已经把车况四项含在里面）。
            // 其余时候只取轻的：重接口不该跟着 60 秒的节律跑。
            let due = lastHeavyAt.map { Date().timeIntervalSince($0) >= Cadence.heavy } ?? true
            if pageArrived || due {
                await store.fetchVehicleData()
                lastHeavyAt = Date()
            } else {
                await store.fetchCore()
            }
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
        lastHeavyAt = Date()
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
