import SwiftUI


struct RawDataSection: View {
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
    @State private var loadTask: Task<Void, Never>? = nil

    init(kind: Kind = .analysis) {
        _kind = State(wrappedValue: kind)
    }

    struct Block: Identifiable {
        let h: String
        let rows: [(k: String, v: String)]
        var id: String { h }
    }

    var body: some View {
        Group {
            VStack(alignment: .leading, spacing: TokensSpacing.lg) {
                sectionBar
                if loading {
                    loadingState
                } else if blocks.isEmpty {
                    if !errText.isEmpty {
                        DSPlaceholder(icon: "exclamationmark.triangle",
                                      title: "读取失败",
                                      message: errText,
                                      actionTitle: "重新加载",
                                      cls: "warn") { reload() }
                    } else {
                        DSPlaceholder(icon: "doc.text.magnifyingglass",
                                      title: "暂无数据",
                                      message: store.carId.isEmpty ? "请先绑定车辆" : "下拉或点右上角刷新重试",
                                      actionTitle: "重新加载") { reload() }
                    }
                } else {
                    ForEach(Array(blocks.enumerated()), id: \.element.id) { idx, b in
                        blockView(b, isFirst: idx == 0)
                    }
                    Text(footerText)
                        .font(TokensTypo.footnote)
                        .foregroundStyle(TokensPalette.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, TokensHair.inset)
                }
            }
        }
        .onAppear { loadIfNeeded() }
        .onDisappear { loadTask?.cancel(); loadTask = nil }
    }

    private var sectionBar: some View {
        HStack(spacing: TokensSpacing.lg) {
            DSSectionHeader(title: "车端原始读数")
            kindMenu
            Button { copyAll() } label: { Image(safeSymbol: "doc.on.doc", fallback: "doc.on.doc") }
                .accessibilityLabel(Text("复制全部数据"))
            Button { reload() } label: { Image(safeSymbol: "arrow.clockwise", fallback: "arrow.clockwise") }
                .accessibilityLabel(Text("刷新"))
            ShareLink(item: shareText,
                      subject: Text("全量数据 · \(kind.title)"),
                      preview: SharePreview(kind.title)) {
                Image(safeSymbol: "square.and.arrow.up", fallback: "square.and.arrow.up")
            }
            .accessibilityLabel(Text("分享"))
        }
        .font(TokensTypo.fixed(15))
        .foregroundStyle(TokensPalette.ambient)
    }


    private var kindMenu: some View {
        Menu {
            ForEach(Kind.allCases) { k in
                Button {
                    guard k != kind else { return }
                    kind = k
                    onKindChange()
                } label: {
                    if k == kind {
                        Label(k.title, systemImage: "checkmark")
                    } else {
                        Text(k.title)
                    }
                }
            }
        } label: {
            HStack(spacing: TokensSpacing.xs) {
                Text(kind.title)
                    .font(TokensTypo.subheadline.weight(.semibold))
                Image(safeSymbol: "chevron.up.chevron.down", fallback: "chevron.up.chevron.down")
                    .font(TokensTypo.caption2.weight(.semibold))
            }
            .foregroundStyle(TokensPalette.ambient)
        }
        .accessibilityLabel(Text("数据分类：\(kind.title)"))
    }


    private var loadingState: some View {
        DSLoadingSkeleton(message: "正在整理 \(kind.title)…", heights: [44, 132, 88])
    }

    private var footerText: String {
        let fields = blocks.reduce(0) { $0 + $1.rows.count }
        var s = "共 \(blocks.count) 组 · \(fields) 项"
        let t = VM.nowText()
        if !t.isEmpty { s += " · \(t)" }
        return s
    }


    @ViewBuilder
    private func blockView(_ b: Block, isFirst: Bool) -> some View {
        if kind == .analysis && isFirst {
            analysisHero(b)
        } else {
            DSGroup(title: b.h, trailing: b.rows.isEmpty ? "无数据" : "\(b.rows.count)") {
                ForEach(Array(b.rows.enumerated()), id: \.offset) { idx, r in
                    DSGroupRow(showsSeparator: idx < b.rows.count - 1) {
                        if kind == .analysis {
                            DSKeyValueRow(key: r.v, value: r.k, valueCls: analysisCls(r.k), mono: false)
                        } else {
                            DSKeyValueRow(key: r.k, value: r.v, valueCls: rawCls(r.k, r.v))
                        }
                    }
                }
            }
        }
    }

    private func analysisHero(_ b: Block) -> some View {
        let headline = b.rows.first(where: { $0.k == "状态" })?.v ?? ""
        let detail = b.rows.first(where: { $0.k == "说明" })?.v ?? ""
        return VStack(alignment: .leading, spacing: 0) {
            DSSectionHeader(title: b.h)
            Text(headline.isEmpty ? "—" : headline)
                .font(TokensTypo.title2)
                .foregroundStyle(TokensPalette.primary)
                .fixedSize(horizontal: false, vertical: true)
            if !detail.isEmpty {
                Text(detail)
                    .font(TokensTypo.subheadline)
                    .foregroundStyle(TokensPalette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, TokensSpacing.xs)
            }
        }
        .accessibilityElement(children: .combine)
    }


    private func analysisCls(_ tag: String) -> String {
        switch tag {
        case "异常": return "bad"
        case "关注": return "warn"
        case "正常": return "ok"
        default:     return "na"
        }
    }

    private func rawCls(_ key: String, _ value: String) -> String {
        let k = key.lowercased()
        let v = value.trimmingCharacters(in: .whitespaces)
        if k.contains("faultcount") || k.contains("faultcode") {
            if v.isEmpty || v == "0" || v == "--" || v == "无" { return "ok" }
            return "bad"
        }
        if k == "carstatus" || k == "status" || k == "firestatus" || k == "validgps" {
            let lower = v.lowercased()
            if lower.contains("fault") || lower.contains("故障") { return "bad" }
            if lower.contains("warn") || lower.contains("预警") || lower == "0" { return "warn" }
            return "ok"
        }
        return "na"
    }


    private func reload() {
        loadTask?.cancel()
        loading = true
        loadTask = Task { await load() }
    }

    private func loadIfNeeded() {
        guard !store.carId.isEmpty else { loading = false; return }
        guard loadTask == nil || loadTask!.isCancelled else { return }
        switch kind {
        case .status, .charge, .location, .env, .check:
            loadTask = Task { await load() }
        default:
            blocks = reloadBlocks()
            errText = ""
            loading = false
        }
    }

    private func onKindChange() {
        loadTask?.cancel()
        loadTask = nil
        blocks = reloadBlocks()
        errText = ""
        loading = blocks.isEmpty && !store.carId.isEmpty
        if loading { loadTask = Task { await load() } }
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

        if kind != .analysis && kind != .user && kind != .car && !carId.isEmpty {
            await fetchMissing()
            newBlocks = reloadBlocks()
            if !newBlocks.isEmpty { err = "" }
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
        out.append(Block(h: "核心状态", rows: rows(d, ["CarStatus", "Status", "FireStatus", "VehicleSpeed",
 "TotalOdometer", "ValidGps", "Lat", "Lng", "Alti", "Heading", "SatNum"])))
        out.append(Block(h: "门窗锁", rows: rows(d, ["Door", "Window", "Hood", "Trunk", "Sunroof", "DriverDoorLock",
 "LeftFrontDoor", "RightFrontDoor", "LeftRearDoor", "RightRearDoor"])))
        out.append(Block(h: "灯光", rows: rows(d, ["LowBeam", "HighBeam", "FrontFoglamp", "RearFoglamp",
 "PositionLamp"])))
        out.append(Block(h: "电池核心", rows: rows(d, ["Soc", "RemainPower", "RemainedPowerMile", "TotalVoltage",
 "TotalCurrent", "InsulateResistance", "PowerBatteryStatus"])))
        out.append(Block(h: "轮胎", rows: rows(d, ["LfTyrePressure", "RfTyrePressure", "LrTyrePressure",
 "RrTyrePressure", "LeftFrontTireTemperature", "RightFrontTireTemperature"])))
        out.append(Block(h: "故障码", rows: rows(d, ["EngineFaultCount", "EngineFaultCodes", "DriveMotorFaultCount",
 "DriveMotorFaultCodes", "RechargeableStorageDevicesFaultCount", "RechargeableStorageDevicesFaultCodes"])))
        out.append(Block(h: "系统标识", rows: rows(d, ["Vin", "CarId", "UserId", "Tuid", "LastUpdatedTime"])))
        return out
    }

    private func chargeBlocks(_ d: [String: Any]) -> [Block] {
        [Block(h: "充电状态", rows: rows(d, [
            "ChrgStatus", "RemainPower", "RemainedPowerMile", "ChargDeltMins",
            "ChargeStarttime", "ChargeStoptime", "PowerLineStatus",
            "BatteryHeatingStatus", "ChargeReservationStatus",
            "ReservationUseVehicleTime"
        ]))]
    }

    private func locationBlocks(_ d: [String: Any]) -> [Block] {
        [Block(h: "定位", rows: rows(d, ["CarId", "Lng", "Lat", "AddrDesc", "GpsTime", "Speed", "Heading", "Status",
 "ValidGps"]))]
    }

    private func envBlocks(_ d: [String: Any]) -> [Block] {
        [Block(h: "环境与定位", rows: rows(d, ["Pm25InnnerCarValue", "Pm25OuterCarValue", "VehicleTemperature",
 "EnvironmentalTemperature", "UpdateTime"]))]
    }

    private func userBlocks(_ d: [String: Any]) -> [Block] {
        [
            Block(h: "核心账户", rows: rows(d, ["UserId", "UserNickname", "UserFullname", "Mobile", "Gender",
 "RealnameAuthed"])),
            Block(h: "证件联系", rows: rows(d, ["IdcardType", "Idcard", "Birthday", "Email", "Address", "Telephone"])),
            Block(h: "账号状态", rows: rows(d, ["OpenId", "RegisterTime", "LastLoginTime", "Status", "Locked", "Deleted"]))
        ]
    }

    private func carBlocks(_ d: [String: Any]) -> [Block] {
        [
            Block(h: "身份识别", rows: rows(d, ["CarId", "Vin", "CarName", "PlateNumber", "IsNev", "Pin"])),
            Block(h: "基础配置", rows: rows(d, ["ModelCode", "ConfCode", "ConfName", "BrandCode", "SeriesCode", "Color"])),
            Block(h: "注册与保险", rows: rows(d, ["RegisterTime", "ProductTime", "InsuranceEndDate", "InsuranceCompany",
 "InsurancePhone"]))
        ]
    }

    private func checkBlocks(_ d: [String: Any]) -> [Block] {
        var out: [Block] = [Block(h: "检测概览", rows: rows(d, ["CheckHistoryId", "UserId", "CarId", "CheckTime",
 "Score", "NormalCount", "RiskCount", "FaultCount"]))]
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
        UIPasteboard.general.string = shareText
        TokensHaptic.result(true)
        ToastManager.shared.show("数据已复制", icon: "doc.on.doc.fill")
    }

    private var shareText: String {
        var lines: [String] = ["【\(kind.title)  ·  \(VM.nowText())】"]
        for b in blocks {
            if !b.h.isEmpty { lines.append("【\(b.h)】") }
            for r in b.rows { lines.append("\(r.k) : \(r.v)") }
        }
        return lines.joined(separator: "\n")
    }
}
