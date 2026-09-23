// =============================================================================
// SkyLight.swift — 光引擎：界面的光与色，由车所在地的**真实太阳位置**算出
// =============================================================================
//
// 为什么需要它：界面好不好看，很多时候不是配色问题，是**光有没有来源**。
// 一张图上的光如果方向、色温、强度都是随手调的，人看不出来哪里不对，只觉得"平"。
//
// 这一层把"光"变成物理量：
//   输入 —— 车所在经纬度（location 接口）+ 真实时刻（设备时钟）
//   计算 —— 太阳高度角与方位角（NOAA 简化算法，纯数学，不需要联网）
//   输出 —— 光名（白昼/低角度日光/日出日落/民用暮光/蓝调/深夜）、光的方向、色温、
//           光池强度、暗角强度、颗粒强度，以及**车灯该多亮**
//
// 三类东西必须分清（这是这一层的全部诚实性所在）：
//   ① **天文事实**：太阳高度角、方位角 —— 由经纬度与时刻唯一决定，可复算。
//   ② **设计规则**：把天文事实翻译成界面数值的那几条映射（都写在下面每个字段上，
//      也原样印在界面里）。它们不是气象事实，是我定的规则 —— 所以必须可争论。
//   ③ **天气实况**：云量 / 降水 / 天气码来自 Open-Meteo（见 `WeatherService.swift`）。
//      有实况时：辐照度 = 晴空模型 × **云量衰减**（式子印在界面上，可争论）。
//      没有实况时（离线 / 取数失败 / 还没取到）：退回**晴空模型**（假设无云），
//      并照实写"无天气数据，不是实测"。两种情况的差别写在界面上，不靠用户猜。
//
// 命名：顶层类型，不嵌套泛用名（历史事故见 ArtTheme.swift 的说明）。
// =============================================================================
import SwiftUI
import CoreLocation

// MARK: - 数学小工具（顶层私有，只服务本文件）
private func skyRad(_ deg: Double) -> Double { deg * .pi / 180 }
private func skyDeg(_ rad: Double) -> Double { rad * 180 / .pi }
private func skyClamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { min(max(v, lo), hi) }
private func skyLerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }

// MARK: - 光名
/// 这一刻属于哪个"光名"。阈值取自样品版，且是**按太阳高度角**切的，不是按钟点 ——
/// 同一时刻在不同纬度就是不同的光。
enum SkyPhase: String {
    /// 太阳高过 30°：头顶光，影子最短
    case day
    /// 8°…30°：斜射，地面开始有影子的方向
    case lowSun
    /// 0°…8°：贴着地平线，全天色温最暖
    case horizon
    /// −6°…0°：民用暮光，还能看清路
    case civil
    /// −15°…−6°：蓝调，天空比地面亮
    case blueHour
    /// 低于 −15°：真正的深夜，剩下的是城市辉光
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

    /// 一句话说清这一刻的光**为什么**是这样（印在界面上，不是给内部看的注释）
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

// MARK: - 太阳位置
/// 一个太阳位置（度）。纬度 39.99 的北京，正午大约 50°，这是可复算的事实。
struct SolarFix {
    /// 高度角（度）：地平线以上为正
    let altitude: Double
    /// 方位角（度）：正北为 0，顺时针（东 90 / 南 180 / 西 270）
    let azimuth: Double
}

/// NOAA 简化算法。纯数学、不联网、可复算 —— 这就是"光"能被信任的原因。
enum SolarMath {
    /// 给定时刻与经纬度，算太阳在哪。
    /// 步骤：儒略日 → 太阳平近点角/黄道经度 → 赤纬 → 时差 → 真太阳时 → 高度角/方位角。
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

// MARK: - 一条"为什么现在是这个光"的事实
/// 界面上的「光」表就是若干条这个。`note` 里写清**规则**（我定的）还是**事实**（算出来的）。
struct SkyFact: Identifiable {
    let id: String
    let label: String
    let value: String
    /// 这条是怎么来的
    let note: String
}

// MARK: - 光
/// 这一屏的光。全部数值都由下面的规则从太阳位置算出 —— 没有一处是"配"出来的。
struct SkyLight {

    // MARK: 云量 → 衰减
    /// 云量对辐照度的衰减：G = G_晴空 × (1 − 0.75 × N^3.4)，N = 云量（0…1）。
    /// 这是**公开发表的经验近似**（Kasten–Czeplak 云量-辐照度关系的常用形式），
    /// 不是实测：它把"阴天更暗"变成一个可复算的数，而不是拍脑袋的乘系数。
    static func cloudAttenuation(cloudCover: Double) -> Double {
        let n = skyClamp(cloudCover / 100, 0, 1)
        return skyClamp(1 - 0.75 * pow(n, 3.4), 0, 1)
    }
    /// 光名
    let phase: SkyPhase
    /// 太阳高度角（度）—— 天文事实
    let altitude: Double
    /// 太阳方位角（度）—— 天文事实
    let azimuth: Double
    /// 晴空辐照度（W/m²）
    /// **晴空模型**：1050 × sin(高度角)。真实辐照度会被云削掉一大半，
    /// 而 App 里没有天气数据源 —— 所以这里写"晴空"，不写"实测"。
    let clearSky: Double
    /// **全天空辐照度**（W/m²）= 晴空模型 × 云量衰减。
    /// 有天气实况时它是"按实况云量折算"的值，没有时它等于 `clearSky`。
    /// 界面模式与车灯都用它 —— 阴天的正午确实更暗，这是真实效果，不是装饰。
    let radiation: Double
    /// 天气实况（取不到就是 nil —— 界面照实写「无天气数据」）
    let weather: SkyWeather?
    /// 车灯亮度 0…1（设计规则：1 − 辐照度/220 —— 日照下不该开车灯）
    let lamp: Double
    /// 色温 −1（冷蓝）…+1（琥珀）（设计规则：贴近地平线→琥珀；地平线下越深→冷蓝）
    let warmth: Double
    /// 光池强度（设计规则：夜里是城市辉光，白天是阳光）
    let pool: Double
    /// 暗角强度（设计规则：日光下暗角退场）
    let vignette: Double
    /// 颗粒强度（设计规则：雾/雨/湿会加重颗粒）
    let grain: Double
    /// 光来的方向（单位向量的分量，屏幕坐标：x 向右为正、y 向下为正）
    let dirX: Double
    let dirY: Double
    /// 界面处在"日光模式（纸）"还是"夜行模式（深）"（设计规则：辐照度 > 150 W/m² 即日光）
    let isDaylight: Bool

    /// 方位角的说法（人话）：正北 / 东北 / 东 …
    var bearingText: String {
        let names = ["北", "东北", "东", "东南", "南", "西南", "西", "西北"]
        let idx = Int((azimuth.truncatingRemainder(dividingBy: 360) + 360)
            .truncatingRemainder(dividingBy: 360) / 45 + 0.5) % 8
        return names[idx] + " " + "\(Int(azimuth.rounded()))°"
    }

    /// 天气的一句话（没有数据就是 nil —— 调用方据此决定显不显示）
    func weatherNote(at now: Date) -> String? {
        guard let w = weather else { return nil }
        let wet = w.precipitation > 0.05 ? " · \(w.precipitationText)" : ""
        return "\(w.codeText) \(w.cloudText) 云\(wet)"
    }

    /// 界面上的「光」表。**一行一行都是可复算的**，规则也写在值旁边。
    var facts: [SkyFact] { facts(at: Date()) }

    /// 与 `facts` 相同，只是"现在"由调用方给（时间戳要能复算，不能自己偷看时钟）。
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

    /// 把「看几点」换成一个今天的具体时刻。`hour == nil` 就是此刻（实时）。
    /// 时区用设备本地 —— 滑块是「假设性时刻」的工具，界面上照实写它是按你所在时区。
    static func date(hour: Int?, from now: Date) -> Date {
        guard let hour else { return now }
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: now)
        comps.hour = hour
        comps.minute = 0
        comps.second = 0
        return cal.date(from: comps) ?? now
    }

    /// 由车的位置与此刻算光。**没有位置就没有光**（不拿设备位置冒充车的位置）。
    static func now(at date: Date,
                    coordinate: CLLocationCoordinate2D,
                    weather: SkyWeather? = nil) -> SkyLight {
        let fix = SolarMath.fix(at: date, coordinate: coordinate)
        let alt = fix.altitude
        let azimuth = (fix.azimuth.truncatingRemainder(dividingBy: 360) + 360)
            .truncatingRemainder(dividingBy: 360)

        // ---- ① 有多少光：晴空模型 × 云量衰减 ----
        // 没有天气实况时衰减系数是 1：辐照度就等于晴空模型（界面写明"不是实测"）。
        let clearRadiation = max(0, 1050 * sin(skyRad(alt)))
        let attenuation = weather.map { cloudAttenuation(cloudCover: $0.cloudCover) } ?? 1
        let radiation = clearRadiation * attenuation

        // ---- ② 界面模式：不过渡，直接换 ----
        // 为什么不做连续插值：早先版本用线性混合，08:00 时背景 rgb(142,138,132)、
        // 文字 rgb(122,119,113) —— 「深色↔纸色」线性混合会经过一段灰泥，文字几乎不可读。
        // 所以亮度不过渡（模式直接换），色温仍然连续。
        let tt = skyClamp((radiation - 95) / 110, 0, 1)
        let lightAmount = tt * tt * (3 - 2 * tt)
        let daylight = lightAmount >= 0.5

        // ---- ③ 色温 ----
        var warmth = 0.0
        if alt > -3 {
            warmth = skyClamp(1 - abs(alt) / 14, 0, 1)      // 贴近地平线最暖
        } else {
            // 蓝调是"暮光"现象：-6° 附近最强，越往深夜越退回中性
            warmth = -skyClamp((alt + 21) / 15, 0, 1)
        }

        // ---- ④ 光的方向：由**高度角**决定，不是亮度 ----
        // 为什么强调这一点：用亮度算的话，18:00（太阳高度 1.8°）的方向性会只剩 90px，
        // 而恰恰日出日落才是影子最长、光最有方向的时候。
        let hasSun = skyClamp((alt + 6) / 4, 0, 1)
        let radius = skyLerp(90, 340 * (1 - skyClamp(alt / 60, 0, 1)), hasSun)
        let dirX = sin(skyRad(azimuth)) * radius
        let dirY = -cos(skyRad(azimuth)) * radius

        // ---- ⑤ 光池强度 ----
        let sunPresence = skyClamp((alt + 8) / 20, 0, 1)
        let pool = skyLerp(0.10, 0.20, max(sunPresence, lightAmount))

        // ---- ⑥ 车灯 ----
        let lamp = skyClamp(1 - radiation / 220, 0.05, 1)

        // ---- ⑦ 暗角 / 颗粒 ----
        let vignette = skyLerp(0.62, 0.14, lightAmount)
        // 颗粒的底子是"夜里比白天多一点"，降水再往上加 —— 湿的街面会脏，脏的就是颗粒。
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
