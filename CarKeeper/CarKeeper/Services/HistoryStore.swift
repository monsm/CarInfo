import Foundation

// =============================================================================
//  HistoryStore — 车端数据的时间序列（真实采样 · 落盘）
// =============================================================================
//  为什么必须有这一层：
//  服务端**只有当前状态**接口 —— getControlStatus / charge/info / carcheck / pm25
//  全部是一次性快照，小程序里也没有任何历史接口（我逐个核过 pages/ 与 utils/）。
//  所以曲线只能由 App 自己在每次成功拿到车端数据时采样、按间隔落盘。
//
//  ⚠️ 不要拿 `AppStore.energyHistory` 画趋势图：那是一个「20 条 / 60 秒」的实时缓冲，
//  专门用来算瞬时变化率。之前 BatteryView 的「本周 / 本月」折线图读的就是它 ——
//  于是永远只有最近 60 秒的数据，画出来是空的或一条直线。三条曲线现在都读这里。
//
//  采样规则（都是"够用就好"，不是越密越好）：
//    · SOC：每 5 分钟一次；或电量变化 ≥ 2%（充电时会更快地留下点）
//    · 充电功率：只在充电中记录，每 1 分钟一次
//    · 胎压：每 30 分钟一次；或任一胎变化 ≥ 5 kPa（补气 / 慢漏气能看出来）
// =============================================================================

final class HistoryStore {
    static let shared = HistoryStore()

    // MARK: - 数据结构

    struct Point: Codable, Identifiable {
        var id = UUID()
        let t: Date
        let v: Double
    }

    struct TyrePoint: Codable, Identifiable {
        var id = UUID()
        let t: Date
        let fl: Double?
        let fr: Double?
        let rl: Double?
        let rr: Double?

        /// 四条轮位的 (名称, 值) —— 顺序与车况页的胎压格子一致
        var values: [(name: String, v: Double)] {
            [("左前", fl), ("右前", fr), ("左后", rl), ("右后", rr)].compactMap { name, v in
                v.map { (name, $0) }
            }
        }
    }

    // MARK: - 采样参数（界面上的说明文字也引用这些值，避免两处对不上）

    static let socInterval: TimeInterval = 5 * 60
    static let powerInterval: TimeInterval = 60
    static let tyreInterval: TimeInterval = 30 * 60
    static let socJump = 2.0        // % —— 变化超过它立刻留一个点
    static let tyreJump = 5.0       // kPa

    private let socCap = 2000       // 5 分钟一个 ≈ 7 天
    private let powerCap = 1500     // 1 分钟一个 ≈ 25 小时的充电曲线
    private let tyreCap = 760       // 30 分钟一个 ≈ 16 天

    private let socKey = "carkeeper_hist_soc_v1"
    private let powerKey = "carkeeper_hist_power_v1"
    private let tyreKey = "carkeeper_hist_tyre_v1"

    // MARK: - 数据

    private(set) var soc: [Point] = []
    private(set) var power: [Point] = []
    private(set) var tyre: [TyrePoint] = []

    private var dirty = false
    private var lastSave = Date.distantPast
    private let saveThrottle: TimeInterval = 20

    private init() {
        load()
    }

    // MARK: - 采样（唯一的写入口）

    /// 每次成功拿到车端数据后调用。
    /// - Parameters:
    ///   - socPct: 剩余电量 %
    ///   - charging: 是否在充电
    ///   - powerKW: 充电功率 kW（未上报传 nil）
    ///   - tyres: 四轮胎压 kPa，顺序：左前 / 右前 / 左后 / 右后（未上报传 nil）
    func record(socPct: Int, charging: Bool, powerKW: Double?, tyres: [Double?]) {
        let now = Date()

        // ---- SOC ----
        if socPct > 0 {
            let due = soc.last == nil || now.timeIntervalSince(soc.last!.t) >= Self.socInterval
            let jumped = soc.last.map { abs(Double(socPct) - $0.v) >= Self.socJump } ?? false
            if due || jumped {
                soc.append(Point(t: now, v: Double(socPct)))
                trim(&soc, cap: socCap)
                dirty = true
            }
        }

        // ---- 充电功率（只在充电中记：不充电时功率本就没有意义）----
        if charging, let p = powerKW, p > 0.05 {
            if power.last == nil || now.timeIntervalSince(power.last!.t) >= Self.powerInterval {
                power.append(Point(t: now, v: p))
                trim(&power, cap: powerCap)
                dirty = true
            }
        }

        // ---- 胎压 ----
        if tyres.contains(where: { $0 != nil }) {
            let due = tyre.last == nil || now.timeIntervalSince(tyre.last!.t) >= Self.tyreInterval
            let changed = tyre.last.map { old -> Bool in
                let olds = [old.fl, old.fr, old.rl, old.rr]
                for i in 0..<4 {
                    if let a = olds[i], let b = i < tyres.count ? tyres[i] : nil,
                       abs(a - b) >= Self.tyreJump { return true }
                }
                return false
            } ?? false
            if due || changed {
                tyre.append(TyrePoint(t: now,
                                      fl: at(tyres, 0), fr: at(tyres, 1),
                                      rl: at(tyres, 2), rr: at(tyres, 3)))
                trim(&tyre, cap: tyreCap)
                dirty = true
            }
        }
        maybeSave(now)
    }

    private func at(_ values: [Double?], _ idx: Int) -> Double? {
        idx < values.count ? values[idx] : nil
    }

    // MARK: - 查询

    func socSeries(hours: Double) -> [Point] { filter(soc, hours: hours) }
    func powerSeries(hours: Double) -> [Point] { filter(power, hours: hours) }
    func tyreSeries(hours: Double) -> [TyrePoint] {
        guard let cut = Calendar.current.date(byAdding: .second, value: Int(-hours * 3600), to: Date()) else { return tyre }
        return tyre.filter { $0.t >= cut }
    }

    private func filter(_ points: [Point], hours: Double) -> [Point] {
        guard let cut = Calendar.current.date(byAdding: .second, value: Int(-hours * 3600), to: Date()) else { return points }
        return points.filter { $0.t >= cut }
    }

    var socCount: Int { soc.count }
    var powerCount: Int { power.count }
    var tyreCount: Int { tyre.count }

    var firstSample: Date? { [soc.first?.t, power.first?.t, tyre.first?.t].compactMap { $0 }.min() }

    // MARK: - 清理（退出登录用：这些同样绑定账号）

    func clear() {
        soc = []; power = []; tyre = []
        UserDefaults.standard.removeObject(forKey: socKey)
        UserDefaults.standard.removeObject(forKey: powerKey)
        UserDefaults.standard.removeObject(forKey: tyreKey)
    }

    // MARK: - 落盘

    private func trim<T>(_ array: inout [T], cap: Int) {
        if array.count > cap { array.removeFirst(array.count - cap) }
    }

    private func maybeSave(_ now: Date) {
        guard dirty, now.timeIntervalSince(lastSave) >= saveThrottle else { return }
        save()
        dirty = false
        lastSave = now
    }

    private func save() {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .secondsSince1970
        if let d = try? enc.encode(soc) { UserDefaults.standard.set(d, forKey: socKey) }
        if let d = try? enc.encode(power) { UserDefaults.standard.set(d, forKey: powerKey) }
        if let d = try? enc.encode(tyre) { UserDefaults.standard.set(d, forKey: tyreKey) }
    }

    private func load() {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .secondsSince1970
        if let d = UserDefaults.standard.data(forKey: socKey), let v = try? dec.decode([Point].self, from: d) { soc = v }
        if let d = UserDefaults.standard.data(forKey: powerKey), let v = try? dec.decode([Point].self, from: d) { power = v }
        if let d = UserDefaults.standard.data(forKey: tyreKey), let v = try? dec.decode([TyrePoint].self, from: d) { tyre = v }
    }
}
