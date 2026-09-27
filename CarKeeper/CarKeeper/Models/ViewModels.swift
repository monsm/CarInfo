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
        // 带时分秒这一档必须有：服务端的 `tserviceEndtime` 形如 `2041-10-31 18:01:18`，
        // 少了它会**静默解析失败** → 车联网服务到期日永远不显示（daysUntil 返回 nil）。
        let formats = ["yyyy-MM-dd", "yyyy-MM-dd HH:mm:ss", "yyyy/MM/dd HH:mm:ss",
                       "yyyy/M/d", "yyyy.MM.dd", "yyyyMMdd", "yyyy年M月d日"]
        // 7 个构造器搬进 `DateText` 的池子（2026-09-25 性能轮）：原来每次调用现造 7 个，
        // 而日期串是**按记录**来的 —— 一页列表就是 7 × 条数次。locale 一字未改。
        return DateText.shared.date(t, formats: formats, locale: "zh_CN")
    }

    // ---------- 车辆选择 ----------
    static func carSel(_ cars: [[String: Any]], _ carId: String) -> (options: [(id: String, name: String)], index: Int, car: [String: Any]?, count: Int) {
        let options = cars.map { c in
            // 用 ciPick 而不是 `c["CarName"] ?? c["carName"]`：报文键是 carName（首字母小写），
            // 首字母大写那个分支永远读不到 —— 靠 ?? 兜底能“看起来正常”，但下一处没兜底的就会说谎。
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

    // ---------- 数据龄期（车端最后一次上报） ----------
    /// 服务端**不保证新鲜**：它回放的是车端最后一次上报的快照。本次抓包就是活例 ——
    /// 09:56 那次刷新拿到的 `lastUpdatedTime` 是 **07:19:28**（龄期 2 小时 37 分），
    /// 而紧接着十几次轮询拿到的数值一字不差。所以「在线」这个词必须带上年龄，
    /// 否则界面在说「现在 66%」，而事实是「07:19 时是 66%」。
    /// 想让它变新，只能让车端立刻上报（车控里有 `UpCarCondition` 这条指令）。
    static func reportAge(_ control: [String: Any]?) -> (text: String, minutes: Int, stale: Bool)? {
        guard let d = serverDate(ciPick(control, ["LastUpdatedTime"]))
                ?? serverDate(ciPick(control, ["DeviceTime"])) else { return nil }
        let mins = Int(Date().timeIntervalSince(d) / 60)
        guard mins >= 0 else { return nil }   // 车端时钟走到手机前面时不显示负数
        let text: String
        if mins < 2 { text = "刚刚" }
        else if mins < 60 { text = "\(mins) 分钟前" }
        else if mins < 60 * 24 { text = "\(mins / 60) 小时前" }
        else { text = "\(mins / (60 * 24)) 天前" }
        // 30 分钟是「开始值得怀疑」的阈值：TBOX 正常上报间隔远小于它。
        return (text, mins, mins >= 30)
    }

    /// 服务端时间字符串 → Date（先过哨兵守卫，再按已知格式解析）。
    static func serverDate(_ v: Any?) -> Date? {
        guard let t = antiSentinel(v) else { return nil }
        return parseDate(String(t.prefix(19)))
    }

    // ---------- 告警总灯（车端自己置的报警位，唯一来源） ----------
    /// 报文的每个 `*Alarm` 都是车端置的 0/1/2…，我们只搬运「非 0 即亮」，
    /// **不拿阈值猜**（阈值另一套：胎压/胎温各有自己的 warning 位）。
    /// 16 个键全部来自本次抓包的真实键名；`maxAlarmLevel` 是服务端自己算的最高等级。
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

    /// 亮着的报警位：0 与「键缺失」都不算 —— 缺失是没数据，不是正常。
    static func activeAlarms(_ cache: [String: Any?]) -> [String] {
        guard let control = cacheObject(cache, "control") else { return [] }
        return alarmFlags.compactMap { f in
            guard let x = ciNumber(control, [f.key]), x != 0 else { return nil }
            return f.label
        }
    }

    /// `maxAlarmLevel`：服务端给的整车最高报警等级。0 与缺失都返回 nil，
    /// 免得把「没上报」显示成「等级 0 = 一切正常」。
    static func maxAlarmLevel(_ cache: [String: Any?]) -> Double? {
        guard let control = cacheObject(cache, "control"),
              let ml = ciNumber(control, ["MaxAlarmLevel"]), ml > 0 else { return nil }
        return ml
    }

    // ---------- 已删除：能力位图（car.funCode）的解析 ----------
    //
    //  2026-09-27（用户：「删除开发者入口，诊断中删除无用的」→ 勾了「能力位图」）：
    //  `VM.capabilities(_:)` 与 `VM.Capability` **整段删了**，它唯一的读处是
    //  诊断页里那 7 组 43 个原始开关。删了之后的账要写清：
    //    · `getMyCars[].funCode` 从此**不被解析**（也没人再读）——而它本来就是
    //      「只搬运、不驱动界面」的证据（当时写下它的那句话还在 `API-FIELD-MAP.md`
    //      的 §17）；
    //    · 为什么证据不再需要一块常驻的界面：那一段的结论（「按 0 隐藏控件可能藏掉
    //      真能用的功能」）已经写进文档，而**位图本身是快照**——要看它拿一份报文
    //      对照即可，不必在 App 里养一条只有开发者读的链。
    //  这一段的取值依据与两组同名开关互相矛盾那件事，留在 `API-FIELD-MAP.md` §17。

    // ---------- 车控回执的成败（唯一判定） ----------
    /// 返回 `nil` 表示：车端确实回执了，但那个状态值我们**不认识**。
    ///
    /// 为什么要写成三态：参考实现（D:/xm/ChangAnCarInfo，C#）只把 `HandleStatus` 与
    /// `HandleStatusDesc` 原样显示，**从不下判断** —— 这等于说真实取值集合并未核实。
    /// 以前我们拿一份自己编的字符串表判「终态 + 成败」，坏方向是：
    /// 真值不在表里 → 每条指令都等满 60 秒、落到「结果待确认」；
    /// 而若把不认识的值一律当失败，又会把一次真的成功指令记成失败。
    /// 所以：认识的才说成败，不认识的就直说「未识别」。
    static func controlOutcome(status: String, handleCode: String) -> Bool? {
        // HandleCode 的取值集合同样未核实，所以它只被原样显示，不参与判定。
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

    // ---------- 充电功率（唯一算法） ----------
    /// 报文里**没有** `ChargPower` / `ChargingPower` 这两个键 —— 而全库都在读它们，
    /// 所以功率恒为 nil：充电曲线、账本 kWh、小组件功率、充电推送全是空的。
    /// 真实功率就在控制报文里：**P = totalVoltage × totalCurrent**。
    /// 静止不充电时 `totalCurrent: 0.0`，所以这个公式自己就知道「什么时候没有功率」，
    /// 不需要额外的“是否在充电”开关（那个开关本身就是用同一个字段推出来的）。
    static func chargePowerKW(_ charge: [String: Any]?, _ control: [String: Any]?) -> Double? {
        if let p = ciNumber(charge, ["ChargPower", "ChargingPower"]), p > 0.1 { return p }
        guard let v = ciNumber(control, ["TotalVoltage"]),
              let a = ciNumber(control, ["TotalCurrent"]), a > 0 else { return nil }
        return v * a / 1000.0   // V·A = W → kW
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
        let chargeSt = s(ciPick(charge, ["ChrgStatus"])) ?? ""
        var chargeText = "未充电", chargeCls = "idle"
        // 「3」不是「充电完成」，而是**没在充电**：车主已确认（§0.1 #1）2026-09-22 那次抓包时
        // 车刚行驶回来、根本没插枪，报文里就是 `chrgStatus:"3"`。
        // 写成「充电完成」会让一辆停着的车整天挂着一个充电状态。
        // `chargeStarttime` / `chargeStoptime` / `chargDeltMins` 三个字段因此属于
        // **上一次充电**（2024-05-20），只能在真的充电时作为参考，不能当“现在”。
        switch chargeSt {
        case "1": chargeText = "充电中"; chargeCls = "ok"
        case "2": chargeText = "即将充满"; chargeCls = "ok"
        case "3": chargeText = "未在充电"; chargeCls = "idle"
        default: break
        }

        let range = vnumOf(charge, ["RemainedPowerMile"]).map { String(Int($0.rounded())) }
            ?? vnumOf(control, ["RemainedPowerMile"]).map { String(Int($0.rounded())) }
            ?? "--"
        //  电压与电流是**两个读数**，所以是两个字段（用户 2026-09-25：「充电里面的电压/电流
        //  拥挤了」）。上一版它们被拼成一句 `398.2V / 12.4A`（一个字段、12 个字符），
        //  而它要坐的是「充电功率 / 电池温度 / 电压电流」那一排里的**三分之一宽** ——
        //  只能靠缩小字号挤进去。拼句的代价就在这里：两个本来各自很短的读数，
        //  拼在一起就超过了一格的宽度（一个事实一个出处：这里的「事实」是两个数）。
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
            // 「在线」要带**龄期**：`lastUpdatedTime` 是车端最后一次上报的时刻，
            // 车端停报时它一直不变 —— 只写「在线」会让两小时前的快照看起来像此刻。
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

        // #1 充电倒计时：(100 - socPct) / power(kW) * 60 = 分钟
        var timeToFull: String? = nil
        if chargeSt == "1" || chargeSt == "2" {
            // ⚠️ 这里原来读 `ChargPower` / `ChargingPower` —— 报文里**没有**这两个键，
            // 于是「预计充满」恒为空（电池页与小组件都写着它，却永远显示不出来）。
            // 唯一算法在 `chargePowerKW`（totalVoltage × totalCurrent）。
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
        // #2 SOC耗尽预测：基于当前续航估算行驶时间（假设平均时速40km/h）
        //  （同一段里原本还有一个「百公里能耗」的估算 —— 按「socPct ÷ 续航 × 15」
        //   推出来的，而它的唯一读者是地图抽屉里那一格。用户 2026-09-27：
        //   「地图页抽屉去掉平均功耗」，于是估算与那个字段一起删了：一个自己估的数
        //   摆在一排车端读数里，比不摆更坏。）
        var timeToEmpty: String? = nil
        if let r = Double(range), r > 0, socPct > 0 {
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
            charging: charging, volt: volt, amp: amp, battTemp: battTemp, insulate: insulate,
            online: online, updated: updated, carName: carName,
            timeToFull: timeToFull,
            timeToEmpty: timeToEmpty
        )
    }

    static func nowText() -> String {
        DateText.shared.string(Date(), "yyyy-MM-dd HH:mm:ss")
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
                cls: (!hasCtrl || ok == nil) ? "na" : (ok == true ? "ok" : "bad")
            )
        }

        /// ⚠️ 旧实现是 `num(...) == 0`，而 `num(nil)` 返回 **0** —— 于是「字段缺失」被判成「已关」，
        /// 车锁/车窗永远显示「已锁/已关」（无论真实状态）。现在值缺失就显示「无数据」（cls = na）。
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

    // ---------- 动力 / 电池健康 ----------
    static func driveStatus(_ cache: [String: Any?]) -> DriveModel {
        let control = ciVal(cache, "control")
        let hasCtrl = control != nil
        //  ⚠️ 2026-09-27：**车速**与「在不在动」改读**定位报文**（`location.speed`），
        //  不再读 control 的 `VehicleSpeed`。两条报文里是同一个量
        //（`API-FIELD-MAP.md` §4.4 写着「`speed` … 与 control `speed`/`vehicleSpeed`
        //  一致」，抓包逐字核过），而车在动时那一拍**只取定位这一份**
        //（`RefreshLoop` 的 1 秒节律）——读数必须住在**那一份真的在取的报文**里。
        //  否则地图上的车速会整趟冻在「开始动」那一刻的值上，而它看起来是活的
        //（比读数慢更糟：慢看得见，假看不见）。
        let location = ciVal(cache, "location")
        let speedRaw = ciPick(location, ["speed"])

        // ⚠️ 报文中 DriveMotorData / MotorData 是「数组」（小程序取 [0]，batteryModel 里也是数组），
        // 之前按对象解析 → 永远取不到 → 首页/车况页的电机温度恒为 "--"。
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

    // ---------- 空调 / 座椅 / PM2.5 ----------
    static func comfortStatus(_ cache: [String: Any?]) -> ComfortModel {
        let control = ciVal(cache, "control")
        let hasCtrl = control != nil
        let pmRaw = ciVal(cache, "pm25")
        let air = nestedObject(control, "Air")
        // air 缺失则 acOn = nil
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
            // 空调关着时这两个是**上次设定值**，所以文案是「已关闭 · 上次设定 26℃ · 风量 3 档」，
            // 不能写成“当前 26℃”（车主已确认 2026-09-22 抓包时空调是关的）。
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

    // ---------- 胎压 ----------
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

    // ---------- 位置 ----------
    static func locStatus(_ cache: [String: Any?]) -> LocModel {
        let control = ciVal(cache, "control")
        let locRaw = ciVal(cache, "location")
        let hasCtrl = control != nil
        // 位置接口偶尔返回空对象 / 失灵时，退回 pm25 报文里那份 CarLocationResp ——
        // 小程序 utils/texts.js 的 envText 正是从 pm25 里读 AddrDesc / Lat / Lng。
        let loc: [String: Any]? = {
            guard let locRaw else { return ciObject(ciVal(cache, "pm25"), ["CarLocationResp", "carLocationResp"]) }
            let hasAddr = !((ciString(locRaw, ["AddrDesc"]) ?? "").isEmpty)
            let hasCoord = ciNumber(locRaw, ["Lat"]) != nil && ciNumber(locRaw, ["Lng"]) != nil
            if hasAddr || hasCoord { return locRaw }
            return ciObject(ciVal(cache, "pm25"), ["CarLocationResp", "carLocationResp"]) ?? locRaw
        }()
        // ValidGps 可能是布尔 / 0-1 数字 / "0"-"1" 字符串，统一走 ciBool
        // （小程序用 !!loc.ValidGps；原来只认 NSNumber，字符串时整项变 "--"）
        let gpsOk = ciBool(loc, ["ValidGps"])
        let heading = ciNumber(loc, ["Heading"])
        let deg = heading == nil ? 0 : norm360(heading!)
        // 卫星数缺失时不要硬造 "0 颗"，直接显示 "--"
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
                let st = (ciPick(it, ["Status"]) as? String ?? "").lowercased()
                let m: [String: String]
                if let found = map[st] { m = found }
                else if ciPick(it, ["Status"]) == nil { m = ["cls": "ok", "cn": "正常"] }
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
            return HealthSystem(
                name: s(ciPick(s2, ["ItemName"])) ?? "",
                statusCls: hasBad ? "bad" : (hasWarn ? "warn" : "ok"),
                statusText: hasBad ? "故障" : (hasWarn ? "预警" : "正常"),
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

    // ---------- 用户 ----------
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

    // ---------- 服务端的「空」是哨兵，不是 null ----------
    /// 报文里同一个意思有三种写法：
    ///   · `"0000-00-00"`                 —— `insuranceEndDate` / `lastCheckTime`
    ///   · `"0000-00-00\n\t\t00:00:00"`    —— `activeTime`（连制表符一起发过来）
    ///   · `""` / 键缺失
    /// 它们全是「没有登记」，不是日期。原样打印会让页面显示「保险到期 0000-00-00」——
    /// 那不是数据，那是空值的编码方式；用户读到的是「零年零月」。
    static func antiSentinel(_ v: Any?) -> String? {
        guard let t = s(v)?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        if t.hasPrefix("0000-00-00") { return nil }
        if t.hasPrefix("0001-01-01") { return nil }
        return t
    }

    // ---------- 保养计划（唯一来源） ----------
    /// 三个数字的来处**各不相同**，这正是以前一直算错的原因：
    ///
    ///   · 当前里程 → `control.totalOdometer`（本次抓包 53766.4）。
    ///                注意 `getMyCars` 里也有一个 `totalOdometer`，但它恒为 **null** ——
    ///                车端实时值只存在于 `/api/car/getControlStatus` 报文里。
    ///   · 保养间隔 → `car.maintainSpaceMileage`（20000，服务端说了算）
    ///   · 上次保养 → `car.lastMaintainMileage`（20100，服务端说了算）
    ///
    /// 服务端这两个字段缺了才退回本机记录（间隔 10000 + 用户自己记的里程），
    /// 并保留 `fromServer` 让界面能区分「车厂计划」与「本地估算」——
    /// 以前两者被混成同一个看起来同样权威的数字。
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

    // ---------- 车辆档案摘要 ----------
    /// `control` 是可选参数：里程（`totalOdometer`）只在车控报文里有，档案接口里是 null。
    static func vehicleSummary(_ carRaw: [String: Any]?, _ control: [String: Any]? = nil) -> VehicleSummary? {
        guard let c = carRaw else { return nil }
        let pinCN: [String: String] = ["exist": "已设置", "none": "未设置"]
        let pinKey = (ciPick(c, ["Pin"]) as? String ?? "").lowercased()
        let insuranceEnd = antiSentinel(ciPick(c, ["InsuranceEndDate"])) ?? ""
        let serviceEnd = antiSentinel(ciPick(c, ["TserviceEndtime"])) ?? ""
        let vname = s(ciPick(c, ["CarName"])) ?? ""
        let vplate = s(ciPick(c, ["PlateNumber"])) ?? ""
        let vvin = s(ciPick(c, ["Vin"])) ?? ""
        let vcolor = s(ciPick(c, ["Color"])) ?? ""  // 本次抓包是 null → 显示「--」而不是编一个颜色
        let parts = [s(ciPick(c, ["ModelCode"])) ?? "", s(ciPick(c, ["ConfName"])) ?? ""].filter { !$0.isEmpty }
        let vmodel = parts.isEmpty ? "--" : parts.joined(separator: " · ")
        // #16 维保里程提醒：唯一来源是 VM.maintenancePlan（服务端计划优先）
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
        // 删掉了原来的「首次设置：把当前里程记成上次保养里程」——
        // 那是**在视图模型里凭空造一个事实**：我们并不知道上一次保养发生在多少公里，
        // 把「今天」当成「上次保养」会让每一次首次启动都重置保养计划。
        // 没有服务端计划、也没有用户记过的里程时，就什么也不说。

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
