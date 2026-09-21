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

struct HealthView: View {
    private let store = AppStore.shared
    @State private var model: HealthModel?
    @State private var loading = true
    @State private var errText: String?
    @State private var expandedSystems: Set<String> = []
    @State private var loadTask: Task<Void, Never>? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TokensSpacing.lg) {
                if loading {
                    loadingState
                } else if let model {
                    scoreSection(model)
                    systemsSection(model)
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
                                  message: "车辆完成一次全车检测后，这里会显示评分与逐系统明细",
                                  actionTitle: "重新加载") { Task { await load() } }
                }
            }
            .padding(.top, TokensSpacing.sm)
            .padding(.bottom, TokensSpacing.xxl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(TokensPalette.background)
        .navigationTitle("健康报告")
        .refreshable { await load() }
        .onAppear {
            if expandedSystems.isEmpty, let m = model {
                for sys in m.systems where sys.statusCls == "bad" { expandedSystems.insert(sys.name) }
            }
            loadIfNeeded()
        }
        .onDisappear { loadTask?.cancel(); loadTask = nil }
    }

    // MARK: - 加载态（安静的内容占位，不加边距 —— 画布已经统一给了 20pt）

    private var loadingState: some View {
        VStack(alignment: .leading, spacing: TokensSpacing.md) {
            HStack(spacing: TokensSpacing.sm) {
                ProgressView().controlSize(.small)
                Text("正在读取健康报告…")
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

    // MARK: - ② 检测系统（inset-grouped，逐项可展开）

    private func systemsSection(_ m: HealthModel) -> some View {
        DSGroup(title: "检测系统",
                trailing: "\(m.systems.count) 项",
                footer: m.systems.isEmpty ? "本次检测没有返回分系统数据" : nil) {
            ForEach(Array(m.systems.enumerated()), id: \.element.id) { idx, sys in
                systemRow(sys, showsSeparator: idx < m.systems.count - 1)
            }
        }
    }

    private func systemRow(_ sys: HealthSystem, showsSeparator: Bool) -> some View {
        let isOpen = expandedSystems.contains(sys.name)
        let tint = TokensPalette.statusColor(sys.statusCls)
        return VStack(alignment: .leading, spacing: 0) {
            Button { toggle(sys.name) } label: {
                HStack(spacing: TokensSpacing.md) {
                    Image(safeSymbol: systemIcon(sys.name), fallback: "circle")
                        .font(.system(size: TokensSize.icon))
                        .foregroundStyle(tint)
                        .frame(width: TokensSize.iconColumn)
                    VStack(alignment: .leading, spacing: 3) {
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
                            .padding(.top, 3)
                    }
                    Spacer(minLength: TokensSpacing.sm)
                    Text("\(sys.healthPct)%")
                        .font(TokensTypo.data)
                        .foregroundStyle(tint)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
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
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(sys.children.enumerated()), id: \.element.id) { cIdx, item in
                        DSGroupRow(showsSeparator: cIdx < sys.children.count - 1 || !dtcItems(sys).isEmpty) {
                            childRow(item)
                        }
                    }
                    ForEach(Array(dtcItems(sys).enumerated()), id: \.element.id) { dIdx, code in
                        DSGroupRow(showsSeparator: dIdx < dtcItems(sys).count - 1) {
                            DSKeyValueRow(key: code.name,
                                          value: DTCDictionary.translate(code.name),
                                          valueCls: "warn")
                        }
                    }
                }
                .background(TokensPalette.nightSurface.opacity(0.6))
            }

            if showsSeparator { DSSeparator(inset: 0) }
        }
    }

    private func childRow(_ item: HealthItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
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
                       footer: hasMeta ? nil : "本次检测未返回检测 ID 与时间戳") {
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
                        .font(.system(size: TokensSize.icon))
                        .foregroundStyle(TokensPalette.ambient)
                        .frame(width: TokensSize.iconColumn)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("检测 ID")
                            .font(TokensTypo.body)
                            .foregroundStyle(TokensPalette.primary)
                        Text(cid)
                            .font(.system(size: 15, design: .monospaced))
                            .foregroundStyle(TokensPalette.secondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: TokensSpacing.sm)
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 15))
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
        case 0...39:  return "存在故障，建议尽快检修"
        case 40...69: return "多项需要关注，建议安排检查"
        case 70...89: return "车况正常，有少量项目需留意"
        default:      return "车况良好，无需处理"
        }
    }

    private func vehicleText(_ raw: String) -> String {
        switch raw {
        case "normal":  return "车辆状态正常"
        case "fault":   return "车辆状态故障"
        case "warning": return "车辆状态预警"
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
        guard model == nil || store.isCacheExpired("check") else { return }
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
