import SwiftUI
import CoreLocation
import MapKit

// =============================================================================
//  MapCameraFollow —— 镜头跟谁、跟到什么位置（纯函数，一个状态都不存）
// =============================================================================
//
//  用户 2026-09-26（这一件是他点名要的）：
//    「地图页要随着车的方向实时改变地图朝向，且如果选了车的定位，车永远居中在地图
//      顶部到底部抽屉之间居中，如果是选了人的位置也同样的逻辑显示，且车在运动的时候
//      车永远是优先于人的位置显示，地图要永远跟着车一起刷新到车的位置显示」。
//
//  这四句话拆成四件可判的事：
//    ① **朝向随车**：车在动时镜头 `heading` = 车头朝向（`MapFollowTarget` 那一侧的
//      `heading` 参数），停着时回正北（`0`）。为什么停着要回正北：停着时地图转着没有任何
//      参照物能解释它为什么转，而北向上的地图是每个人认路的那一张。
//    ② **车居中在「顶 → 抽屉」那一段里**：镜头中心因此要比车**偏后**一点
//      （见 `bandCenter` 与 `spanFactor`）—— 直接 `centerCoordinate = 车` 会把车钉在
//      **整屏**正中，而那正是被抽屉压住的那一半的开始。
//    ③ **选了人的位置也走同一套**：偏移与俯仰一模一样，只有「跟谁」不同
//      （所以这两个按钮调的是同一个函数，不是一个正北镜头 + 一个别样的镜头）。
//    ④ **车优先**：车在动时一律跟车，即使用户刚选了手机（判断在 `MapSpineView` 里，
//      因为「车在不在动」是那里的输入）。
//
//  ⚠️ 为什么是**纯函数**而不是往 `MapSpineView` 里再写几行：那个文件在 1200 行的阈值上
//  （`scan/lintcfg.py`），而「镜头该落在哪儿」本来就不需要知道任何视图状态 ——
//  四个输入进去、一个 `MapCameraPosition` 出来。顺带它成了这一屏**唯一**能读懂镜头
//  的地方：此前三处（回到车 / 移到手机 / 点充电站聚合点）各写一遍 `MapCamera(…)`，
//  三处的距离与俯仰靠「记得写一样」来保证一致。
//
//  ⚠️ 唯一的估算量：`spanFactor`（一屏纵向覆盖多少米 ÷ 镜头距离）。它随俯仰角变，
//  而 Apple 没有给「这个距离下屏幕上有多少米」这个数。所以它是**一根回退线**：
//  真机上若觉得车钉偏高或偏低，改的只有这一个数（0.5 → 车钉正好在正中）。
// =============================================================================

// =============================================================================
//  这个文件里是**镜头这一件事的全部**：一个纯函数（上面）+ 两个把镜头移过去的动作
//  （下面的 `extension`）。
//
//  ⚠️ 后两个 2026-09-26 从 `MapSpineView.swift` 搬来：那个文件当时 1231 行，
//  越过了 `lintcfg.py` 的 1200 阈值 —— 按那个阈值的用法是**把一件事搬出去**
//  （不是加排除清单、也不是抬阈值到刚够）。搬的正是「镜头」：
//  在此之前「镜头落在哪儿」与「什么时候去移它」分在两个文件里，
//  而它们是同一个决定的两半 —— 比如「车在动时地图要跟着转」必须两处都写对才成立。
//  界面一字未改。
//
//  ⚠️ 跨文件要读 `didCenterOnce`，所以那个 `@State` 在 MapSpineView 里放开了 `private`
//  （`extguard.py` 会拦下扩展碰别的文件的私有成员 —— 这是本仓反复栽的那个坑）。
// =============================================================================

/// 镜头跟谁。用户按的是地图右侧那两枚钮（「回到车」/「手机的位置」）。
enum MapFollowTarget: String, CaseIterable, Identifiable {
    case car
    case phone

    var id: String { rawValue }

    var title: String {
        switch self {
        case .car: return "车"
        case .phone: return "手机"
        }
    }
}

/// 「镜头该落在哪儿」—— 一个坐标 + 朝向 + 距离 + 俯仰，进去出 `MapCameraPosition`。
enum MapCameraFollow {

    /// 目标要落在屏幕纵向的哪个位置（0 = 顶，1 = 底）。
    ///
    /// 0.38 = 「地图顶 → 底部抽屉上沿」那一条带子的正中：抽屉占掉下面大约 40%，
    /// 于是可见带的中心在屏幕的 38% 处（`MapSpineView.barTotal` = 94pt 是**底条**，
    /// 抽屉拉到一半时还要更高一些 —— 取 0.38 是这两者之间的那个位置）。
    /// 它与 `spanFactor` 一起把「车钉居中在带子里」这句原话变成一个数。
    static let bandCenter: Double = 0.38

    /// 一屏的纵向覆盖（米）÷ 镜头距离。65° 俯仰下的经验值；
    /// **这是这一组里唯一需要用真机校一次的数**（改大 = 车钉更靠上）。
    static let spanFactor: Double = 1.55

    /// 每度纬度多少米（够用即可：这是镜头取景，不是测距）。
    private static let metresPerDegree: Double = 111_320

    /// 一个目标点的取景。
    ///
    /// - Parameters:
    ///   - coordinate: 要居中的点（车或手机 —— 换算成 GCJ-02 的那个，见 `ChinaDatum`）。
    ///   - heading: 镜头朝向（度，0 = 正北）。车在动时传车头朝向，否则传 0。
    ///   - distance: 镜头距离（米）。
    ///   - pitch: 俯仰角（度）。
    /// - Returns: 镜头位置；`nil` = 没有这个点（**不摆一个假坐标**）。
    static func camera(on coordinate: CLLocationCoordinate2D?,
                       heading: Double,
                       distance: Double,
                       pitch: Double) -> MapCameraPosition? {
        guard let c = coordinate else { return nil }
        // 偏移的方向是**目标背后**（屏幕下方），而不是「正南」：地图按航向转起来之后，
        // 「屏幕下沿」在经纬度上已经不是南了 —— 不跟着转的话车会随着航向绕到屏幕别处去
        //（这正是①与②必须放在同一个函数里的原因）。
        let back = (heading + 180) * .pi / 180
        let shift = (0.5 - bandCenter) * distance * spanFactor
        let dLat = shift * cos(back) / metresPerDegree
        // 经度上一度比纬度短（按当前纬度收缩）；极区那一下用 0.2 兜底防除零。
        let shrink = max(0.2, cos(c.latitude * .pi / 180))
        let dLng = shift * sin(back) / (metresPerDegree * shrink)
        // 中心 = 目标点 **沿「背后」那个方向** 推出去一段（航向 0 时就是向南推，
        // 于是车出现在屏幕中心之上 —— 而带子的中心正在那里）。
        let center = CLLocationCoordinate2D(latitude: c.latitude + dLat,
                                           longitude: c.longitude + dLng)
        return .camera(MapCamera(centerCoordinate: center,
                                 distance: distance,
                                 heading: heading,
                                 pitch: pitch))
    }
}

extension MapSpineView {

    /// 把相机移到车上（用户 2026-09-26：「地图要永远跟着车一起刷新到车的位置显示」）。
    ///
    /// 镜头落在**哪儿**全部由 `MapCameraFollow.camera(on:…)` 算（朝向随车、车钉落在
    /// 「地图顶 → 底部抽屉」那一段的正中）—— 这里只负责三件事：跟谁、要不要跟、挂上动画。
    ///
    /// **要不要跟**（`didCenterOnce`）：镜头被别的事移开过（比如点了一条事件的
    /// 「在图上看看」）就不再抢回来 —— 那一下是用户刚点的。但**车一动就一定抢回来**
    /// （用户：「车在运动的时候车永远是优先于人的位置显示」）：那一刻地图要回答的是
    /// 「车在哪儿」，而人刚才是去看某个位置的。
    ///
    /// **不是 `private`**：右侧那枚「回到车」在 `MapQuickButtons.swift` 里。
    @MainActor
    func centerOnCar(force: Bool) {
        guard let c = store.currentLocation?.coordinate else { return }
        if didCenterOnce && !force && !store.isCarMoving { return }
        didCenterOnce = true
        // 朝向：车在动时是**车头朝向**（地图跟着车转，用户第一条要求），
        // 停着时回正北 —— 停着的地图转起来没有任何参照物解释它为什么转。
        let heading = store.isCarMoving ? store.carHeadingDeg : 0
        guard let pos = MapCameraFollow.camera(on: c, heading: heading,
                                               distance: cameraDistance,
                                               pitch: cameraPitch) else { return }
        withAnimation(TokensMotion.value) { camera = pos }
    }
}
