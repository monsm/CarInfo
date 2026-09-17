import SwiftUI

// 全量数据页：把原始报文逐字段结构化排版（对应小程序 data.js + texts.js 语义）
// 支持 8 种 kind；analysis 为统一分析层输出的「结论树」。

struct DataView: View {
    private let store = AppStore.shared

    enum Kind: String, CaseIterable, Identifiable {
        case status, charge, location, env, user, car, check, analysis
        var id: String { rawValue }
        var title: String {
            switch self {
            case .status: "全量车况数据"; case .charge: "充电数据"; case .location: "定位数据"
            case .env: "环境与PM2.5"; case .check: "检测报告原文"; case .user: "用户资料"
            case .car: "车辆档案原文"; case .analysis: "全量分析"
            }
        }
    }

    @State private var kind: Kind
    @State private var blocks: [Block] = []
    @State private var loading = true
    @State private var errText = ""

    init(kind: Kind = .status) {
        _kind = State(wrappedValue: kind)
    }

    struct Block: Identifiable {
        let h: String
        let rows: [(k: String, v: String)]
        var id: String { h }
    }

    var body: some View {
        VStack(spacing: 0) {
            // kind 切换器（8 种数据视图）
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(DataView.Kind.allCases) { k in
                        Button(k.title) {
                            kind = k
                            refresh()
                        }
                        .font(.system(size: 13, weight: kind == k ? .semibold : .regular))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Capsule().fill(kind == k ? Color.accentColor.opacity(0.15) : Color(.systemGray6)))
                        .foregroundStyle(kind == k ? Color.accentColor : .secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .background(Color(.systemBackground))
            Divider()
            ScrollView {
            VStack(spacing: Theme.cardSpacing) {
                if !loading && blocks.isEmpty {
                    ContentUnavailableView(errText.isEmpty ? "暂无数据" : errText, systemImage: "doc", description: Text("暂无数据"))
                } else {
                    ForEach(blocks) { b in
                        CardBox(title: b.h) {
                            VStack(spacing: 0) {
                                ForEach(Array(b.rows.enumerated()), id: \.offset) { _, r in
                                    HStack(alignment: .top) {
                                        Text(r.k).font(.system(size: 13)).foregroundStyle(.secondary)
                                        Spacer(minLength: 12)
                                        Text(r.v).font(.system(size: 13, design: .monospaced)).foregroundStyle(.primary)
                                            .multilineTextAlignment(.trailing).lineLimit(3)
                                    }
                                    .padding(.vertical, 7)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(kind.title)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    Button { copyAll() } label: { Image(systemName: "doc.on.doc") }
                    Button { refresh() } label: { Image(systemName: "arrow.clockwise") }
                    ShareLink(item: shareText, subject: Text("全量数据 · \(kind.title)"), preview: SharePreview(kind.title, text: shareText)) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
        .onAppear { refresh() }
    }

    private func refresh() {
        loading = true
        Task { await load() }
    }

    @MainActor
    private func load() async {
        let carId = store.carId
        var newBlocks: [Block] = []
        var err = ""

        switch kind {
        case .analysis:
            newBlocks = analysisBlocks()
        case .status:
            let raw = store.caches["control"] as? [String: Any]
            newBlocks = raw.map { statusBlocks($0) } ?? []
            if newBlocks.isEmpty { err = "暂无全车状态数据" }
        case .charge:
            let raw = store.caches["charge"] as? [String: Any]
            newBlocks = raw.map { chargeBlocks($0) } ?? []
            if newBlocks.isEmpty { err = "暂无充电数据" }
        case .location:
            let raw = store.caches["location"] as? [String: Any]
            newBlocks = raw.map { locationBlocks($0) } ?? []
            if newBlocks.isEmpty { err = "暂无定位数据" }
        case .env:
            let raw = store.caches["pm25"] as? [String: Any]
            newBlocks = raw.map { envBlocks($0) } ?? []
            if newBlocks.isEmpty { err = "暂无环境数据" }
        case .check:
            let raw = store.caches["check"] as? [String: Any]
            newBlocks = raw.map { checkBlocks($0) } ?? []
            if newBlocks.isEmpty { err = "暂无检测报告" }
        case .user:
            let raw = store.user
            newBlocks = raw.map { userBlocks($0) } ?? []
            if newBlocks.isEmpty { err = "暂无用户资料" }
        case .car:
            let raw = store.car
            newBlocks = raw.map { carBlocks($0) } ?? []
            if newBlocks.isEmpty { err = "暂无车辆档案" }
        }

        // 缓存为空时尝试拉取
        if newBlocks.isEmpty && kind != .analysis && kind != .user && kind != .car && !carId.isEmpty {
            await fetchMissing()
            newBlocks = reloadBlocks()
        }

        blocks = newBlocks
        errText = err
        loading = false
    }

    private func fetchMissing() async {
        let api = APIClient.shared
        let carId = store.carId
        switch kind {
        case .status: if let v = try? await api.getControl(carId: carId) { store.saveCache(["control": v]) }
        case .charge: if let v = try? await api.getCharge(carId: carId) { store.saveCache(["charge": v]) }
        case .location: if let v = try? await api.getLocation(carId: carId) { store.saveCache(["location": v]) }
        case .env: if let v = try? await api.getCarPm25(carId: carId) { store.saveCache(["pm25": v]) }
        case .check: if let v = try? await api.getCarCheck(carId: carId) { store.saveCache(["check": v]) }
        default: break
        }
    }

    private func reloadBlocks() -> [Block] {
        switch kind {
        case .status: return (store.caches["control"] as? [String: Any]).map(statusBlocks) ?? []
        case .charge: return (store.caches["charge"] as? [String: Any]).map(chargeBlocks) ?? []
        case .location: return (store.caches["location"] as? [String: Any]).map(locationBlocks) ?? []
        case .env: return (store.caches["pm25"] as? [String: Any]).map(envBlocks) ?? []
        case .check: return (store.caches["check"] as? [String: Any]).map(checkBlocks) ?? []
        default: return []
        }
    }

    private func rows(_ d: [String: Any], _ keys: [String]) -> [(String, String)] {
        keys.compactMap { k in
            let v = ciString(d, [k])
            return (v?.isEmpty ?? true) ? nil : (k, v!)
        }
    }

    private func statusBlocks(_ d: [String: Any]) -> [Block] {
        var out: [Block] = []
        out.append(Block(h: "核心状态", rows: rows(d, ["CarStatus", "Status", "FireStatus", "VehicleSpeed", "TotalOdometer", "ValidGps", "Lat", "Lng", "Alti", "Heading", "SatNum"])))
        out.append(Block(h: "门窗锁", rows: rows(d, ["Door", "Window", "Hood", "Trunk", "Sunroof", "DriverDoorLock", "LeftFrontDoor", "RightFrontDoor", "LeftRearDoor", "RightRearDoor"])))
        out.append(Block(h: "灯光", rows: rows(d, ["LowBeam", "HighBeam", "FrontFoglamp", "RearFoglamp", "PositionLamp"])))
        out.append(Block(h: "电池核心", rows: rows(d, ["Soc", "RemainPower", "RemainedPowerMile", "TotalVoltage", "TotalCurrent", "InsulateResistance", "PowerBatteryStatus"])))
        out.append(Block(h: "轮胎", rows: rows(d, ["LfTyrePressure", "RfTyrePressure", "LrTyrePressure", "RrTyrePressure", "LeftFrontTireTemperature", "RightFrontTireTemperature"])))
        out.append(Block(h: "故障码", rows: rows(d, ["EngineFaultCount", "EngineFaultCodes", "DriveMotorFaultCount", "DriveMotorFaultCodes", "RechargeableStorageDevicesFaultCount", "RechargeableStorageDevicesFaultCodes"])))
        out.append(Block(h: "系统标识", rows: rows(d, ["Vin", "CarId", "UserId", "Tuid", "LastUpdatedTime"])))
        return out
    }

    private func chargeBlocks(_ d: [String: Any]) -> [Block] {
        [Block(h: "充电状态", rows: rows(d, ["ChrgStatus", "RemainPower", "RemainedPowerMile", "ChargDeltMins", "ChargeStarttime", "ChargeStoptime", "PowerLineStatus", "BatteryHeatingStatus", "ChargeReservationStatus", "ReservationUseVehicleTime"]))]
    }

    private func locationBlocks(_ d: [String: Any]) -> [Block] {
        [Block(h: "定位", rows: rows(d, ["CarId", "Lng", "Lat", "AddrDesc", "GpsTime", "Speed", "Heading", "Status", "ValidGps"]))]
    }

    private func envBlocks(_ d: [String: Any]) -> [Block] {
        [Block(h: "环境与定位", rows: rows(d, ["Pm25InnnerCarValue", "Pm25OuterCarValue", "VehicleTemperature", "EnvironmentalTemperature", "UpdateTime"]))]
    }

    private func userBlocks(_ d: [String: Any]) -> [Block] {
        [
            Block(h: "核心账户", rows: rows(d, ["UserId", "UserNickname", "UserFullname", "Mobile", "Gender", "RealnameAuthed"])),
            Block(h: "证件联系", rows: rows(d, ["IdcardType", "Idcard", "Birthday", "Email", "Address", "Telephone"])),
            Block(h: "账号状态", rows: rows(d, ["OpenId", "RegisterTime", "LastLoginTime", "Status", "Locked", "Deleted"]))
        ]
    }

    private func carBlocks(_ d: [String: Any]) -> [Block] {
        [
            Block(h: "身份识别", rows: rows(d, ["CarId", "Vin", "CarName", "PlateNumber", "IsNev", "Pin"])),
            Block(h: "基础配置", rows: rows(d, ["ModelCode", "ConfCode", "ConfName", "BrandCode", "SeriesCode", "Color"])),
            Block(h: "注册与保险", rows: rows(d, ["RegisterTime", "ProductTime", "InsuranceEndDate", "InsuranceCompany", "InsurancePhone"]))
        ]
    }

    private func checkBlocks(_ d: [String: Any]) -> [Block] {
        var out: [Block] = [Block(h: "检测概览", rows: rows(d, ["CheckHistoryId", "UserId", "CarId", "CheckTime", "Score", "NormalCount", "RiskCount", "FaultCount"]))]
        if let details = ciArray(d, ["Details"]) {
            for sys in details {
                let sName = ciString(sys, ["ItemName"]) ?? "系统"
                var childRows: [(String, String)] = []
                for item in ciArray(sys, ["Child"]) ?? [] {
                    let name = ciString(item, ["ItemName"]) ?? ""
                    let status = ciString(item, ["Status"]) ?? "正常"
                    childRows.append((name, "状态 \(status) · 检测值 \(ciString(item, ["DetectValue"]) ?? "--")"))
                }
                out.append(Block(h: sName, rows: childRows))
            }
        }
        return out
    }

    private func analysisBlocks() -> [Block] {
        let s = AN.summarize(store.caches, store.car)
        var out: [Block] = []
        out.append(Block(h: "综合结论", rows: [
            ("状态", s.overall.title), ("说明", s.overall.sub)
        ].filter { !$0.1.isEmpty }))
        for d in s.domains {
            var rows: [(String, String)] = []
            if !d.title.isEmpty { rows.append(("结论", d.title)) }
            for r in d.reasons {
                let tag = r.cls == "bad" ? "异常" : (r.cls == "warn" ? "关注" : "正常")
                rows.append((tag, r.t))
            }
            for m in d.metrics { rows.append((m.k, m.v)) }
            out.append(Block(h: d.label, rows: rows))
        }
        return out
    }

    private func copyAll() {
        var lines: [String] = []
        for b in blocks {
            if !b.h.isEmpty { lines.append("【\(b.h)】") }
            for r in b.rows { lines.append("\(r.k) : \(r.v)") }
        }
        UIPasteboard.general.string = lines.joined(separator: "\n")
    }

    // 导出文本（复制 / 分享共用）。
    private var shareText: String {
        var lines: [String] = ["【\(kind.title)  ·  \(VM.nowText())】"]
        for b in blocks {
            if !b.h.isEmpty { lines.append("【\(b.h)】") }
            for r in b.rows { lines.append("\(r.k) : \(r.v)") }
        }
        return lines.joined(separator: "\n")
    }
}
