import SwiftUI

// 健康报告 —— iOS 27 Liquid Glass：
// 评分圆环入场动画 + 脉冲外发光 + 浮动粒子 + 交错计数徽章 + 玻璃展开列表。

struct HealthView: View {
    private let store = AppStore.shared
    @State private var model: HealthModel?
    @State private var loading = true
    @State private var errText: String?
    @State private var expandedSystems: Set<String> = []
    @State private var loadTask: Task<Void, Never>? = nil

    // MARK: 动画状态
    @State private var scoreProgress: CGFloat = 0      // 圆环进度 0→scorePct
    @State private var cardOpacity: CGFloat = 0        // 卡片入场淡入
    @State private var cardSlideY: CGFloat = 24        // 卡片入场下滑
    @State private var pillPhase: Int = -1             // 三项徽章交错动画相位
    @State private var isRefreshing = false            // 下拉刷新涟漪标志
    @State private var pulseTrigger: String = ""        // 触发数值脉冲高亮（评分变化时更新）
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
                    TireTrendChart(checkRaw: store.caches["check"] as? [String: Any] ?? [:]).staggeredEntrance(index: 2)
                    // E55 实时能耗率显示
                    RealtimeEnergyDisplay(store: store).staggeredEntrance(index: 3)
                    // E56 SOC历史曲线
                    SOCHistoryChart(store: store).staggeredEntrance(index: 4)
                    // E62 驾驶风格热力图
                    DrivingStyleHeatmap(store: store).staggeredEntrance(index: 5)
                } else if let err = errText {
                    PageErrorView(err) { Task { await load() } }
                }
            }
            
            
        }
        .scrollBounceBehavior(.basedOnSize)
        .pageBackground(Theme.pageGreen)
        .navigationTitle("健康报告").navBarStyle()
        .onAppear {
            if expandedSystems.isEmpty, let m = model {
                for sys in m.systems where sys.statusCls == "bad" { expandedSystems.insert(sys.name) }
            }
            loadIfNeeded()
            startAnimations()
        }
        .onDisappear { loadTask?.cancel(); loadTask = nil }
        .refreshable { isRefreshing = true; await load(); isRefreshing = false }
        .glassRefreshRipple(isRefreshing: $isRefreshing)
    }

    // MARK: 入场动画
    private func startAnimations() {
        // 圆环从 0 动画到目标分数
        guard let m = model else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.spring(response: 0.65, dampingFraction: 0.65, blendDuration: 0.9)) {
            }
        }
        withAnimation(Theme.Duration.springNormal) {
            cardOpacity = 1
            cardSlideY = 0
        }
        // 三项计数徽章交错出现
        withAnimation(Theme.Duration.springFast.delay(0.35)) { pillPhase = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.48) { withAnimation(Theme.Duration.springFast.delay(0.08)) { pillPhase = 1 } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.61) { withAnimation(Theme.Duration.springFast.delay(0.08)) { pillPhase = 2 } }
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

            // 三项计数徽章（交错出现）
            HStack(spacing: 12) {
                ForEach(Array(m.counts.enumerated()), id: \ .offset) { idx, c in
                    countPill(c, phase: idx, active: pillPhase >= idx)
                }
            }

            // 时间信息行
            infoRow(m)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .dynamicTypeCompress()
        .glassHeroCard(corner: Theme.Radius.hero)
        .glassLongPressDeform()
        .opacity(cardOpacity)
        .offset(y: cardSlideY)
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
                    .runningGlow(color: .green)
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
        .staggeredEntrance(index: 0)
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: "chevron.down")
                .font(Theme.font(.footnote as Font).bold())
                .foregroundStyle(.tertiary)
                .rotationEffect(chevronAngle)
                .animation(.spring(response: 0.35, dampingFraction: 0.6), value: heroExpanded)
                .padding([.bottom, .trailing], 18)
        }
    }

    // MARK: 评分圆环
    private func scoreRing(_ m: HealthModel) -> some View {
        ZStack {
            // ── 第 0 层：外扩散光晕（呼吸脉冲）───────────────────────
            Circle()
                .fill(AngularGradient(
                    colors: scoreGlowColors(m.scorePct),
                    center: .center, startAngle: .degrees(-90), endAngle: .degrees(270)
                ))
                .frame(width: 248, height: 248)
                .opacity(0.18)
                .blur(radius: 12)

            // ── 第 0.5 层：EKG 心电图描边流动环（首尾相连，沿圆环持续行进）────────
            EKGFloRingDynamic(size: 242, lineWidth: 1.5, speed: 3.5, percentage: Double(m.scorePct) / 100.0)

            // ── 第 1 层：脉冲光环（持续呼吸）───────────────────────
            Circle()
                .strokeBorder(
                    AngularGradient(colors: [.green, .teal], center: .center, startAngle: .degrees(-90), endAngle: .degrees(270)),
                    lineWidth: 2
                )
                .frame(width: 236, height: 236)
                .opacity(0.12)
                .blur(radius: 6)
                .heartbeatPulse()

            // ── 第 2 层：浅色底轨 ─────────────────────────────────
            Circle()
                .stroke(Color(.systemGray5).opacity(0.45), lineWidth: 22)
                .frame(width: 216, height: 216)

            // ── 第 3 层：彩色进度弧 ────────────────────────────────
            Circle()
                .trim(from: 0, to: max(0.015, scoreProgress / 100))
                .stroke(
                    AngularGradient(colors: scoreRingColors(m.scorePct),
                                    center: .center, startAngle: .degrees(-90), endAngle: .degrees(270)),
                    style: StrokeStyle(lineWidth: 22, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: 216, height: 216)
                .shadow(color: scoreShadowColor(m.scorePct).opacity(0.35), radius: 12, y: 4)

            // ── 第 4 层：浮动装饰粒子 ──────────────────────────────
            FloatingParticles(size: 216)

            // ── 第 5 层：中心数字（流体字体，随容器宽度自适应）────────────
            VStack(spacing: 3) {
                FluidScoreHero(m.score)
                    .foregroundStyle(scoreForeground(m.scorePct))
                    .dynamicTypeLineLimit(1)
                Text("健康评分")
                    .font(Theme.caption)
                    .foregroundStyle(.secondary)
                    .dynamicTypeTextCompress(isTitle: true)
                    .accessibilityLabel(Text("健康评分"))
            }
        }
        .frame(width: 216, height: 216)
        .valuePulse(tint: .green)
    }

    // MARK: 三项计数徽章（交错出现）
    private func countPill(_ c: CountPill, phase: Int, active: Bool) -> some View {
        let clsColor = Theme.statusColor(c.cls)
        return VStack(spacing: 4) {
            Text(c.n)
                .font(Theme.d4)
                .foregroundStyle(clsColor)
            Text(c.key)
                .font(Theme.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(clsColor.opacity(0.20), lineWidth: 1)
        )
        .opacity(active ? 1 : 0)
        .offset(y: active ? 0 : 16)
        .animation(Theme.Duration.springFast.delay(Double(phase) * 0.08), value: active)
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

    private func scoreGlowColors(_ pct: Int) -> [Color] {
        switch pct {
        case 0...39:   return [.red.opacity(0.6), .clear]
        case 40...69:  return [.orange.opacity(0.5), .clear]
        case 70...89:  return [.yellow.opacity(0.5), .green.opacity(0.3)]
        default:       return [.green.opacity(0.5), .teal.opacity(0.3)]
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

    private func scoreForeground(_ pct: Int) -> Color {
        switch pct {
        case 0...39: return .red
        case 40...69: return .orange
        case 70...89: return .yellow
        default: return .green
        }
    }

    // MARK: 检测系统列表
    private func systemList(_ m: HealthModel) -> some View {
        // 整体卡片：弹簧高度动画 + 玻璃形变光晕 + 弹性缩放
        ZStack(alignment: .center) {
            CardBox(title: "检测系统", side: "\(m.systems.count) 项", sideCls: "na") {
                VStack(spacing: 0) {
                    ForEach(Array(m.systems.enumerated()), id: \.element.id) { idx, sys in
                        systemRow(sys) { toggleExpand(sys.name) }
                        if idx < m.systems.count - 1 { ListDivider().padding(.vertical, 4) }
                    }
                }
            }
            // 玻璃形变光晕：有展开项时叠加柔和色扩散
            if !expandedSystems.isEmpty {
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(
                        AngularGradient(
                            colors: [Theme.ok.opacity(0.08), Theme.ok.opacity(0.02), .clear],
                            center: .center,
                            startAngle: .degrees(0),
                            endAngle: .degrees(360)
                        )
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
            }
        }
        // 弹簧高度 + 弹性缩放：有展开项时卡片轻微压缩（liquid glass 触感 0.98），收起时回弹
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

    // MARK: DTC 故障码翻译卡片 (#15)
    @ViewBuilder
    private func dtcTranslationCard(_ sys: HealthSystem) -> some View {
        let hasDTC = sys.children.contains { $0.name.range(of: "P\\d", options: .regularExpression) != nil }
        if hasDTC {
        VStack(alignment: .leading, spacing: 6) {
            Text("故障码说明").font(Theme.caption).foregroundStyle(.secondary)
            ForEach(sys.children.filter { $0.name.range(of: "P\\d", options: .regularExpression) != nil }) { item in
                let dtcCode = item.name
                let description = DTCDictionary.translate(dtcCode)
                HStack {
                    Text(dtcCode).font(Theme.mono).foregroundStyle(.orange)
                    Spacer()
                    Text(description).font(Theme.caption).foregroundStyle(.secondary)
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
            if let checkRaw = try? await api.getCarCheck(carId: store.carId) {
                store.saveCache(["check": checkRaw])
            }
            model = VM.healthModel(store.caches["check"] as? [String: Any])
            errText = nil
            // 刷新后重置并重播入场动画
            withAnimation(Theme.Duration.springFast) {
                scoreProgress = 0
                cardOpacity = 0
                cardSlideY = 24
                pillPhase = -1
                pulseTrigger = ""
            }
            startAnimations()
        } catch {
            errText = error.localizedDescription
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
                // 标题行：带玻璃形变高亮
                HStack(spacing: 10) {
                    StatusDot(cls: sys.statusCls)
                    Text(sys.name).font(Theme.h4)
                    Spacer()
                    // 小圆环健康统计卡（带心跳脉冲）
                    HealthSystemRing(name: sys.name, statusCls: sys.statusCls,
                                     statusText: sys.statusText, pct: sys.healthPct)
                    // 旋转 Chevron + 玻璃反光条
                    HStack(spacing: 6) {
                        Capsule()
                            .fill(isOpen
                                  ? Theme.statusColor(sys.statusCls).opacity(0.35)
                                  : Color.white.opacity(0.0))
                            .frame(width: isOpen ? 18 : 0, height: 2)
                            .animation(.spring(response: 0.45, dampingFraction: 0.8, blendDuration: 0.3), value: isOpen)
                        Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                            .font(Theme.font(.footnote as Font).bold())
                            .foregroundStyle(isOpen ? AnyShapeStyle(Theme.statusColor(sys.statusCls)) : AnyShapeStyle(.tertiary))
                            .rotationEffect(.degrees(isOpen ? 0 : 180))
                            .animation(.spring(response: 0.35, dampingFraction: 0.65), value: isOpen)
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 4)

                // 展开内容：交错淡入
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
                            dtcTranslationCard(sys)
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

// MARK: - 检测子项行（交错入场 + 液体玻璃拉伸形变 + 反光条流动）
struct SystemChildRow: View {
    let item: HealthItem
    let idx: Int

    @State private var appeared = false
    @State private var reflectPhase: CGFloat = 0   // 0→1 表示反光条滑过进度

    var body: some View {
        GeometryReader { geo in
            let rowWidth = geo.size.width
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(item.name).font(Theme.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(item.statusText)
                        .font(Theme.font(.footnote as Font).bold())
                        .foregroundStyle(Theme.statusColor(item.statusCls))
                }
                if let d = item.detect, !d.isEmpty { KVRow(k: "检测值", v: d) }
                if let s = item.suggest, !s.isEmpty { KVRow(k: "参考范围", v: s) }
                if let desc = item.desc, !desc.isEmpty {
                    Text(desc).font(Theme.footnote).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 8)
            // 液体玻璃拉伸：垂直方向从 0.85 弹性扩张到 1.0
            .scaleEffect(y: appeared ? 1.0 : 0.85)
            // 整体淡入 + 上滑复位
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 10)
            // 玻璃反光条：从左侧滑入覆盖全行宽度后停止
            .overlay(alignment: .leading) {
                if appeared && reflectPhase < 1 {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    .clear,
                                    .white.opacity(0.08),
                                    .white.opacity(0.18),
                                    .white.opacity(0.08),
                                    .clear
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: rowWidth * 0.35, height: 2)
                        .offset(x: reflectPhase * (rowWidth + rowWidth * 0.35) - rowWidth * 0.35)
                        .cornerRadius(1)
                }
            }
            .animation(.spring(response: 0.45, dampingFraction: 0.65, blendDuration: 0.3)
                        .delay(Double(idx) * 0.07), value: appeared)
            .onAppear { appeared = true }
            // 反光条在卡片出现后延迟滑过（模拟 Liquid Glass 折射光掠过）
            .onChange(of: appeared) { visible in
                guard visible else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12 + Double(idx) * 0.07) {
                    withAnimation(.spring(response: 0.55, dampingFraction: 0.7, blendDuration: 0.25)) {
                        reflectPhase = 1.0
                    }
                }
            }
        }
        .frame(height: nil, alignment: .leading)
        .liquidGlassRipple(cornerRadius: Theme.Radius.small)
    }
}
}
