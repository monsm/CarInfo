// =============================================================================
//  RouteService —— 两点之间的**道路路线**（不是直线）
// =============================================================================
//
//  用户 2026-09-25 第 1 条：「行程卡片起点终点图标不容易区分，且是俩点直线距离，
//  可否根据道路模拟下路线…」—— 这份文件只回答中间那一问：把直线换成**沿着路走的那条线**。
//
//  ── 第一版用的是 `MKDirections`，它被本仓的门禁当场拦下 ──
//  写这一轮的时候先写的 MapKit 路线（`MKDirections` + `MKRoute.polyline`），
//  `scan/paidcap.py` 立刻报红，而它的依据是 Apple 自己的话：
//
//    非 ADP 成员（也就是本项目用的免费账号）可以用 MapKit，**但不能提供路线导航**。
//    （`scan/paidcap.py` 头注引的就是 Apple《Supported capabilities (iOS)》那一页）
//
//  这不是「门禁太严」：那一段代码在付费账号下能跑，在**这个 App 的账号下不行** ——
//  而它在模拟器/真机上可能只是安静地失败，看起来像网络问题。所以它必须走。
//  同一份文件里还有一条本仓的先例：天气原来用 WeatherKit（付费），
//  后来换成 Open-Meteo（免密钥）—— 这里用的是同一条路数。
//
//  ── 现在用的是 OSRM 的公共演示服务（免密钥、不需要账号）──
//    GET https://router.project-osrm.org/route/v1/driving/{lon},{lat};{lon},{lat}
//        ?overview=simplified&geometries=geojson
//  实测（2026-09-25，杭州 → 上海）：HTTP 200、1.1 KB、4.4 秒，返回 GeoJSON 线串与
//  它自己的 `distance`（米）。`overview=simplified` 是关键：这条线要画在 132pt 高的
//  小地图上，全精度点串（几千个点）在这里没有意义 —— 换成路网的主干形状就够。
//
//  ── 为什么请求前后都要换算坐标（这一条最容易被忽略）──
//  行程坐标来自车端接口（`mapType=GCJ02`），而 OSRM 吃的是**WGS-84**。
//  直接把 GCJ-02 发过去，它会拿一个偏移 300–600 m 的点去求路 —— 出来的线
//  与地图瓦片对不上（线在北边、钉在南边）。所以：
//    · 发请求前：`ChinaDatum.wgs84(fromGCJ02:)` 把两个端点还原成真实经纬度；
//    · 拿到点串后：`ChinaDatum.gcj02(fromWGS84:)` 逐点换回来（瓦片是 GCJ-02）。
//  这正是 `ChinaDatum` 头注里写的「反向换算也写了用途」那一件事 —— 它在这里第一次被用上。
//  境外两点则两边都原样返回（`ChinaDatum` 自己判），所以海外行程不会因此变形。
//
//  ── 已知边界（写在这里，免得下一个人以为是 bug）──
//    · **这是演示服务器**，没有 SLA、有速率限制，也可能被墙/变慢。
//      取不到就是 `nil`，调用点画直线并在卡片上写明「线是两点连线」（见 `MiniTripMap`）。
//    · 它给的是**此刻**的道路走法，不是车当时开的那条路。同样的起终点，
//      早晚高峰的推荐路线可以不同 —— 所以它叫「路线」，不叫「轨迹」。
//    · 它不做导航（没有转向指令），我们也不要：要的只是一条线上图的形状。
//    · 本机没有 iOS 运行时，**这条链路只有真机能验**（返回形状对着真实响应核过）。
// =============================================================================

import Foundation
import CoreLocation

@MainActor
final class RouteService: ObservableObject {
    static let shared = RouteService()

    /// 一条路线：点串（**已经是 GCJ-02，能直接画在中国的瓦片上**）+ 它自己的长度（米）。
    /// 长度用服务给的（不是把点串加起来）—— 那是两回事。
    struct Route {
        let points: [CLLocationCoordinate2D]
        let distanceMeters: Double
    }

    /// 免密钥的路线服务。写在这里而不是散在函数里：它是这套功能唯一的外部依赖
    ///（与 `WallpaperService` 那两个取图口同一种写法）。
    private static let base = "https://router.project-osrm.org/route/v1/driving/"

    /// 同一对坐标只问一次。键是取到 5 位小数（≈1 米）的**输入**坐标 ——
    /// 行程是从 GPS 配出来的，同一段路在两次求值里小数位可能差一点，而它们是同一个地方。
    private var cache: [String: Route] = [:]
    /// 正在飞的请求。没有它，「同一张卡在不同图层被同时求值」会发两个一样的请求。
    private var inflight: [String: Task<Route?, Never>] = [:]
    /// 缓存里刚多了一条 —— 卡片背面那一行「路线长度」靠它出现（见 `revision` 的读者）。
    @Published private(set) var revision: Int = 0

    private init() {}

    /// 取一条路线。取不到返回 `nil`（调用点画直线）。
    func route(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) async -> Route? {
        let key = Self.key(a, b)
        if let hit = cache[key] { return hit }
        if let flying = inflight[key] { return await flying.value }
        let task = Task<Route?, Never> { await Self.fetch(a, b) }
        inflight[key] = task
        let out = await task.value
        inflight[key] = nil
        if let out {
            cache[key] = out
            revision += 1
        }
        return out
    }

    /// 缓存里有没有（同步问一问：行程卡背面据此决定摆不摆「路线长度」那一行）。
    func cached(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Route? {
        cache[Self.key(a, b)]
    }

    // MARK: - 真正去问的那一次

    private static func fetch(_ a: CLLocationCoordinate2D,
                              _ b: CLLocationCoordinate2D) async -> Route? {
        // 端点先还原成 WGS-84（OSRM 的口径），见文件头注。
        let wa = ChinaDatum.wgs84(fromGCJ02: a)
        let wb = ChinaDatum.wgs84(fromGCJ02: b)
        // OSRM 的路径是 `{经度},{纬度}`（与「纬度在前」的习惯相反），这一行写错
        // 就会得到一个在另一个半球的点 —— 服务会回一个 `NoRoute`，而那时人只会
        // 以为“这条路线取不到”。
        let path = String(format: "%.6f,%.6f;%.6f,%.6f",
                          wa.longitude, wa.latitude, wb.longitude, wb.latitude)
        guard let url = URL(string: base + path
                            + "?overview=simplified&geometries=geojson&steps=false") else {
            return nil
        }
        var req = URLRequest(url: url)
        // 实测这一次是 4.4 秒（境内网络到这台演示服务器会更快或更慢）。
        // 20 秒是「慢但能成」与「别让卡片一直等」之间的取舍 —— 超时就退回直线。
        req.timeoutInterval = 20
        req.setValue("CarKeeper/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            return nil
        }
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let routes = obj["routes"] as? [[String: Any]],
              let first = routes.first,
              let geometry = first["geometry"] as? [String: Any],
              let coords = geometry["coordinates"] as? [[Double]] else {
            return nil
        }
        // `coordinates` 是 `[经度, 纬度]` 的数组（GeoJSON 的顺序）。
        var points: [CLLocationCoordinate2D] = []
        points.reserveCapacity(coords.count)
        for pair in coords {
            guard pair.count >= 2 else { continue }
            let wgs = CLLocationCoordinate2D(latitude: pair[1], longitude: pair[0])
            points.append(ChinaDatum.gcj02(fromWGS84: wgs))
        }
        // 少于两个点画不出线 —— 当成没取到（调用点会画直线，并且自己会说明）。
        guard points.count > 1 else { return nil }
        return Route(points: points,
                     distanceMeters: (first["distance"] as? Double) ?? 0)
    }

    /// 缓存 / 合流用的键。5 位小数 ≈ 1 米 —— 比 GPS 的抖动小一个量级。
    private static func key(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> String {
        String(format: "%.5f,%.5f>%.5f,%.5f", a.latitude, a.longitude, b.latitude, b.longitude)
    }
}
