import Foundation

// MARK: - Case-insensitive decoding
//
// 长安服务端返回的键大小写不固定（桌面版靠 .NET 的 PropertyNameCaseInsensitive 兜底），
// 这里用一个「先解码成 [String: Any] 再按 ciPick 取值」的宽松策略，避免 Codable 默认键策略不匹配。

/// 大小写不敏感取键：等价于小程序的 ciPick。dict 为 nil 时返回 nil。
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

// MARK: - 缓存桥接
// 缓存值是 [String: Any?]，取值后需要转成 [String: Any] 才能用 ci* 助手。

/// 从缓存字典里取某个键并转成对象。
func ciVal(_ cache: [String: Any?], _ key: String) -> [String: Any]? {
    (cache[key]) as? [String: Any]
}
/// 从对象里取嵌套对象（用于 Air 等）。
func nestedObject(_ o: [String: Any]?, _ key: String) -> [String: Any]? {
    guard let o else { return nil }
    return (o[key]) as? [String: Any]
}

/// 从缓存字典 [String: Any?] 里取某个键并转成 [String: Any]（用于 analysis / batteryModel 等
/// 直接操作缓存的地方，避免把 [String: Any?] 强转成 [String: Any] 失败）。
func cacheObject(_ cache: [String: Any?], _ key: String) -> [String: Any]? {
    (cache[key]) as? [String: Any]
}

/// 把 JSON 顶层对象（或字段）解析为 [String: Any]，供页面使用。
func jsonToAny(_ text: String) -> [String: Any]? {
    guard let data = text.data(using: .utf8),
          let any = try? JSONSerialization.jsonObject(with: data, options: [.allowFragments])
    else { return nil }
    return any as? [String: Any]
}

func jsonArray(_ text: String) -> [[String: Any]]? {
    guard let data = text.data(using: .utf8),
          let any = try? JSONSerialization.jsonObject(with: data, options: [.allowFragments])
    else { return nil }
    if let arr = any as? [[String: Any]] { return arr }
    if let arr = any as? [Any] { return arr.compactMap { $0 as? [String: Any] } }
    return nil
}

// MARK: - Token 持久化

struct TokenConfig: Codable {
    var accessToken: String
    var refreshToken: String
    var mobile: String
    var updateTime: String?
}

// MARK: - 页面模型（原始报文 → 可渲染结构）

struct CarSel: Identifiable {
    let id: String
    let name: String
    var car: [String: Any]?
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
    var voltAmp: String
    var battTemp: String
    var insulate: String
    var online: OnlineState
    var updated: String
    var carName: String
    // #1 充电倒计时（充电中时显示还需多久充满）
    var timeToFull: String? = nil
    // #2 SOC耗尽预测（未充电时显示预计剩余行驶时间）
    var timeToEmpty: String? = nil
    // #23 百公里能耗（kWh/100km）
    var avgConsumption: String? = nil
}

struct ChargingSession {
    var start: String
    var end: String
    var durMin: String
    var power: String
    // #1 计算出的充满倒计时
    var timeToFull: String? = nil
}

// #15 DTC故障码字典（常见故障码 → 中文描述）
struct DTCFault {
    let code: String
    let description: String
    let severity: String  // "info" / "warn" / "bad"
}

enum DTCDictionary {
    static let faults: [DTCFault] = [
        // 动力系统
        ("P0AAA", "电机控制器故障", "bad"),
        ("P0A01", "电机控制器内部温度过高", "warn"),
        ("P0A0A", "电机控制器直流母线过流", "bad"),
        ("P0A0B", "电机控制器直流母线过压", "warn"),
        ("P0A0C", "电机控制器直流母线欠压", "bad"),
        ("P0A0D", "电机控制器直流母线预充电失败", "bad"),
        ("P0A10", "电机控制器绝缘电阻过低", "bad"),
        // 储能系统
        ("P0A14", "电池管理系统通信故障", "bad"),
        ("P0A15", "电池管理系统温度传感器故障", "warn"),
        ("P0A17", "电池单体电压不一致超限", "warn"),
        ("P0A18", "电池 SOC 计算异常", "warn"),
        ("P0A19", "电池绝缘电阻过低", "bad"),
        ("P0A20", "电池加热系统故障", "warn"),
        ("P0A21", "电池冷却系统故障", "warn"),
        ("P0A22", "电池充电超时", "warn"),
        // 发动机系统
        ("P0300", "随机/多缸检测不到点火", "bad"),
        ("P0301", "1 缸检测不到点火", "bad"),
        ("P0302", "2 缸检测不到点火", "bad"),
        ("P0303", "3 缸检测不到点火", "bad"),
        ("P0304", "4 缸检测不到点火", "bad"),
        ("P0401", "EGR 流通量不足", "warn"),
        ("P0420", "催化转化器效率低于阈值", "warn"),
        ("P0440", "燃油蒸发系统控制回路故障", "warn"),
        ("P0446", "燃油蒸发系统通风控制回路故障", "info"),
        // 制动系统
        ("C0035", "左前轮速传感器电路故障", "bad"),
        ("C0040", "右前轮速传感器电路故障", "bad"),
        ("C0110", "制动压力传感器电路故障", "warn"),
        ("C0200", "制动踏板位置传感器电路故障", "warn"),
        // 通用
        ("U0100", "与 ECM/PCM 通信丢失", "bad"),
        ("U0101", "与 TCM 通信丢失", "warn"),
        ("U0121", "与 ABS 模块通信丢失", "warn"),
        ("U0155", "与组合仪表通信丢失", "warn"),
    ]

    static func lookup(_ code: String) -> DTCFault? {
        faults.first { $0.code.uppercased() == code.uppercased() }
    }

    static func translate(_ code: String) -> String {
        if let dtc = lookup(code) { return dtc.description }
        return "未知故障码（\(code)）"
    }

    static func severityColor(_ severity: String) -> String {
        switch severity {
        case "bad": return "bad"
        case "warn": return "warn"
        default: return "na"
        }
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

struct TyreItem: Identifiable {
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
    /// 计算健康百分比：ok=100, warn=60, bad=20，按子项加权平均
    var healthPct: Int {
        guard !children.isEmpty else { return statusCls == "ok" ? 100 : (statusCls == "warn" ? 60 : 20) }
        let scores = children.map { $0.statusCls == "ok" ? 100 : ($0.statusCls == "warn" ? 60 : 20) }
        return max(0, min(100, Int(scores.reduce(0, +) / CGFloat(scores.count))))
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
    /// 检测ID（CheckHistoryId）
    var checkId: String?
    /// 数据更新时间（CarDataUpdateTime）
    var endTime: String?
    /// 车辆状态（Status: normal/fault 等）
    var vehicleStatus: String?
}

struct CountPill: Identifiable {
    var id: String { key }
    let key: String
    let n: String
    let cls: String
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
    // #16 维保提醒
    var serviceReminder: String? = nil
    // #40 维保价格估算
    var mileage: Int? = nil  // 当前里程
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
    var text: String
    var cls: String
    var soc: String
    var range: String
    var power: String
    var durMin: String
    var start: String
    var end: String
    var powerLine: String
    var heating: String
    var reservation: String
    var reserveTime: String
}

// MARK: - 统一分析层（8 域 verdict + overall）

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
