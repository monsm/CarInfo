import SwiftUI

// 健康报告：评分圆环 + 系统级手风琴
struct HealthView: View {
    private let store = AppStore.shared
    @State private var model: HealthModel?
    @State private var loading = true
    @State private var errText: String?

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.cardSpacing) {
                if loading {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("正在读取健康报告…").font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 40)
                } else if let model {
                    // 评分 hero
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .stroke(Color(.systemGray5), lineWidth: 12)
                                .frame(width: 180, height: 180)
                            Circle()
                                .trim(from: 0, to: CGFloat(model.scorePct) / 100)
                                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                                .frame(width: 180, height: 180)
                            VStack(spacing: 2) {
                                Text(model.score).font(Theme.d1).foregroundStyle(.primary)
                                Text("/ 100").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        // 状态计数
                        HStack(spacing: 16) {
                            ForEach(model.counts) { c in
                                VStack(spacing: 4) {
                                    Text(c.n).font(Theme.d3)
                                        .foregroundStyle(c.cls == "ok" ? Color.green : (c.cls == "warn" ? Color.orange : Color.red))
                                    Text(c.key).font(.system(size: 12)).foregroundStyle(.secondary)
                                }
                            }
                        }
                        if !model.time.isEmpty {
                            Text("最近检测 \(model.time)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)

                    // 系统手风琴
                    CardBox(title: "检测系统") {
                        VStack(spacing: 0) {
                            ForEach(Array(model.systems.enumerated()), id: \.offset) { idx, sys in
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text(sys.name).font(.system(size: 15, weight: .semibold))
                                        Spacer()
                                        Text(sys.statusText)
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundStyle(Theme.statusColor(sys.statusCls))
                                    }
                                    if sys.open {
                                        ForEach(sys.children) { item in
                                            VStack(alignment: .leading, spacing: 4) {
                                                HStack {
                                                    Text(item.name).font(.system(size: 13)).foregroundStyle(.secondary)
                                                    Spacer()
                                                    Text(item.statusText)
                                                        .font(.system(size: 12, weight: .medium))
                                                        .foregroundStyle(Theme.statusColor(item.statusCls))
                                                }
                                                if let d = item.detect, !d.isEmpty {
                                                    KVRow(k: "检测值", v: d)
                                                }
                                                if let s = item.suggest, !s.isEmpty {
                                                    KVRow(k: "参考范围", v: s)
                                                }
                                                if let desc = item.desc, !desc.isEmpty {
                                                    Text(desc).font(.system(size: 12)).foregroundStyle(.tertiary)
                                                }
                                            }
                                            .padding(.leading, 8)
                                        }
                                    }
                                }
                                .padding(.vertical, 6)
                                if idx < model.systems.count - 1 { Divider() }
                            }
                        }
                    }
                } else if let err = errText {
                    ContentUnavailableView("暂无健康报告", systemImage: "exclamationmark.triangle",
                                           description: Text(err))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("健康报告")
        .onAppear { Task { await load() } }
        .refreshable { await load() }
    }

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
        } else {
            errText = "车辆可能未生成体检报告"
        }
        loading = false
    }
}
