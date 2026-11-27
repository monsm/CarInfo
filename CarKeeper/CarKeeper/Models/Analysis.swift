import Foundation


enum AN {

    static let BAD = "bad", WARN = "warn", OK = "ok", NA = "na"

    static func stats(_ arr: [Double]) -> (min: Double, max: Double, avg: Double, count: Int)? {
        guard let mn = arr.min(), let mx = arr.max() else { return nil }
        let avg = arr.reduce(0, +) / Double(arr.count)
        return (mn, mx, avg, arr.count)
    }

    static func numberList(_ dict: [String: Any]?, _ key: String) -> [Double] {
        (ciPick(dict, [key]) as? [Any])?.compactMap { (v) -> Double? in
            if let s = v as? String { return Double(s) }
            if let n = v as? NSNumber { return n.doubleValue }
            return nil
        } ?? []
    }

    static func extremeText(_ arr: [Double], digits: Int, lowest: Bool) -> String {
        let v = lowest ? arr.min() : arr.max()
        return v.map { String(format: "%.\(digits)f", $0) } ?? "--"
    }

    static func barsOf(_ arr: [Double], maxBars: Int = 128) -> [Double] {
        let step = max(1, Int(ceil(Double(arr.count) / Double(maxBars))))
        var out: [Double] = []
        var i = 0
        while i < arr.count { out.append(arr[i]); i += step }
        return out
    }

    static func summarize(_ cache: [String: Any?], _ carRaw: [String: Any]?) -> Summary {
        let hasCtrl = cacheObject(cache, "control") != nil
        let control = cacheObject(cache, "control")
        var domains: [DomainVerdict] = []

        domains.append(batteryDomain(cache))
        domains.append(chargeDomain(cache))
        domains.append(bodyDomain(cache))
        domains.append(tyreDomain(cache))
        domains.append(climateDomain(cache))
        domains.append(powerDomain(cache))
        domains.append(safetyDomain(cache, control: control, hasCtrl: hasCtrl))
        domains.append(networkDomain(cache))
        domains.append(serviceDomain(cache, carRaw))

        let badN = domains.filter { $0.cls == BAD }.count
        let warnN = domains.filter { $0.cls == WARN }.count
        let overall: OverallVerdict
        if !hasCtrl {
            overall = OverallVerdict(cls: NA, title: "等待车辆数据", sub: "下拉刷新获取最新车况")
        } else if badN == 0 && warnN == 0 {
            let done = domains.filter { $0.cls != NA }.count
            overall = OverallVerdict(cls: OK, title: "一切正常", sub: "\(done) 个系统检查完毕")
        } else {
            let c: String = badN > 0 ? BAD : WARN
            overall = OverallVerdict(cls: c, title: "\(badN + warnN) 项需要注意",
                                     sub: "异常 \(badN) 项 · 关注 \(warnN) 项")
        }
        return Summary(overall: overall, domains: domains.filter { $0.key != "never" })
    }

    private static func batteryDomain(_ cache: [String: Any?]) -> DomainVerdict {
        let b = batteryModel(cache)
        var d = DomainVerdict(key: "battery", label: "电池", url: "/pages/battery/battery",
                              cls: NA, short: "--", title: "暂无数据", reasons: [], metrics: [])
        d.metrics.append(Metric(k: "SOC", v: (b.hasCtrl && !b.charging.soc.isEmpty && b.charging.soc != "--") ? "\(b.charging.soc)%" : "--"))
        if let dv = b.diffV { d.metrics.append(Metric(k: "压差", v: String(format: "%.3f", dv) + " V")) }
        if let dt = b.diffT { d.metrics.append(Metric(k: "温差", v: String(format: "%.1f", dt) + " ℃")) }
        if !b.hasCtrl { return d }
        d.cls = OK; d.short = "正常"; d.title = "电池状态正常"
        if !b.alarms.isEmpty {
            d.cls = BAD; d.short = "异常"
            d.title = "电池告警 \(b.alarms.count) 项"
            for a in b.alarms.prefix(3) { d.reasons.append(Reason(t: "\(a) 触发", cls: BAD)) }
        }
        let vf = b.faults.first { $0.name == "储能设备" }
        if let vf, vf.count > 0 {
            if d.cls != BAD { d.cls = BAD; d.short = "异常"; d.title = "储能设备故障码 \(vf.count) 条" }
            d.reasons.append(Reason(t: "储能故障码 \(vf.count) 条" + (vf.codes.isEmpty ? "" : "：" + vf.codes), cls: BAD))
        }
        if d.cls == OK, let dv = b.diffV, dv >= 0.05 {
            d.cls = WARN; d.short = "关注"; d.title = "单体一致性偏差"
            d.reasons.append(Reason(t: "压差 \(String(format: "%.3f", dv))V 偏高", cls: WARN))
        }
        if d.cls == OK, let dt = b.diffT, dt >= 8 {
            d.cls = WARN; d.short = "关注"; d.title = "电池温差偏大"
            d.reasons.append(Reason(t: "温差 \(String(format: "%.1f", dt))℃ 偏大", cls: WARN))
        }
        if d.cls == OK && d.reasons.isEmpty {
            d.reasons.append(Reason(t: "单体一致性正常，无告警", cls: OK))
        }
        if d.reasons.count > 3 { d.reasons.removeLast(d.reasons.count - 3) }
        return d
    }

    private static func chargeDomain(_ cache: [String: Any?]) -> DomainVerdict {
        let b = batteryModel(cache)
        let c = b.charging
        var d = DomainVerdict(key: "charge", label: "充电", url: "/pages/battery/battery",
                              cls: OK, short: "未充电", title: "未充电", reasons: [], metrics: [])
        if !b.hasChg { d.cls = NA; d.short = "--"; d.title = "暂无充电数据"; return d }
        let isChg = c.text == "充电中" || c.text == "即将充满"
        d.short = isChg ? "充电中" : "未充电"
        d.title = isChg ? "充电中 \(c.power)" : "未充电"
        if !c.power.isEmpty && c.power != "--" { d.metrics.append(Metric(k: "功率", v: c.power)) }
        if !c.reserveTime.isEmpty && c.reserveTime != "--" { d.metrics.append(Metric(k: "预约用车", v: c.reserveTime)) }
        if c.powerLine == "异常" {
            d.cls = WARN; d.short = "关注"; d.title = "电源线路异常"
            d.reasons.append(Reason(t: "电源线路状态异常，充电可能中断", cls: WARN))
        } else if c.powerLine != "--" {
            d.reasons.append(Reason(t: "电源线路正常", cls: OK))
        }
        return d
    }

    private static func bodyDomain(_ cache: [String: Any?]) -> DomainVerdict {
        let chips = VM.bodyStatus(cache)
        let bads = chips.filter { $0.cls == "bad" }
        let hasCtrl = cacheObject(cache, "control") != nil
        var d = DomainVerdict(key: "body", label: "车身", url: "",
                              cls: hasCtrl ? OK : NA, short: hasCtrl ? "正常" : "--",
                              title: hasCtrl ? "门窗锁正常" : "暂无数据", reasons: [], metrics: [])
        if !bads.isEmpty {
            d.cls = BAD; d.short = "异常"
            d.title = "车身 \(bads.count) 项未就绪"
            for c in bads.prefix(4) { d.reasons.append(Reason(t: "\(c.label)\(c.text)", cls: BAD)) }
        } else if hasCtrl {
            d.reasons.append(Reason(t: "车门 / 车窗 / 后备箱 / 天窗均已关闭", cls: OK))
        }
        return d
    }

    private static func tyreDomain(_ cache: [String: Any?]) -> DomainVerdict {
        let t = VM.tyreStatus(cache)
        var d = DomainVerdict(key: "tyre", label: "胎压", url: "",
                              cls: t.alarmCls, short: t.alarmCls == "bad" ? "异常" : (t.alarmCls == "ok" ? "正常" : "--"),
                              title: t.alarmText, reasons: [], metrics: [])
        for i in t.items {
            if i.warn { d.reasons.append(Reason(t: "\(i.label) 胎压异常", cls: BAD)) }
            if i.kpa != "--" && !i.kpa.isEmpty { d.metrics.append(Metric(k: i.label, v: "\(i.kpa) kPa")) }
        }
        if t.alarmCls == "ok" {
            if t.tempRange != "--" {
                d.reasons.append(Reason(t: "四轮胎压正常 · 胎温 \(t.tempRange)", cls: OK))
            } else if cacheObject(cache, "control") != nil {
                d.reasons.append(Reason(t: "四轮胎压正常", cls: OK))
            }
        }
        return d
    }

    private static func climateDomain(_ cache: [String: Any?]) -> DomainVerdict {
        let conf = VM.comfortStatus(cache)
        let hasCtrl = cacheObject(cache, "control") != nil
        var d = DomainVerdict(key: "climate", label: "座舱", url: "/pages/data/data?kind=env",
                              cls: hasCtrl ? OK : NA, short: hasCtrl ? "正常" : "--",
                              title: !hasCtrl ? "暂无数据" : (conf.acOn == nil ? "座舱状态正常" : (conf.acOn == true ? "空调运行中" : "空调已关闭")),
                              reasons: [], metrics: [])
        if conf.pmIn != "--" {
            d.metrics.append(Metric(k: "车内PM2.5", v: "\(conf.pmIn) μg/m³"))
            let pmIn = Double(conf.pmIn) ?? -1
            if pmIn >= 150 {
                d.cls = BAD; d.short = "异常"
                d.reasons.append(Reason(t: "车内 PM2.5 \(Int(pmIn)) μg/m³，建议开启内循环或净化", cls: BAD))
            } else if pmIn >= 75 {
                if d.cls != BAD { d.cls = WARN; d.short = "关注" }
                d.reasons.append(Reason(t: "车内 PM2.5 \(Int(pmIn)) μg/m³ 偏高", cls: WARN))
            }
        }
        if conf.cabinTemp != "--", let cabin = Double(conf.cabinTemp.replacingOccurrences(of: "℃", with: "")) {
            d.metrics.append(Metric(k: "车内温度", v: conf.cabinTemp))
            if cabin >= 35 || cabin <= 0 {
                if d.cls != BAD { d.cls = WARN; d.short = "关注" }
                d.reasons.append(Reason(t: "车内温度 \(conf.cabinTemp)，建议提前开启空调", cls: WARN))
            }
        }
        if d.cls == OK && hasCtrl && d.reasons.isEmpty {
            d.reasons.append(Reason(t: "温度 / 空气质量正常", cls: OK))
        }
        return d
    }

    private static func powerDomain(_ cache: [String: Any?]) -> DomainVerdict {
        let b = batteryModel(cache)
        var d = DomainVerdict(key: "power", label: "动力", url: "/pages/battery/battery",
                              cls: NA, short: "--", title: "暂无数据", reasons: [], metrics: [])
        let mf = b.faults.first { $0.name == "驱动电机" }
        if let m = b.motors.first {
            if m.rpm != "--" { d.metrics.append(Metric(k: "转速", v: "\(m.rpm) rpm")) }
            if m.torque != "--" { d.metrics.append(Metric(k: "扭矩", v: "\(m.torque) N·m")) }
            let t1 = Double(m.temp.replacingOccurrences(of: "℃", with: "")) ?? -1
            let t2 = Double(m.ctrlTemp.replacingOccurrences(of: "℃", with: "")) ?? -1
            let tMax = max(t1, t2)
            d.cls = OK; d.short = "正常"; d.title = "电机系统正常"
            if tMax >= 75 {
                d.cls = WARN; d.short = "关注"; d.title = "电机温度偏高"
                d.reasons.append(Reason(t: "电机 / 控制器温度 \(Int(tMax))℃", cls: WARN))
            } else if tMax >= 0 {
                d.reasons.append(Reason(t: "电机温度正常（\(Int(tMax))℃）", cls: OK))
            }
        }
        if let mf, mf.count > 0 {
            d.cls = BAD; d.short = "异常"; d.title = "驱动电机故障码 \(mf.count) 条"
            d.reasons.append(Reason(t: "电机故障码 \(mf.count) 条" + (mf.codes.isEmpty ? "" : "：" + mf.codes), cls: BAD))
        }
        if d.cls == NA && mf == nil { return DomainVerdict(key: "never", label: "", url: "", cls: NA, short: "", title: "", reasons: [], metrics: []) }
        return d
    }

    private static func safetyDomain(_ cache: [String: Any?], control: [String: Any]?, hasCtrl: Bool) -> DomainVerdict {
        let chips = VM.bodyStatus(cache)
        let bads = chips.filter { ($0.label == "制动" || $0.label == "气囊") && $0.cls == "bad" }
        var d = DomainVerdict(key: "safety", label: "安全", url: "/pages/health/health",
                              cls: hasCtrl ? OK : NA, short: hasCtrl ? "正常" : "--",
                              title: "安全系统正常", reasons: [], metrics: [])
        if !bads.isEmpty {
            d.cls = BAD; d.short = "异常"; d.title = "安全系统报警"
            for c in bads { d.reasons.append(Reason(t: "\(c.label)\(c.text)", cls: BAD)) }
        } else if hasCtrl {
            let ml = ciNumber(control, ["MaxAlarmLevel"])
            if let ml, ml > 0 {
                d.cls = WARN; d.short = "关注"; d.title = "存在报警等级 \(Int(ml))"
                d.reasons.append(Reason(t: "整车最高报警等级 \(Int(ml))", cls: WARN))
            } else {
                d.reasons.append(Reason(t: "制动 / 气囊系统正常", cls: OK))
            }
        }
        return d
    }

    private static func networkDomain(_ cache: [String: Any?]) -> DomainVerdict {
        let loc = VM.locStatus(cache)
        let e = VM.energy(cache, nil)
        let hasCtrl = cacheObject(cache, "control") != nil
        var d = DomainVerdict(key: "network", label: "网络", url: "",
                              cls: hasCtrl ? OK : NA, short: hasCtrl ? "在线" : "--",
                              title: hasCtrl ? "车辆在线" : "暂无数据", reasons: [], metrics: [])
        if hasCtrl {
            d.reasons.append(Reason(t: e.online.text, cls: e.online.cls == "ok" ? OK : WARN))
            if loc.gpsCls == "bad" {
                d.cls = WARN; d.short = "关注"
                d.reasons.append(Reason(t: "GPS 信号异常", cls: WARN))
            } else if loc.gpsCls == "ok" {
                d.reasons.append(Reason(t: "GPS 信号有效", cls: OK))
            }
            if !loc.satAlt.isEmpty && loc.satAlt != "--" { d.metrics.append(Metric(k: "卫星 / 海拔", v: loc.satAlt)) }
        }
        return d
    }

    private static func serviceDomain(_ cache: [String: Any?], _ carRaw: [String: Any]?) -> DomainVerdict {
        let car = carRaw
        let insDays: Int? = car.flatMap { VM.daysUntil(ciPick($0, ["InsuranceEndDate"])) }
        let srvDays: Int? = car.flatMap { VM.daysUntil(ciPick($0, ["TserviceEndtime"])) }
        var d = DomainVerdict(key: "service", label: "服务", url: "/pages/vehicle/vehicle",
                              cls: NA, short: "--", title: "暂无到期信息", reasons: [], metrics: [])
        if let insDays { d.metrics.append(Metric(k: "保险到期", v: insDays < 0 ? "已过 \(abs(insDays)) 天" : "剩 \(insDays) 天")) }
        if let srvDays { d.metrics.append(Metric(k: "服务到期", v: srvDays < 0 ? "已过 \(abs(srvDays)) 天" : "剩 \(srvDays) 天")) }
        if insDays == nil && srvDays == nil { return d }
        d.cls = OK; d.short = "正常"; d.title = "保险 / 服务未到期"
        let insExpired = insDays.map { $0 < 0 } ?? false
        let srvExpired = srvDays.map { $0 < 0 } ?? false
        if insExpired || srvExpired {
            d.cls = BAD; d.short = "异常"; d.title = "存在已到期项目"
            if insExpired { d.reasons.append(Reason(t: "保险已到期，请及时续保", cls: BAD)) }
            if srvExpired { d.reasons.append(Reason(t: "车辆服务已到期", cls: BAD)) }
        } else {
            let insSoon = insDays.map { $0 <= 30 } ?? false
            let srvSoon = srvDays.map { $0 <= 30 } ?? false
            if insSoon || srvSoon {
                d.cls = WARN; d.short = "关注"; d.title = "即将到期"
                if insSoon { d.reasons.append(Reason(t: "保险 \(insDays!) 天后到期", cls: WARN)) }
                if srvSoon { d.reasons.append(Reason(t: "服务 \(srvDays!) 天后到期", cls: WARN)) }
            } else {
                d.reasons.append(Reason(t: "保险 / 服务均在有效期内", cls: OK))
            }
        }
        return d
    }
}


func batteryModel(_ cache: [String: Any?]) -> BatteryModel {
    let control = cacheObject(cache, "control")
    let charge = cacheObject(cache, "charge")
    let hasCtrl = control != nil
    let hasChg = charge != nil

    func collect(_ listKey: String, _ itemKey: String) -> [Double] {
        guard hasCtrl, let list = ciArray(control, [listKey]) else { return [] }
        var out: [Double] = []
        for sub in list {
            let arr: [Any] = ciPick(sub, [itemKey]) as? [Any] ?? []
            for v in arr {
                let d: Double?
                if let s = v as? String { d = Double(s) }
                else if let n = v as? NSNumber { d = n.doubleValue }
                else { d = nil }
                if let d { out.append(d) }
            }
        }
        return out
    }
    let cells = collect("NevChargeSystemVoltageDtoList", "BatteryVoltage")
    let probes = collect("NevChargeSystemTemperatureDtoList", "ProbeTemperatures")

    func statsOf(_ arr: [Double]) -> CellStats? {
        guard let s = AN.stats(arr) else { return nil }
        return CellStats(min: s.min, max: s.max, avg: s.avg, count: s.count, bars: AN.barsOf(arr))
    }
    let cellStats = statsOf(cells)
    let probeStats = statsOf(probes)

    let diffV: Double? = {
        guard let hi = ciNumber(control, ["MaxVoltageBattery"]), let lo = ciNumber(control, ["MinVoltageBattery"]) else { return nil }
        return abs(hi - lo)
    }()
    let diffT: Double? = {
        guard let hi = ciNumber(control, ["MaxTemperatureValue"]), let lo = ciNumber(control, ["MinTemperatureValue"]) else { return nil }
        return abs(hi - lo)
    }()

    let motors: [MotorModel] = {
        guard hasCtrl else { return [] }
        let list = (ciArray(control, ["DriveMotorData"])?.isEmpty == false ? ciArray(control, ["DriveMotorData"])
            : (ciArray(control, ["MotorData"])?.isEmpty == false ? ciArray(control, ["MotorData"]) : nil)) ?? []
        return list.map { m in
            MotorModel(
                num: VM.n0(ciPick(m, ["Num"])) ?? "--",
                state: VM.s(ciPick(m, ["State"])) ?? "--",
                rpm: VM.n0(ciPick(m, ["RevolutionSpeed"])) ?? "--",
                torque: VM.n0(ciPick(m, ["Torque"])) ?? "--",
                temp: VM.n0(ciPick(m, ["Temperature"])) ?? "--",
                ctrlTemp: VM.n0(ciPick(m, ["ControllerTemperature"])) ?? "--",
                inputV: VM.n1(ciPick(m, ["ControllerInputVoltage"])) ?? "--",
                dcBus: VM.n0(ciPick(m, ["ControllerDcBusCurrent"])) ?? "--"
            )
        }
    }()

    func fault(_ name: String, _ countKey: String, _ codeKey: String) -> FaultItem {
        let n = ciNumber(control, [countKey]) ?? 0
        let code = VM.s(ciPick(control, [codeKey])) ?? ""
        return FaultItem(name: name, count: Int(max(0, n)), codes: code.isEmpty || code == "无" ? "" : code)
    }
    let faults: [FaultItem] = [
        fault("发动机", "EngineFaultCount", "EngineFaultCodes"),
        fault("驱动电机", "DriveMotorFaultCount", "DriveMotorFaultCodes"),
        fault("储能设备", "RechargeableStorageDevicesFaultCount", "RechargeableStorageDevicesFaultCodes"),
        fault("其他", "OtherFaultCount", "OtherFaultCodes")
    ]

    let alarms: [String] = VM.activeAlarms(cache)

    let chgSt = VM.s(ciPick(charge, ["ChrgStatus"])) ?? ""
    let chgText: String = switch chgSt {
    case "1": "充电中"
    case "2": "即将充满"
    case "3": "未在充电"
    default: "未充电"
    }
    let chgCls = (["1", "2"].contains(chgSt)) ? "ok" : ""

    let charging = ChargeDetail(
        text: chgText, cls: chgCls,
        soc: VM.n0(ciPick(charge, ["RemainPower"])) ?? "--",
        range: VM.n0(ciPick(charge, ["RemainedPowerMile"])) ?? VM.n0(ciPick(control, ["RemainedPowerMile"])) ?? "--",
        power: { let p = VM.chargePowerKW(charge, control); return p == nil ? "--" : "\(Int(p!)) kW" }(),
        durMin: VM.n0(ciPick(charge, ["ChargDeltMins"])) ?? "--",
        start: VM.s(ciPick(charge, ["ChargeStarttime"])) ?? "--",
        end: VM.s(ciPick(charge, ["ChargeStoptime"])) ?? "--",
        powerLine: ciNumber(charge, ["PowerLineStatus"]) == 0 ? "正常" : (hasChg ? "异常" : "--"),
        heating: ciNumber(charge, ["BatteryHeatingStatus"]) == 1 ? "开启" : (hasChg ? "关闭" : "--"),
        reservation: ciNumber(charge, ["ChargeReservationStatus"]) == 1 ? "已预约" : (hasChg ? "未预约" : "--"),
        reserveTime: VM.s(ciPick(charge, ["ReservationUseVehicleTime"])) ?? "--"
    )

    let subsystems: [SubSystem] = (ciArray(control, ["NevChargeSystemVoltageDtoList"]) ?? []).map { sub in
        SubSystem(
            num: VM.n0(ciPick(sub, ["ChildSystemNum"])) ?? "--",
            count: VM.n0(ciPick(sub, ["CurrentBatteryCount"])) ?? VM.n0(ciPick(sub, ["BatteryCount"])) ?? "--",
            volt: VM.n1(ciPick(sub, ["ChargeSystemVoltage"])) ?? "--",
            amp: VM.n0(ciPick(sub, ["ChargeSystemCurrent"])) ?? "--",
            vMin: AN.extremeText(AN.numberList(sub, "BatteryVoltage"), digits: 3, lowest: true),
            vMax: AN.extremeText(AN.numberList(sub, "BatteryVoltage"), digits: 3, lowest: false)
        )
    }
    let tempSubs: [TempSub] = (ciArray(control, ["NevChargeSystemTemperatureDtoList"]) ?? []).map { sub in
        TempSub(
            num: VM.n0(ciPick(sub, ["ChildSystemNum"])) ?? "--",
            count: VM.n0(ciPick(sub, ["ChargeTemperatureProbeNum"])) ?? "--",
            tMin: AN.extremeText(AN.numberList(sub, "ProbeTemperatures"), digits: 1, lowest: true),
            tMax: AN.extremeText(AN.numberList(sub, "ProbeTemperatures"), digits: 1, lowest: false)
        )
    }

    return BatteryModel(
        hasCtrl: hasCtrl, hasChg: hasChg,
        cellStats: cellStats,
        cellMinNum: VM.n0(ciPick(control, ["MinVoltageBatteryNum"])),
        cellMaxNum: VM.n0(ciPick(control, ["MaxVoltageBatteryNum"])),
        probeStats: probeStats,
        diffV: diffV, diffT: diffT,
        subsystems: subsystems, tempSubs: tempSubs,
        motors: motors, faults: faults,
        faultTotal: faults.reduce(0) { $0 + $1.count },
        alarms: alarms, charging: charging
    )
}
