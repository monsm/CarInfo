import Foundation
import CoreLocation

// =============================================================================
//  ChinaDatum —— 中国大陆的两套坐标：WGS-84（真实）与 GCJ-02（地图上那份）
// =============================================================================
//
//  为什么这个 App 需要它（用户 2026-09-25 原话）：
//    「我的位置离车很近很近就 20 米左右，但是给我自己定位到湖里面去了！」
//
//  这不是定位不准，是**两套坐标**：那个点自称精度 ≤20 m（所以图上连误差圈都不画），
//  却落在 600 m 外的水面上 —— 一个「自信且错」的读数，只有系统性偏移做得到。
//
//  两边的来源不同（这是根因）：
//    · **手机**：`CLLocationManager` 给的是 **WGS-84**（GPS 原始值）。
//      Apple 自己的蓝点不偏，是因为它内部替我们换了 —— 而第三方 App 拿到的
//      还是原始值。iOS 文档与国内开发者文档都这么写：把 WGS-84 直接打在
//      中国区地图上就会偏 300–600 m。
//    · **车**：车端接口 `/cardata/getCarLocation?mapType=GCJ02` —— **已经声明是 GCJ-02**
//      （见 `API-FIELD-MAP.md`：`lng` 那一行、「坐标系 `GCJ02`」）。所以车钉是对的。
//    · **地图瓦片**：中国区由高德提供（地图右下角就写着「高德地图」），GCJ-02。
//
//  于是只有**自己那个点**是歪的 —— 与用户看到的现象一致（车钉在小区里、蓝点在湖里）。
//
//  这一对函数做的是那件事的**唯一出口**：`PhoneLocation.mapCoordinate` 调它，
//  别处不许自己再来一遍（这个仓库对「同一件事有两个出处」零容忍）。
//
//  域外原样返回：这两套坐标在中国境外是同一套，公式在境外用会把点推到几百米外 ——
//  所以 `outOfChina` 那道判断不是优化，是正确性的一部分。
//
//  它是**公开的近似算法**（GCJ-02 没有官方实现）：克拉索夫斯基椭球 + 两组
//  三角函数级数。这里逐项照抄那份被广泛实现的形式，本机没有编译器也不改写它 ——
//  **错的换算比不换算更糟**（用户会看到一个「动过手脚」的点，而它仍然不对）。
// =============================================================================
enum ChinaDatum {

    /// 从 GPS 原始坐标（WGS-84）换成中国区地图坐标（GCJ-02）。境外原样返回。
    static func gcj02(fromWGS84 c: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        guard !outOfChina(c) else { return c }
        let d = delta(lat: c.latitude, lon: c.longitude)
        return CLLocationCoordinate2D(latitude: c.latitude + d.dLat,
                                      longitude: c.longitude + d.dLon)
    }

    /// 反过来：把地图上的坐标（GCJ-02）换成 GPS 原始坐标（WGS-84）。境外原样返回。
    ///
    /// 这个方向**没有闭式解**（级数只在正方向成立），所以用迭代：先按正解的偏移反推
    /// 一个初值，再回代两三次 —— 误差很快就掉到亚米级（远小于 GPS 自己的精度）。
    /// 它现在没有读者（画在图上只需要正方向），但**留着**：拿到车端 GCJ-02 的坐标
    /// 想把手机那个点算成「离车多远」以外的地理量时，方向必须是这个 ——
    /// 而且 `scan/orphans.py` 只盖系统类型的扩展成员，看不见它，
    /// 所以这里写明它的用途，免得下一个人以为它是死代码。
    static func wgs84(fromGCJ02 c: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        guard !outOfChina(c) else { return c }
        var guess = CLLocationCoordinate2D(
            latitude: c.latitude - delta(lat: c.latitude, lon: c.longitude).dLat,
            longitude: c.longitude - delta(lat: c.latitude, lon: c.longitude).dLon)
        for _ in 0..<3 {
            let d = delta(lat: guess.latitude, lon: guess.longitude)
            let next = CLLocationCoordinate2D(latitude: c.latitude - d.dLat,
                                              longitude: c.longitude - d.dLon)
            if next.latitude == guess.latitude && next.longitude == guess.longitude { break }
            guess = next
        }
        return guess
    }

    // MARK: 内部 —— 公式本体

    /// 克拉索夫斯基椭球长半轴（米）
    private static let axis = 6_378_245.0
    /// 偏心率平方
    private static let eccentricity = 0.006_693_421_622_965_943

    private static func outOfChina(_ c: CLLocationCoordinate2D) -> Bool {
        if c.longitude < 72.004 || c.longitude > 137.8347 { return true }
        if c.latitude < 0.8293 || c.latitude > 55.8271 { return true }
        return false
    }

    private static func delta(lat: Double, lon: Double) -> (dLat: Double, dLon: Double) {
        var dLat = transformLat(lon - 105.0, lat - 35.0)
        var dLon = transformLon(lon - 105.0, lat - 35.0)
        let radLat = lat / 180.0 * Double.pi
        var magic = sin(radLat)
        magic = 1 - eccentricity * magic * magic
        let sqrtMagic = sqrt(magic)
        dLat = (dLat * 180.0) / ((axis * (1 - eccentricity)) / (magic * sqrtMagic) * Double.pi)
        dLon = (dLon * 180.0) / (axis / sqrtMagic * cos(radLat) * Double.pi)
        return (dLat, dLon)
    }

    private static func transformLat(_ x: Double, _ y: Double) -> Double {
        var ret = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * sqrt(abs(x))
        ret += (20.0 * sin(6.0 * x * Double.pi) + 20.0 * sin(2.0 * x * Double.pi)) * 2.0 / 3.0
        ret += (20.0 * sin(y * Double.pi) + 40.0 * sin(y / 3.0 * Double.pi)) * 2.0 / 3.0
        ret += (160.0 * sin(y / 12.0 * Double.pi) + 320.0 * sin(y * Double.pi / 30.0)) * 2.0 / 3.0
        return ret
    }

    private static func transformLon(_ x: Double, _ y: Double) -> Double {
        var ret = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * sqrt(abs(x))
        ret += (20.0 * sin(6.0 * x * Double.pi) + 20.0 * sin(2.0 * x * Double.pi)) * 2.0 / 3.0
        ret += (20.0 * sin(x * Double.pi) + 40.0 * sin(x / 3.0 * Double.pi)) * 2.0 / 3.0
        ret += (150.0 * sin(x / 12.0 * Double.pi) + 300.0 * sin(x / 30.0 * Double.pi)) * 2.0 / 3.0
        return ret
    }
}
