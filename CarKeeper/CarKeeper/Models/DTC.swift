import Foundation


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
