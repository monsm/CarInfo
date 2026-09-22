// =============================================================================
// PureLogicTests.swift — 纯函数的测试
// =============================================================================
//
// 为什么只测这几样：它们是**纯函数**，错了不会崩、也不会有编译错误，
// 只会安静地给出错的光和错的圈 —— 那正是这类错最难被看见的原因。
//
// 这里的期望值不是「把实现抄一遍」（抄一遍只能证明它没被改过），
// 而是**可独立核对的天文与几何事实**：
//   • 夏至/冬至正午的太阳高度 = 90 − |纬度 − 赤纬|
//   • 极圈以北的仲夏夜太阳不落、冬至正午太阳在地平线下
//   • 相距 111m 的两站必然并成一组、相距 1.1km 的必然分开
//
// 运行方式（本机没有 Swift 工具链，所以只在 CI 上跑）：
//   cd CarKeeper && xcodegen generate && xcodebuild test -scheme CarKeeper \
//       -destination 'platform=iOS Simulator,name=iPhone 17'
// =============================================================================
import XCTest
import Foundation
import CoreLocation
@testable import CarKeeper

// MARK: - 光：太阳位置

final class SkyLightTests: XCTestCase {

    /// 北京（北纬 40.0°）—— 用整纬度，期望值才可以直接手算
    private let beijing = CLLocationCoordinate2D(latitude: 40.0, longitude: 116.4)

    private func utc(_ s: String) -> Date {
        ISO8601DateFormatter().date(from: s)!
    }

    /// 夏至正午：太阳高度 ≈ 90 − (40 − 23.44) = 73.44°
    /// 正午前后高度角是驻定的（一阶导为 0），所以经度时差与均时差的影响可忽略。
    func testJuneSolsticeNoonAltitude() {
        let light = SkyLight.now(at: utc("2026-06-21T04:00:00Z"), coordinate: beijing)
        XCTAssertEqual(light.altitude, 73.44, accuracy: 1.2)
    }

    /// 冬至正午：太阳高度 ≈ 90 − (40 + 23.44) = 26.56°
    func testDecemberSolsticeNoonAltitude() {
        let light = SkyLight.now(at: utc("2026-12-21T04:00:00Z"), coordinate: beijing)
        XCTAssertEqual(light.altitude, 26.56, accuracy: 1.2)
    }

    /// 当地午夜（北京时间 00:00 = 前一日 16:00Z）：没有太阳、没有辐照度、车灯全开
    func testLocalMidnightIsDark() {
        let light = SkyLight.now(at: utc("2026-06-21T16:00:00Z"), coordinate: beijing)
        XCTAssertLessThan(light.altitude, 0)
        XCTAssertEqual(light.clearSky, 0, accuracy: 0.001)
        XCTAssertFalse(light.isDaylight)
        XCTAssertEqual(light.lamp, 1.0, accuracy: 0.001)
    }

    /// 「日光模式」的判据必须与界面上写的那句话一致：辐照度 > 150 W/m² 即日光。
    /// 这句话印在「光」表里 —— 那么它就得真的是那条规则。
    func testDaylightThresholdMatchesTheDocumentedRule() {
        for hour in 0..<24 {
            let light = SkyLight.now(at: utc(String(format: "2026-03-20T%02d:00:00Z", hour)),
                                     coordinate: beijing)
            XCTAssertEqual(light.isDaylight, light.clearSky >= 150,
                           "小时 \(hour)：isDaylight 与 150 W/m² 的规则不一致")
        }
    }

    /// 一年里每小时一次的范围检查：越界的值会画出画不出来的光
    func testRangesHoldThroughTheWholeYear() {
        for day in stride(from: 0, to: 365, by: 3) {
            for hour in stride(from: 0, to: 24, by: 3) {
                let t = utc("2026-01-01T00:00:00Z").addingTimeInterval(Double(day * 24 + hour) * 3600)
                let light = SkyLight.now(at: t, coordinate: beijing)
                XCTAssertTrue((-90...90).contains(light.altitude), "高度角 \(light.altitude)")
                XCTAssertTrue((0..<360).contains(light.azimuth), "方位角 \(light.azimuth)")
                XCTAssertGreaterThanOrEqual(light.clearSky, 0)
                XCTAssertTrue((0...1).contains(light.lamp), "车灯 \(light.lamp)")
                XCTAssertTrue((-1...1).contains(light.warmth), "色温 \(light.warmth)")
                XCTAssertTrue((-1...1).contains(light.dirX))
                XCTAssertTrue((-1...1).contains(light.dirY))
            }
        }
    }

    /// 北极圈以北的仲夏夜：太阳**不落**（朗伊尔城当地午夜 ≈ 前一日 22:00Z）
    func testMidnightSunAboveTheArcticCircle() {
        let svalbard = CLLocationCoordinate2D(latitude: 78.2, longitude: 15.6)
        let light = SkyLight.now(at: utc("2026-06-21T22:00:00Z"), coordinate: svalbard)
        XCTAssertGreaterThan(light.altitude, 0)
    }

    /// 冬至的 Svalbard：正午太阳也在地平线下（≈ −11.6°）
    func testPolarNightInDecember() {
        let svalbard = CLLocationCoordinate2D(latitude: 78.2, longitude: 15.6)
        let light = SkyLight.now(at: utc("2026-12-21T11:00:00Z"), coordinate: svalbard)
        XCTAssertLessThan(light.altitude, 0)
        XCTAssertFalse(light.isDaylight)
        XCTAssertEqual(light.lamp, 1.0, accuracy: 0.001)
    }

    /// 光池的方向由方位角决定：同一天早晚，方向必须相反
    func testLightComesFromOppositeSidesMorningAndEvening() {
        let morning = SkyLight.now(at: utc("2026-03-20T23:30:00Z"), coordinate: beijing)  // 07:30 北京
        let evening = SkyLight.now(at: utc("2026-03-20T09:30:00Z"), coordinate: beijing)  // 17:30 北京
        XCTAssertLessThan(morning.dirX, 0, "上午的光应当偏东（屏幕左侧）")
        XCTAssertGreaterThan(evening.dirX, 0, "下午的光应当偏西（屏幕右侧）")
    }

    /// 「看几点」滑块：不给小时就是此刻；给了小时就整点
    func testHourSliderSnapsToTheHour() {
        let now = Date()
        XCTAssertEqual(SkyLight.date(hour: nil, from: now), now)
        let six = SkyLight.date(hour: 6, from: now)
        let cal = Calendar.current
        XCTAssertEqual(cal.component(.hour, from: six), 6)
        XCTAssertEqual(cal.component(.minute, from: six), 0)
    }
}

// MARK: - 天气：云量对光的衰减

final class SkyWeatherTests: XCTestCase {

    private let beijing = CLLocationCoordinate2D(latitude: 40.0, longitude: 116.4)
    private func utc(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }

    private func weather(cloud: Double, precip: Double = 0, code: Int = 3) -> SkyWeather {
        SkyWeather(cloudCover: cloud, precipitation: precip, temperatureC: 20, code: code,
                   fetchedAt: utc("2026-06-21T04:00:00Z"), latitude: 40.0, longitude: 116.4)
    }

    /// 式子本身：G = G_晴空 × (1 − 0.75 × N^3.4)。这条印在界面上，所以它必须真的成立。
    func testAttenuationMatchesThePrintedFormula() {
        XCTAssertEqual(SkyLight.cloudAttenuation(cloudCover: 0), 1.0, accuracy: 1e-9)
        XCTAssertEqual(SkyLight.cloudAttenuation(cloudCover: 100), 0.25, accuracy: 1e-9)
        // 50% 云：(1 − 0.75 × 0.5^3.4) ≈ 0.929
        XCTAssertEqual(SkyLight.cloudAttenuation(cloudCover: 50), 0.9290, accuracy: 5e-4)
    }

    /// 全是云的正午：辐照度恰好是晴空模型的 25%（而晴空值本身不变）
    func testOvercastNoonKeepsAQuarterOfTheClearSkyValue() {
        let noon = utc("2026-06-21T04:00:00Z")
        let clear = SkyLight.now(at: noon, coordinate: beijing)
        let overcast = SkyLight.now(at: noon, coordinate: beijing, weather: weather(cloud: 100))
        // 没有天气数据时，全天空辐照度就等于晴空模型（界面写明「不是实测」）
        XCTAssertEqual(clear.radiation, clear.clearSky, accuracy: 1e-9)
        XCTAssertEqual(overcast.radiation, clear.clearSky * 0.25, accuracy: 0.5)
        XCTAssertEqual(overcast.clearSky, clear.clearSky, accuracy: 1e-9)
    }

    /// 云越多 → 越暗、车灯越亮；但**太阳的位置不变**（云不改变天文）
    func testMoreCloudsMeansDimmerLightAndBrighterLamps() {
        let noon = utc("2026-06-21T04:00:00Z")
        let thin = SkyLight.now(at: noon, coordinate: beijing, weather: weather(cloud: 0))
        let thick = SkyLight.now(at: noon, coordinate: beijing, weather: weather(cloud: 100))
        XCTAssertLessThan(thick.radiation, thin.radiation)
        XCTAssertGreaterThanOrEqual(thick.lamp, thin.lamp)
        XCTAssertEqual(thin.azimuth, thick.azimuth, accuracy: 1e-9)
        XCTAssertEqual(thin.altitude, thick.altitude, accuracy: 1e-9)
    }

    /// 降水加重颗粒（湿的街面会脏）
    func testRainAddsGrain() {
        let noon = utc("2026-06-21T04:00:00Z")
        let dry = SkyLight.now(at: noon, coordinate: beijing, weather: weather(cloud: 60))
        let wet = SkyLight.now(at: noon, coordinate: beijing, weather: weather(cloud: 60, precip: 2))
        XCTAssertGreaterThan(wet.grain, dry.grain)
    }

    /// 表里的说法必须对应真实情况：没有天气时写「晴空辐照度」，有时写「全天空辐照度」
    func testFactsSayClearSkyWhenThereIsNoWeather() {
        let noon = utc("2026-06-21T04:00:00Z")
        let none = SkyLight.now(at: noon, coordinate: beijing)
        XCTAssertNil(none.weather)
        let rows = none.facts(at: noon)
        XCTAssertNil(rows.first { $0.id == "sky" }, "没有天气数据时不该出现云量行")
        XCTAssertEqual(rows.first { $0.id == "rad" }?.label, "晴空辐照度")

        let some = SkyLight.now(at: noon, coordinate: beijing, weather: weather(cloud: 75))
        let rows2 = some.facts(at: noon)
        XCTAssertEqual(rows2.first { $0.id == "sky" }?.value, "75%")
        XCTAssertEqual(rows2.first { $0.id == "wx" }?.value, "阴")
        XCTAssertEqual(rows2.first { $0.id == "rad" }?.label, "全天空辐照度")
    }

    /// 请求 URL：只发两位小数的经纬度、只发那一个域名、**精确坐标绝不能出现**
    func testRequestURLRoundsCoordinatesAndCarriesNoIdentity() {
        let text = WeatherService.requestURL(latitude: 40.03712345,
                                             longitude: 116.47098765)?.absoluteString ?? ""
        XCTAssertTrue(text.hasPrefix("https://api.open-meteo.com/"), text)
        XCTAssertTrue(text.contains("latitude=40.04"), text)
        XCTAssertTrue(text.contains("longitude=116.47"), text)
        XCTAssertTrue(text.contains("cloud_cover"), text)
        XCTAssertFalse(text.contains("40.03712345"), "精确坐标不得出现在请求里：\(text)")
        XCTAssertFalse(text.contains("116.47098765"), "精确坐标不得出现在请求里：\(text)")
    }

    /// 解析：字段齐就给值；缺关键字段就返回 nil —— 宁可没有天气，也不编一个
    func testParseReadsTheCurrentBlock() {
        let json = """
        {"latitude":40.04,"current":{"time":"2026-09-22T01:30","interval":900,
         "cloud_cover":75,"precipitation":0.4,"temperature_2m":18.6,"weather_code":61}}
        """.data(using: .utf8)!
        let w = WeatherService.parse(json, latitude: 40.04, longitude: 116.47,
                                     at: utc("2026-09-22T01:31:00Z"))
        XCTAssertEqual(w?.cloudCover, 75)
        XCTAssertEqual(w?.precipitation ?? -1, 0.4, accuracy: 1e-9)
        XCTAssertEqual(w?.code, 61)
        XCTAssertEqual(w?.codeText, "雨")
        // 取数时刻记的是**我们取的那一下**（不是服务端报文里的时间）
        XCTAssertEqual(w?.fetchedAt, utc("2026-09-22T01:31:00Z"))
        XCTAssertEqual(w?.ageMinutes(at: utc("2026-09-22T01:46:00Z")) ?? -1, 15.0, accuracy: 1e-9)

        let missing = #"{"latitude":40.04,"current":{"time":"2026-09-22T01:30"}}"#.data(using: .utf8)!
        XCTAssertNil(WeatherService.parse(missing, latitude: 40.04, longitude: 116.47, at: Date()),
                     "缺 cloud_cover / temperature_2m 时必须返回 nil")

        XCTAssertNil(WeatherService.parse(Data("not json".utf8),
                                          latitude: 40.04, longitude: 116.47, at: Date()))
    }

    /// 快照的「作废距离」：挪 500m 不重取，挪 10km 必重取
    func testSnapshotDistanceIsMeasuredInMeters() {
        let snapshot = weather(cloud: 50)
        XCTAssertLessThan(
            WeatherService.distanceMeters(from: snapshot,
                                          to: CLLocationCoordinate2D(latitude: 40.005, longitude: 116.4)),
            1_000)
        XCTAssertGreaterThan(
            WeatherService.distanceMeters(from: snapshot,
                                          to: CLLocationCoordinate2D(latitude: 40.09, longitude: 116.4)),
            WeatherService.moveThresholdMeters)
    }
}

// MARK: - 地图：充电站聚合

final class ChargerClusterTests: XCTestCase {

    private func charger(_ id: String, lat: Double, lon: Double, meters: Double) -> MapCharger {
        MapCharger(id: id,
                   coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                   name: "站 \(id)",
                   distanceMeters: meters,
                   isEVCharger: true)
    }

    func testEmptyInputProducesNothing() {
        XCTAssertTrue(MapSpineData.clusterChargers([]).isEmpty)
    }

    /// 纬度方向 0.001° ≈ 111m —— 必然落在 400m 之内
    func testNearbyStationsMergeIntoOne() {
        let out = MapSpineData.clusterChargers([
            charger("a", lat: 40.0, lon: 116.4, meters: 300),
            charger("b", lat: 40.001, lon: 116.4, meters: 400)
        ])
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].count, 2)
    }

    /// 0.01° ≈ 1.1km —— 必须分开
    func testDistantStationsStaySeparate() {
        let out = MapSpineData.clusterChargers([
            charger("a", lat: 40.0, lon: 116.4, meters: 300),
            charger("b", lat: 40.01, lon: 116.4, meters: 1400)
        ])
        XCTAssertEqual(out.count, 2)
        XCTAssertEqual(out.map(\.count), [1, 1])
    }

    /// 组的坐标是成员**重心**（两点 → 中点）
    func testClusterCoordinateIsTheCentroid() {
        let out = MapSpineData.clusterChargers([
            charger("a", lat: 40.0, lon: 116.4, meters: 300),
            charger("b", lat: 40.002, lon: 116.4, meters: 500)
        ])
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].coordinate.latitude, 40.001, accuracy: 1e-9)
    }

    /// 代表是**离车最近**的那一个（组内排序后保留 first）—— 点开时必须报得出名字
    func testClusterKeepsTheNearestStationAsItsRepresentative() {
        let out = MapSpineData.clusterChargers([
            charger("far", lat: 40.002, lon: 116.4, meters: 900),
            charger("near", lat: 40.0, lon: 116.4, meters: 120)
        ])
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].nearest.id, "near")
    }

    /// 组的位置是重心，所以「链条」不会无限延长：
    /// a—b 相距 390m 会并组，但 c 到 {a,b} 的重心已有 584m → 独立成组。
    func testGreedyGroupingUsesTheCentroidSoChainsDoNotGrowForever() {
        let out = MapSpineData.clusterChargers([
            charger("a", lat: 40.0, lon: 116.4, meters: 100),
            charger("b", lat: 40.0035, lon: 116.4, meters: 200),
            charger("c", lat: 40.007, lon: 116.4, meters: 300)
        ])
        XCTAssertEqual(out.count, 2)
        XCTAssertEqual(out.map(\.count).sorted(), [1, 2])
    }
}
