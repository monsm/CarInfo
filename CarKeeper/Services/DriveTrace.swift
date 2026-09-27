import SwiftUI
import CoreLocation

// =============================================================================
//  DriveTrace —— 「这一趟开过的路」（用户 2026-09-26）
// =============================================================================
//
//  用户原话：「车动起来后在地图页画出行驶轨迹（加个模拟测试的，我试试），
//  直至车辆熄火」。
//
//  为什么需要一个新的服务：全仓此前**没有**任何轨迹点。`TripRecord` 只有起终点
//  两个坐标（车端 `isPrivacyDrvingHistory: 1`，不上传行驶历史），所以行程卡里
//  那条线一直是「起终点连线」。而“现在这一趟”的轨迹不需要车端给 —— 我们自己
//  每次收到定位就落一个点，那就是真走过的路。
//
//  三个边界，每一个都对着用户那句话里的一个词：
//    · 「车动起来后」—— 车停着不动时不落点（一次刷新同一个坐标，落进去的就是
//      一堆重合的点；距离门槛见 `minStep`，5.5 米是秒级抖动的量级，与
//      `AppStore` 那条「动了才喊」的门槛同一个数）。
//    · 「直至车辆熄火」—— 熄火（`FLAMEOUT` 事件）之后这一段就**封口**：
//      点不再增加，图上的线留着（直到下一次点火把它清成新的一段）。
//    · 「加个模拟测试的」—— **已于 2026-09-26 删除**（用户：「删除刷新调试和模拟
//      轨迹调试」）。它当时沿车当前位置画一条蛇形的假轨迹，好让人不用真开一段
//      就能看一眼轨迹长什么样；那一次试用结束之后，它就是一段没人再走的代码
//      （`simulate` / `setSimulate` / `simulated` 与那个 Task 一起删）。
//
//  ⚠️ 落点的地方只有**一处**：`AppStore.saveCache` 里那条定位通知的同一个点上。
//  与 `.locationUpdated` 一样 —— 「车的位置只从那里进来」（那条通知的头注写着
//  同一件事：此前它有三个观察者却一个发射点都没有）。
//
//  ⚠️ 它是 `ObservableObject` 而不是往 `AppStore` 里塞一个数组：轨迹变化的节奏
//  与车况完全不同（每个定位一个点 vs 车在动时每 1 秒一份报文），而且地图那一屏**必须
//  订阅它**才会重画（`MapSpineView.trace`）—— 订阅一个专门的单例，比让整棵树
//  跟着车况变要小得多。
// =============================================================================
@MainActor
final class DriveTrace: ObservableObject {
    static let shared = DriveTrace()

    /// 这一段的点（地理坐标，按时间顺序）。空 = 还没有轨迹。
    @Published private(set) var points: [CLLocationCoordinate2D] = []
    /// 这一段还在长吗（点火之后、熄火之前）。
    @Published private(set) var active = false

    /// 两个点至少要隔这么远才落第二个：GPS 抖动与停车都在这个门槛下。
    ///  5.5 米 = `AppStore` 那条「动了才喊」的门槛（≈5.5 米）—— 同一个量级，
    ///  但不是同一个数：那一个是「镜头要不要跟」，这一个是「轨迹要不要多一个点」。
    private let minStep: Double = 8
    /// 点数的上限。按 8 米一个点算，2000 点 ≈ 16 km —— 一趟够用，
    /// 而再多就只是把一条线越画越重（内存与渲染都是）。
    private let maxPoints = 2_000

    private init() {}

    // MARK: - 一段的开始与结束

    /// 点火：新的一段从**空**开始（上一趟的轨迹就此消失，用户那句话的「直至熄火」
    /// 说的是“这一段”，不是“这一整天”）。
    func begin() {
        points = []
        active = true
    }

    /// 熄火：封口。点**不清**（图上的线留着），只是不再增加。
    func end() {
        active = false
    }

    /// 车端的一次定位（`AppStore.saveCache` 调）。
    ///
    ///  没点过火但车在动时，它自己开一段：点火事件是**事后**才从消息流里读到的
    ///  （用户打开 App 时车可能已经开出去一段了），而轨迹不该等那一条事件。
    func ingest(_ coordinate: CLLocationCoordinate2D, moving: Bool) {
        if !active {
            guard moving else { return }
            points = []
            active = true
        }
        append(coordinate)
    }

    private func append(_ coordinate: CLLocationCoordinate2D) {
        if let last = points.last {
            let a = CLLocation(latitude: last.latitude, longitude: last.longitude)
            let b = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            guard a.distance(from: b) >= minStep else { return }
        }
        points.append(coordinate)
        if points.count > maxPoints {
            points.removeFirst(points.count - maxPoints)
        }
    }

    //  「模拟（调试）」那一整段曾在这里：`simulate` 开关、`setSimulate(_:)` 与那条
    //  每 1.5 秒多落一个点（向北走、东西按 `sin` 摆）的 Task。
    //  用户 2026-09-26：「删除刷新调试和模拟轨迹调试」—— 整段删掉，
    //  连同它的入口（地图图层菜单里那一项）。理由与头注里那条一样：
    //  一个只在调试时才有的开关，试用结束之后就是一段没人再走的代码。
}
