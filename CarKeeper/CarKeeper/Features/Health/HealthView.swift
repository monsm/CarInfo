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

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.cardSpacing) {
                if loading {
                    loadingView
                } else if let model {
                    scoreHero(model)
                    systemList(model)
                } else if let err = errText {
                    ContentUnavailableView("暂无健康报告", systemImage: "exclamationmark.triangle",
                                           description: Text(err))
                        .glassCard()
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .scrollBounceBehavior(.basedOnSize)
        .pageBackground(.green)
        .navigationTitle("健康报告").navBarStyle()
        .onAppear {
            if expandedSystems.isEmpty, let m = model {
                for sys in m.systems where sys.statusCls == "bad" { expandedSystems.insert(sys.name) }
            }
            loadIfNeeded()
            startAnimations()
        }
        .onDisappear { loadTask?.cancel(); loadTask = nil }
        .refreshable { await load() }
    }

    // MARK: 入场动画
    private func startAnimations() {
        withAnimation(.spring(Theme.Duration.springNormal)) {
            cardOpacity = 1
            cardSlideY = 0
        }
        // 圆环从 0 动画到目标分数
        guard let m = model else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.spring(response: 0.65, dampingFraction: 0.65, blendDuration: 0.9)) {
                scoreProgress = CGFloat(m.scorePct)
            }
        }
        // 三项计数徽章交错出现
        withAnimation(.spring(Theme.Duration.springFast).delay(0.35)) { pillPhase = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.48) { withAnimation(.spring(Theme.Duration.springFast).delay(0.08)) { pillPhase = 1 } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.61) { withAnimation(.spring(Theme.Duration.springFast).delay(0.08)) { pillPhase = 2 } }
    }

    // MARK: 加载状态
    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView().controlSize(.large).tint(.green)
            Text("正在读取健康报告…").font(.system(size: 13)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 60)
        .glassCard()
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

            // ── 第 1 层：脉冲光环（持续呼吸）───────────────────────
            Circle()
                .strokeBorder(
                    AngularGradient(colors: [.green, .teal], center: .center, startAngle: .degrees(-90), endAngle: .degrees(270)),
                    lineWidth: 2
                )
                .frame(width: 236, height: 236)
                .opacity(0.12)
                .blur(radius: 6)
                .scaleEffect(scoreProgress > 0 ? 1.0 : 1.0)
                .animation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true), value: scoreProgress)

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

            // ── 第 5 层：中心数字 ──────────────────────────────────
            VStack(spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(m.score)
                        .font(Theme.d1)
                        .foregroundStyle(scoreForeground(m.scorePct))
                    Text("分")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Text("健康评分")
                    .font(.system(size: 13, weight: .medium))
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
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(clsColor)
            Text(c.key)
                .font(.system(size: 11))
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
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text("最近检测  \(m.time)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            if m.checkId != nil || m.endTime != nil {
                VStack(alignment: .leading, spacing: 4) {
                    if let id = m.checkId, !id.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.text.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            Text("检测 ID: \(id.prefix(16))…")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let et = m.endTime, !et.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "clock.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            Text("数据更新: \(et)")
                                .font(.system(size: 11, design: .monospaced))
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
                        .font(.system(size: 11, weight: .medium))
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
        CardBox(title: "检测系统", side: "\(m.systems.count) 项", sideCls: "na") {
            VStack(spacing: 0) {
                ForEach(Array(m.systems.enumerated()), id: \ .element.id) { idx, sys in
                    systemRow(sys)
                    if idx < m.systems.count - 1 { ListDivider().padding(.vertical, 4) }
                }
            }
        }
    }

    private func systemRow(_ sys: HealthSystem) -> some View {
        let isOpen = expandedSystems.contains(sys.name)
        SystemRowView(sys: sys, isOpen: isOpen)
    }
}

// MARK: - 检测系统行（液态玻璃形变动效）
struct SystemRowView: View {
    let sys: HealthSystem
    let isOpen: Bool

    var body: some View {
        VStack(spacing: 0) {
            // 标题行：带玻璃形变高亮
            HStack(spacing: 10) {
                StatusDot(cls: sys.statusCls)
                Text(sys.name).font(.system(size: 15, weight: .semibold))
                Spacer()
                Text(sys.statusText)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.statusColor(sys.statusCls))
                // 旋转 Chevron + 玻璃反光条
                HStack(spacing: 6) {
                    Capsule()
                        .fill(isOpen
                              ? Theme.statusColor(sys.statusCls).opacity(0.35)
                              : Color.white.opacity(0.0))
                        .frame(width: isOpen ? 18 : 0, height: 2)
                        .animation(.spring(.duration(0.3)), value: isOpen)
                    Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
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
}

// MARK: - 检测子项行（交错入场）
struct SystemChildRow: View {
    let item: HealthItem
    let idx: Int

    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(item.name).font(.system(size: 13)).foregroundStyle(.secondary)
                Spacer()
                Text(item.statusText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.statusColor(item.statusCls))
            }
            if let d = item.detect, !d.isEmpty { KVRow(k: "检测值", v: d) }
            if let s = item.suggest, !s.isEmpty { KVRow(k: "参考范围", v: s) }
            if let desc = item.desc, !desc.isEmpty {
                Text(desc).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 10)
        .animation(.spring(response: 0.4, dampingFraction: 0.7, blendDuration: 0.25).delay(Double(idx) * 0.07), value: appeared)
        .onAppear { appeared = true }
    }
}