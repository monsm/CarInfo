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
//  2026-09-26（第三十一轮地毯式审核）把标题那句话**重新变成真的**：外壳里原本还挂着
//  一条 `Timer.publish(every: 30)`，每 30 秒 ping 一次 `getCars()`（每小时 120 次 ——
//  比地图页停着时的上限还多），而它要回答的只是「网络还在不在」。那条定时器已删，
//  那个问题改由**真实取数的结果**回答（`AppStore.networkStatus` 现在是算出来的）。
//  于是「多久取一次数」又只剩这一处。
//
//  为什么不是「每个页面自己开一个定时器」：六页是**同时建出来**的（`MapSpineView.pageDeck`
//  一次搭好六档，换档只是淡出淡入）。每页一个 `Timer` 就等于六个循环各按自己的节律取数，
//  而它们问的是同一个服务端、同一辆车 —— 一次「换档」会同时把六份请求都点着。
//  这个仓库上一次删掉的东西正是这一类（同一件事有好几套实现）。
//
//  所以：**一个循环**，节律由三个输入算出来，而这三个输入都只有一处出：
//    · 在哪一档 —— `HomeMode.storageKey`（模式条自己写的那一个键，DSSwipeStrip → @AppStorage）
//    · 车在不在动 —— 最近一份**定位报文**里的 `speed`（`AppStore.isCarMoving`，
//      2026-09-27 起就是这一个字段：车在动时那一拍只取那一份，见下）
//    · 手动刷新 —— 由人点（`refreshAll()`），不参与节律
//
//  ── 节律本身（一个数一个理由） ──
//
//  | 何时 | 间隔 | 取什么 | 为什么 |
//  |---|---|---|---|
//  | 地图页 · 车在动 | **1 s** | `fetchMotion()`：**只取定位那一份** | 会一秒一变的东西只有车速 / 位置 / 航向 / 地址，而它们全在那一份报文里 |
//  | 地图页 · 车在动 · 第 10 拍 | 与上一行同一拍 | `fetchCore()`（整趟四个接口） | 电量 / 续航 / 胎压 / 车锁的变化尺度是分钟级，见下 |
//  | 地图页 · 车停着 | **2→4→8→16→32→60 s**（每读到一次 0 就翻倍，封顶 60） | `fetchCore()` | 见下 |
//  | 其他五档 · 轻 | **60 s** | `fetchCore()` | 那几页的骨架是车况四项 |
//  | 其他五档 · 重 | **300 s** 或**翻到这一页时** | `fetchVehicleData()` | 消息 + 体检是两路重接口，见下 |
//
//  ── 运动那一档：**1 秒，而且只花一个请求**（用户 2026-09-27 第 2 条） ──────
//
//  原话：「地图页的刷新，运动情况下是否可以做到 1 秒刷新一次，再就是这 1 秒中
//  只取车速和定位，哪个 api 可以一次就获取到，不要浪费请求。」
//
//  一次就够的那一份是 **`cardata/getCarLocation`**（`APIClient.getLocation`）：
//  它一份报文里同时带着 `lat` / `lng`（GCJ-02，可直接投 Apple 地图）、`speed`（km/h）、
//  `heading`、`gpsTime`、`addrDesc`（服务端逆地理地址）。`API-FIELD-MAP.md` §4.4 那
//  13 个字段是抓包逐字核过的，而且那里写明 `speed` 与 control 的 `VehicleSpeed`
//  **是同一个量** —— 于是「车速」那一个读数的出处跟着搬到这一份里（`VM.driveStatus`）。
//  换句话说：用户要的「车速 + 定位一次拿到」在报文层面已经有现成的答案，
//  不需要新接口，也不需要同时问两个接口。
//
//  为什么不能继续拿 `fetchCore()` 当 1 秒那一拍（那一趟是 4 个接口）：电量 / 续航 /
//  胎压 / 车锁的变化尺度是**分钟级**，1 秒问一次它们不会有新答案。于是运动时：
//    · **每一拍**只取定位那一份（1 个请求）—— 位置、车速、航向、地址是 1 秒的；
//    · **每 10 拍**（≈10 秒）改取一整趟（4 个请求）—— 那一横与抽屉里其余读数跟着它走。
//  算账：旧版 2 秒一趟×4 个 = **2.0 请求/秒**；新版 1 + 4/10 = **1.4 请求/秒** ——
//  运动那部分快了一倍，而**总请求量反而少了三成**（这也是对「不要浪费请求」的答复）。
//
//  ⚠️ 实际周期 = 1 秒 **+ 这一趟请求的耗时**：第 ① 条自我约束是「不并发」（上一趟
//  `await` 完了才睡下一次），弱网里这一拍会自然拉长 —— 这是刻意的：
//  同一秒点着两趟才叫浪费。
//
//  ⚠️ 这一拍**不参与网络判定**（`saveCache(…, declaresOffline: false)`）：它只问一个源，
//  「一个都没取到」在那儿说明不了「网络断了」，而外壳上那枚弱网提示会因此每秒闪一次。
//  网络判定仍然只在整趟那一拍做。
//
//  ⚠️ 没量到的一件事，如实写：车端 tbox 在行驶中**多久上报一次**，我们没有实测数字。
//  如果它比 1 秒慢，这 1 秒一拍会读到同一份快照（`gpsTime` 没前进）——
//  报文里 `gpsTime` 就是为回答这件事存在的（见 `API-FIELD-MAP.md` 开头那段
//  「11 次请求逐字节相同」）。要验证只在真机上：诊断页的原始日志里
//  看连续几次 `getCarLocation` 的 `gpsTime` 有没有前进。
//
//  ── 停着那一档是一条**退避曲线**（用户 2026-09-26：「15 秒久了，改用更智能的
//     算法吧，直至最高 60 秒」）─────────────────────────────────────────
//
//  那句话读起来像矛盾（要更快、又只要到 60），其实是一条曲线的两端：
//  **刚停下要快，停越久越省**。自变量不另存时钟，就是「连着读到过几次 0 速度」——
//  每一次取数本身就是一次读数，所以没有「两处都在算时间」的问题。
//
//    · 停下后的头几次：**2 → 4 → 8 秒**。红绿灯、临时靠边、下人 —— 都在这一段里。
//      它们随时可能再动，而「地图要跟着车」最需要接上的就是这一刻。
//      放在这一档里的东西代价极低（停着的车报文几乎不变），而**漏掉起步**的代价是整张图留在原地。
//    · 之后 16 → 32 → **60 秒封顶**（用户给的数）：停在车位上十分钟还是一小时，
//      对我们已经没有区别了 —— 那就按「问一次能省多少」来。
//      一直停着的车不会比 1 分钟问得更少（这是他与“省接口”之间的那条线）。
//
//  ⚠️ 发现起步的代价永远只是**当前这一档的等待**（2…60 秒），而车一动就归零：
//  下一拍立刻回到 2 秒。所以这条曲线不是在「慢」与「准」之间取舍 ——
//  它是用停车时长换接口量，而换掉的那部分是**确定不会变**的那一段。
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
//  它的第一次取数在 2 秒（地图页）/ 60 秒（其他档）之后 —— 它是全 App「多久取一次数」
//  的**唯一**一处（2026-09-26 第三十一轮审核之后尤其如此：当时删掉了外壳里那条
//  每 30 秒 ping 一次的定时器，它就是唯一剩下的那条节律）。
// =============================================================================

@MainActor
final class RefreshLoop {

    static let shared = RefreshLoop()

    private init() {}

    /// 全部节律（秒）。**它们只在这里出现一次** —— 别处再写一个 2 或 300 就是第二份节律。
    enum Cadence {
        /// 地图页 · 车在动（实时）—— **1 秒**（用户 2026-09-27 第 2 条点名要的数）
        static let moving: Double = 1
        /// 运动时**每几拍**取一次整趟（`fetchCore`，四个接口）
        static let movingFullEvery: Int = 10
        /// 地图页 · 刚停下（退避曲线的起点 —— 与「车在动」是同一个数，这不是巧合：
        /// 刚停下时我们**还不知道**它是红灯还是停车位，那时按「还在动」问最安全）
        static let parkedFloor: Double = 2
        /// 地图页 · 停久了的封顶（用户 2026-09-26 给的数）
        static let parkedCeil: Double = 60
        /// 退避曲线翻几次就封顶（2·2^5 = 64 > 60，所以五步就到顶）
        static let parkedSteps: Int = 5
        /// 其他五档的**轻**取数（车况四项）
        static let page: Double = 60
        /// 其他五档的**重**取数（消息 + 体检）
        static let heavy: Double = 300
    }

    private var task: Task<Void, Never>? = nil

    //  `lastTickAt`（最近一次取数的时刻）曾在这里 —— 已于 2026-09-26 随
    //  「删除刷新调试」一起删（`MapRefreshBadge` 是它唯一的外部读者，
    //  而循环自己从不读它）。留着它就是一个只有写者、没有读者的变量。

    /// 连着读到过**几次 0 速度**（只数地图页的读数）。车在动就归零。
    ///
    /// 它是停着那条退避曲线的**自变量**（不是「确认了几次才认定停着」——
    /// 那个形状 2026-09-26 当天就被用户否掉了，见文件头），也是循环自己读的那个数
    ///（`parkedInterval`）—— 于是它 `private` 就够（那枚调试倒计时删了之后没有外部读者）。
    private var zeroStreak = 0

    /// 运动时数到第几拍（只在「车在动」这一档里数）。它只回答一件事：
    /// 这一拍该只取定位，还是取一整趟（`Cadence.movingFullEvery`）。车一停就归零。
    private var motionTicks = 0

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
    /// 车一动的那一秒内它就会变成 2 —— 循环每一拍都重算它（见 `start()`）。
    var interval: Double {
        guard isOnMap else { return Cadence.page }
        return AppStore.shared.isCarMoving ? Cadence.moving : parkedInterval
    }

    /// 停着时的等待（秒）：**每读到一次 0 就翻倍，封顶 60**。
    ///
    /// 曲线本身：`2 → 4 → 8 → 16 → 32 → 60`（第五步就顶到封顶值，
    /// 因为 2·2⁵ = 64）。`min(zeroStreak, steps)` 那一步只是防溢出：
    /// 停了一整夜之后这个计数会很大，而 `pow(2, 1000)` 是个没意义的数。
    ///
    /// 为什么不用一条时间曲线（比如「停够 1 分钟就 60」）：那要另记一个时刻，
    /// 而**每一次取数本身就是一次读数**。用读数当自变量，就只有一个变量。
    var parkedInterval: Double {
        let steps = min(zeroStreak, Cadence.parkedSteps)
        return min(Cadence.parkedCeil, Cadence.parkedFloor * pow(2, Double(steps)))
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
            //  运动：1 秒一拍，而绝大多数拍子**只取定位那一份**；每 10 拍取一次整趟
            //（理由与算账见文件头「运动那一档」）。
            //  停着：整趟（那几拍本来就稀疏），并把「还是 0」记进退避曲线的自变量。
            if store.isCarMoving {
                zeroStreak = 0
                motionTicks += 1
                if motionTicks % Cadence.movingFullEvery == 0 {
                    await store.fetchCore()
                } else {
                    await store.fetchMotion()
                }
            } else {
                motionTicks = 0
                await store.fetchCore()
                zeroStreak += 1
            }
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
    }

    /// 手动「全局刷新」：**全部 API**（车况 + 消息 + 体检）。
    /// 地图页那颗「全局刷新」走它 —— 用户按下去要的是「所有东西都给我重取一遍」，
    /// 而不是「比自动那次多一点点」。
    func refreshAll() async {
        let store = AppStore.shared
        guard store.isLoggedIn, !store.carId.isEmpty else { return }
        await store.fetchVehicleData()
        lastHeavyAt = Date()
        // 一颗按下去就没有回音的按钮，用户只会怀疑它没生效 —— 而它其实取完了。
        // 所以刷完说一句：全取到就是一句「好了」，有缺项就**如实说几项**
        //（缺项不是失败：`saveCache` 已经把没取到的源清空，界面自己会显示「没取到」）。
        let missed = store.lastMissedSources
        ToastManager.shared.show(
            missed.isEmpty ? "已取到最新数据" : "有 \(missed.count) 项没取到",
            icon: missed.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
    }
}
