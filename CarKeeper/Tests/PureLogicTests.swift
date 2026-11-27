import XCTest
import Foundation
import CoreLocation
@testable import CarKeeper


final class SkyLightTests: XCTestCase {

    private let beijing = CLLocationCoordinate2D(latitude: 40.0, longitude: 116.4)

    private func utc(_ s: String) -> Date {
        ISO8601DateFormatter().date(from: s)!
    }

    func testJuneSolsticeNoonAltitude() {
        let light = SkyLight.now(at: utc("2026-06-21T04:00:00Z"), coordinate: beijing)
        XCTAssertEqual(light.altitude, 73.44, accuracy: 1.2)
    }

    func testDecemberSolsticeNoonAltitude() {
        let light = SkyLight.now(at: utc("2026-12-21T04:00:00Z"), coordinate: beijing)
        XCTAssertEqual(light.altitude, 26.56, accuracy: 1.2)
    }

    func testLocalMidnightIsDark() {
        let light = SkyLight.now(at: utc("2026-06-21T16:00:00Z"), coordinate: beijing)
        XCTAssertLessThan(light.altitude, 0)
        XCTAssertEqual(light.clearSky, 0, accuracy: 0.001)
        XCTAssertFalse(light.isDaylight)
        XCTAssertEqual(light.lamp, 1.0, accuracy: 0.001)
    }

    func testDaylightThresholdMatchesTheDocumentedRule() {
        for hour in 0..<24 {
            let light = SkyLight.now(at: utc(String(format: "2026-03-20T%02d:00:00Z", hour)),
                                     coordinate: beijing)
            XCTAssertEqual(light.isDaylight, light.clearSky >= 150,
                           "小时 \(hour)：isDaylight 与 150 W/m² 的规则不一致")
        }
    }

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

    func testMidnightSunAboveTheArcticCircle() {
        let svalbard = CLLocationCoordinate2D(latitude: 78.2, longitude: 15.6)
        let light = SkyLight.now(at: utc("2026-06-21T22:00:00Z"), coordinate: svalbard)
        XCTAssertGreaterThan(light.altitude, 0)
    }

    func testPolarNightInDecember() {
        let svalbard = CLLocationCoordinate2D(latitude: 78.2, longitude: 15.6)
        let light = SkyLight.now(at: utc("2026-12-21T11:00:00Z"), coordinate: svalbard)
        XCTAssertLessThan(light.altitude, 0)
        XCTAssertFalse(light.isDaylight)
        XCTAssertEqual(light.lamp, 1.0, accuracy: 0.001)
    }

    func testLightComesFromOppositeSidesMorningAndEvening() {
        let morning = SkyLight.now(at: utc("2026-03-20T23:30:00Z"), coordinate: beijing)
        let evening = SkyLight.now(at: utc("2026-03-20T09:30:00Z"), coordinate: beijing)
        XCTAssertLessThan(morning.dirX, 0, "上午的光应当偏东（屏幕左侧）")
        XCTAssertGreaterThan(evening.dirX, 0, "下午的光应当偏西（屏幕右侧）")
    }

    func testHourSliderSnapsToTheHour() {
        let now = Date()
        XCTAssertEqual(SkyLight.date(hour: nil, from: now), now)
        let six = SkyLight.date(hour: 6, from: now)
        let cal = Calendar.current
        XCTAssertEqual(cal.component(.hour, from: six), 6)
        XCTAssertEqual(cal.component(.minute, from: six), 0)
    }
}


final class SkyWeatherTests: XCTestCase {

    private let beijing = CLLocationCoordinate2D(latitude: 40.0, longitude: 116.4)
    private func utc(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }

    private func weather(cloud: Double, precip: Double = 0, code: Int = 3) -> SkyWeather {
        SkyWeather(cloudCover: cloud, precipitation: precip, temperatureC: 20, code: code,
                   fetchedAt: utc("2026-06-21T04:00:00Z"), latitude: 40.0, longitude: 116.4)
    }

    func testAttenuationMatchesThePrintedFormula() {
        XCTAssertEqual(SkyLight.cloudAttenuation(cloudCover: 0), 1.0, accuracy: 1e-9)
        XCTAssertEqual(SkyLight.cloudAttenuation(cloudCover: 100), 0.25, accuracy: 1e-9)
        XCTAssertEqual(SkyLight.cloudAttenuation(cloudCover: 50), 0.9290, accuracy: 5e-4)
    }

    func testOvercastNoonKeepsAQuarterOfTheClearSkyValue() {
        let noon = utc("2026-06-21T04:00:00Z")
        let clear = SkyLight.now(at: noon, coordinate: beijing)
        let overcast = SkyLight.now(at: noon, coordinate: beijing, weather: weather(cloud: 100))
        XCTAssertEqual(clear.radiation, clear.clearSky, accuracy: 1e-9)
        XCTAssertEqual(overcast.radiation, clear.clearSky * 0.25, accuracy: 0.5)
        XCTAssertEqual(overcast.clearSky, clear.clearSky, accuracy: 1e-9)
    }

    func testMoreCloudsMeansDimmerLightAndBrighterLamps() {
        let noon = utc("2026-06-21T04:00:00Z")
        let thin = SkyLight.now(at: noon, coordinate: beijing, weather: weather(cloud: 0))
        let thick = SkyLight.now(at: noon, coordinate: beijing, weather: weather(cloud: 100))
        XCTAssertLessThan(thick.radiation, thin.radiation)
        XCTAssertGreaterThanOrEqual(thick.lamp, thin.lamp)
        XCTAssertEqual(thin.azimuth, thick.azimuth, accuracy: 1e-9)
        XCTAssertEqual(thin.altitude, thick.altitude, accuracy: 1e-9)
    }

    func testRainAddsGrain() {
        let noon = utc("2026-06-21T04:00:00Z")
        let dry = SkyLight.now(at: noon, coordinate: beijing, weather: weather(cloud: 60))
        let wet = SkyLight.now(at: noon, coordinate: beijing, weather: weather(cloud: 60, precip: 2))
        XCTAssertGreaterThan(wet.grain, dry.grain)
    }

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
        XCTAssertEqual(w?.fetchedAt, utc("2026-09-22T01:31:00Z"))
        XCTAssertEqual(w?.ageMinutes(at: utc("2026-09-22T01:46:00Z")) ?? -1, 15.0, accuracy: 1e-9)

        let missing = #"{"latitude":40.04,"current":{"time":"2026-09-22T01:30"}}"#.data(using: .utf8)!
        XCTAssertNil(WeatherService.parse(missing, latitude: 40.04, longitude: 116.47, at: Date()),
                     "缺 cloud_cover / temperature_2m 时必须返回 nil")

        XCTAssertNil(WeatherService.parse(Data("not json".utf8),
                                          latitude: 40.04, longitude: 116.47, at: Date()))
    }

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

    func testNearbyStationsMergeIntoOne() {
        let out = MapSpineData.clusterChargers([
            charger("a", lat: 40.0, lon: 116.4, meters: 300),
            charger("b", lat: 40.001, lon: 116.4, meters: 400)
        ])
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].count, 2)
    }

    func testDistantStationsStaySeparate() {
        let out = MapSpineData.clusterChargers([
            charger("a", lat: 40.0, lon: 116.4, meters: 300),
            charger("b", lat: 40.01, lon: 116.4, meters: 1400)
        ])
        XCTAssertEqual(out.count, 2)
        XCTAssertEqual(out.map(\.count), [1, 1])
    }

    func testClusterCoordinateIsTheCentroid() {
        let out = MapSpineData.clusterChargers([
            charger("a", lat: 40.0, lon: 116.4, meters: 300),
            charger("b", lat: 40.002, lon: 116.4, meters: 500)
        ])
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].coordinate.latitude, 40.001, accuracy: 1e-9)
    }

    func testClusterKeepsTheNearestStationAsItsRepresentative() {
        let out = MapSpineData.clusterChargers([
            charger("far", lat: 40.002, lon: 116.4, meters: 900),
            charger("near", lat: 40.0, lon: 116.4, meters: 120)
        ])
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].nearest.id, "near")
    }

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


final class MessageWindowTests: XCTestCase {

    private func at(_ s: String) -> Date {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.date(from: s)!
    }

    func testWindowsTileBackwardsWithoutGaps() {
        let now = at("2026-09-24 12:00:00")
        let w = APIClient.messageWindows(days: 30, sliceDays: 7, now: now)
        XCTAssertEqual(w.count, 5)
        XCTAssertEqual(w[0].end, now)
        for seg in w.prefix(4) {
            XCTAssertEqual(seg.end.timeIntervalSince(seg.start), 7 * 24 * 3600, accuracy: 0.5)
        }
        XCTAssertEqual(w[4].end.timeIntervalSince(w[4].start), 2 * 24 * 3600, accuracy: 0.5)
        for i in 1..<w.count { XCTAssertEqual(w[i].end, w[i - 1].start) }
        XCTAssertEqual(w[4].start, now.addingTimeInterval(-30 * 24 * 3600))
    }

    func testTinyOrNegativeSpanStillReturnsOneWindow() {
        XCTAssertEqual(APIClient.messageWindows(days: 0, now: Date()).count, 1)
        XCTAssertEqual(APIClient.messageWindows(days: -30, now: Date()).count, 1)
        XCTAssertEqual(APIClient.messageWindows(days: 3, now: Date()).count, 1)
        let w = APIClient.messageWindows(days: 3, now: Date())
        XCTAssertGreaterThanOrEqual(w[0].start, Date().addingTimeInterval(-3 * 24 * 3600 - 1))
    }

    func testMergeDedupesAndSortsNewestFirst() {
        let old: [String: Any] = ["stubId": "1:a", "createdAt": "2026-09-04 07:01:55"]
        let new: [String: Any] = ["stubId": "1:b", "createdAt": "2026-09-10 08:00:00"]
        let dupe: [String: Any] = ["stubId": "1:a", "createdAt": "2026-09-04 07:01:55"]
        let merged = APIClient.mergeMessages([[old], [new, dupe]])
        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged.first?["stubId"] as? String, "1:b")
    }

    func testMergeKeepsRowsWithoutIdsAndSortsUndatedLast() {
        let undated: [String: Any] = ["title": "无 id 无时间"]
        let dated: [String: Any] = ["title": "有 id", "id": "77",
                                    "createdAt": "2026-09-01 00:00:00"]
        let merged = APIClient.mergeMessages([[undated, dated]])
        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged.first?["title"] as? String, "有 id")
        XCTAssertEqual(merged.last?["title"] as? String, "无 id 无时间")
    }

    func testMergeCapsTheResult() {
        let many: [[String: Any]] = (0..<(APIClient.messageCap + 50)).map {
            ["stubId": "s\($0)",
             "createdAt": String(format: "2026-09-%02d 00:00:00", ($0 % 28) + 1)]
        }
        XCTAssertEqual(APIClient.mergeMessages([many]).count, APIClient.messageCap)
    }
}


final class APIEnvelopeTests: XCTestCase {

    func testTokenExpiredEnvelopeIsDetected() {
        let text = #"{"code":"2","data":"{}","msg":"token expired"}"#
        let env = APIClient.decodeEnvelope(text)
        XCTAssertFalse(env.ok)
        XCTAssertTrue(env.expired)
        XCTAssertEqual(env.code, 2)
    }

    func testSuccessEnvelopeWins() {
        let text = #"{"success":true,"code":0,"data":{"soc":66}}"#
        let env = APIClient.decodeEnvelope(text)
        XCTAssertTrue(env.ok)
        XCTAssertFalse(env.expired)
        XCTAssertEqual((env.data as? [String: Any])?["soc"] as? Int, 66)
    }

    func testSuccessFalseBeatsZeroCode() {
        let text = #"{"success":false,"code":0,"msg":"nope"}"#
        XCTAssertFalse(APIClient.decodeEnvelope(text).ok)
    }

    func testDataAsJSONStringIsDecoded() {
        let text = "{\"code\":0,\"data\":\"[1,2]\"}"
        let env = APIClient.decodeEnvelope(text)
        XCTAssertEqual((env.data as? [Any])?.count, 2)
    }

    func testNonJSONIsFailure() {
        let env = APIClient.decodeEnvelope("<html>oops</html>")
        XCTAssertFalse(env.ok)
        XCTAssertFalse(env.expired)
    }

    func testBusinessCodeTwoWithoutTokenMessageIsNotExpired() {
        let text = #"{"code":"2","data":"{}","msg":"some other error"}"#
        let env = APIClient.decodeEnvelope(text)
        XCTAssertFalse(env.ok)
        XCTAssertFalse(env.expired)
    }

    func testMessageHasMoreOnlyWhenFullPageAndNotLast() {
        let more = #"{"data":{"size":20,"numberOfElements":20,"last":false}}"#
        let short = #"{"data":{"size":2000,"numberOfElements":56,"last":false}}"#
        let last = #"{"data":{"size":20,"numberOfElements":20,"last":true}}"#
        XCTAssertTrue(APIClient.messageHasMore(more))
        XCTAssertFalse(APIClient.messageHasMore(short))
        XCTAssertFalse(APIClient.messageHasMore(last))
    }
}


final class PureHelpersTests: XCTestCase {

    func testTriStateTreatsMissingAsUnknown() {
        XCTAssertEqual(AN.triState(nil, on: "正常", off: "异常"), "--")
        XCTAssertEqual(AN.triState(0, on: "正常", off: "异常"), "正常")
        XCTAssertEqual(AN.triState(1, on: "正常", off: "异常"), "异常")
    }

    func testTriStateBool() {
        XCTAssertEqual(AN.triStateBool(nil, on: "开启", off: "关闭"), "--")
        XCTAssertEqual(AN.triStateBool(1, on: "开启", off: "关闭"), "开启")
        XCTAssertEqual(AN.triStateBool(0, on: "开启", off: "关闭"), "关闭")
    }

    func testCardOrderKeepsUserOrderAndAppendsNewCards() {
        let known = ["a", "b", "c", "d"]
        XCTAssertEqual(AppStore.normalizeCardOrder(nil, known: known), known)
        XCTAssertEqual(AppStore.normalizeCardOrder(["c", "a"], known: known), ["c", "a", "b", "d"])
        XCTAssertEqual(AppStore.normalizeCardOrder(["gone", "b"], known: known), ["b", "a", "c", "d"])
    }

    func testHeadingIsNormalizedIntoRange() {
        let cache: [String: Any?] = ["location": ["Heading": 550.4]]
        let deg = VM.headingDegFast(cache)
        XCTAssertGreaterThanOrEqual(deg, 0)
        XCTAssertLessThan(deg, 360)
        XCTAssertEqual(deg, 190.4, accuracy: 0.01)
    }
}


final class DriveScoreTests: XCTestCase {

    func testEffortModeUsesFixedBaseline() {
        let s = DriveScore(efforts: [15, 15, 15], percents: [])
        XCTAssertFalse(s.usesPercent)
        XCTAssertEqual(s.baseline, 15.0)
        XCTAssertEqual(s.energy, 100)
        XCTAssertEqual(s.hit, 100)
    }

    func testPercentModeUsesMedianBaseline() {
        let s = DriveScore(efforts: [], percents: [10, 12, 14])
        XCTAssertTrue(s.usesPercent)
        XCTAssertEqual(s.baseline, 12.0)
    }

    func testEfficiencyPointsClampToRange() {
        XCTAssertEqual(DriveScore.efficiencyPoints(30, baseline: 15, lowerIsBetter: true), 40)
        XCTAssertEqual(DriveScore.efficiencyPoints(5, baseline: 15, lowerIsBetter: true), 100)
        XCTAssertEqual(DriveScore.efficiencyPoints(30, baseline: 15, lowerIsBetter: true) >= 0, true)
    }

    func testEmptyInputsProduceNoScore() {
        let s = DriveScore(efforts: [], percents: [])
        XCTAssertNil(s.overall)
        XCTAssertNil(s.grade)
    }
}


final class MessageFeedTests: XCTestCase {

    func testClassifierTags() {
        XCTAssertEqual(MessageClassifier.classify(title: "电池故障", content: "").tag, "报警")
        XCTAssertEqual(MessageClassifier.classify(title: "车辆熄火", content: "开始充电").tag, "充电")
        XCTAssertEqual(MessageClassifier.classify(title: "位置更新", content: "").tag, "定位")
        XCTAssertEqual(MessageClassifier.classify(title: "普通通知", content: "").tag, "")
    }

    func testResolveBodySkipsNullAndEmpty() {
        let m: [String: Any] = ["content": "null", "detail": "无", "description": "真实内容"]
        XCTAssertEqual(MessageClassifier.resolveBody(m), "真实内容")
        XCTAssertEqual(MessageClassifier.resolveBody([:]), "")
    }

    func testDayKeyParsesBothSeparators() {
        XCTAssertEqual(MessageGrouping.dayKey("2026-09-22 07:08:25"), "2026-09-22")
        XCTAssertEqual(MessageGrouping.dayKey("2026/9/2 01:02:03"), "2026/9/2")
        XCTAssertEqual(MessageGrouping.dayKey("没有日期"), "")
    }

    func testGroupsSortNewestFirstAndPutEarlierLast() {
        let items = [
            MessageItem(id: "a", title: "", body: "", location: "", time: "2026-09-20 10:00:00",
                        plate: "", read: false, tag: "", tagCls: "", coordinate: nil),
            MessageItem(id: "b", title: "", body: "", location: "", time: "2026-09-22 10:00:00",
                        plate: "", read: true, tag: "", tagCls: "", coordinate: nil),
            MessageItem(id: "c", title: "", body: "", location: "", time: "",
                        plate: "", read: false, tag: "", tagCls: "", coordinate: nil)
        ]
        let groups = MessageGrouping.groups(items)
        XCTAssertEqual(groups.map(\.label).last, "更早")
        XCTAssertEqual(groups.last?.items.map(\.id), ["c"])
        XCTAssertEqual(groups.first?.items.map(\.id), ["b"])
        XCTAssertEqual(groups.first?.unread, 0)
    }

    func testDecodePrefersReceiverPlateAndReadsStatus() {
        let m: [String: Any] = [
            "stubId": "s1", "title": "T", "content": "C",
            "createdAt": "2026-09-22 07:08:25",
            "realReceiverId": "id-1", "receiverPlate": "京A*****",
            "readStatus": 1
        ]
        let items = MessageDecoder.decode([m], readSet: [])
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].id, "s1")
        XCTAssertEqual(items[0].plate, "京A*****")
        XCTAssertTrue(items[0].read)
    }

    func testDecodeTreatsNewFlagAsUnread() {
        let m: [String: Any] = ["stubId": "s2", "title": "T", "content": "C",
                                "createdAt": "2026-09-22 07:08:25", "new": true]
        XCTAssertFalse(MessageDecoder.decode([m], readSet: []).first!.read)
        XCTAssertTrue(MessageDecoder.decode([m], readSet: ["s2"]).first!.read)
    }
}


final class BodyStateTests: XCTestCase {

    func testNilOrEmptyControlProducesNoState() {
        XCTAssertNil(BodyState(control: nil))
        XCTAssertNil(BodyState(control: [:]))
    }

    func testClosedAndLockedDoorsAreOK() {
        let state = BodyState(control: [
            "LeftFrontDoor": 0, "LeftFrontDoorLock": 0
        ])
        XCTAssertEqual(state?.doorRows.count, 1)
        XCTAssertEqual(state?.doorRows.first?.value, "已关 · 已锁")
        XCTAssertEqual(state?.doorRows.first?.cls, "ok")
        XCTAssertEqual(state?.summary, "全部正常")
    }

    func testOpenDoorIsAbnormal() {
        let state = BodyState(control: ["LeftFrontDoor": 1, "LeftFrontDoorLock": 0])
        XCTAssertEqual(state?.doorRows.first?.cls, "bad")
        XCTAssertEqual(state?.summary, "1 项异常")
        XCTAssertEqual(state?.cls, "bad")
    }

    func testWindowDegreeAndLampAndHood() {
        let state = BodyState(control: [
            "LeftAnteriorWindowDegree": 30, "LowBeam": 1, "Hood": 1
        ])
        XCTAssertEqual(state?.windowRows.first?.value, "开启 30°")
        XCTAssertEqual(state?.windowRows.first?.cls, "bad")
        XCTAssertEqual(state?.lampRows.first?.value, "亮")
        XCTAssertEqual(state?.extraRows.first?.label, "引擎盖")
        XCTAssertEqual(state?.extraRows.first?.cls, "bad")
        XCTAssertEqual(state?.summary, "2 项异常")
    }

    func testOnlyLampsStillGetsSummary() {
        let state = BodyState(control: ["HighBeam": 0])
        XCTAssertEqual(state?.lampRows.first?.value, "灭")
        XCTAssertEqual(state?.summary, "全部正常")
    }
}


final class AppDomainTests: XCTestCase {

    func testTripRecordComputesKmPerPercent() {
        let open = TripTracker.Open(startTime: Date(timeIntervalSince1970: 0),
                                    startSoc: 80, startLocation: nil,
                                    startMileage: 1000, startAddr: "A")
        let record = TripTracker.makeRecord(open, distanceKm: 60, endSoc: 60,
                                            endLocation: nil, at: Date(timeIntervalSince1970: 3600),
                                            endAddr: "B")
        XCTAssertEqual(record.kmPerPercent, 3.0, accuracy: 0.0001)
        XCTAssertEqual(record.distanceKm, 60)
        XCTAssertEqual(record.startAddr, "A")
        XCTAssertEqual(record.endAddr, "B")
    }

    func testTripRecordLeavesKmPerPercentNilWhenSocDidNotDrop() {
        let open = TripTracker.Open(startTime: Date(), startSoc: 50,
                                    startLocation: nil, startMileage: nil, startAddr: "")
        let record = TripTracker.makeRecord(open, distanceKm: 10, endSoc: 50,
                                            endLocation: nil, at: Date(), endAddr: "")
        XCTAssertNil(record.kmPerPercent)
    }

    func testTripKmFallsBackToZero() {
        let open = TripTracker.Open(startTime: Date(), startSoc: 50,
                                    startLocation: nil, startMileage: 2000, startAddr: "")
        XCTAssertEqual(TripTracker.tripKm(open: open, endMileage: 2030), 30)
        XCTAssertEqual(TripTracker.tripKm(open: open, endMileage: 1990), 0)
        XCTAssertEqual(TripTracker.tripKm(open: nil, endMileage: 2030), 0)
    }

    func testParkingDedupeWithin120m() {
        let last = ParkingMark(lat: 30.0, lng: 114.0, time: Date(), address: "")
        XCTAssertTrue(ParkingTracker.shouldSkip(last: last,
                                                new: CLLocationCoordinate2D(latitude: 30.0005, longitude: 114.0)))
        XCTAssertFalse(ParkingTracker.shouldSkip(last: last,
                                                 new: CLLocationCoordinate2D(latitude: 30.02, longitude: 114.0)))
        XCTAssertFalse(ParkingTracker.shouldSkip(last: nil,
                                                 new: CLLocationCoordinate2D(latitude: 30.0, longitude: 114.0)))
    }

    func testCommandHistoryKeepsNewestAndCaps() {
        var list: [CommandRecord] = []
        for i in 0..<60 {
            let e = CommandRecord(cmd: "c", name: "n\(i)", startedAt: Date(),
                                 finishedAt: Date(), success: true, confirmed: true, duration: 1)
            list = CommandHistoryTracker.insert(e, into: list)
        }
        XCTAssertEqual(list.count, CommandHistoryTracker.cap)
        XCTAssertEqual(list.first?.name, "n59")
    }
}


final class TripBuilderTests: XCTestCase {

    private func message(kind: String, id: String, lat: Double, lng: Double, addr: String) -> [String: Any] {
        let jump = "{\"action\":\"INNER_JUMP\",\"uriParams\":{\"gpsTime\":\"2026-09-22 07:08:25\","
            + "\"lat\":\(lat),\"lng\":\(lng),\"addrName\":\"\(addr)\"}}"
        return ["infoTypeId": kind, "stubId": id,
                "createdAt": "2026-09-22 07:08:25", "jumpParam": jump]
    }

    func testEventsDecodeBothKinds() {
        let msgs = [message(kind: "IGNITION", id: "a", lat: 30.0, lng: 114.0, addr: "A"),
                    message(kind: "FLAMEOUT", id: "b", lat: 30.01, lng: 114.0, addr: "B"),
                    ["infoTypeId": "OTHER", "stubId": "c"]]
        let events = TripBuilder.events(from: msgs)
        XCTAssertEqual(events.count, 2)
        XCTAssertTrue(events[0].ignition)
        XCTAssertFalse(events[1].ignition)
        XCTAssertEqual(events[1].addr, "B")
        XCTAssertNotNil(events[0].coordinate)
    }

    func testDisplayTripsPairsAndComputesDistance() {
        let msgs = [message(kind: "IGNITION", id: "a", lat: 30.0, lng: 114.0, addr: "A"),
                    message(kind: "FLAMEOUT", id: "b", lat: 30.01, lng: 114.0, addr: "B")]
        let trips = TripBuilder.displayTrips(from: TripBuilder.events(from: msgs))
        XCTAssertEqual(trips.count, 1)
        XCTAssertGreaterThan(trips[0].distanceKm, 1.0)
        XCTAssertEqual(trips[0].startAddr, "A")
        XCTAssertEqual(trips[0].endAddr, "B")
    }

    func testOpenIgnitionProducesUnfinishedTrip() {
        let msgs = [message(kind: "IGNITION", id: "a", lat: 30.0, lng: 114.0, addr: "A")]
        let trips = TripBuilder.displayTrips(from: TripBuilder.events(from: msgs))
        XCTAssertEqual(trips.count, 1)
        XCTAssertNil(trips[0].endTime)
        XCTAssertEqual(trips[0].distanceKm, 0)
    }

    func testMergePrefersStoredDistanceAndFillsAddresses() {
        let stored = TripLog(startTime: Date(timeIntervalSince1970: 100), endTime: nil,
                             startLocation: nil, endLocation: nil, distanceKm: 5,
                             startSoc: 0, endSoc: 0, avgEfficiency: nil, kmPerPercent: nil,
                             startAddr: "S", endAddr: "")
        let fromMsg = TripLog(startTime: Date(timeIntervalSince1970: 100), endTime: nil,
                              startLocation: nil, endLocation: nil, distanceKm: 0,
                              startSoc: 0, endSoc: 0, avgEfficiency: nil, kmPerPercent: nil,
                              startAddr: "M", endAddr: "E")
        let merged = TripBuilder.merge(fromMessages: [fromMsg], stored: [stored])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].distanceKm, 5)
        XCTAssertEqual(merged[0].startAddr, "S")
        XCTAssertEqual(merged[0].endAddr, "E")
    }
}
