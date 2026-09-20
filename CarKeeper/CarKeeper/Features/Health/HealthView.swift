import SwiftUI

// 健康报告 —— DS 设计系统：
// 评分单色弧 + 三项计数徽章 + 系统列表（可展开）+ 历史趋势。
// 只有一条轨道、一段进度和一组计数：所有信息都由排版与颜色表达。

struct HealthView: View {
    private let store = AppStore.shared
    @State private var model: HealthModel?
    @State private var loading = true
    @State private var errText: String?
    @State private var expandedSystems: Set<String> = []
    @State private var loadTask: Task<Void, Never>? = nil

    // MARK: 动画状态
    @State private var isRefreshing = false            // 下拉刷新进行中
    @State private var heroExpanded = false            // Hero 卡片整体展开/收起系统列表
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.cardSpacing) {
                if loading {
                    loadingView
                } else if let model {
                    scoreHeroListWrapper(model)
                    // E54 胎压趋势折线图
                    TireTrendChart(checkRaw: store.caches["check"] as? [String: Any] ?? [:])
                    // E55 实时能耗率显示
                    RealtimeEnergyDisplay(store: store)
                    // E56 SOC历史曲线
                    SOCHistoryChart(store: store)
                    // E62 驾驶风格热力图
                    DrivingStyleHeatmap(store: store)
                } else if let err = errText {
                    PageErrorView(err) { Task { await load() } }
                }
            }
            
            
        }
        .scrollBounceBehavior(.basedOnSize)
        .pageBackground()
        .navigationTitle("健康报告")
        .onAppear {
            if expandedSystems.isEmpty, let m = model {
                for sys in m.systems where sys.statusCls == "bad" { expandedSystems.insert(sys.name) }
            }
            loadIfNeeded()
        }
        .onDisappear { loadTask?.cancel(); loadTask = nil }
        .refreshable { isRefreshing = true; await load(); isRefreshing = false }
    }

    // MARK: 加载状态
    private var loadingView: some View {
        PageLoadingView("正在读取健康报告…")
    }

    // MARK: 评分 Hero — Apple Watch Activity Rings + Liquid Glass
    private func scoreHero(_ m: HealthModel) -> some View {
        VStack(spacing: 22) {
            // 评分圆环
            scoreRing(m)

            // 三项计数徽章
            HStack(spacing: DS.Space.md) {
                ForEach(Array(m.counts.enumerated()), id: \ .offset) { _, c in
                    countPill(c)
                }
            }

            // 时间信息行
            infoRow(m)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Space.xxxl)
        .glassHeroCard(corner: Theme.Radius.hero)
    }

    // MARK: Hero 卡片 + 系统列表（整体可展开/收起）
    /// 点击 scoreHero 区域切换展开状态：系统列表弹簧高度展开 + 整体玻璃压缩形变
    private func scoreHeroListWrapper(_ m: HealthModel) -> some View {
        let chevronAngle: Angle = heroExpanded ? .degrees(90) : .degrees(0)
        return Button {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.65, blendDuration: 0.35)) {
                heroExpanded.toggle()
            }
        } label: {
            VStack(spacing: 0) {
                scoreHero(m)
                // 展开内容区：系统列表弹簧高度过渡
                if heroExpanded {
                    systemList(m)
                }
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(heroExpanded ? 0.97 : 1.0)
        .animation(.spring(response: 0.5, dampingFraction: 0.65, blendDuration: 0.4), value: heroExpanded)
        .accessibilityLabel(Text("健康评分报告"))
        .accessibilityHint(Text(heroExpanded ? "点击收起系统详情" : "点击展开系统详情，查看各子系统状态"))
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: "chevron.down")
                .font(Theme.font(.footnote as Font).bold())
                .foregroundStyle(.tertiary)
                .rotationEffect(chevronAngle)
                .animation(.spring(response: 0.35, dampingFraction: 0.6), value: heroExpanded)
                .padding([.bottom, .trailing], 18)
        }
    }

    // MARK: 健康评分环
    // 规则：一条单色轨道 + 一条单色进度。环只负责「读数刻度」，颜色只表达健康度分级。
    private func scoreRing(_ m: HealthModel) -> some View {
        DSGauge(progress: Double(m.scorePct) / 100.0,
                lineWidth: 16,
                tint: scoreShadowColor(m.scorePct),
                value: m.score,
                caption: "健康评分",
                size: 200)
        .frame(width: 216, height: 216)
    }

    // MARK: 三项计数徽章
    private func countPill(_ c: CountPill) -> some View {
        let clsColor = DS.Palette.status(c.cls)
        return VStack(spacing: DS.Space.xs) {
            // 补齐图标：原来这一格只有数字 + 颜色，没有图标
            Image(safeSymbol: c.iconName, fallback: "info.circle.fill")
                .font(Theme.footnote.weight(.semibold))
                .foregroundStyle(clsColor)
            Text(c.n)
                .font(Theme.d4)
                .foregroundStyle(clsColor)
            Text(c.key)
                .font(Theme.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Space.md)
        .background(RoundedRectangle(cornerRadius: DS.Radius.small, style: .continuous)
            .fill(DS.Palette.surfaceRaised))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.small, style: .continuous)
                .strokeBorder(clsColor.opacity(0.20), lineWidth: DS.Hair.line)
        )
        .accessibilityElement(children: .combine)
    }

    // MARK: 时间信息行
    private func infoRow(_ m: HealthModel) -> some View {
        VStack(spacing: 8) {
            if !m.time.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "calendar.badge.clock")
                        .font(Theme.footnote)
                        .foregroundStyle(.secondary)
                    Text("最近检测  \(m.time)")
                        .font(Theme.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            if m.checkId != nil || m.endTime != nil {
                VStack(alignment: .leading, spacing: 4) {
                    if let id = m.checkId, !id.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.text.fill")
                                .font(Theme.micro)
                                .foregroundStyle(.secondary)
                            Text("检测 ID: \(id.prefix(16))…")
                                .font(Theme.mono)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let et = m.endTime, !et.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "clock.fill")
                                .font(Theme.micro)
                                .foregroundStyle(.secondary)
                            Text("数据更新: \(et)")
                                .font(Theme.mono)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if let vs = m.vehicleStatus, !vs.isEmpty {
                let vsCN: [String: String] = ["normal": "正常", "fault": "故障", "warning": "预警"]
                let vsCls: [String: String] = ["normal": "ok", "fault": "bad", "warning": "warn"]
                HStack(spacing: 6) {
                    StatusDot(cls: vsCls[vs] ?? "na")
                    Text(vsCN[vs] ?? vs)
                        .font(Theme.footnote)
                        .foregroundStyle(Theme.statusColor(vsCls[vs] ?? "na"))
                }
            }
        }
    }

    // MARK: 颜色辅助
    private func scoreRingColors(_ pct: Int) -> [Color] {
        switch pct {
        case 0...39:   return [.red, .red, .orange]
        case 40...69:  return [.orange, .orange, .yellow]
        case 70...89:  return [.yellow, .green, .green]
        default:       return [.green, .green, .teal]
        }
    }

    private func scoreShadowColor(_ pct: Int) -> Color {
        switch pct {
        case 0...39: return .red
        case 40...69: return .orange
        case 70...89: return .yellow
        default: return .green
        }
    }

    // MARK: 检测系统列表
    private func systemList(_ m: HealthModel) -> some View {
        // 展开由内容高度 + 发丝线表达；卡片只做轻微的压缩/回弹
        CardBox(title: "检测系统", side: "\(m.systems.count) 项", sideCls: "na") {
            VStack(spacing: 0) {
                ForEach(Array(m.systems.enumerated()), id: \.element.id) { idx, sys in
                    systemRow(sys) { toggleExpand(sys.name) }
                    if idx < m.systems.count - 1 { ListDivider().padding(.vertical, 4) }
                }
            }
        }
        .scaleEffect(expandedSystems.isEmpty ? 1.0 : 0.98)
        .animation(.spring(response: 0.5, dampingFraction: 0.65, blendDuration: 0.4), value: expandedSystems.isEmpty)
    }

    private func systemRow(_ sys: HealthSystem, toggle: @escaping () -> Void) -> some View {
        let isOpen = expandedSystems.contains(sys.name)
        return SystemRowView(sys: sys, isOpen: isOpen, onToggle: toggle)
    }

    private func toggleExpand(_ name: String) {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.7, blendDuration: 0.3)) {
            if expandedSystems.contains(name) {
                expandedSystems.remove(name)
            } else {
                expandedSystems.insert(name)
            }
        }
    }

    // MARK: 数据加载
    private func loadIfNeeded() {
        guard model == nil || store.isCacheExpired("check") else { return }
        loadTask = Task { await load() }
    }

    @MainActor
    private func load() async {
        guard !store.carId.isEmpty else { return }
        let api = APIClient.shared
        do {
            // ⚠️ 必须用 try：原来用 try? 时 do 体内不会抛错，下面的 catch 是死代码
            //（CI 日志里的 'catch block is unreachable' 警告就是它）
            let checkRaw = try await api.getCarCheck(carId: store.carId)
            store.saveCache(["check": checkRaw])
            model = VM.healthModel(store.caches["check"] as? [String: Any])
            errText = nil
        } catch {
            errText = error.localizedDescription
            let errDesc = error.localizedDescription.lowercased()
            if errDesc.contains("未找到") || errDesc.contains("登录") || errDesc.contains("token") {
                // token 失效：真正需要重新登录
                AppStore.shared.logout()
            }
        }
    }

// MARK: - #15 DTC 故障码翻译卡片（供 SystemRowView 复用）
struct DTCCard: View {
    let sys: HealthSystem

    private var dtcItems: [HealthItem] {
        sys.children.filter { $0.name.range(of: "P\\d", options: .regularExpression) != nil }
    }

    var body: some View {
        if !dtcItems.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("故障码说明").font(Theme.caption).foregroundStyle(.secondary)
                ForEach(dtcItems) { item in
                    HStack {
                        Text(item.name).font(Theme.mono).foregroundStyle(.orange)
                        Spacer()
                        Text(DTCDictionary.translate(item.name)).font(Theme.caption).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.orange.opacity(0.2), lineWidth: 1))
            .padding(.horizontal, 4)
            .padding(.top, 4)
        }
    }
}

// MARK: - 检测系统行（液态玻璃形变动效）
struct SystemRowView: View {
    let sys: HealthSystem
    let isOpen: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            VStack(spacing: 0) {
                // 标题行：状态点 + 名称 + 健康小环 + 展开箭头
                HStack(spacing: DS.Space.sm) {
                    StatusDot(cls: sys.statusCls)
                    Text(sys.name).font(DS.Typo.headline)
                    Spacer(minLength: DS.Space.sm)
                    HealthSystemRing(name: sys.name, statusCls: sys.statusCls,
                                     statusText: sys.statusText, pct: sys.healthPct)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DS.Palette.labelTertiary)
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                        .animation(DS.Motion.press, value: isOpen)
                }
                .padding(.vertical, DS.Space.md)
                .padding(.horizontal, DS.Space.xs)

                // 展开内容
                if isOpen {
                    VStack(spacing: 0) {
                        ForEach(Array(sys.children.enumerated()), id: \.element.id) { idx, item in
                            SystemChildRow(item: item, idx: idx)
                            if idx < sys.children.count - 1 {
                                ListDivider().padding(.leading, 4)
                            }
                        }
                        // #15 DTC 故障码翻译提示
                        if sys.name.contains("故障") || sys.name.contains("DTC") {
                            DTCCard(sys: sys)
                        }
                    }
                    .padding(.leading, 22)
                    .padding(.horizontal, 4)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isOpen ? Color.white.opacity(0.06) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        isOpen
                            ? Theme.statusColor(sys.statusCls).opacity(0.20)
                            : Color.clear,
                        lineWidth: 1
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 检测子项行
struct SystemChildRow: View {
    let item: HealthItem
    let idx: Int

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            HStack(spacing: DS.Space.sm) {
                Text(item.name)
                    .font(DS.Typo.caption)
                    .foregroundStyle(DS.Palette.labelSecondary)
                Spacer(minLength: DS.Space.sm)
                Text(item.statusText)
                    .font(DS.Typo.footnote.weight(.semibold))
                    .foregroundStyle(DS.Palette.status(item.statusCls))
            }
            if let d = item.detect, !d.isEmpty { KVRow(k: "检测值", v: d) }
            if let s = item.suggest, !s.isEmpty { KVRow(k: "参考范围", v: s) }
            if let desc = item.desc, !desc.isEmpty {
                Text(desc)
                    .font(DS.Typo.footnote)
                    .foregroundStyle(DS.Palette.labelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, DS.Space.sm)
        .accessibilityElement(children: .combine)
    }
}
}
