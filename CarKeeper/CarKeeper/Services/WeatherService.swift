import Foundation
import CoreLocation
import Combine

// =============================================================================
// WeatherService.swift — 天气实况：让「光」从晴空模型变成按云量折算的值
// =============================================================================
//
// 为什么需要它：`SkyLight` 算得出太阳在哪，但算不出**天上有多少云**。
// 阴天的正午和晴天的正午，太阳高度一样，光却差一大截 —— 没有云量，界面就只能
// 一直按「假设无云」画，而界面上必须照实写「晴空模型，不是实测」。
//
// 数据源：**Open-Meteo**（`api.open-meteo.com`），不用密钥、不用注册。
// 为什么不用苹果内置的 WeatherKit：
//   WeatherKit 需要 `com.apple.developer.weatherkit` entitlement，而本项目是
//   **未签名 / 侧载**构建（`project.yml` 里因此关掉了 CloudKit ——
//   无 entitlement 时构造 CKContainer 会抛 ObjC 异常直接杀进程）。
//   WeatherKit 受同一约束：拿不到 entitlement 就调不通。所以内置的用不了。
//
// 一件必须说清楚的事（隐私）：
//   车的位置会随这一次请求发给 Open-Meteo。缓解措施有三条，都在代码里：
//     ① 只发经纬度，**保留两位小数**（约 1.1 km 网格）—— 云量不需要比这更准；
//     ② 只发 HTTPS，只发这一个域名，不带任何车辆标识 / 账号 / 设备号；
//     ③ **不落盘**：快照只活在内存里，杀进程就没了。
//   隐私面板里有一条对应的披露（PrivacyDashboardView）。
//
// 失败时怎么办：**保持沉默但诚实** —— 快照留在 nil，界面回到晴空模型并写明
//「无天气数据」。绝不拿默认值冒充实况。
//
// 命名：顶层类型，不嵌套泛用名（历史事故见 ArtTheme.swift 的说明）。
// =============================================================================

// MARK: - WMO 天气码 → 中文
// 只有这几档；表里没有的一律照实显示「天气码 N」，不猜。
enum WMOWeather {
    static func text(_ code: Int) -> String? {
        switch code {
        case 0: return "晴"
        case 1: return "大致晴朗"
        case 2: return "局部多云"
        case 3: return "阴"
        case 45, 48: return "雾"
        case 51, 53, 55: return "毛毛雨"
        case 56, 57: return "冻毛毛雨"
        case 61, 63, 65: return "雨"
        case 66, 67: return "冻雨"
        case 71, 73, 75: return "雪"
        case 77: return "雪粒"
        case 80, 81, 82: return "阵雨"
        case 85, 86: return "阵雪"
        case 95: return "雷暴"
        case 96, 99: return "雷暴伴冰雹"
        default: return nil
        }
    }
}

// MARK: - 一份天气实况
/// 取数那一刻的天气。全部字段都是**服务端报的**，没有一处是本地推算的。
struct SkyWeather: Equatable {
    /// 云量 0…100（%）
    var cloudCover: Double
    /// 当前小时降水量（mm）
    var precipitation: Double
    /// 2 米气温（℃）
    var temperatureC: Double
    /// WMO 天气码
    var code: Int
    /// 取数时刻
    var fetchedAt: Date
    /// 取数用的位置（两位小数网格）—— 用来判断车是否已经走远
    var latitude: Double
    var longitude: Double

    /// 取数过了多少分钟
    func ageMinutes(at now: Date) -> Double { now.timeIntervalSince(fetchedAt) / 60 }

    /// 云量的说法：天上有多少云
    var cloudText: String { "\(Int(cloudCover.rounded()))%" }

    /// 降水一行：0 就说 0（不写成「无」——那是解释，不是数据）
    var precipitationText: String { String(format: "%.1f mm/h", precipitation) }

    var temperatureText: String { String(format: "%.1f ℃", temperatureC) }

    /// 天气码的说法；表里没有就照实说是个码
    var codeText: String { WMOWeather.text(code) ?? "天气码 \(code)" }

    /// 界面上引用这份数据时挂的尾巴：谁给的、什么时候取的
    func sourceText(at now: Date) -> String {
        "Open-Meteo 实况 · \(Int(ageMinutes(at: now).rounded())) 分钟前"
    }
}

// MARK: - 服务
/// 取一份天气实况。**有 TTL、有并发护栏、不落盘**。
@MainActor
final class WeatherService: ObservableObject {

    static let shared = WeatherService()

    enum Status: Equatable {
        case idle
        case loading
        case ok
        case failed(String)
    }

    /// 当前快照。nil = 没有天气数据（界面回到晴空模型并写明）。
    @Published private(set) var current: SkyWeather?
    @Published private(set) var status: Status = .idle

    // 下面三条与三个纯函数都标 `nonisolated`：常量与纯函数没有需要隔离的状态，
    // 而调用它们的地方（SkyLight 的纯计算、单元测试）本来就不在主线程上。
    // 不标的话 Swift 5 会给出「main actor-isolated ... from a nonisolated context」
    // 的警告（Swift 6 模式下直接是错误）。AppStore 里的两个键用的是同一写法。

    /// 多久重取一次（分钟）
    nonisolated static let refreshMinutes: Double = 15
    /// 车挪出这个距离就作废旧快照（米）
    nonisolated static let moveThresholdMeters: Double = 5_000
    /// 唯一会收到请求的域名
    nonisolated static let host = "api.open-meteo.com"

    private var inFlight = false
    private var lastAttempt: Date?

    private init() {}

    // -------------------------------------------------------------------------
    // MARK: 纯函数（可测）

    /// 请求 URL。经纬度**保留两位小数**（约 1.1 km）—— 云量不需要比这更准，
    /// 而精度的每一次增加都是隐私的每一次减少。
    nonisolated static func requestURL(latitude: Double, longitude: Double) -> URL? {
        let lat = (latitude * 100).rounded() / 100
        let lon = (longitude * 100).rounded() / 100
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = host
        comps.path = "/v1/forecast"
        comps.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.2f", lat)),
            URLQueryItem(name: "longitude", value: String(format: "%.2f", lon)),
            URLQueryItem(name: "current", value: "cloud_cover,precipitation,temperature_2m,weather_code"),
            URLQueryItem(name: "timezone", value: "UTC")
        ]
        return comps.url
    }

    /// 解析响应。字段缺一个就返回 nil —— **宁可不显示，也不显示一个编的数**。
    nonisolated static func parse(_ data: Data,
                                  latitude: Double,
                                  longitude: Double,
                                  at now: Date) -> SkyWeather? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cur = obj["current"] as? [String: Any] else { return nil }
        guard let cloud = (cur["cloud_cover"] as? NSNumber)?.doubleValue,
              let temp = (cur["temperature_2m"] as? NSNumber)?.doubleValue else { return nil }
        let precip = (cur["precipitation"] as? NSNumber)?.doubleValue ?? 0
        let code = (cur["weather_code"] as? NSNumber)?.intValue ?? -1
        return SkyWeather(cloudCover: min(max(cloud, 0), 100),
                          precipitation: max(0, precip),
                          temperatureC: temp,
                          code: code,
                          fetchedAt: now,
                          latitude: latitude,
                          longitude: longitude)
    }

    // -------------------------------------------------------------------------
    // MARK: 取数

    /// 需要时才取：TTL 内、且车没走远，就直接用现成的。
    func refreshIfNeeded(coordinate: CLLocationCoordinate2D, force: Bool = false) async {
        guard !inFlight else { return }
        let now = Date()
        if !force, let snapshot = current, let last = lastAttempt,
           now.timeIntervalSince(last) < Self.refreshMinutes * 60,
           Self.distanceMeters(from: snapshot, to: coordinate) < Self.moveThresholdMeters {
            return
        }
        await fetch(coordinate: coordinate, at: now)
    }

    /// 无条件取一次（下拉刷新用）。
    func refresh(coordinate: CLLocationCoordinate2D) async {
        guard !inFlight else { return }
        await fetch(coordinate: coordinate, at: Date())
    }

    private func fetch(coordinate: CLLocationCoordinate2D, at now: Date) async {
        inFlight = true
        status = .loading
        defer {
            inFlight = false
            lastAttempt = Date()
        }
        guard let url = Self.requestURL(latitude: coordinate.latitude,
                                        longitude: coordinate.longitude) else {
            status = .failed("坐标无效")
            return
        }
        do {
            var req = URLRequest(url: url)
            req.httpMethod = "GET"
            req.timeoutInterval = 20
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            guard http.statusCode == 200 else { throw URLError(.badServerResponse) }
            guard let parsed = Self.parse(data,
                                          latitude: coordinate.latitude,
                                          longitude: coordinate.longitude,
                                          at: Date()) else {
                status = .failed("响应里没有天气字段")
                return
            }
            current = parsed
            status = .ok
        } catch {
            // 失败**不改写已有快照**（15 分钟前的那份也比没有强），也不伪装成实况。
            status = .failed(error.localizedDescription)
        }
    }

    // -------------------------------------------------------------------------
    // MARK: 小工具

    nonisolated static func distanceMeters(from snapshot: SkyWeather,
                                           to coordinate: CLLocationCoordinate2D) -> Double {
        let a = CLLocation(latitude: snapshot.latitude, longitude: snapshot.longitude)
        let b = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return a.distance(from: b)
    }
}
