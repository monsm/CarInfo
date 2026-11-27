import SwiftUI
import UIKit


struct HealthDataView: View {
    private let store = AppStore.shared
    @State private var model: HealthModel?
    @State private var loading = true
    @State private var errText: String?
    @State private var expandedSystems: Set<String> = []
    @State private var fullyOpen: Set<String> = []
    @State private var loadTask: Task<Void, Never>? = nil
    @Environment(\.cardViewport) private var cardViewport

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if loading {
                loadingState
            } else if let model {
                scoreSection(model)
                systemsSection(model)
                faultsSection
                infoSection(model)
            } else if let err = errText {
                DSPlaceholder(icon: "exclamationmark.triangle",
                              title: "读取失败",
                              message: err,
                              actionTitle: "重新加载",
                              cls: "warn") { Task { await load() } }
            } else {
                DSPlaceholder(icon: "checkmark.shield",
                              title: "暂无检测报告",
                              message: "完成一次全车检测后显示",
                              actionTitle: "重新加载") { Task { await load() } }
            }
            RawDataSection(kind: .check)
        }
        .onAppear {
            autoOpenBadSystems()
            loadIfNeeded()
        }
        .onDisappear { loadTask?.cancel(); loadTask = nil }
    }


    private var loadingState: some View {
        DSLoadingSkeleton(message: "加载中…", heights: [96, 64, 44],
                          label: "正在读取健康报告")
    }


    private func scoreSection(_ m: HealthModel) -> some View {
        let tint = scoreColor(m.scorePct)
        return VStack(alignment: .leading, spacing: 0) {
            DSSectionHeader(title: "健康评分")

            HStack(alignment: .center, spacing: TokensSpacing.lg) {
                DSRing(progress: Double(max(0, min(100, m.scorePct))) / 100.0, tint: tint) {
                    VStack(spacing: TokensSpacing.xxs) {
                        Text(m.score.isEmpty ? "--" : m.score)
                            .font(TokensTypo.display(44, weight: .semibold))
                            .foregroundStyle(tint)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text("分")
                            .font(TokensTypo.caption)
                            .foregroundStyle(TokensPalette.secondary)
                    }
                }
                .accessibilityLabel(Text("健康评分"))
                .accessibilityValue(Text(m.score.isEmpty ? "没有报告" : "\(m.score) 分"))

                VStack(alignment: .leading, spacing: TokensSpacing.sm) {
                    Text(verdict(m.scorePct))
                        .font(TokensTypo.title3)
                        .foregroundStyle(TokensPalette.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let vs = m.vehicleStatus, !vs.isEmpty {
                        DSChip(text: vehicleText(vs), cls: vehicleCls(vs), icon: vehicleIcon(vs))
                    }
                    if !m.time.isEmpty {
                        Text("最近检测 \(m.time)")
                            .font(TokensTypo.footnote)
                            .foregroundStyle(TokensPalette.tertiary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.top, TokensSpacing.sm)
            .padding(.bottom, TokensSpacing.lg)

            if !m.counts.isEmpty {
                DSStatStrip(items: m.counts.map {
                    DSStatStrip.Item($0.key, $0.n, cls: $0.cls, icon: $0.iconName)
                })
                    .overlay(alignment: .top) { DSDivider() }
                    .overlay(alignment: .bottom) { DSDivider() }
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var faultsSection: some View {
        let b = batteryModel(store.caches)
        let active = b.faults.filter { $0.count > 0 }
        if b.hasCtrl {
            DSSection(title: "故障码",
                      trailing: b.faultTotal > 0 ? "共 \(b.faultTotal) 条" : "无故障",
                      trailingCls: b.faultTotal > 0 ? "bad" : "ok") {
                if active.isEmpty {
                    DSGroupRow(showsSeparator: false) {
                        Text("均无故障")
                            .font(TokensTypo.footnote)
                            .foregroundStyle(TokensPalette.secondary)
                    }
                } else {
                    ForEach(Array(active.enumerated()), id: \.element.id) { idx, f in
                        DSGroupRow(showsSeparator: idx < active.count - 1) {
                            DSKeyValueRow(key: f.name,
                                          value: f.codes.isEmpty ? "\(f.count) 条"
                                                                 : "\(f.count) 条 · \(f.codes)",
                                          valueCls: "bad")
                        }
                    }
                }
            }
        }
    }


    private func systemsSection(_ m: HealthModel) -> some View {
        DSGroup(title: "检测系统",
                trailing: "\(m.systems.count) 项",
                footer: m.systems.isEmpty ? "没有分系统数据" : nil) {
            ForEach(Array(m.systems.enumerated()), id: \.element.id) { idx, sys in
                systemRow(sys, model: m, showsSeparator: idx < m.systems.count - 1)
            }
        }
    }


    private var fitWidth: CGFloat { CardFit.contentWidth(cardViewport) }

    private enum Detail: Identifiable {
        case child(HealthItem)
        case dtc(HealthItem)

        var id: String {
            switch self {
            case .child(let i): return "c:" + i.id
            case .dtc(let i):   return "d:" + i.id
            }
        }
    }

    private func expandedDetails(_ sys: HealthSystem) -> [Detail] {
        sys.children.map(Detail.child) + dtcItems(sys).map(Detail.dtc)
    }

    private func fitRow(_ d: Detail) -> CardFit.Row {
        switch d {
        case .child(let item):
            var blocks: [CardFit.Block] = [
                .pair(item.name, .subheadline, item.statusText, .subheadline, cap: 2)
            ]
            if let v = item.detect, !v.isEmpty {
                blocks.append(.gap(TokensSpacing.md))
                blocks.append(.pair("检测值", .footnote, v, .footnote, cap: nil))
            }
            if let v = item.suggest, !v.isEmpty {
                blocks.append(.gap(TokensSpacing.md))
                blocks.append(.pair("参考范围", .footnote, v, .footnote, cap: nil))
            }
            if let v = item.desc, !v.isEmpty {
                blocks.append(.gap(TokensSpacing.sm))
                blocks.append(.text(v, .footnote, cap: nil))
            }
            return CardFit.Row(blocks, padTop: TokensSpacing.sm, padBottom: TokensSpacing.sm)
        case .dtc(let code):
            return .keyValue(code.name, DTCDictionary.translate(code.name))
        }
    }

    @ViewBuilder
    private func detailView(_ d: Detail) -> some View {
        switch d {
        case .child(let item):
            childRow(item)
        case .dtc(let code):
            DSKeyValueRow(key: code.name,
                          value: DTCDictionary.translate(code.name),
                          valueCls: "warn")
        }
    }

    private func collapsedFitRow(_ sys: HealthSystem) -> CardFit.Row {
        var blocks: [CardFit.Block] = [.text(sys.name, .body, cap: nil)]
        if !sys.statusText.isEmpty {
            blocks.append(.gap(TokensSpacing.xs))
            blocks.append(.text(sys.statusText, .footnote, cap: nil))
        }
        return CardFit.Row(blocks, floor: TokensSpacing.row)
    }

    private func systemsFixedHeight(_ m: HealthModel) -> CGFloat {
        var h = CardFit.textHeight("检测系统", style: .footnote, width: fitWidth) + TokensSpacing.sm
        for sys in m.systems {
            h += CardFit.height(of: collapsedFitRow(sys), width: fitWidth) + TokensHair.line
        }
        return h
    }

    private func verdictFor(_ details: [Detail], model m: HealthModel) -> CardFit.Verdict {
        CardFit.verdict(details.map(fitRow), width: fitWidth, viewport: cardViewport,
                        reserved: systemsFixedHeight(m))
    }

    private func planFor(_ sys: HealthSystem, model m: HealthModel,
                         details: [Detail]) -> CardFit.Plan {
        if fullyOpen.contains(sys.name) { return .all }
        return CardFit.plan(details.map(fitRow), width: fitWidth, viewport: cardViewport,
                            reserved: systemsFixedHeight(m))
    }

    private func autoOpenBadSystems() {
        guard expandedSystems.isEmpty, let m = model else { return }
        let bad = m.systems.filter { $0.statusCls == "bad" }
        guard let first = bad.first else { return }
        guard cardViewport.height > 0, fitWidth > 0 else {
            expandedSystems.insert(first.name)
            return
        }
        let fixed = systemsFixedHeight(m)
        var used = fixed
        var opened = 0
        for sys in bad {
            let h = CardFit.height(of: expandedDetails(sys).map(fitRow), width: fitWidth)
            if opened > 0, used + h > cardViewport.height { break }
            expandedSystems.insert(sys.name)
            used += h
            opened += 1
        }
    }

    private func systemRow(_ sys: HealthSystem, model m: HealthModel,
                           showsSeparator: Bool) -> some View {
        let isOpen = expandedSystems.contains(sys.name)
        let tint = TokensPalette.statusColor(sys.statusCls)
        return VStack(alignment: .leading, spacing: 0) {
            Button { toggle(sys.name) } label: {
                HStack(spacing: TokensSpacing.md) {
                    Image(safeSymbol: systemIcon(sys.name), fallback: "circle")
                        .font(TokensTypo.fixed(TokensSize.icon))
                        .foregroundStyle(tint)
                        .frame(width: TokensSize.iconColumn)
                    VStack(alignment: .leading, spacing: TokensSpacing.xs) {
                        Text(sys.name)
                            .font(TokensTypo.body)
                            .foregroundStyle(TokensPalette.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        Text(sys.statusText.isEmpty ? "—" : sys.statusText)
                            .font(TokensTypo.footnote)
                            .foregroundStyle(tint)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    Spacer(minLength: TokensSpacing.sm)
                    Text("\(sys.healthPct)%")
                        .font(TokensTypo.data.weight(.semibold))
                        .foregroundStyle(tint)
                        .lineLimit(1)
                    Image(safeSymbol: "chevron.down", fallback: "chevron.down")
                        .font(TokensTypo.caption.weight(.semibold))
                        .foregroundStyle(TokensPalette.tertiary)
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                        .animation(TokensMotion.tap, value: isOpen)
                }
                .frame(minHeight: TokensSpacing.row)
                .contentShape(Rectangle())
            }
            .buttonStyle(DSRowButtonStyle())
            .accessibilityLabel(Text("\(sys.name)，\(sys.statusText)，健康度 \(sys.healthPct)%"))
            .accessibilityHint(Text(isOpen ? "点击收起明细" : "点击展开明细"))

            if isOpen {
                let details = expandedDetails(sys)
                let plan = planFor(sys, model: m, details: details)
                let shown = plan.keep.map { Array(details.prefix($0)) } ?? details
                let screens = verdictFor(details, model: m).screens
                let inset: Color = TokensPalette.surface.opacity(0.6)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { idx, item in
                        DSGroupRow(showsSeparator: idx < shown.count - 1
                                   || plan.hidden > 0
                                   || fullyOpen.contains(sys.name)) {
                            detailView(item)
                        }
                    }
                    if plan.hidden > 0 {
                        DSGroupRow(showsSeparator: false) {
                            DSCardMoreRow(rest: plan.hidden, screens: screens, open: false) {
                                withAnimation(TokensMotion.count) { _ = fullyOpen.insert(sys.name) }
                            }
                        }
                    } else if fullyOpen.contains(sys.name), details.count > 1 {
                        DSGroupRow(showsSeparator: false) {
                            DSCardMoreRow.collapse {
                                withAnimation(TokensMotion.count) { _ = fullyOpen.remove(sys.name) }
                            }
                        }
                    }
                }
                .background(inset)
            }

            if showsSeparator { DSSeparator(inset: 0) }
        }
    }

    private func childRow(_ item: HealthItem) -> some View {
        VStack(alignment: .leading, spacing: TokensSpacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: TokensSpacing.sm) {
                Text(item.name)
                    .font(TokensTypo.subheadline)
                    .foregroundStyle(TokensPalette.primary)
                    .lineLimit(2)
                Spacer(minLength: TokensSpacing.sm)
                Text(item.statusText)
                    .font(TokensTypo.subheadline)
                    .foregroundStyle(TokensPalette.statusColor(item.statusCls))
            }
            if let d = item.detect, !d.isEmpty { DSKeyValueRow(key: "检测值", value: d) }
            if let s = item.suggest, !s.isEmpty { DSKeyValueRow(key: "参考范围", value: s) }
            if let desc = item.desc, !desc.isEmpty {
                Text(desc)
                    .font(TokensTypo.footnote)
                    .foregroundStyle(TokensPalette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, TokensSpacing.sm)
        .accessibilityElement(children: .combine)
    }

    private func dtcItems(_ sys: HealthSystem) -> [HealthItem] {
        sys.children.filter { $0.name.range(of: "P\\d", options: .regularExpression) != nil }
    }


    private func infoSection(_ m: HealthModel) -> some View {
        let hasMeta = (m.checkId?.isEmpty == false) || (m.endTime?.isEmpty == false) || !m.time.isEmpty
        return DSGroup(title: "检测信息",
                       footer: hasMeta ? nil : "没有检测 ID 与时间戳") {
            if let cid = m.checkId, !cid.isEmpty { checkIdRow(cid) }
            if let et = m.endTime, !et.isEmpty {
                DSGroupRow {
                    DSRow(icon: "clock.arrow.circlepath", title: "数据更新", value: et)
                }
            }
            if !m.time.isEmpty {
                DSGroupRow(showsSeparator: false) {
                    DSRow(icon: "calendar.badge.clock", title: "最近检测", value: m.time)
                }
            }
        }
    }

    private func checkIdRow(_ cid: String) -> some View {
        DSGroupRow {
            Button {
                UIPasteboard.general.string = cid
                TokensHaptic.result(true)
                ToastManager.shared.show("检测 ID 已复制", icon: "doc.on.doc.fill")
            } label: {
                HStack(spacing: TokensSpacing.md) {
                    Image(safeSymbol: "number.square.fill", fallback: "number")
                        .font(TokensTypo.fixed(TokensSize.icon))
                        .foregroundStyle(TokensPalette.ambient)
                        .frame(width: TokensSize.iconColumn)
                    VStack(alignment: .leading, spacing: TokensSpacing.xxs) {
                        Text("检测 ID")
                            .font(TokensTypo.body)
                            .foregroundStyle(TokensPalette.primary)
                        Text(cid)
                            .font(TokensTypo.digits(15))
                            .foregroundStyle(TokensPalette.secondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: TokensSpacing.sm)
                    Image(safeSymbol: "doc.on.doc", fallback: "doc.on.doc")
                        .font(TokensTypo.fixed(15))
                        .foregroundStyle(TokensPalette.ambient)
                }
                .frame(minHeight: TokensSpacing.row)
                .contentShape(Rectangle())
            }
            .buttonStyle(DSRowButtonStyle())
            .accessibilityLabel(Text("检测 ID \(cid)，点击复制"))
        }
    }


    private func scoreColor(_ pct: Int) -> Color {
        switch pct {
        case 0...39:  return TokensPalette.error
        case 40...69: return TokensPalette.warning
        case 70...89: return TokensPalette.info
        default:      return TokensPalette.success
        }
    }

    private func verdict(_ pct: Int) -> String {
        switch pct {
        case 0...39:  return "建议尽快检修"
        case 40...69: return "建议安排检查"
        case 70...89: return "有少量项目需留意"
        default:      return "车况良好，无需处理"
        }
    }

    private func vehicleText(_ raw: String) -> String {
        switch raw {
        case "normal":  return "正常"
        case "fault":   return "故障"
        case "warning": return "预警"
        default:        return raw
        }
    }

    private func vehicleCls(_ raw: String) -> String {
        switch raw {
        case "normal":  return "ok"
        case "fault":   return "bad"
        case "warning": return "warn"
        default:        return "na"
        }
    }

    private func vehicleIcon(_ raw: String) -> String {
        switch raw {
        case "normal":  return "checkmark.circle.fill"
        case "fault":   return "xmark.octagon.fill"
        case "warning": return "exclamationmark.triangle.fill"
        default:        return "info.circle.fill"
        }
    }

    private func systemIcon(_ name: String) -> String {
        let n = name.lowercased()
        if name.contains("电池") || n.contains("battery") { return "battery.100" }
        if name.contains("充电") || n.contains("charge") { return "bolt.fill" }
        if name.contains("电机") || name.contains("驱动") { return "gearshape.2.fill" }
        if name.contains("制动") || name.contains("刹车") { return "octagon.fill" }
        if name.contains("轮胎") || name.contains("胎压") { return "circle.dashed" }
        if name.contains("灯光") || name.contains("照明") { return "lightbulb.fill" }
        if name.contains("空调") || name.contains("温控") { return "snowflake" }
        if name.contains("气囊") || name.contains("安全") { return "shield.fill" }
        if name.contains("故障") || name.contains("dtc") { return "exclamationmark.triangle.fill" }
        if name.contains("车身") || name.contains("门窗") { return "car.side.fill" }
        return "checkmark.shield.fill"
    }


    private func toggle(_ name: String) {
        withAnimation(TokensMotion.count) {
            if expandedSystems.contains(name) { expandedSystems.remove(name) }
            else { expandedSystems.insert(name) }
        }
        TokensHaptic.select()
    }


    private func loadIfNeeded() {
        loadTask = Task { await load() }
    }

    @MainActor
    private func load() async {
        guard !store.carId.isEmpty else { loading = false; return }
        let api = APIClient.shared
        do {
            let checkRaw = try await api.getCarCheck(carId: store.carId)
            store.saveCache(["check": checkRaw])
            model = VM.healthModel(store.caches["check"] as? [String: Any])
            errText = nil
        } catch {
            errText = error.localizedDescription
            if model == nil { loading = false }
        }
        loading = false
    }
}
