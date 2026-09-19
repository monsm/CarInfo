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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize = ContentSizeCategory.med

    var body: some View {
        ScrollView {
            VStack(spacing: DynamicTypeScale.spacing(Theme.cardSpacing, dynamicTypeSize)) {
                if loading {
                    loadingView
                } else if let model {
                    scoreHero(model)
                    systemList(model)
                } else if let err = errText {
                    PageErrorView(err) { Task { await load() } }
                }
                }
            }
            .adaptivePagePadding(dynamicTypeSize)
            .adaptiveSafeAreaBottom(8, dynamicTypeSize)
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
        withAnimation(.spring(Theme.Duration.springNormal)) {
            cardOpacity = 1
            cardSlideY = 0
        }
        // 三项计数徽章交错出现
        withAnimation(.spring(Theme.Duration.springFast).delay(0.35)) { pillPhase = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.48) { withAnimation(.spring(Theme.Duration.springFast).delay(0.08)) { pillPhase = 1 } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.61) { withAnimation(.spring(Theme.Duration.springFast).delay(0.08)) { pillPhase = 2 } }
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
        .opacity(cardOpacity)
        .offset(y: cardSlideY)
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
            EKGFloRing(size: 242, color: .green.opacity(0.45), lineWidth: 1.5, speed: 3.5)

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
                Text("健康评分")
                    .font(Theme.caption)))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 216, height: 216)
    }

    // MARK: 三项计数徽章（交错出现）
    private func countPill(_ c: CountPill, phase: Int, active: Bool) -> some View {
        let clsColor = Theme.statusColor(c.cls)
        return VStack(spacing: 4) {
            Text(c.n)
                .font(Theme.d4) weight: .bold, design: .rounded))
                .foregroundStyle(clsColor)
            Text(c.key)
                .font(Theme.footnote))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.thin, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(clsColor.opacity(0.20), lineWidth: 1)
        )
        .opacity(active ? 1 : 0)
        .offset(y: active ? 0 : 16)
        .animation(.spring(Theme.Duration.springFast).delay(Double(phase) * 0.08), value: active)
    }

    // MARK: 时间信息行
    private func infoRow(_ m: HealthModel) -> some View {
        VStack(spacing: 8) {
            if !m.time.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "calendar.badge.clock")
                        .font(Theme.footnote))
                        .foregroundStyle(.secondary)
                    Text("最近检测  \(m.time)")
                        .font(Theme.footnote))
                        .foregroundStyle(.secondary)
                }
            }
            if m.checkId != nil || m.endTime != nil {
                VStack(alignment: .leading, spacing: 4) {
                    if let id = m.checkId, !id.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.text.fill")
                                .font(Theme.micro))
                                .foregroundStyle(.secondary)
                            Text("检测 ID: \(id.prefix(16))…")
                                .font(Theme.mono))
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let et = m.endTime, !et.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "clock.fill")
                                .font(Theme.micro))
                                .foregroundStyle(.secondary)
                            Text("数据更新: \(et)")
                                .font(Theme.mono))
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
                        .font(Theme.footnote)))
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
        SystemRowView(sys: sys, isOpen: isOpen, onToggle: toggle)
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
            if let checkRaw = try? await api.getCarCheck(carId: store.carId) {
                store.saveCache(["check": checkRaw])
            }
            model = VM.healthModel(store.caches["check"] as? [String: Any])
            errText = nil
            // 刷新后重置并重播入场动画
            withAnimation(.spring(Theme.Duration.springFast)) {
                scoreProgress = 0
                cardOpacity = 0
                cardSlideY = 24
                pillPhase = -1
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
                    Text(sys.name).font(Theme.h4)))
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
                            .animation(.spring(.duration(0.3)), value: isOpen)
                        Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                            .font(Theme.footnote.bold())))
                            .foregroundStyle(isOpen ? Theme.statusColor(sys.statusCls) : .tertiary)
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
                            SystemChildRow(item: item, idx: idx, total: sys.children.count)
                            if idx < sys.children.count - 1 {
                                ListDivider().padding(.leading, 4)
                            }
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
                    Text(item.name).font(Theme.caption)).foregroundStyle(.secondary)
                    Spacer()
                    Text(item.statusText)
                        .font(Theme.footnote.bold())))
                        .foregroundStyle(Theme.statusColor(item.statusCls))
                }
                if let d = item.detect, !d.isEmpty { KVRow(k: "检测值", v: d) }
                if let s = item.suggest, !s.isEmpty { KVRow(k: "参考范围", v: s) }
                if let desc = item.desc, !desc.isEmpty {
                    Text(desc).font(Theme.footnote)).foregroundStyle(.secondary)
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
    }
}