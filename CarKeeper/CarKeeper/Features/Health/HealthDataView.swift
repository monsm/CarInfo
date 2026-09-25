import SwiftUI
import UIKit

// =============================================================================
//  健康报告 —— v4 信息架构
// =============================================================================
//  ① 评分区：一个大数字（综合评分）+ 一句结论 + 一条光条 + 三条带图标的计数
//     没有仪表环：环和数字说的是同一件事，v4 用它只表达一次。
//  ② 检测系统：inset-grouped 分组，逐项可展开（展开区是内凹表面 + 发丝线）
//  ③ 检测信息：检测 ID / 数据更新 / 最近检测 / 车辆状态，ID 可一键复制
//
//  规则：分组标题在画布上、行在分组表面上；颜色只表达状态；玻璃不进入内容层。
// =============================================================================

/// 体检与数据 —— 车端自检的结论（评分 / 逐系统明细 / 检测信息）+ 它依据的原始字段。
///
/// 原为「健康报告」页（`HealthView`）。批 6 把「全量数据」吸收进来：
/// 结论与依据同源（都是同一次 `carcheck`），分成两页只是把一句话拆成两屏。
struct HealthDataView: View {
    private let store = AppStore.shared
    @State private var model: HealthModel?
    @State private var loading = true
    @State private var errText: String?
    @State private var expandedSystems: Set<String> = []
    /// 被「摊开全部」的那几个分系统（分块之后要能合回去，见 `DSCardMoreRow`）
    @State private var fullyOpen: Set<String> = []
    @State private var loadTask: Task<Void, Never>? = nil
    /// 卡片量到的可用区域（`ArcStack` 写进来的真数；量不到时是 `.zero`）
    @Environment(\.cardViewport) private var cardViewport

    var body: some View {
        //  正文只提供内容 —— 页面外壳（滚动 / 纸面底 / 页标题）不在这里，
        //  它是 `VehicleView` 里那张叫「体检」的卡（邻居 `MileageJournalSection`
        //  / `VehicleTipsSection` / `ExportDataSection` 同一条约定：一个页面只能
        //  有一个所有者，而这里的所有者是那张卡）。
        //
        //  此前这里包着 `DSPaperPage`，于是叠进卡里的是**第二层 ScrollView +
        //  第二层纸面底 + 自己的左右内边距**：卡 18pt + 纸 16pt = 内容距卡边
        //  34pt，比别人窄一圈；而里外两层都可滚动时，手势塌到内层（它拿到的是
        //  无限高，永远不会滚）—— 用户 2026-09-25：「每个卡片仔细核对，
        //  内容展开后是否拥挤」。现在只剩卡片自己那一层。
        //
        //  随之失效的是 `.refreshable`（它必须挂在 ScrollView 上）：读不到时
        //  那条「重新加载」是重试入口，它本来就在。
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
            // 依据：同一次 carcheck 的原文（原「全量数据」页）。
            // 它在 if/else **之外** —— 体检报告读不到时，原始字段往往正是排错要看的东西。
            RawDataSection(kind: .check)
        }
        .onAppear {
            autoOpenBadSystems()
            loadIfNeeded()
        }
        .onDisappear { loadTask?.cancel(); loadTask = nil }
    }

    // MARK: - 加载态（安静的内容占位，不加边距 —— 画布已经统一给了 20pt）

    private var loadingState: some View {
        VStack(alignment: .leading, spacing: TokensSpacing.md) {
            HStack(spacing: TokensSpacing.sm) {
                ProgressView().controlSize(.small)
                Text("加载中…")
                    .font(TokensTypo.footnote)
                    .foregroundStyle(TokensPalette.secondary)
            }
            DSSkeleton(height: 96)
            DSSkeleton(height: 64)
            DSSkeleton(height: 44)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("正在读取健康报告"))
    }

    // MARK: - ① 评分区

    private func scoreSection(_ m: HealthModel) -> some View {
        let tint = scoreColor(m.scorePct)
        return VStack(alignment: .leading, spacing: 0) {
            DSSectionHeader(title: "健康评分")

            HStack(spacing: TokensSpacing.sm) {
                if let vs = m.vehicleStatus, !vs.isEmpty {
                    DSChip(text: vehicleText(vs), cls: vehicleCls(vs), icon: vehicleIcon(vs))
                }
                Spacer(minLength: TokensSpacing.sm)
                if !m.time.isEmpty {
                    Text("最近检测 \(m.time)")
                        .font(TokensTypo.footnote)
                        .foregroundStyle(TokensPalette.secondary)
                }
            }

            DSBigNumber(value: m.score.isEmpty ? "--" : m.score,
                        unit: "分",
                        caption: verdict(m.scorePct),
                        size: 96,
                        tint: tint)
                .padding(.top, TokensSpacing.lg)

            DSLightBar(progress: Double(max(0, min(100, m.scorePct))) / 100.0,
                       height: 6,
                       tint: LinearGradient(colors: [TokensPalette.lightSource, tint.opacity(0.72), tint],
                                            startPoint: .leading, endPoint: .trailing))
                .padding(.top, TokensSpacing.xl)
                .padding(.bottom, TokensSpacing.xl)

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

    // MARK: - ②' 故障码（从「充电」页搬进来：车端故障是健康问题，不是电池读数）
    /// 数据源是控制报文里的 DTC（`batteryModel(store.caches).faults`），
    /// 与电池页读的是同一份响应 —— 只是归属换了。没有码就整节不出现。
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

    // MARK: - ③ 检测系统（inset-grouped，逐项可展开）

    private func systemsSection(_ m: HealthModel) -> some View {
        DSGroup(title: "检测系统",
                trailing: "\(m.systems.count) 项",
                footer: m.systems.isEmpty ? "没有分系统数据" : nil) {
            ForEach(Array(m.systems.enumerated()), id: \.element.id) { idx, sys in
                systemRow(sys, model: m, showsSeparator: idx < m.systems.count - 1)
            }
        }
    }

    // =========================================================================
    // MARK: 展开后有多挤（CardFit）
    // =========================================================================
    //
    //  用户 2026-09-25：「所有卡片内需要展开的都要严格计算展开后的拥挤程度，
    //  完全根据数据来，不能猜」。这一节是全文最挤的地方：每个分系统展开后要把
    //  它**全部**子项与故障码摊开，而子项有几条、每一条带不带检测值与说明，
    //  全由这一次检测的数据决定 —— 从前那个「有问题就全开」的写法，遇到
    //  三个各带八个子项的系统，一屏里会摊开 24 行。
    //
    //  ★ 下面每一个 Block 都对应 `systemRow` / `childRow` 里**真画出来的那一件**
    //  （同一个 VStack spacing、同一个 lineLimit、同一条 3pt 光带）。这是 CardFit
    //  唯一的约定：它量的是版式，版式改了要跟着改。
    //
    //  ⚠️ 容差：键值行自带上下 8pt 内边距，这里用 `TokensSpacing.md` 近似 ——
    //  单行级别的 ±8pt 不改变裁决（裁决是按屏数分的），但「有没有这一行」必须准：
    //  那才是数据。

    /// 卡片内容的真实宽度（视口已扣除叠叠乐左右各 18，这里是卡片自己的左右 18）
    private var fitWidth: CGFloat { max(0, cardViewport.width - 2 * StackSpec.Card.padH) }

    /// 展开后要画的一格：子项，或一个故障码
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

    /// 一格的**高度模型**
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

    /// 画出来的一格 —— 与 `fitRow` 一一对应
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

    /// 一个分系统**收起**时那一行的高度（对应 `systemRow` 收起时画的东西）
    private func collapsedFitRow(_ sys: HealthSystem) -> CardFit.Row {
        var blocks: [CardFit.Block] = [.text(sys.name, .body, cap: nil)]
        if !sys.statusText.isEmpty {
            blocks.append(.gap(TokensSpacing.xs))
            blocks.append(.text(sys.statusText, .footnote, cap: nil))
        }
        blocks.append(.gap(TokensSpacing.xs))
        blocks.append(.fixed(3))            // 健康度那条光带
        return CardFit.Row(blocks, floor: TokensSpacing.row)
    }

    /// 「检测系统」这一节**固定**要占的高度：节标题 + 每个分系统收起时那一行 + 分隔线。
    /// 展开的那几块只能在这一节剩下的地方里摊开。
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

    /// 自动展开哪几个分系统：**按算出来的高度**一个个开，开到放不下为止。
    ///
    /// 原来这里是「有问题的全开」。现在判据是数据加真实度量：每个系统展开后要多少
    /// 高度（`fitRow` 逐行量出来）、这一节固定占多少（`systemsFixedHeight`）、
    /// 卡片量到的可用高度是多少。
    ///
    /// 量不到视口时只开**第一个** —— 不猜（宁可少开一个，也不按一个想象的屏高全摊开）。
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
                        Text(sys.statusText.isEmpty ? "—" : sys.statusText)
                            .font(TokensTypo.footnote)
                            .foregroundStyle(tint)
                        DSLightBar(progress: Double(max(0, min(100, sys.healthPct))) / 100.0,
                                   height: 3,
                                   showsGlow: false,
                                   tint: LinearGradient(colors: [tint, tint],
                                                        startPoint: .leading, endPoint: .trailing))
                            .frame(width: 88)
                            .padding(.top, TokensSpacing.xs)
                    }
                    Spacer(minLength: TokensSpacing.sm)
                    Text("\(sys.healthPct)%")
                        .font(TokensTypo.data)
                        .foregroundStyle(tint)
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
                // 展开的明细铺在**凹进去的一层**上（卡片底 × 60%）。
                //
                // 为什么多一个具名局部量：`Color.opacity` 与 `ShapeStyle.opacity`
                // 同名，而 `.background(_:)` 的参数是泛型 `S: ShapeStyle` ——
                // 在那个上下文里两个候选都合法，2026-09-25 的 CI 报的正是
                // “ambiguous use of 'opacity'”。把**期望类型**写成 `Color` 之后，
                // 返回 `some ShapeStyle` 的那一支不成立，歧义消失。
                let inset: Color = TokensPalette.nightSurface.opacity(0.6)
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
                                withAnimation(TokensMotion.count) { fullyOpen.insert(sys.name) }
                            }
                        }
                    } else if fullyOpen.contains(sys.name), details.count > 1 {
                        DSGroupRow(showsSeparator: false) {
                            DSCardMoreRow.collapse {
                                withAnimation(TokensMotion.count) { fullyOpen.remove(sys.name) }
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

    /// P 开头的故障码子项（#15 DTC 翻译）
    private func dtcItems(_ sys: HealthSystem) -> [HealthItem] {
        sys.children.filter { $0.name.range(of: "P\\d", options: .regularExpression) != nil }
    }

    // MARK: - ③ 检测信息

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

    // MARK: - 语义映射

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

    // MARK: - 交互

    private func toggle(_ name: String) {
        withAnimation(TokensMotion.count) {
            if expandedSystems.contains(name) { expandedSystems.remove(name) }
            else { expandedSystems.insert(name) }
        }
        TokensHaptic.select()
    }

    // MARK: - 数据

    private func loadIfNeeded() {
        // 每次进入都取一次自检报告：没有 TTL 复用，也不拿上一次的响应凑合。
        loadTask = Task { await load() }
    }

    @MainActor
    private func load() async {
        guard !store.carId.isEmpty else { loading = false; return }
        let api = APIClient.shared
        do {
            // ⚠️ 必须用 try：try? 不会让下面的 catch 生效，那会让错误永远被吞掉
            let checkRaw = try await api.getCarCheck(carId: store.carId)
            store.saveCache(["check": checkRaw])
            model = VM.healthModel(store.caches["check"] as? [String: Any])
            errText = nil
        } catch {
            errText = error.localizedDescription
            if model == nil { loading = false }
            let errDesc = error.localizedDescription.lowercased()
            if errDesc.contains("未找到") || errDesc.contains("登录") || errDesc.contains("token") {
                AppStore.shared.logout()
            }
        }
        loading = false
    }
}
