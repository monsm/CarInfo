import Foundation

// 视图模型：把接口原始数据映射成页面可渲染的结构化模型（对应小程序 vm.js）。
// 严格取数：属性缺失 / null / 空串视为「无数据」（避免 Number(null)===0 误显示）。

enum VM {

    // ---------- 严格数值 ----------
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

    // ---------- 日期 ----------
    /// 距今天数（未来正数 / 已过期负数 / 解析失败 null）。
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
        let formats = ["yyyy-MM-dd", "yyyy/M/d", "yyyy.MM.dd", "yyyyMMdd", "yyyy年M月d日"]
        for f in formats {
            let df = DateFormatter()
            df.locale = Locale(identifier: "zh_CN")
            df.dateFormat = f
            if let d = df.date(from: t) { return d }
        }
        return nil
    }

    // ---------- 车辆选择 ----------
    static func carSel(_ cars: [[String: Any]], _ carId: String) -> (options: [(id: String, name: String)], index: Int, car: [String: Any]?, count: Int) {
        let options = cars.map { c in
            let cname = s(c["CarName"] ?? c["carName"]) ?? ""
            let plate = s(c["PlateNumber"] ?? c["plateNumber"]) ?? ""
            let name = "\(cname) \(plate)".trimmingCharacters(in: .whitespaces)
            let id = s(c["CarId"] ?? c["carId"]) ?? ""
            return (id, name)
        }
        var idx = options.firstIndex { $0.0 == carId } ?? 0
        if idx < 0 { idx = 0 }
        return (options, idx, idx < cars.count ? cars[idx] : nil, cars.count)
    }

    // ---------- 首页能量卡 ----------
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
        let chargeSt = s(charge?["ChrgStatus"]) ?? ""
        var chargeText = "未充电", chargeCls = "idle"
        switch chargeSt {
        case "1": chargeText = "充电中"; chargeCls = "ok"
        case "2": chargeText = "即将充满"; chargeCls = "ok"
        case "3": chargeText = "充电完成"; chargeCls = "ok"
        default: break
        }

        let range = vnumOf(charge, ["RemainedPowerMile"]).map { String(Int($0.rounded())) }
            ?? vnumOf(control, ["RemainedPowerMile"]).map { String(Int($0.rounded())) }
            ?? "--"
        let voltAmp = hasCtrl
            ? "\(n1(control?["TotalVoltage"]) ?? "--")V / \(n1(control?["TotalCurrent"]) ?? "--")A"
            : "--"
        let btLo = n0(control?["MinTemperatureValue"])
        let btHi = n0(control?["MaxTemperatureValue"])
        let battTemp = (hasCtrl && btLo != nil && btHi != nil) ? "\(btLo!) ~ \(btHi!)℃" : "--"
        let insulate = hasCtrl ? "\(n0(control?["InsulateResistance"]) ?? "--") Ω" : "--"

        var charging: ChargingSession?
        if chargeSt == "1" || chargeSt == "2" {
            let pow = ciNumber(charge, ["ChargPower", "ChargingPower"])
            charging = ChargingSession(
                start: dash(charge?["ChargeStarttime"]) ?? "--",
                end: dash(charge?["ChargeStoptime"]) ?? "--",
                durMin: n0(charge?["ChargDeltMins"]) ?? "--",
                power: pow == nil ? "--" : "\(Int(pow!)) kW"
            )
        }

        var online = OnlineState(text: "离线", cls: "bad")
        var updated = "--"
        if let c = control, c["LastUpdatedTime"] != nil {
            let control = c
            let devT = s(control["DeviceTime"]) ?? ""
            updated = devT.count > 10 ? devT : nowText()
            online = OnlineState(text: "在线 · \(updated)", cls: "ok")
        }

        let carName: String
        if let car {
            let cv = car
            let cname = s(cv["CarName"] ?? cv["carName"]) ?? ""
            let plate = s(cv["PlateNumber"] ?? cv["plateNumber"]) ?? ""
            carName = "\(cname) \(plate)".trimmingCharacters(in: .whitespaces)
        } else {
            carName = "未绑定车辆"
        }

        // #1 充电倒计时：(100 - socPct) / power(kW) * 60 = 分钟
        var timeToFull: String? = nil
        if chargeSt == "1" || chargeSt == "2" {
            if let pow = pow, pow > 0.1, socPct < 100 {
                let minutes = Int(Double(100 - socPct) / pow * 60)
                if minutes > 0 {
                    let h = minutes / 60
                    let m = minutes % 60
                    timeToFull = h > 0 ? "约\(h)小时\(m)分钟" : "约\(m)分钟"
                    charging?.timeToFull = timeToFull
                }
            }
        }
        // #2 SOC耗尽预测：基于当前续航估算行驶时间（假设平均时速40km/h）
        var timeToEmpty: String? = nil
        var avgCons: String? = nil
        if let r = Double(range), r > 0, socPct > 0 {
            // 百公里能耗 = socPct / range * 15 (假设电池容量约15kWh，估算)
            let cons = (Double(socPct) / r * 15).rounded(to: 1)
            avgCons = "\(cons) kWh/100km"
            let hoursToEmpty = Int(r / 40.0)
            if hoursToEmpty > 0 {
                timeToEmpty = "约\(hoursToEmpty)小时" // 按40km/h平均时速估算
            }
        }

        return EnergyModel(
            soc: socStr, socPct: socPct,
            socCls: socPct >= 15 ? "ok" : "bad", socWarn: (socPct < 30 && socPct >= 15) ? "low" : "",
            range: range, chargeText: chargeText, chargeCls: chargeCls,
            chargePct: socStr == "--" ? "--" : socStr,
            charging: charging, voltAmp: voltAmp, battTemp: battTemp, insulate: insulate,
            online: online, updated: updated, carName: carName,
            timeToFull: timeToFull,
            timeToEmpty: timeToEmpty,
            avgConsumption: avgCons
        )
    }

    static func nowText() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: Date())
    }

    // ---------- 门窗锁状态条 ----------
    static func bodyStatus(_ cache: [String: Any?]) -> [StatusChip] {
        let control = ciVal(cache, "control")
        let hasCtrl = control != nil

        func mk(_ label: String, _ ok: Bool?, _ text: String) -> StatusChip {
            StatusChip(
                label: label,
                ok: hasCtrl ? ok : nil,
                text: hasCtrl ? text : "--",
                cls: !hasCtrl ? "na" : (ok == true ? "ok" : "bad")
            )
        }

        var chips: [StatusChip] = []
        let doorOk = hasCtrl && num(control?["Door"]) == 0
        chips.append(mk("车门", doorOk, doorOk ? "已关" : "开启"))
        let winOk = hasCtrl && s(control?["Window"]) == "0"
        chips.append(mk("车窗", winOk, winOk ? "已关" : "开启"))
        let trunkOk = hasCtrl && num(control?["Trunk"]) == 0
        chips.append(mk("后备箱", trunkOk, trunkOk ? "已关" : "开启"))
        let roofOk = hasCtrl && num(control?["Sunroof"]) == 0
        chips.append(mk("天窗", roofOk, roofOk ? "已关" : "开启"))
        let lockOk = hasCtrl && num(control?["DriverDoorLock"]) == 0
        chips.append(mk("车锁", lockOk, lockOk ? "已锁" : "未锁"))

        func guardChip(_ label: String, _ key: String) -> StatusChip {
            let x = ciNumber(control, [key])
            let good = x != nil && x == 0
            return mk(label, good, x == nil ? "--" : (good ? "正常" : "报警"))
        }
        chips.append(guardChip("制动", "BrakeSystemAlarm"))
        chips.append(guardChip("气囊", "AirbagSystemStatus"))
        return chips
    }

    // ---------- 动力 / 电池健康 ----------
    static func driveStatus(_ cache: [String: Any?]) -> DriveModel {
        let control = ciVal(cache, "control")
        let hasCtrl = control != nil

        let motorArr: [String: Any]? = control.flatMap { c -> [String: Any]? in
            let drive = ciObject(c, ["DriveMotorData"])
            if drive != nil { return drive }
            return ciObject(c, ["MotorData"])
        }
        let motor = motorArr

        let gearCls = (hasCtrl && num(control?["ShiftPosition"]) != 0) ? "bad" : ""

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
            speed: hasCtrl ? (n0(control?["VehicleSpeed"]) ?? "--") : "--",
            mile: hasCtrl ? (n0(control?["TotalOdometer"]) ?? "--") : "--",
            gear: hasCtrl ? (num(control?["ShiftPosition"]) == 0 ? "P" : "D") : "--",
            gearSub: hasCtrl ? (num(control?["ShiftPosition"]) == 0 ? "驻车" : "行驶") : "",
            gearCls: gearCls,
            motorTemp: motor == nil ? "--" : (t != nil ? "\(Int(t!))°" : "--") + " / " + (ct != nil ? "\(Int(ct!))°" : "--"),
            batteryNote: note,
            isMoving: hasCtrl && num(control?["VehicleSpeed"]) > 0,
            fireStatus: fireStatus
        )
    }

    // ---------- 空调 / 座椅 / PM2.5 ----------
    static func comfortStatus(_ cache: [String: Any?]) -> ComfortModel {
        let control = ciVal(cache, "control")
        let hasCtrl = control != nil
        let pmRaw = ciVal(cache, "pm25")
        let air = nestedObject(control, "Air")
        // air 缺失则 acOn = nil
        let acOnFinal: Bool? = air == nil ? nil : (s(air?["Status"]) != "0")

        let pmInRaw = s(pmRaw?["Pm25InnnerCarValue"]) ?? ""
        let pmIn: String
        if pmInRaw == "-1" || pmInRaw.isEmpty { pmIn = "--" } else { pmIn = pmInRaw }
        let pmOut = s(pmRaw?["Pm25OuterCarValue"]) ?? "--"

        let vehTemp = ciNumber(pmRaw, ["VehicleTemperature"])
        let envT = ciNumber(pmRaw, ["EnvironmentalTemperature"])
        let purifier = ciNumber(control, ["AirPurifierStatus"])

        return ComfortModel(
            acOn: acOnFinal,
            acText: air == nil ? "暂无数据" : "\(acOnFinal == true ? "运行中" : "已关闭") · \(s(air?["Temperature"]) ?? "26")℃ · 风量\(s(air?["Wind"]) ?? "0")档",
            acCls: acOnFinal == nil ? "na" : (acOnFinal == true ? "ok" : "off"),
            seatD: hasCtrl ? "通风\(num(control?["DriverSeatAirStatus"]) == 1 ? "开" : "关") · 加热\(num(control?["DriverSeatHeatStatus"]) == 1 ? "开" : "关")" : "--",
            seatP: hasCtrl ? "通风\(num(control?["PassengerSeatAirStatus"]) == 1 ? "开" : "关") · 加热\(num(control?["PassengerSeatHeatStatus"]) == 1 ? "开" : "关")" : "--",
            pmIn: pmIn, pmOut: pmOut,
            cabinTemp: (vehTemp == nil || Int(vehTemp!) == 0) ? "--" : "\(Int(vehTemp!))℃",
            envTemp: (envT == nil || Int(envT!) == 0) ? "--" : "\(Int(envT!))℃",
            purifier: purifier == nil ? "--" : (purifier! == 1 ? "运行" : "关闭")
        )
    }

    // ---------- 胎压 ----------
    static func tyreStatus(_ cache: [String: Any?]) -> TyreModel {
        let control = ciVal(cache, "control")
        let hasCtrl = control != nil

        func item(_ label: String, _ presKey: String, _ tempKey: String, _ warnKey: String) -> TyreItem {
            let w = ciNumber(control, [warnKey])
            let warn = (w != nil && w! > 0)
            return TyreItem(
                label: label,
                kpa: n0(control?[presKey]) ?? "--",
                temp: n0(control?[tempKey]) ?? "--",
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

    // ---------- 位置 ----------
    static func locStatus(_ cache: [String: Any?]) -> LocModel {
        let control = ciVal(cache, "control")
        let loc = ciVal(cache, "location")
        let hasCtrl = control != nil
        let gpsOk = loc.map { $0 }.flatMap { $0["ValidGps"] as? NSNumber }.map { $0.boolValue }
        let heading = ciNumber(loc, ["Heading"])
        let deg = heading == nil ? 0 : norm360(heading!)
        return LocModel(
            addr: loc?["AddrDesc"] as? String ?? "",
            snap: s(loc?["LocationImgurl"]) ?? s(loc?["ThumbnailLocationImgUrl"]) ?? "",
            gpsText: gpsOk == nil ? "--" : (gpsOk! ? "GPS 信号有效" : "GPS 信号异常"),
            gpsCls: gpsOk == nil ? "na" : (gpsOk! ? "ok" : "bad"),
            dir: heading == nil ? "--" : directionText(deg),
            deg: heading == nil ? "--" : "\(Int(deg.rounded()))°",
            degNum: heading == nil ? 0 : Int(deg.rounded()),
            satAlt: hasCtrl ? "\(Int(num(control?["SatNum"]))) 颗 · 海拔 \(n1(control?["Alti"]) ?? "--") m" : "--",
            lat: (loc?["Lat"] as? String) ?? (loc?["Lat"] as? NSNumber).map { $0.stringValue } ?? "--",
            lng: (loc?["Lng"] as? String) ?? (loc?["Lng"] as? NSNumber).map { $0.stringValue } ?? "--"
        )
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

    // ---------- 健康报告 ----------
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
                let st = (it["Status"] as? String ?? "").lowercased()
                let m: [String: String]
                if let found = map[st] { m = found }
                else if it["Status"] == nil { m = ["cls": "ok", "cn": "正常"] }
                else { m = ["cls": "warn", "cn": s(it["Status"]) ?? ""] }
                let name: String
                if let sn = s(it["ItemName"]) { name = sn } else { name = "" }
                return HealthItem(
                    name: name,
                    statusCls: m["cls"] ?? "ok",
                    statusText: m["cn"] ?? "",
                    desc: it["Description"] as? String,
                    detect: it["DetectValue"] as? String,
                    suggest: it["Suggest"] as? String
                )
            }
            let hasBad = children.contains { $0.statusCls == "bad" }
            let hasWarn = children.contains { $0.statusCls == "warn" }
            return HealthSystem(
                name: s2["ItemName"] as? String ?? "",
                statusCls: hasBad ? "bad" : (hasWarn ? "warn" : "ok"),
                statusText: hasBad ? "故障" : (hasWarn ? "预警" : "正常"),
                children: children,
                open: hasBad
            )
        }
        let timeStr: String
        if let ct = s(d["CheckTime"]) { timeStr = ct } else { timeStr = "" }
        let idStr: String?
        if let cid = s(d["CheckHistoryId"]) { idStr = cid } else { idStr = nil }
        let statusMap: [String: String] = ["normal": "正常", "fault": "故障", "warning": "预警", "risk": "风险", "abnormal": "异常", "ok": "正常"]
        let vehicleStatus = s(d["Status"]).flatMap { statusMap[$0] ?? $0 }
        return HealthModel(
            time: timeStr,
            score: score == nil ? "--" : "\(Int(score!.rounded()))",
            scorePct: score == nil ? 0 : max(0, min(100, Int(score!.rounded()))),
            counts: [
                CountPill(key: "正常", n: n0(d["NormalCount"]) ?? "--", cls: "ok"),
                CountPill(key: "风险", n: n0(d["RiskCount"]) ?? "--", cls: "warn"),
                CountPill(key: "故障", n: n0(d["FaultCount"]) ?? "--", cls: "bad")
            ],
            systems: systems,
            id: idStr,
            checkId: s(d["CheckHistoryId"]),
            endTime: s(d["CarDataUpdateTime"]),
            vehicleStatus: vehicleStatus
        )
    }

    // ---------- 用户 ----------
    static func userModel(_ uRaw: [String: Any]?) -> UserVM? {
        guard let u = uRaw else { return nil }
        let name = s(u["UserFullname"] ?? u["UserNickname"]) ?? ""
        let nameFinal = name.isEmpty ? "车主" : name
        let mobile = s(u["Mobile"]) ?? ""
        let authed = (ciBool(u, ["RealnameAuthed"]) ?? false)
        let nickname = s(u["UserNickname"]) ?? ""
        let genderRaw = s(u["Gender"]) ?? ""
        let genderCN: [String: String] = ["m": "男", "f": "女"]
        let gender = genderCN[genderRaw] ?? genderRaw
        let lastLogin = s(u["LastLoginTime"]) ?? ""
        let lastLoginClean = lastLogin.replacingOccurrences(of: "\.0$", with: "")
        let source = s(u["Source"]) ?? ""
        return UserVM(
            name: nameFinal,
            avatar: (u["UserNickname"] as? String ?? nameFinal).prefix(1).uppercased() as String,
            mobile: mobile.count >= 11 ? String(mobile.prefix(3)) + "****" + String(mobile.suffix(4)) : (mobile.isEmpty ? "--" : mobile),
            authed: authed,
            nickname: nickname.isEmpty ? "未设置昵称" : nickname,
            gender: gender.isEmpty ? "" : gender,
            birthday: s(u["Birthday"]) ?? "",
            lastLoginTime: (lastLoginClean.count > 10 ? String(lastLoginClean.suffix(10)) : lastLoginClean),
            source: source
        )
    }

    // ---------- 车辆档案摘要 ----------
    static func vehicleSummary(_ carRaw: [String: Any]?) -> VehicleSummary? {
        guard let c = carRaw else { return nil }
        let pinCN: [String: String] = ["exist": "已设置", "none": "未设置"]
        let pinKey = (c["Pin"] as? String ?? "").lowercased()
        let insuranceEnd = s(c["InsuranceEndDate"]) ?? ""
        let serviceEnd = s(c["TserviceEndtime"]) ?? ""
        let vname = s(c["CarName"]) ?? ""
        let vplate = s(c["PlateNumber"]) ?? ""
        let vvin = s(c["Vin"]) ?? ""
        let vcolor = s(c["Color"]) ?? ""
        let parts = [s(c["ModelCode"]) ?? "", s(c["ConfName"]) ?? ""].filter { !$0.isEmpty }
        let vmodel = parts.isEmpty ? "--" : parts.joined(separator: " · ")
        // #16 维保里程提醒：从 control 缓存中读取当前里程，计算距下次保养剩余
        let currentMileage = ciNumber(c, ["Mileage", "mileage", "TotalMileage"]).map { Int($0.rounded()) }
        let lastService = AppStore.shared.lastServiceMileage
        let interval = AppStore.defaultServiceInterval
        var serviceReminder: String? = nil
        if let里程 = currentMileage, 里程 > 0, lastService > 0 {
            let remaining = interval - (里程 - lastService)
            if remaining > 0 && remaining < 5000 {
                serviceReminder = "下次保养：再跑 \(remaining) km"
            } else if remaining <= 0 {
                serviceReminder = "已到保养里程！"
            }
        } else if let里程 = currentMileage, 里程 > 0 {
            // 首次设置：记录当前里程为上次保养里程
            UserDefaults.standard.set(里程, forKey: AppStore.lastServiceMileageKey)
            serviceReminder = "\(interval) km 后保养"
        }
        // #40 获取当前里程用于维保估算
        let currentMileage = ciNumber(c, ["Mileage", "mileage", "TotalMileage"]).map { Int($0.rounded()) }
        
        return VehicleSummary(
            name: vname,
            plate: vplate.isEmpty ? "未上牌" : vplate,
            vin: vvin,
            isNev: num(c["IsNev"]) == 1,
            pinText: pinCN[pinKey] ?? (c["Pin"] as? String ?? "--"),
            pinCls: pinKey == "exist" ? "ok" : "warn",
            model: vmodel,
            color: vcolor.isEmpty ? "--" : vcolor,
            insuranceEnd: insuranceEnd,
            insuranceDays: daysUntil(c["InsuranceEndDate"]),
            serviceEnd: serviceEnd,
            serviceDays: daysUntil(c["TserviceEndtime"]),
            serviceReminder: serviceReminder,
            mileage: currentMileage
        )
    }
}
