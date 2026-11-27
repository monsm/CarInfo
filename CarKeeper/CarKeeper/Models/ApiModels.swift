import Foundation


func ciPick(_ dict: [String: Any]?, _ names: [String]) -> Any? {
    guard let dict, !dict.isEmpty else { return nil }
    var lower: [String: Any] = [:]
    for (k, v) in dict { lower[k.lowercased()] = v }
    for n in names {
        if let v = lower[n.lowercased()], v as? NSNull == nil {
            return v
        }
    }
    return nil
}

func ciString(_ dict: [String: Any]?, _ names: [String]) -> String? {
    guard let v = ciPick(dict, names) else { return nil }
    if let s = v as? String { return s }
    if let n = v as? NSNumber { return n.stringValue }
    return nil
}

func ciNumber(_ dict: [String: Any]?, _ names: [String]) -> Double? {
    guard let v = ciPick(dict, names) else { return nil }
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber { return n.doubleValue }
    if let s = v as? String { return Double(s) }
    return nil
}

func ciNumberInt(_ dict: [String: Any]?, _ names: [String]) -> Int? {
    guard let v = ciPick(dict, names) else { return nil }
    if let i = v as? Int { return i }
    if let n = v as? NSNumber { return n.intValue }
    if let d = v as? Double { return Int(d) }
    if let s = v as? String { return Int(s) }
    return nil
}

func ciBool(_ dict: [String: Any]?, _ names: [String]) -> Bool? {
    guard let v = ciPick(dict, names) else { return nil }
    if let b = v as? Bool { return b }
    if let s = v as? String {
        switch s.lowercased() {
        case "true", "1", "authed": return true
        case "false", "0", "unauth", "none": return false
        default: return nil
        }
    }
    if let n = v as? NSNumber { return n.boolValue }
    return nil
}

func ciArray(_ dict: [String: Any]?, _ names: [String]) -> [[String: Any]]? {
    guard let v = ciPick(dict, names) else { return nil }
    if let arr = v as? [[String: Any]] { return arr }
    if let arr = v as? [Any] { return arr.compactMap { $0 as? [String: Any] } }
    return nil
}

func ciObject(_ dict: [String: Any]?, _ names: [String]) -> [String: Any]? {
    guard let v = ciPick(dict, names) else { return nil }
    return v as? [String: Any]
}

func unwrapEntity(_ any: Any?) -> [String: Any]? {
    if let arr = any as? [Any] { return arr.compactMap { $0 as? [String: Any] }.first }
    guard let dict = any as? [String: Any] else { return nil }
    let wrapperKeys: Set<String> = ["carlocationresp", "data", "result", "entity", "row", "body"]
    if dict.count == 1, let (k, v) = dict.first, wrapperKeys.contains(k.lowercased()) {
        if let inner = v as? [String: Any] { return inner.isEmpty ? dict : inner }
        if let arr = v as? [Any] { return arr.compactMap { $0 as? [String: Any] }.first ?? dict }
    }
    return dict
}


func ciVal(_ cache: [String: Any?], _ key: String) -> [String: Any]? {
    (cache[key]) as? [String: Any]
}
func nestedObject(_ o: [String: Any]?, _ key: String) -> [String: Any]? {
    guard let o else { return nil }
    return (o[key]) as? [String: Any]
}

func cacheObject(_ cache: [String: Any?], _ key: String) -> [String: Any]? {
    (cache[key]) as? [String: Any]
}

func jsonToAny(_ text: String) -> [String: Any]? {
    jsonValue(text) as? [String: Any]
}

func jsonValue(_ text: String) -> Any? {
    guard let data = text.data(using: .utf8),
          let any = try? JSONSerialization.jsonObject(with: data, options: [.allowFragments])
    else { return nil }
    return any
}


struct TokenConfig: Codable {
    var accessToken: String
    var refreshToken: String
    var mobile: String
    var updateTime: String?
    var expiresAt: Date?
}



struct EnergyModel {
    var soc: String
    var socPct: Int
    var socCls: String
    var socWarn: String
    var range: String
    var chargeText: String
    var chargeCls: String
    var chargePct: String
    var charging: ChargingSession?
    var volt: String
    var amp: String
    var battTemp: String
    var insulate: String
    var online: OnlineState
    var updated: String
    var carName: String
    var timeToFull: String? = nil
    var timeToEmpty: String? = nil
}

struct ChargingSession {
    var start: String
    var end: String
    var durMin: String
    var power: String
    var timeToFull: String? = nil
}

struct DTCFault {
    let code: String
    let description: String
    let severity: String
}

enum DTCDictionary {
    static let faults: [DTCFault] = [
        DTCFault(code: "P0AAA", description: "电机控制器故障", severity: "bad"),
        DTCFault(code: "P0A01", description: "电机控制器内部温度过高", severity: "warn"),
        DTCFault(code: "P0A0A", description: "电机控制器直流母线过流", severity: "bad"),
        DTCFault(code: "P0A0B", description: "电机控制器直流母线过压", severity: "warn"),
        DTCFault(code: "P0A0C", description: "电机控制器直流母线欠压", severity: "bad"),
        DTCFault(code: "P0A0D", description: "电机控制器直流母线预充电失败", severity: "bad"),
        DTCFault(code: "P0A10", description: "电机控制器绝缘电阻过低", severity: "bad"),
        DTCFault(code: "P0A14", description: "电池管理系统通信故障", severity: "bad"),
        DTCFault(code: "P0A15", description: "电池管理系统温度传感器故障", severity: "warn"),
        DTCFault(code: "P0A17", description: "电池单体电压不一致超限", severity: "warn"),
        DTCFault(code: "P0A18", description: "电池 SOC 计算异常", severity: "warn"),
        DTCFault(code: "P0A19", description: "电池绝缘电阻过低", severity: "bad"),
        DTCFault(code: "P0A20", description: "电池加热系统故障", severity: "warn"),
        DTCFault(code: "P0A21", description: "电池冷却系统故障", severity: "warn"),
        DTCFault(code: "P0A22", description: "电池充电超时", severity: "warn"),
        DTCFault(code: "P0300", description: "随机/多缸检测不到点火", severity: "bad"),
        DTCFault(code: "P0301", description: "1 缸检测不到点火", severity: "bad"),
        DTCFault(code: "P0302", description: "2 缸检测不到点火", severity: "bad"),
        DTCFault(code: "P0303", description: "3 缸检测不到点火", severity: "bad"),
        DTCFault(code: "P0304", description: "4 缸检测不到点火", severity: "bad"),
        DTCFault(code: "P0401", description: "EGR 流通量不足", severity: "warn"),
        DTCFault(code: "P0420", description: "催化转化器效率低于阈值", severity: "warn"),
        DTCFault(code: "P0440", description: "燃油蒸发系统控制回路故障", severity: "warn"),
        DTCFault(code: "P0446", description: "燃油蒸发系统通风控制回路故障", severity: "info"),
        DTCFault(code: "C0035", description: "左前轮速传感器电路故障", severity: "bad"),
        DTCFault(code: "C0040", description: "右前轮速传感器电路故障", severity: "bad"),
        DTCFault(code: "C0110", description: "制动压力传感器电路故障", severity: "warn"),
        DTCFault(code: "C0200", description: "制动踏板位置传感器电路故障", severity: "warn"),
        DTCFault(code: "U0100", description: "与 ECM/PCM 通信丢失", severity: "bad"),
        DTCFault(code: "U0101", description: "与 TCM 通信丢失", severity: "warn"),
        DTCFault(code: "U0121", description: "与 ABS 模块通信丢失", severity: "warn"),
        DTCFault(code: "U0155", description: "与组合仪表通信丢失", severity: "warn"),
    ]

    static func lookup(_ code: String) -> DTCFault? {
        faults.first { $0.code.uppercased() == code.uppercased() }
    }

    static func translate(_ code: String) -> String {
        if let dtc = lookup(code) { return dtc.description }
        return "未知故障码（\(code)）"
    }
}

struct OnlineState {
    var text: String
    var cls: String
}

struct StatusChip: Identifiable {
    var id: String { label + text }
    let label: String
    let ok: Bool?
    let text: String
    let cls: String
}

struct DriveModel {
    var speed: String
    var mile: String
    var gear: String
    var gearSub: String
    var gearCls: String
    var motorTemp: String
    var batteryNote: String
    var isMoving: Bool
    var fireStatus: String?
}

struct ComfortModel {
    var acOn: Bool?
    var acText: String
    var acCls: String
    var seatD: String
    var seatP: String
    var pmIn: String
    var pmOut: String
    var cabinTemp: String
    var envTemp: String
    var purifier: String
}

struct TyreItem: Identifiable, Equatable {
    var id: String { label }
    let label: String
    let kpa: String
    let temp: String
    let cls: String
    let warn: Bool
}

struct TyreModel {
    var items: [TyreItem]
    var warnAny: Bool
    var alarmText: String
    var alarmCls: String
    var tempRange: String
}

struct LocModel {
    var addr: String
    var snap: String
    var gpsText: String
    var gpsCls: String
    var dir: String
    var deg: String
    var degNum: Int
    var satAlt: String
    var lat: String
    var lng: String
}

struct HealthSystem: Identifiable {
    var id: String { name }
    let name: String
    let statusCls: String
    let statusText: String
    let children: [HealthItem]
    var open: Bool
    var healthPct: Int {
        guard !children.isEmpty else { return statusCls == "ok" ? 100 : (statusCls == "warn" ? 60 : 20) }
        let scores = children.map { $0.statusCls == "ok" ? 100 : ($0.statusCls == "warn" ? 60 : 20) }
        let avg = CGFloat(scores.reduce(0, +)) / CGFloat(scores.count)
        return max(0, min(100, Int(avg)))
    }
}

struct HealthItem: Identifiable {
    var id: String { name + String(detect ?? "") }
    let name: String
    let statusCls: String
    let statusText: String
    let desc: String?
    let detect: String?
    let suggest: String?
}

struct HealthModel {
    var time: String
    var score: String
    var scorePct: Int
    var counts: [CountPill]
    var systems: [HealthSystem]
    var id: String?
    var checkId: String?
    var endTime: String?
    var vehicleStatus: String?
}

struct CountPill: Identifiable {
    var id: String { key }
    let key: String
    let n: String
    let cls: String

    var iconName: String {
        switch cls {
        case "ok": return "checkmark.circle.fill"
        case "warn": return "exclamationmark.triangle.fill"
        case "bad": return "xmark.octagon.fill"
        default: return "info.circle.fill"
        }
    }
}

struct UserVM {
    var name: String
    var avatar: String
    var mobile: String
    var authed: Bool
    var nickname: String
    var gender: String?
    var birthday: String?
    var lastLoginTime: String?
    var source: String?
}

struct VehicleSummary {
    var name: String
    var plate: String
    var vin: String
    var isNev: Bool
    var pinText: String
    var pinCls: String
    var model: String
    var color: String
    var insuranceEnd: String
    var insuranceDays: Int?
    var serviceEnd: String
    var serviceDays: Int?
    var serviceReminder: String? = nil
    var mileage: Int? = nil
}

struct FaultItem: Identifiable {
    var id: String { name + String(count) }
    let name: String
    let count: Int
    let codes: String
}

struct BatteryModel {
    var hasCtrl: Bool
    var hasChg: Bool
    var cellStats: CellStats?
    var cellMinNum: String?
    var cellMaxNum: String?
    var probeStats: CellStats?
    var diffV: Double?
    var diffT: Double?
    var subsystems: [SubSystem]
    var tempSubs: [TempSub]
    var motors: [MotorModel]
    var faults: [FaultItem]
    var faultTotal: Int
    var alarms: [String]
    var charging: ChargeDetail
}

struct CellStats {
    var min: Double
    var max: Double
    var avg: Double
    var count: Int
    var bars: [Double]
}

struct SubSystem {
    var num: String
    var count: String
    var volt: String
    var amp: String
    var vMin: String
    var vMax: String
}

struct TempSub {
    var num: String
    var count: String
    var tMin: String
    var tMax: String
}

struct MotorModel {
    var num: String
    var state: String
    var rpm: String
    var torque: String
    var temp: String
    var ctrlTemp: String
    var inputV: String
    var dcBus: String
}

struct ChargeDetail {
    var text: String = "--"
    var cls: String = ""
    var soc: String = "--"
    var range: String = "--"
    var power: String = "--"
    var durMin: String = "--"
    var start: String = "--"
    var end: String = "--"
    var powerLine: String = "--"
    var heating: String = "--"
    var reservation: String = "--"
    var reserveTime: String = "--"
    var timeToFull: String? = nil
}


struct DomainVerdict: Identifiable {
    var id: String { key }
    let key: String
    let label: String
    let url: String
    var cls: String
    var short: String
    var title: String
    var reasons: [Reason]
    var metrics: [Metric]
}

struct Reason: Identifiable {
    var id: String { t + cls }
    let t: String
    let cls: String
}

struct Metric: Identifiable {
    var id: String { k + v }
    let k: String
    let v: String
}

struct OverallVerdict {
    var cls: String
    var title: String
    var sub: String
}

struct Summary {
    var overall: OverallVerdict
    var domains: [DomainVerdict]
}
