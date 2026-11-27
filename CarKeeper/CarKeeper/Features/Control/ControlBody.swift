import Foundation

struct BodyState {
    struct Row: Identifiable, Equatable {
        var id: String { label }
        let label: String
        let value: String
        let cls: String
    }

    struct Lamp: Identifiable, Equatable {
        var id: String { label }
        let label: String
        let value: String
    }

    let summary: String
    let cls: String
    let doorRows: [Row]
    let windowRows: [Row]
    let extraRows: [Row]
    let lampRows: [Lamp]

    init?(control: [String: Any]?) {
        guard let ctrl = control, !ctrl.isEmpty else { return nil }

        func num(_ k: String) -> Int? { ciNumberInt(ctrl, [k]) }

        var doorRows: [Row] = []
        let doorDefs: [(String, String, String)] = [
            ("左前门", "LeftFrontDoor", "LeftFrontDoorLock"),
            ("右前门", "RightFrontDoor", "RightFrontDoorLock"),
            ("左后门", "LeftRearDoor", "LeftRearDoorLock"),
            ("右后门", "RightRearDoor", "RightRearDoorLock")
        ]
        for (label, doorK, lockK) in doorDefs {
            let d = num(doorK), lk = num(lockK)
            if d == nil && lk == nil { continue }
            let parts: [String] = [
                d.map { $0 == 0 ? "已关" : "开启" },
                lk.map { $0 == 0 ? "已锁" : "未锁" }
            ].compactMap { $0 }
            if !parts.isEmpty {
                let isBad = (d != nil && d! != 0) || (lk != nil && lk! != 0)
                doorRows.append(Row(label: label, value: parts.joined(separator: " · "),
                                    cls: isBad ? "bad" : "ok"))
            }
        }

        var windowRows: [Row] = []
        let winDefs: [(String, String)] = [
            ("左前窗", "LeftAnteriorWindowDegree"),
            ("右前窗", "RightAnteriorWindowDegree"),
            ("左后窗", "LeftRearWindowDegree"),
            ("右后窗", "RightRearWindowDegree")
        ]
        for (label, degK) in winDefs {
            let deg = num(degK)
            if deg == nil { continue }
            let v = deg == 0 ? "关闭" : "开启 \(deg!)°"
            windowRows.append(Row(label: label, value: v, cls: deg != 0 ? "bad" : "ok"))
        }

        var lampRows: [Lamp] = []
        let lampDefs: [(String, String, String?)] = [
            ("近光灯", "LowBeam", nil),
            ("远光灯", "HighBeam", nil),
            ("前雾灯", "FrontFoglamp", "FrontFogLight"),
            ("后雾灯", "RearFoglamp", "RearFogLight"),
            ("示廓灯", "PositionLamp", "PositionLight"),
            ("左转向灯", "LeftTurnSignal", "TurnLndicatorLeft"),
            ("右转向灯", "RightTurnSignal", "TurnLndicatorRight")
        ]
        for (label, k1, k2) in lampDefs {
            let x1 = num(k1), x2 = k2.map { num($0) }
            if x1 == nil && x2 == nil { continue }
            let isOn = (x1 != nil && x1! != 0) || (x2 != nil && x2! != 0)
            lampRows.append(Lamp(label: label, value: isOn ? "亮" : "灭"))
        }

        var extraRows: [Row] = []
        if let hood = ciNumber(ctrl, ["Hood", "hood"]) {
            extraRows.append(Row(label: "引擎盖", value: hood == 0 ? "关闭" : "开启",
                                 cls: hood != 0 ? "bad" : "ok"))
        }
        if let sunroof = ciNumber(ctrl, ["Sunroof", "sunroof"]) {
            extraRows.append(Row(label: "天窗", value: sunroof == 0 ? "关闭" : "开启",
                                 cls: sunroof != 0 ? "bad" : "ok"))
        }

        let badCount = doorRows.filter { $0.cls == "bad" }.count
            + windowRows.filter { $0.cls == "bad" }.count
            + extraRows.filter { $0.cls == "bad" }.count

        self.doorRows = doorRows
        self.windowRows = windowRows
        self.extraRows = extraRows
        self.lampRows = lampRows
        self.summary = doorRows.isEmpty && windowRows.isEmpty && lampRows.isEmpty
            ? "--"
            : (badCount > 0 ? "\(badCount) 项异常" : "全部正常")
        self.cls = badCount > 0 ? "bad" : "ok"
    }
}
