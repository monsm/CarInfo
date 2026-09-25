import Foundation
import CoreLocation
import Combine

// =============================================================================
//  PhoneLocation —— 手机自己的位置
// =============================================================================
//
//  2026-09-25 用户：「地图页要像 ios 地图 app 右侧的图标一样加入快速回到车的位置
//  和手机的位置」。
//
//  为什么需要它：这一屏上「位置」一直只有一个 —— **车**的位置
//（`AppStore.currentLocation`，从车端报文来）。手机的位置从来没被取过。
//  而 iOS 地图右侧那两枚钮回答的是两个不同的问题：「车在哪」与「我在哪」；
//  少了第二个，地图就答不出「我离车多远」。
//
//  ── 2026-09-25 第 9 条：「手机的位置飘逸很严重，我选了精确定位，但是离我近 1 公里」 ──
//
//  三个原因叠在一起，每一个都能在代码里指出来：
//
//   ① **我们只要了百米精度**（`kCLLocationAccuracyHundredMeters`）。那一版头注写着
//      「百米精度足够回答我在哪、离车多远」—— 而「足够」是拿这句话当假设用的：
//      系统按这个请求只保证**百米级**，而百米级的点在系统心里可能只是
//      「一个基站 + 一个 WiFi 指纹」。用户在权限框上选的是**精确定位**，
//      我们自己却把精度降到了百米 —— 那一步是这一屏最贵的谎。
//   ② **第一个点直接用**（`locations.last` 拿来就 `stopUpdating`）。第一个点常常是
//      系统缓存的旧点（上次打开地图时留下的），它可能离你现在几百米到几公里。
//   ③ **没有精度门槛**：`horizontalAccuracy` 是 CoreLocation 自己给的「这个点有多准」，
//      而我们从来没读过它。iOS 地图的蓝点会随精度放大一圈，精度差时它自己就说明白了。
//
//  现在：要**最高精度**、**读 `horizontalAccuracy`**、**拿够准的点就停**，
//  并且把这个数**如实画出来**（蓝点外面那圈淡圆 = 不确定范围，见 `MapQuickButtons.phonePin`）。
//  拿不到够准的点时也照实说（`Status.coarse`），而不是把一个 1 公里外的点当地址用。
//
//  四条自我约束（每条都对应这个仓库吃过的一次亏）：
//    · **按需**：只在用户按了那枚钮之后才要权限、才开始定位 —— 权限要在用到的
//      那一刻要（HIG），启动就定位不是这个 App 该做的事。
//    · **取到就停**：按一次 = 把镜头移到手机那里一次。持续定位要
//      `allowsBackgroundLocationUpdates`（另一类权限、另一笔电池账），这里不需要。
//    · **如实**：权限被拒 / 取不到点 / 只拿到粗点都是**状态**，界面上要说得出来。
//    · **不猜**：没拿到点就是 `coordinate == nil`，不摆一个 (0,0)（那个坐标在
//      大西洋上，而地图会老老实实飞过去）。
final class PhoneLocation: NSObject, ObservableObject, CLLocationManagerDelegate {

    static let shared = PhoneLocation()

    enum Status: Equatable {
        /// 还没问过
        case idle
        /// 权限框已经弹出去了，等用户答
        case asking
        /// 用户拒绝 / 系统限制
        case denied
        /// 有权限，正在等第一个点
        case locating
        /// 已经拿到位置
        case found
        /// 拿到了点，但**精度不够**（比 `coarseLimit` 差）—— 照实标出来，
        /// 让用户知道「这个点大概在这一圈里」，而不是假装它准。
        case coarse
        /// 有权限但取不到（室内、飞行模式…）—— 与「被拒绝」是两件事
        case failed
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var coordinate: CLLocationCoordinate2D?
    /// CoreLocation 给的「这个点有多准」（米，95% 置信半径）。
    /// 它是**画在图上**的：蓝点外那圈淡圆的半径就是它 —— 这是 iOS 地图的做法，
    /// 也是我们这一屏唯一能如实表达「我有多确定」的方式。
    @Published private(set) var accuracy: CLLocationAccuracy?

    /// 画在**地图**上用的那个坐标（GCJ-02）。
    ///
    /// `coordinate` 是 CoreLocation 给的**原始读数**（WGS-84），而中国区的地图瓦片
    /// （高德，见地图右下角那个署名）用的是 GCJ-02 —— 两者差 300–600 m。
    /// 2026-09-25 用户报的「我的位置离车很近很近就 20 米左右，但是给我自己定位到
    /// 湖里面去了」就是这一条：手机那个点用原始坐标画出去，偏了约 600 m；
    /// 而车的坐标本来就是 GCJ-02（车端接口 `mapType=GCJ02`，见 `API-FIELD-MAP.md`），
    /// 所以整屏只有它一个是歪的。
    ///
    /// **画地图时才用它**（钉、镜头、误差圈）：距离、方位这类量用哪个坐标系都一样。
    /// 换算只有 `ChinaDatum` 一个出处（境外原样返回），别处不许自己再算一遍。
    var mapCoordinate: CLLocationCoordinate2D? {
        coordinate.map { ChinaDatum.gcj02(fromWGS84: $0) }
    }

    /// 够准的门槛（米）。比它差的点先留着当兜底，但继续等更好的。
    ///
    /// 35 是一个取舍：iPhone 在城市里拿到 5–20 m 是常态（用了 WiFi 指纹就更准），
    /// 而 35 m 已经足够回答「我在哪条街上、离车多远」。等不到时也不会卡死 ——
    /// `settleDeadline` 之后就用手里那个（并标成 `coarse`）。
    private static let goodAccuracy: CLLocationAccuracy = 35
    /// 超过这个精度就算「粗」（点还画，但状态是 `coarse`）。
    private static let coarseLimit: CLLocationAccuracy = 100
    /// 等多久就不再等更好的点（秒）。没有它，站在室内会一直「正在取手机的位置」。
    private static let settleDeadline: TimeInterval = 6

    private let manager = CLLocationManager()
    /// 兜底点（精度不够但可用）+ 它的精度 —— 超时之后就用它。
    private var fallback: CLLocation?
    /// 超时计时器的代号（同一手法见 `DSSwipeStrip.retractToken`：那种「到期前又发生了一次
    /// 就把上一次作废」的计时器都带一个代号）：一次新的请求会让上一次的等待作废。
    private var settleToken = 0

    private override init() {
        super.init()
        manager.delegate = self
        // 用户要的是「我到底在哪」——就按系统能给的最准的来。
        // 它只在用户在图上按了那枚钮之后才跑，取到点就停（见文件头第二、三条约束）。
        manager.desiredAccuracy = kCLLocationAccuracyBest
        // 位置在变时才回调：我们要的是「此刻的位置」，不是一条轨迹。
        manager.distanceFilter = kCLDistanceFilterNone
    }

    /// 按一下那枚钮：要权限 → 取一个点 → 停。
    /// 已经拿到过位置也重新走一趟（用户可能已经开出去一段了）。
    func request() {
        switch manager.authorizationStatus {
        case .notDetermined:
            status = .asking
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            status = .locating
            fallback = nil
            armSettleTimer()
            manager.startUpdatingLocation()
        case .denied, .restricted:
            status = .denied
        @unknown default:
            status = .denied
        }
    }

    // MARK: CLLocationManagerDelegate

    /// 用户在权限框上点了什么，只有**这里**知道（`request()` 那一刻只知道「问了」）。
    /// 答应之后接着把点取回来 —— 否则按一次要等下一次按才开始定位。
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            if status == .asking { request() }
        case .denied, .restricted:
            status = .denied
        case .notDetermined:
            break
        @unknown default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // ① 只留**有效**的点：`horizontalAccuracy < 0` 是 CoreLocation 自己文档里写的
        //    「这个点无效」的哨兵值（旧点 / 系统还在解算）。
        // ② 在有效的里面挑**最准**的一个：一批回调里常常混着缓存的旧点与新鲜的点。
        let valid = locations.filter { $0.horizontalAccuracy >= 0 }
        guard let best = valid.min(by: { $0.horizontalAccuracy < $1.horizontalAccuracy }) else { return }

        if best.horizontalAccuracy <= Self.goodAccuracy {
            accept(best)
            return
        }
        // 不够准：留住它当兜底，但继续等（不再「第一个点就用」—— 那正是漂移 1 公里的来源）。
        if fallback == nil || best.horizontalAccuracy < (fallback?.horizontalAccuracy ?? .greatestFiniteMagnitude) {
            fallback = best
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // 失败要分两种：拿到过点的人只是这一次没取到（旧点仍然可用），
        // 一次都没拿到才是「取不到」。
        status = coordinate == nil ? .failed : status
    }

    // MARK: 落点

    /// 采纳一个点：写坐标与精度、停更新、把状态说清楚。
    private func accept(_ location: CLLocation) {
        coordinate = location.coordinate
        accuracy = location.horizontalAccuracy
        // 精度不够就说不够（`coarse`），而不是把它当准的用 ——
        // 这个状态在 UI 上就是「蓝点外面那圈圆有多大」（见 `phonePin`）。
        status = location.horizontalAccuracy <= Self.coarseLimit ? .found : .coarse
        settleToken += 1              // 计时器作废
        manager.stopUpdatingLocation()  // 取到就停（见文件头第二条）
        fallback = nil
    }

    /// 等 `settleDeadline` 秒：到点了还在等，就用手里那个（并标成粗点）。
    /// 少了它，室内或信号差时那一枚钮会永远停在「正在取手机的位置」。
    private func armSettleTimer() {
        settleToken += 1
        let token = settleToken
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleDeadline) {
            guard token == self.settleToken, self.status == .locating else { return }
            if let f = self.fallback {
                self.accept(f)
            } else {
                // 一个点都没有：照实说取不到（而不是让钮一直转）。
                self.status = .failed
                self.manager.stopUpdatingLocation()
            }
        }
    }
}
