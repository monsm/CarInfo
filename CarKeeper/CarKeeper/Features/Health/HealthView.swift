import SwiftUI

// 健康报告 —— iOS 27 Liquid Glass：
// 渐变评分圆环 + 三项计数徽章 + 可展开检测系统玻璃卡。

struct HealthView: View {
    private let store = AppStore.shared
    @State private var model: HealthModel?
    @State private var loading = true
    @State private var errText: String?
    @State private var expandedSystems: Set<String> = []
    @State private var loadTask: Task<Void, Never>? = nil

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
        .navigationTitle("健康报告")
        .onAppear {
            if expandedSystems.isEmpty, let m = model {
                for sys in m.systems where sys.statusCls == "bad" { expandedSystems.insert(sys.name) }
            }
            loadIfNeeded()
        }
        .onDisappear { loadTask?.cancel(); loadTask = nil }
        .refreshable { await load() }
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView().controlSize(.large).tint(.green)
            Text("正在读取健康报告…").font(.system(size: 13)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 60)
        .glassCard()
    }    // MARK: 评分 Hero — Apple Watch Activity Rings 风格
    private func scoreHero(_ m: HealthModel) -> some View {
        VStack(spacing: 20) {
            ZStack {
                // 外发光
                Circle()
                    .fill(AngularGradient(colors: [.green.opacity(0.08), .accentColor.opacity(0.05)],
                                          center: .center, startAngle: .degrees(-90), endAngle: .degrees(270)))
                    .frame(width: 216, height: 216)
                // 轨道
                Circle()
                    .stroke(Color(.systemGray5).opacity(0.5), lineWidth: 20)
                    .frame(width: 216, height: 216)
                // 进度弧
                Circle()
                    .trim(from: 0, to: max(0.01, CGFloat(m.scorePct) / 100))
                    .stroke(
                        AngularGradient(colors: [.red, .orange, .yellow, .green, .green],
                                        center: .center, startAngle: .degrees(-90), endAngle: .degrees(270)),
                        style: StrokeStyle(lineWidth: 20, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 216, height: 216)
                    .shadow(color: .green.opacity(0.2), radius: 16, y: 6)
                // 中心数字
                VStack(spacing: 2) {
                    Text(m.score).font(Theme.d1)
                    Text("健康评分").font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                }
            }
            // 三计数徽章
            HStack(spacing: 12) {
                ForEach(m.counts) { c in
                    VStack(spacing: 4) {
                        Text(c.n).font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.statusColor(c.cls))
                        Text(c.key).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
            if !m.time.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "calendar").font(.system(size: 11)).foregroundStyle(.tertiary)
                    Text("最近检测 \(m.time)").font(.system(size: 11)).foregroundStyle(.tertiary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .glassHeroCard()
    }

    // MARK: 系统列表（可展开）
    private func systemList(_ m: HealthModel) -> some View {
        CardBox(title: "检测系统", side: "\(m.systems.count) 项", sideCls: "na") {
            VStack(spacing: 0) {
                ForEach(Array(m.systems.enumerated()), id: \.element.id) { idx, sys in
                    systemRow(sys)
                    if idx < m.systems.count - 1 { ListDivider().padding(.vertical, 4) }
                }
            }
        }
    }

    private func systemRow(_ sys: HealthSystem) -> some View {
        let isOpen = expandedSystems.contains(sys.name)
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) {
                    if isOpen { expandedSystems.remove(sys.name) } else { expandedSystems.insert(sys.name) }
                }
            } label: {
                HStack(spacing: 10) {
                    StatusDot(cls: sys.statusCls)
                    Text(sys.name).font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Text(sys.statusText)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.statusColor(sys.statusCls))
                    Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if isOpen {
                VStack(spacing: 0) {
                    ForEach(Array(sys.children.enumerated()), id: \.element.id) { idx, item in
                        itemRow(item)
                        if idx < sys.children.count - 1 { ListDivider().padding(.leading, 8) }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func itemRow(_ item: HealthItem) -> some View {
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
                Text(desc).font(.system(size: 11)).foregroundStyle(.tertiary)
            }
        }
        .padding(.leading, 8)
        .padding(.vertical, 4)
    }

    private func loadIfNeeded() {
        guard !store.carId.isEmpty else { return }
        guard loadTask == nil || loadTask!.isCancelled else { return }
        if store.needsRefresh("check") {
            loadTask = Task { await load() }
        }
    }

    // MARK: 加载（逻辑不变）
    @MainActor
    private func load() async {
        guard !store.carId.isEmpty else {
            errText = "请先在车况页选择车辆"; loading = false; return
        }
        loading = true
        if let raw = store.caches["check"] as? [String: Any] {
            model = VM.healthModel(raw)
        }
        if let raw = try? await APIClient.shared.getCarCheck(carId: store.carId) {
            store.saveCache(["check": raw])
            model = VM.healthModel(raw)
            errText = nil
        } else if model == nil {
            errText = "车辆可能未生成体检报告"
        }
        loading = false
    }
}
