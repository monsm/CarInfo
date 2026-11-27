import Foundation


final class HistoryStore {
    static let shared = HistoryStore()


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

        var values: [(name: String, v: Double)] {
            [("左前", fl), ("右前", fr), ("左后", rl), ("右后", rr)].compactMap { name, v in
                v.map { (name, $0) }
            }
        }
    }


    static let socInterval: TimeInterval = 5 * 60
    static let powerInterval: TimeInterval = 60
    static let tyreInterval: TimeInterval = 30 * 60
    static let socJump = 2.0
    static let tyreJump = 5.0

    private let socCap = 2000
    private let powerCap = 1500
    private let tyreCap = 760

    private let socKey = "carkeeper_hist_soc_v1"
    private let powerKey = "carkeeper_hist_power_v1"
    private let tyreKey = "carkeeper_hist_tyre_v1"


    private(set) var soc: [Point] = []
    private(set) var power: [Point] = []
    private(set) var tyre: [TyrePoint] = []

    private var dirty = false
    private var lastSave = Date.distantPast
    private let saveThrottle: TimeInterval = 20

    private init() {
        load()
    }


    func record(socPct: Int, charging: Bool, powerKW: Double?, tyres: [Double?]) {
        let now = Date()

        if socPct > 0 {
            let due = soc.last.map { now.timeIntervalSince($0.t) >= Self.socInterval } ?? true
            let jumped = soc.last.map { abs(Double(socPct) - $0.v) >= Self.socJump } ?? false
            if due || jumped {
                soc.append(Point(t: now, v: Double(socPct)))
                trim(&soc, cap: socCap)
                dirty = true
            }
        }

        if charging, let p = powerKW, p > 0.05 {
            if power.last.map({ now.timeIntervalSince($0.t) >= Self.powerInterval }) ?? true {
                power.append(Point(t: now, v: p))
                trim(&power, cap: powerCap)
                dirty = true
            }
        }

        if tyres.contains(where: { $0 != nil }) {
            let due = tyre.last.map { now.timeIntervalSince($0.t) >= Self.tyreInterval } ?? true
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


    func socSeries(hours: Double) -> [Point] { filter(soc, hours: hours) }
    func powerSeries(hours: Double) -> [Point] { filter(power, hours: hours) }

    private func filter(_ points: [Point], hours: Double) -> [Point] {
        guard let cut = Calendar.current.date(byAdding: .second, value: Int(-hours * 3600), to: Date()) else { return points }
        return points.filter { $0.t >= cut }
    }


    func clear() {
        soc = []; power = []; tyre = []
        UserDefaults.standard.removeObject(forKey: socKey)
        UserDefaults.standard.removeObject(forKey: powerKey)
        UserDefaults.standard.removeObject(forKey: tyreKey)
    }


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
