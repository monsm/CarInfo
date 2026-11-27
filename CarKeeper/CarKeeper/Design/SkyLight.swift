import SwiftUI
import CoreLocation

private func skyRad(_ deg: Double) -> Double { deg * .pi / 180 }
private func skyDeg(_ rad: Double) -> Double { rad * 180 / .pi }
private func skyClamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { min(max(v, lo), hi) }
private func skyLerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }

enum SkyPhase: String {
    case day
    case lowSun
    case horizon
    case civil
    case blueHour
    case deepNight

    static func of(altitude: Double) -> SkyPhase {
        if altitude >= 30 { return .day }
        if altitude >= 8 { return .lowSun }
        if altitude >= 0 { return .horizon }
        if altitude >= -6 { return .civil }
        if altitude >= -15 { return .blueHour }
        return .deepNight
    }

    var title: String {
        switch self {
        case .day: return "白昼"
        case .lowSun: return "低角度日光"
        case .horizon: return "日出 / 日落"
        case .civil: return "民用暮光"
        case .blueHour: return "蓝调"
        case .deepNight: return "深夜"
        }
    }

    var note: String {
        switch self {
        case .day: return "太阳在头顶，光几乎没有方向"
        case .lowSun: return "斜射，影子开始变长"
        case .horizon: return "贴着地平线，色温最暖"
        case .civil: return "太阳刚落，天还没黑透"
        case .blueHour: return "天空比地面亮，偏冷"
        case .deepNight: return "没有太阳，只剩城市辉光"
        }
    }
}

struct SolarFix {
    let altitude: Double
    let azimuth: Double
}

enum SolarMath {
    static func fix(at date: Date, coordinate: CLLocationCoordinate2D) -> SolarFix {
        let ms = date.timeIntervalSince1970 * 1000
        let julianDay = ms / 86_400_000 + 2_440_587.5
        let t = (julianDay - 2_451_545.0) / 36_525

        let l0 = 280.46646 + t * (36_000.76983 + 0.0003032 * t)
        let m = 357.52911 + t * (35_999.05029 - 0.0001537 * t)
        let e = 0.016708634 - t * (0.000042037 + 0.0000001267 * t)
        let c = sin(skyRad(m)) * (1.914602 - t * (0.004817 + 0.000014 * t))
            + sin(skyRad(2 * m)) * (0.019993 - 0.000101 * t)
            + sin(skyRad(3 * m)) * 0.000289

        let omega = 125.04 - 1934.136 * t
        let lambda = (l0 + c) - 0.00569 - 0.00478 * sin(skyRad(omega))
        let eps0 = 23 + (26 + (21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))) / 60) / 60
        let eps = eps0 + 0.00256 * cos(skyRad(omega))
        let declination = skyDeg(asin(sin(skyRad(eps)) * sin(skyRad(lambda))))

        var y = tan(skyRad(eps / 2))
        y *= y
        let equationOfTime = 4 * skyDeg(
            y * sin(2 * skyRad(l0))
                - 2 * e * sin(skyRad(m))
                + 4 * e * y * sin(skyRad(m)) * cos(2 * skyRad(l0))
                - 0.5 * y * y * sin(4 * skyRad(l0))
                - 1.25 * e * e * sin(2 * skyRad(m))
        )

        let dayMs = 86_400_000.0
        var utcMs = ms.truncatingRemainder(dividingBy: dayMs)
        if utcMs < 0 { utcMs += dayMs }
        let utcMinutes = utcMs / 60_000
        let trueSolarMinutes = utcMinutes + equationOfTime + 4 * coordinate.longitude
        var hourAngle = trueSolarMinutes / 4 - 180
        while hourAngle < -180 { hourAngle += 360 }
        while hourAngle > 180 { hourAngle -= 360 }

        let la = skyRad(coordinate.latitude)
        let de = skyRad(declination)
        let ha = skyRad(hourAngle)
        let altitude = skyDeg(asin(sin(la) * sin(de) + cos(la) * cos(de) * cos(ha)))
        let azimuth = skyDeg(atan2(sin(ha), cos(ha) * sin(la) - tan(de) * cos(la))) + 180

        return SolarFix(altitude: altitude, azimuth: azimuth)
    }
}

struct SkyFact: Identifiable {
    let id: String
    let label: String
    let value: String
    let note: String
}

struct SkyLight {

    static func cloudAttenuation(cloudCover: Double) -> Double {
        let n = skyClamp(cloudCover / 100, 0, 1)
        return skyClamp(1 - 0.75 * pow(n, 3.4), 0, 1)
    }
    let phase: SkyPhase
    let altitude: Double
    let azimuth: Double
    let clearSky: Double
    let radiation: Double
    let weather: SkyWeather?
    let lamp: Double
    let warmth: Double
    let pool: Double
    let vignette: Double
    let grain: Double
    let dirX: Double
    let dirY: Double
    let isDaylight: Bool

    var bearingText: String {
        let names = ["北", "东北", "东", "东南", "南", "西南", "西", "西北"]
        let idx = Int((azimuth.truncatingRemainder(dividingBy: 360) + 360)
            .truncatingRemainder(dividingBy: 360) / 45 + 0.5) % 8
        return names[idx] + " " + "\(Int(azimuth.rounded()))°"
    }


    var facts: [SkyFact] { facts(at: Date()) }

    func facts(at now: Date) -> [SkyFact] {
        var rows: [SkyFact] = [
            SkyFact(id: "phase", label: "光名", value: phase.title, note: phase.note),
            SkyFact(id: "alt", label: "太阳高度",
                    value: String(format: "%.1f°", altitude),
                    note: "由车的经纬度与此刻算出的天文事实"),
            SkyFact(id: "az", label: "方位", value: bearingText,
                    note: "光从这个方向来")
        ]
        if let w = weather {
            rows.append(SkyFact(id: "sky", label: "云量",
                                value: w.cloudText,
                                note: w.sourceText(at: now) + " · 每 \(Int(WeatherService.refreshMinutes)) 分钟一次"))
            rows.append(SkyFact(id: "wx", label: "天气",
                                value: w.codeText,
                                note: "WMO 天气码 \(w.code)；降水 \(w.precipitationText) · \(w.temperatureText)"))
        }
        rows.append(SkyFact(id: "rad",
                            label: weather == nil ? "晴空辐照度" : "全天空辐照度",
                            value: "\(Int(radiation.rounded())) W/m²",
                            note: weather == nil
                                ? "晴空模型 1050×sin(高度角)，不是实测"
                                : "晴空模型 × 云量衰减"))
        rows.append(SkyFact(id: "mode", label: "界面模式",
                            value: isDaylight ? "日光（纸）" : "夜行（深）",
                            note: "辐照度 > 150 W/m² 切日光模式"))
        rows.append(SkyFact(id: "lamp", label: "车灯亮度",
                            value: "\(Int((lamp * 100).rounded()))%",
                            note: "规则：1 − 辐照度/220"))
        return rows
    }

    static func date(hour: Int?, from now: Date) -> Date {
        guard let hour else { return now }
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: now)
        comps.hour = hour
        comps.minute = 0
        comps.second = 0
        return cal.date(from: comps) ?? now
    }

    static func now(at date: Date,
                    coordinate: CLLocationCoordinate2D,
                    weather: SkyWeather? = nil) -> SkyLight {
        let fix = SolarMath.fix(at: date, coordinate: coordinate)
        let alt = fix.altitude
        let azimuth = (fix.azimuth.truncatingRemainder(dividingBy: 360) + 360)
            .truncatingRemainder(dividingBy: 360)

        let clearRadiation = max(0, 1050 * sin(skyRad(alt)))
        let attenuation = weather.map { cloudAttenuation(cloudCover: $0.cloudCover) } ?? 1
        let radiation = clearRadiation * attenuation

        let tt = skyClamp((radiation - 95) / 110, 0, 1)
        let lightAmount = tt * tt * (3 - 2 * tt)
        let daylight = lightAmount >= 0.5

        var warmth = 0.0
        if alt > -3 {
            warmth = skyClamp(1 - abs(alt) / 14, 0, 1)
        } else {
            warmth = -skyClamp((alt + 21) / 15, 0, 1)
        }

        let hasSun = skyClamp((alt + 6) / 4, 0, 1)
        let radius = skyLerp(90, 340 * (1 - skyClamp(alt / 60, 0, 1)), hasSun)
        let dirX = sin(skyRad(azimuth)) * radius
        let dirY = -cos(skyRad(azimuth)) * radius

        let sunPresence = skyClamp((alt + 8) / 20, 0, 1)
        let pool = skyLerp(0.10, 0.20, max(sunPresence, lightAmount))

        let lamp = skyClamp(1 - radiation / 220, 0.05, 1)

        let vignette = skyLerp(0.62, 0.14, lightAmount)
        let wet = weather.map { skyClamp($0.precipitation / 2, 0, 1) } ?? 0
        let grain = skyLerp(0.055, 0.04, lightAmount) + wet * 0.03

        return SkyLight(
            phase: SkyPhase.of(altitude: alt),
            altitude: alt,
            azimuth: azimuth,
            clearSky: clearRadiation,
            radiation: radiation,
            weather: weather,
            lamp: lamp,
            warmth: warmth,
            pool: pool,
            vignette: vignette,
            grain: grain,
            dirX: dirX,
            dirY: dirY,
            isDaylight: daylight
        )
    }
}
