import Foundation
import CoreGraphics


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
