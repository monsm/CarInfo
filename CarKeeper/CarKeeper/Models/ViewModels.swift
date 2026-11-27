import Foundation


enum VM {

    static func vnum(_ v: Any?) -> Double? {
        if v == nil { return nil }
        if let s = v as? String, s.isEmpty { return nil }
        if let n = v as? NSNumber { return n.doubleValue }
        if let s = v as? String { return Double(s) }
        if let d = v as? Double { return d }
        if let i = v as? Int { return Double(i) }
        return nil
    }
    static func n0(_ v: Any?) -> String? {
        guard let x = vnum(v) else { return nil }
        return String(Int(x.rounded()))
    }
    static func n1(_ v: Any?) -> String? {
        guard let x = vnum(v) else { return nil }
        return String(format: "%.1f", x)
    }
    static func dash(_ v: Any?) -> String? {
        guard let v else { return nil }
        if v is NSNull { return nil }
        if let s = v as? String { return s.isEmpty ? nil : s }
        return "\(v)"
    }
    static func num(_ v: Any?) -> Double {
        vnum(v) ?? 0
    }
    static func s(_ v: Any?, _ dflt: String = "") -> String? {
        guard let v else { return nil }
        if v is NSNull { return nil }
        if let s = v as? String { return s.isEmpty ? nil : s }
        if let n = v as? NSNumber { return n.stringValue }
        return "\(v)"
    }

    static func daysUntil(_ str: Any?) -> Int? {
        guard let t0 = s(str) else { return nil }
        let t = t0.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        let d = parseDate(t)
        guard let d else { return nil }
        let diff = Int(ceil((d.timeIntervalSinceNow) / 86400))
        return diff
    }

    private static func parseDate(_ t: String) -> Date? {
        let formats = ["yyyy-MM-dd HH:mm:ss", "yyyy/MM/dd HH:mm:ss",
                       "yyyy-MM-dd", "yyyy/M/d", "yyyy.MM.dd", "yyyyMMdd", "yyyy年M月d日"]
        return DateText.shared.date(t, formats: formats, locale: "zh_CN",
                                     timeZone: DateText.serverTimeZone)
    }

    static func carSel(_ cars: [[String: Any]], _ carId: String) -> (options: [(id: String, name: String)], index: Int, car: [String: Any]?, count: Int) {
        let options = cars.map { c in
            let cname = s(ciPick(c, ["CarName"])) ?? ""
            let plate = s(ciPick(c, ["PlateNumber"])) ?? ""
            let name = "\(cname) \(plate)".trimmingCharacters(in: .whitespaces)
            let id = s(ciPick(c, ["CarId"])) ?? ""
            return (id, name)
        }
        var idx = options.firstIndex { $0.0 == carId } ?? 0
        if idx < 0 { idx = 0 }
        return (options, idx, idx < cars.count ? cars[idx] : nil, cars.count)
    }

    static func reportAge(_ control: [String: Any]?) -> (text: String, minutes: Int, stale: Bool)? {
        guard let d = serverDate(ciPick(control, ["LastUpdatedTime"]))
                ?? serverDate(ciPick(control, ["DeviceTime"])) else { return nil }
        let mins = Int(Date().timeIntervalSince(d) / 60)
        guard mins >= 0 else { return nil }
        let text: String
        if mins < 2 { text = "刚刚" }
        else if mins < 60 { text = "\(mins) 分钟前" }
        else if mins < 60 * 24 { text = "\(mins / 60) 小时前" }
        else { text = "\(mins / (60 * 24)) 天前" }
        return (text, mins, mins >= 30)
    }

    static func serverDate(_ v: Any?) -> Date? {
        guard let t = antiSentinel(v) else { return nil }
        return parseDate(String(t.prefix(19)))
    }

    static let alarmFlags: [(label: String, key: String)] = [
        ("电池总报警", "BatteryAlarm"), ("一致性差异", "BatteryConsistencyDifferenceAlarm"),
        ("绝缘报警", "InsulationAlarm"), ("高压互锁", "HighVoltageInterlockStateAlarm"),
        ("单体过压", "SingleBatteryOverVoltageAlarm"), ("单体欠压", "SingleBatteryUnderVoltageAlarm"),
        ("SOC 过低", "SocLowAlarm"), ("SOC 过高", "SocHighAlarm"), ("SOC 跳变", "SocJumpAlarm"),
        ("温差过大", "TemperatureDifferenceAlarm"), ("电机过热", "DriveMotorTemperatureAlarm"),
        ("控制器过热", "DriveMotorControllerTemperatureAlarm"), ("储能过压", "VehicleStorageDeviceOvervoltageAlarm"),
        ("储能欠压", "VehicleStorageDeviceUndervoltageAlarm"), ("储能不匹配", "RechargeableStorageDeviceMismatchAlarm"),
        ("过充保护", "VehiclePureDeviceTypeOvercharge")
    ]

    static func activeAlarms(_ cache: [String: Any?]) -> [String] {
        guard let control = cacheObject(cache, "control") else { return [] }
        return alarmFlags.compactMap { f in
            guard let x = ciNumber(control, [f.key]), x != 0 else { return nil }
            return f.label
        }
    }

    static func maxAlarmLevel(_ cache: [String: Any?]) -> Double? {
        guard let control = cacheObject(cache, "control"),
              let ml = ciNumber(control, ["MaxAlarmLevel"]), ml > 0 else { return nil }
        return ml
    }


    static func controlOutcome(status: String, handleCode: String) -> Bool? {
        _ = handleCode
        let s = status.lowercased()
        if ["success", "completed", "finish", "finished", "done"].contains(s) { return true }
        if ["runfailure", "failed", "fail", "timeout", "error"].contains(s) { return false }
        return nil
    }

    static func controlOutcomeText(_ outcome: Bool?) -> String {
        switch outcome {
        case true: return "执行成功"
        case false: return "执行失败"
        case nil: return "车端已回执"
        }
    }

    static func chargePowerKW(_ charge: [String: Any]?, _ control: [String: Any]?) -> Double? {
        if let p = ciNumber(charge, ["ChargPower", "ChargingPower"]), p > 0.1 { return p }
        guard let v = ciNumber(control, ["TotalVoltage"]),
              let a = ciNumber(control, ["TotalCurrent"]), a > 0 else { return nil }
        return v * a / 1000.0
    }

    static func energy(_ cache: [String: Any?], _ car: [String: Any]?) -> EnergyModel {
        let control = ciVal(cache, "control")
        let charge = ciVal(cache, "charge")
        let hasCtrl = control != nil

        func vnumOf(_ o: [String: Any]?, _ names: [String]) -> Double? {
            o.flatMap { ciNumber($0, names) }
        }

        let socStr = vnumOf(charge, ["RemainPower"]).map { String(Int($0.rounded())) }
            ?? vnumOf(control, ["Soc"]).map { String(Int($0.rounded())) }
            ?? "--"
        let socNum = Double(socStr) ?? 0
        let socPct = max(0, min(100, Int(socNum)))
        let chargeSt = s(ciPick(charge, ["ChrgStatus"])) ?? ""
        var chargeText = "未充电", chargeCls = "idle"
        switch chargeSt {
        case "1": chargeText = "充电中"; chargeCls = "ok"
        case "2": chargeText = "即将充满"; chargeCls = "ok"
        case "3": chargeText = "未在充电"; chargeCls = "idle"
        default: break
        }

        let range = vnumOf(charge, ["RemainedPowerMile"]).map { String(Int($0.rounded())) }
            ?? vnumOf(control, ["RemainedPowerMile"]).map { String(Int($0.rounded())) }
            ?? "--"
        let volt = hasCtrl ? "\(n1(ciPick(control, ["TotalVoltage"])) ?? "--") V" : "--"
        let amp = hasCtrl ? "\(n1(ciPick(control, ["TotalCurrent"])) ?? "--") A" : "--"
        let btLo = n0(ciPick(control, ["MinTemperatureValue"]))
        let btHi = n0(ciPick(control, ["MaxTemperatureValue"]))
        let battTemp = (hasCtrl && btLo != nil && btHi != nil) ? "\(btLo!) ~ \(btHi!)℃" : "--"
        let insulate = hasCtrl ? "\(n0(ciPick(control, ["InsulateResistance"])) ?? "--") Ω" : "--"

        var charging: ChargingSession?
        if chargeSt == "1" || chargeSt == "2" {
            let pow = chargePowerKW(charge, control)
            charging = ChargingSession(
                start: dash(ciPick(charge, ["ChargeStarttime"])) ?? "--",
                end: dash(ciPick(charge, ["ChargeStoptime"])) ?? "--",
                durMin: n0(ciPick(charge, ["ChargDeltMins"])) ?? "--",
                power: pow == nil ? "--" : "\(Int(pow!)) kW"
            )
        }

        var online = OnlineState(text: "离线", cls: "bad")
        var updated = "--"
        if let c = control, ciPick(c, ["LastUpdatedTime"]) != nil {
            let control = c
            if let age = reportAge(control) {
                updated = "车端 \(age.text)上报"
                online = OnlineState(text: "在线 · \(updated)", cls: age.stale ? "warn" : "ok")
            } else {
                let devT = s(ciPick(control, ["DeviceTime"])) ?? ""
                updated = devT.count > 10 ? devT : nowText()
                online = OnlineState(text: "在线 · \(updated)", cls: "ok")
            }
        }

        let carName: String
        if let car {
            let cv = car
            let cname = s(ciPick(cv, ["CarName"])) ?? ""
            let plate = s(ciPick(cv, ["PlateNumber"])) ?? ""
            carName = "\(cname) \(plate)".trimmingCharacters(in: .whitespaces)
        } else {
            carName = "未绑定车辆"
        }

        var timeToFull: String? = nil
        if chargeSt == "1" || chargeSt == "2" {
            if let powerKw = chargePowerKW(charge, control), powerKw > 0.1, socPct < 100 {
                let minutes = Int(Double(100 - socPct) / powerKw * 60)
                if minutes > 0 {
                    let h = minutes / 60
                    let m = minutes % 60
                    timeToFull = h > 0 ? "约\(h)小时\(m)分钟" : "约\(m)分钟"
                    charging?.timeToFull = timeToFull
                }
            }
        }
        var timeToEmpty: String? = nil
        if let r = Double(range), r > 0, socPct > 0 {
            let hoursToEmpty = Int(r / 40.0)
            if hoursToEmpty > 0 {
                timeToEmpty = "约\(hoursToEmpty)小时"
            }
        }

        return EnergyModel(
            soc: socStr, socPct: socPct,
            socCls: socPct >= 15 ? "ok" : "bad", socWarn: (socPct < 30 && socPct >= 15) ? "low" : "",
            range: range, chargeText: chargeText, chargeCls: chargeCls,
            chargePct: socStr == "--" ? "--" : socStr,
            charging: charging, volt: volt, amp: amp, battTemp: battTemp, insulate: insulate,
            online: online, updated: updated, carName: carName,
            timeToFull: timeToFull,
            timeToEmpty: timeToEmpty
        )
    }

    static func nowText() -> String {
        DateText.shared.string(Date(), "yyyy-MM-dd HH:mm:ss")
    }

    static func bodyStatus(_ cache: [String: Any?]) -> [StatusChip] {
        let control = ciVal(cache, "control")
        let hasCtrl = control != nil

        func mk(_ label: String, _ ok: Bool?, _ text: String) -> StatusChip {
            StatusChip(
                label: label,
                ok: hasCtrl ? ok : nil,
                text: hasCtrl ? text : "--",
                cls: (!hasCtrl || ok == nil) ? "na" : (ok == true ? "ok" : "bad")
            )
        }

        func mkValue(_ label: String, _ val: Double?, _ yes: String, _ no: String) -> StatusChip {
            let ok: Bool? = val.map { $0 == 0 }
            return mk(label, ok, ok == nil ? "无数据" : (ok! ? yes : no))
        }

        var chips: [StatusChip] = []
        chips.append(mkValue("车门", ciNumber(control, ["Door"]), "已关", "开启"))
        chips.append(mkValue("车窗", ciNumber(control, ["Window"]), "已关", "开启"))
        chips.append(mkValue("后备箱", ciNumber(control, ["Trunk"]), "已关", "开启"))
        chips.append(mkValue("天窗", ciNumber(control, ["Sunroof"]), "已关", "开启"))
        chips.append(mkValue("车锁", ciNumber(control, ["DriverDoorLock"]), "已锁", "未锁"))

        func guardChip(_ label: String, _ key: String) -> StatusChip {
            let x = ciNumber(control, [key])
            let good = x != nil && x == 0
            return mk(label, good, x == nil ? "--" : (good ? "正常" : "报警"))
        }
        chips.append(guardChip("制动", "BrakeSystemAlarm"))
        chips.append(guardChip("气囊", "AirbagSystemStatus"))
        return chips
    }

    static func driveStatus(_ cache: [String: Any?]) -> DriveModel {
        let control = ciVal(cache, "control")
        let hasCtrl = control != nil
        let location = ciVal(cache, "location")
        let speedRaw = ciPick(location, ["speed"])

        let motor: [String: Any]? = {
            guard let c = control else { return nil }
            if let drive = ciArray(c, ["DriveMotorData"]), !drive.isEmpty { return drive[0] }
            if let m = ciArray(c, ["MotorData"]), !m.isEmpty { return m[0] }
            return nil
        }()

        let gearCls = (hasCtrl && num(ciPick(control, ["ShiftPosition"])) != 0) ? "bad" : ""

        var note = ""
        if hasCtrl {
            let hi = ciNumber(control, ["MaxVoltageBattery"])
            let lo = ciNumber(control, ["MinVoltageBattery"])
            if let hi, let lo {
                note += "单体压差 \(String(format: "%.3f", abs(hi - lo)))V"
            }
            let ht = ciNumber(control, ["MaxTemperatureValue"])
            let lt = ciNumber(control, ["MinTemperatureValue"])
            if let ht, let lt {
                note += (note.isEmpty ? "" : "  ·  ") + "温差 \(ht - lt)℃"
            }
        }

        let t = ciNumber(motor, ["Temperature"])
        let ct = ciNumber(motor, ["ControllerTemperature"])

        let fireSt = ciString(control, ["FireStatus", "fireStatus"]) ?? ""
        let fireCN: [String: String] = ["1": "启动", "2": "熄火"]
        let fireStatus = fireSt.isEmpty ? "" : (fireCN[fireSt] ?? fireSt)
        return DriveModel(
            speed: location != nil ? (n0(speedRaw) ?? "--") : "--",
            mile: hasCtrl ? (n0(ciPick(control, ["TotalOdometer"])) ?? "--") : "--",
            gear: hasCtrl ? (num(ciPick(control, ["ShiftPosition"])) == 0 ? "P" : "D") : "--",
            gearSub: hasCtrl ? (num(ciPick(control, ["ShiftPosition"])) == 0 ? "驻车" : "行驶") : "",
            gearCls: gearCls,
            motorTemp: motor == nil ? "--" : "\(n0(t) ?? "--")℃ / \(n0(ct) ?? "--")℃",
            batteryNote: note,
            isMoving: location != nil && num(speedRaw) > 0,
            fireStatus: fireStatus
        )
    }

    static func comfortStatus(_ cache: [String: Any?]) -> ComfortModel {
        let control = ciVal(cache, "control")
        let hasCtrl = control != nil
        let pmRaw = ciVal(cache, "pm25")
        let air = nestedObject(control, "Air")
        let acOnFinal: Bool? = air == nil ? nil : (s(ciPick(air, ["Status"])) != "0")

        let pmInRaw = s(ciPick(pmRaw, ["Pm25InnnerCarValue"])) ?? ""
        let pmIn: String
        if pmInRaw == "-1" || pmInRaw.isEmpty { pmIn = "--" } else { pmIn = pmInRaw }
        let pmOut = s(ciPick(pmRaw, ["Pm25OuterCarValue"])) ?? "--"

        let vehTemp = ciNumber(pmRaw, ["VehicleTemperature"])
        let envT = ciNumber(pmRaw, ["EnvironmentalTemperature"])
        let purifier = ciNumber(control, ["AirPurifierStatus"])

        return ComfortModel(
            acOn: acOnFinal,
            acText: air == nil ? "暂无数据" : "\(acOnFinal == true ? "运行中" : "已关闭 · 上次设定") \(s(ciPick(air, ["Temperature"])) ?? "26")℃ · 风量\(s(ciPick(air, ["Wind"])) ?? "0")档",
            acCls: acOnFinal == nil ? "na" : (acOnFinal == true ? "ok" : "off"),
            seatD: hasCtrl ? "通风\(num(ciPick(control, ["DriverSeatAirStatus"])) == 1 ? "开" : "关") · 加热\(num(ciPick(control, ["DriverSeatHeatStatus"])) == 1 ? "开" : "关")" : "--",
            seatP: hasCtrl ? "通风\(num(ciPick(control, ["PassengerSeatAirStatus"])) == 1 ? "开" : "关") · 加热\(num(ciPick(control, ["PassengerSeatHeatStatus"])) == 1 ? "开" : "关")" : "--",
            pmIn: pmIn, pmOut: pmOut,
            cabinTemp: (vehTemp == nil || Int(vehTemp!) == 0) ? "--" : "\(Int(vehTemp!))℃",
            envTemp: (envT == nil || Int(envT!) == 0) ? "--" : "\(Int(envT!))℃",
            purifier: purifier == nil ? "--" : (purifier! == 1 ? "运行" : "关闭")
        )
    }

    static func tyreStatus(_ cache: [String: Any?]) -> TyreModel {
        let control = ciVal(cache, "control")
        let hasCtrl = control != nil

        func item(_ label: String, _ presKey: String, _ tempKey: String, _ warnKey: String) -> TyreItem {
            let w = ciNumber(control, [warnKey])
            let warn = (w != nil && w! > 0)
            return TyreItem(
                label: label,
                kpa: n0(ciPick(control, [presKey])) ?? "--",
                temp: n0(ciPick(control, [tempKey])) ?? "--",
                cls: hasCtrl ? (warn ? "bad" : "ok") : "na",
                warn: warn
            )
        }
        let items = [
            item("左前", "LfTyrePressure", "LeftFrontTireTemperature", "LfPressureWarning"),
            item("右前", "RfTyrePressure", "RightFrontTireTemperature", "RfPressureWarning"),
            item("左后", "LrTyrePressure", "LeftRearTireTemperature", "LrPressureWarning"),
            item("右后", "RrTyrePressure", "RightRearTireTemperature", "RrPressureWarning")
        ]
        let warnAny = items.contains { $0.warn }
        let temps: [Double] = control.flatMap { c -> [Double] in
            ["LeftFrontTireTemperature", "RightFrontTireTemperature",
             "LeftRearTireTemperature", "RightRearTireTemperature"]
                .compactMap { ciNumber(c, [$0]) }
        } ?? []
        let tempRange: String
        if temps.isEmpty { tempRange = "--" }
        else if let tmin = temps.min(), let tmax = temps.max() { tempRange = "\(Int(tmin)) ~ \(Int(tmax))℃" }
        else { tempRange = "--" }

        return TyreModel(
            items: items,
            warnAny: warnAny,
            alarmText: hasCtrl ? (warnAny ? "胎压异常" : "胎压正常") : "--",
            alarmCls: hasCtrl ? (warnAny ? "bad" : "ok") : "na",
            tempRange: tempRange
        )
    }

    static func locStatus(_ cache: [String: Any?]) -> LocModel {
        let control = ciVal(cache, "control")
        let locRaw = ciVal(cache, "location")
        let hasCtrl = control != nil
        let loc: [String: Any]? = {
            guard let locRaw else { return ciObject(ciVal(cache, "pm25"), ["CarLocationResp", "carLocationResp"]) }
            let hasAddr = !((ciString(locRaw, ["AddrDesc"]) ?? "").isEmpty)
            let hasCoord = ciNumber(locRaw, ["Lat"]) != nil && ciNumber(locRaw, ["Lng"]) != nil
            if hasAddr || hasCoord { return locRaw }
            return ciObject(ciVal(cache, "pm25"), ["CarLocationResp", "carLocationResp"]) ?? locRaw
        }()
        let gpsOk = ciBool(loc, ["ValidGps"])
        let heading = ciNumber(loc, ["Heading"])
        let deg = heading == nil ? 0 : norm360(heading!)
        let sat = ciNumber(control, ["SatNum"])
        let satAlt: String = (hasCtrl && sat != nil)
            ? "\(Int(sat!)) 颗 · 海拔 \(n1(ciPick(control, ["Alti"])) ?? "--") m"
            : "--"
        return LocModel(
            addr: ciString(loc, ["AddrDesc"]) ?? "",
            snap: s(ciPick(loc, ["LocationImgurl"])) ?? s(ciPick(loc, ["ThumbnailLocationImgUrl"])) ?? "",
            gpsText: gpsOk == nil ? "--" : (gpsOk! ? "GPS 信号有效" : "GPS 信号异常"),
            gpsCls: gpsOk == nil ? "na" : (gpsOk! ? "ok" : "bad"),
            dir: heading == nil ? "--" : directionText(deg),
            deg: heading == nil ? "--" : "\(Int(deg.rounded()))°",
            degNum: heading == nil ? 0 : Int(deg.rounded()),
            satAlt: satAlt,
            lat: s(ciPick(loc, ["Lat"])) ?? "--",
            lng: s(ciPick(loc, ["Lng"])) ?? "--"
        )
    }

    static func isMovingFast(_ cache: [String: Any?]) -> Bool {
        guard let location = ciVal(cache, "location") else { return false }
        return num(ciPick(location, ["speed"])) > 0
    }

    static func headingDegFast(_ cache: [String: Any?]) -> Double {
        let locRaw = ciVal(cache, "location")
        let loc: [String: Any]? = {
            guard let locRaw else { return ciObject(ciVal(cache, "pm25"), ["CarLocationResp", "carLocationResp"]) }
            let hasAddr = !((ciString(locRaw, ["AddrDesc"]) ?? "").isEmpty)
            let hasCoord = ciNumber(locRaw, ["Lat"]) != nil && ciNumber(locRaw, ["Lng"]) != nil
            if hasAddr || hasCoord { return locRaw }
            return ciObject(ciVal(cache, "pm25"), ["CarLocationResp", "carLocationResp"]) ?? locRaw
        }()
        guard let heading = ciNumber(loc, ["Heading"]) else { return 0 }
        return norm360(heading)
    }

    static func norm360(_ v: Double) -> Double {
        let n = v.truncatingRemainder(dividingBy: 360)
        return n < 0 ? n + 360 : n
    }

    static func directionText(_ angle: Double) -> String {
        let d = ["正北", "东北", "正东", "东南", "正南", "西南", "正西", "西北"]
        let idx = Int((norm360(angle) / 45).rounded()) % 8
        return d[(idx + 8) % 8]
    }

    static func healthModel(_ checkRaw: [String: Any]?) -> HealthModel? {
        guard let d = checkRaw else { return nil }
        let score = ciNumber(d, ["Score"])
        let map: [String: [String: String]] = [
            "normal": ["cls": "ok", "cn": "正常"], "ok": ["cls": "ok", "cn": "正常"],
            "fault": ["cls": "bad", "cn": "故障"], "abnormal": ["cls": "bad", "cn": "异常"],
            "warning": ["cls": "warn", "cn": "预警"], "risk": ["cls": "warn", "cn": "风险"]
        ]
        let details = ciArray(d, ["Details"]) ?? []
        let systems: [HealthSystem] = details.map { sys in
            let s2 = sys
            let children = (ciArray(s2, ["Child"]) ?? []).map { it in
                let st = (ciPick(it, ["Status"]) as? String ?? "").lowercased()
                let m: [String: String]
                if let found = map[st] { m = found }
                else if ciPick(it, ["Status"]) == nil { m = ["cls": "na", "cn": "未知"] }
                else { m = ["cls": "warn", "cn": s(ciPick(it, ["Status"])) ?? ""] }
                let name: String
                if let sn = s(ciPick(it, ["ItemName"])) { name = sn } else { name = "" }
                return HealthItem(
                    name: name,
                    statusCls: m["cls"] ?? "ok",
                    statusText: m["cn"] ?? "",
                    desc: ciPick(it, ["Description"]) as? String,
                    detect: ciPick(it, ["DetectValue"]) as? String,
                    suggest: ciPick(it, ["Suggest"]) as? String
                )
            }
            let hasBad = children.contains { $0.statusCls == "bad" }
            let hasWarn = children.contains { $0.statusCls == "warn" }
            let allUnknown = !children.isEmpty && children.allSatisfy { $0.statusCls == "na" }
            let sysCls = hasBad ? "bad" : (hasWarn ? "warn" : (allUnknown ? "na" : "ok"))
            let sysText = hasBad ? "故障" : (hasWarn ? "预警" : (allUnknown ? "未知" : "正常"))
            return HealthSystem(
                name: s(ciPick(s2, ["ItemName"])) ?? "",
                statusCls: sysCls,
                statusText: sysText,
                children: children,
                open: hasBad
            )
        }
        let timeStr: String
        if let ct = s(ciPick(d, ["CheckTime"])) { timeStr = ct } else { timeStr = "" }
        let idStr: String?
        if let cid = s(ciPick(d, ["CheckHistoryId"])) { idStr = cid } else { idStr = nil }
        let statusMap: [String: String] = ["normal": "正常", "fault": "故障", "warning": "预警", "risk": "风险", "abnormal": "异常", "ok": "正常"]
        let vehicleStatus = s(ciPick(d, ["Status"])).flatMap { statusMap[$0] ?? $0 }
        return HealthModel(
            time: timeStr,
            score: score == nil ? "--" : "\(Int(score!.rounded()))",
            scorePct: score == nil ? 0 : max(0, min(100, Int(score!.rounded()))),
            counts: [
                CountPill(key: "正常", n: n0(ciPick(d, ["NormalCount"])) ?? "--", cls: "ok"),
                CountPill(key: "风险", n: n0(ciPick(d, ["RiskCount"])) ?? "--", cls: "warn"),
                CountPill(key: "故障", n: n0(ciPick(d, ["FaultCount"])) ?? "--", cls: "bad")
            ],
            systems: systems,
            id: idStr,
            checkId: s(ciPick(d, ["CheckHistoryId"])),
            endTime: s(ciPick(d, ["CarDataUpdateTime"])),
            vehicleStatus: vehicleStatus
        )
    }

    static func userModel(_ uRaw: [String: Any]?) -> UserVM? {
        guard let u = uRaw else { return nil }
        let name = s(ciPick(u, ["UserFullname"]) ?? ciPick(u, ["UserNickname"])) ?? ""
        let nameFinal = name.isEmpty ? "车主" : name
        let mobile = s(ciPick(u, ["Mobile"])) ?? ""
        let authed = (ciBool(u, ["RealnameAuthed"]) ?? false)
        let nickname = s(ciPick(u, ["UserNickname"])) ?? ""
        let genderRaw = s(ciPick(u, ["Gender"])) ?? ""
        let genderCN: [String: String] = ["m": "男", "f": "女"]
        let gender = genderCN[genderRaw] ?? genderRaw
        let lastLogin = s(ciPick(u, ["LastLoginTime"])) ?? ""
        let lastLoginClean = lastLogin.replacingOccurrences(of: "\\.0$", with: "")
        let source = s(ciPick(u, ["Source"])) ?? ""
        return UserVM(
            name: nameFinal,
            avatar: (ciPick(u, ["UserNickname"]) as? String ?? nameFinal).prefix(1).uppercased() as String,
            mobile: mobile.count >= 11 ? String(mobile.prefix(3)) + "****" + String(mobile.suffix(4)) : (mobile.isEmpty ? "--" : mobile),
            authed: authed,
            nickname: nickname.isEmpty ? "未设置昵称" : nickname,
            gender: gender.isEmpty ? "" : gender,
            birthday: s(ciPick(u, ["Birthday"])) ?? "",
            lastLoginTime: (lastLoginClean.count > 10 ? String(lastLoginClean.suffix(10)) : lastLoginClean),
            source: source
        )
    }

    static func antiSentinel(_ v: Any?) -> String? {
        guard let t = s(v)?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        if t.hasPrefix("0000-00-00") { return nil }
        if t.hasPrefix("0001-01-01") { return nil }
        return t
    }

    struct MaintenancePlan {
        let current: Int
        let last: Int
        let interval: Int
        let fromServer: Bool
        var next: Int { last + interval }
        var remaining: Int { next - current }
    }

    static func maintenancePlan(_ carRaw: [String: Any]?, _ control: [String: Any]?) -> MaintenancePlan? {
        guard let cur = ciNumber(control, ["TotalOdometer"]), cur > 0 else { return nil }
        let srvLast = ciNumber(carRaw, ["LastMaintainMileage"]).flatMap { $0 > 0 ? Int($0.rounded()) : nil }
        let srvInterval = ciNumber(carRaw, ["MaintainSpaceMileage"]).flatMap { $0 > 0 ? Int($0.rounded()) : nil }
        let localLast = UserDefaults.standard.integer(forKey: AppStore.lastServiceMileageKey)
        guard let last = srvLast ?? (localLast > 0 ? localLast : nil) else { return nil }
        return MaintenancePlan(current: Int(cur.rounded()),
                               last: last,
                               interval: srvInterval ?? AppStore.defaultServiceInterval,
                               fromServer: srvLast != nil && srvInterval != nil)
    }

    static func vehicleSummary(_ carRaw: [String: Any]?, _ control: [String: Any]? = nil) -> VehicleSummary? {
        guard let c = carRaw else { return nil }
        let pinCN: [String: String] = ["exist": "已设置", "none": "未设置"]
        let pinKey = (ciPick(c, ["Pin"]) as? String ?? "").lowercased()
        let insuranceEnd = antiSentinel(ciPick(c, ["InsuranceEndDate"])) ?? ""
        let serviceEnd = antiSentinel(ciPick(c, ["TserviceEndtime"])) ?? ""
        let vname = s(ciPick(c, ["CarName"])) ?? ""
        let vplate = s(ciPick(c, ["PlateNumber"])) ?? ""
        let vvin = s(ciPick(c, ["Vin"])) ?? ""
        let vcolor = s(ciPick(c, ["Color"])) ?? ""
        let parts = [s(ciPick(c, ["ModelCode"])) ?? "", s(ciPick(c, ["ConfName"])) ?? ""].filter { !$0.isEmpty }
        let vmodel = parts.isEmpty ? "--" : parts.joined(separator: " · ")
        let plan = maintenancePlan(c, control)
        let mileageNow = plan?.current
        var serviceReminder: String? = nil
        if let plan {
            if plan.remaining <= 0 {
                serviceReminder = "已到保养里程！超出计划 \(abs(plan.remaining)) km"
            } else if plan.remaining < 5000 {
                serviceReminder = "下次保养：再跑 \(plan.remaining) km"
            }
        }

        return VehicleSummary(
            name: vname,
            plate: vplate.isEmpty ? "未上牌" : vplate,
            vin: vvin,
            isNev: num(ciPick(c, ["IsNev"])) == 1,
            pinText: pinCN[pinKey] ?? (ciPick(c, ["Pin"]) as? String ?? "--"),
            pinCls: pinKey == "exist" ? "ok" : "warn",
            model: vmodel,
            color: vcolor.isEmpty ? "--" : vcolor,
            insuranceEnd: insuranceEnd,
            insuranceDays: daysUntil(insuranceEnd),
            serviceEnd: serviceEnd,
            serviceDays: daysUntil(serviceEnd),
            serviceReminder: serviceReminder,
            mileage: mileageNow
        )
    }
}
