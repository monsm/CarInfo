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
//（`AppStore.currentLocation`，从车端报文来）。手机的位置从来没被取过：
//  全仓没有任何 CoreLocation 代码，`NSLocationWhenInUseUsageDescription` 写着
//  「用于显示车辆当前位置」—— 而车的位置是**服务端**给的，那句话其实一直对不上。
//  而 iOS 地图右侧那两枚钮回答的是两个不同的问题：「车在哪」与「我在哪」；
//  少了第二个，地图就答不出「我离车多远」。
//
//  四条自我约束（每条都对应这个仓库吃过的一次亏）：
//    · **按需**：只在用户按了那枚钮之后才要权限、才开始定位 —— 权限要在用到的
//      那一刻要（HIG），启动就定位不是这个 App 该做的事。
//    · **取到就停**：按一次 = 把镜头移到手机那里一次。持续定位要
//      `allowsBackgroundLocationUpdates`（另一类权限、另一笔电池账），这里不需要。
//    · **如实**：权限被拒 / 取不到点都是**状态**，界面上要说得出来 ——
//      上一轮删掉的那批「按了什么都不发生」的按钮就是这么长出来的。
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
        /// 有权限但取不到（室内、飞行模式…）—— 与「被拒绝」是两件事
        case failed
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var coordinate: CLLocationCoordinate2D?

    private let manager = CLLocationManager()

    private override init() {
        super.init()
        manager.delegate = self
        // 百米精度足够回答「我在哪、离车多远」，比最高精度省电得多 ——
        // 这个按钮要的不是导航级定位。
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
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
        guard let last = locations.last else { return }
        coordinate = last.coordinate
        status = .found
        // 取到就停（见文件第二条）：这一次请求的任务已经完成。
        manager.stopUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // 失败要分两种：拿到过点的人只是这一次没取到（旧点仍然可用），
        // 一次都没拿到才是「取不到」。
        status = coordinate == nil ? .failed : .found
    }
}
