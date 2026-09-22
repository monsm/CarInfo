// =============================================================================
// VehicleTipsView - 车辆提示与建议（个性化提醒 + 保养建议 + 节能技巧）
// =============================================================================

import SwiftUI

struct VehicleTipsView: View {
    private let store = AppStore.shared
    @State private var selectedCategory: TipCategory = .all
    @State private var dismissedTips: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "dismissed_tips")
 ?? [])

    // 智能提示引擎
    var tips: [VehicleTip] {
        var result: [VehicleTip] = []

        let cache = store.caches

        // 电量
        let energy = VM.energy(cache, store.car)
        if energy.socPct < 20 {
            result.append(VehicleTip(
                category: .efficiency,
                icon: "bolt.fill",
                title: "电量较低",
                body: "当前SOC \(energy.socPct)%，建议尽快充电",
                action: "去充电",
                severity: .warning
            ))
        }

        // 故障码
        let batt = batteryModel(cache)
        if batt.faultTotal > 0 {
            result.append(VehicleTip(
                category: .safety,
                icon: "exclamationmark.triangle.fill",
                title: "故障警告",
                body: "检测到 \(batt.faultTotal) 个故障码，建议检查",
                action: "查看详情",
                severity: .critical
            ))
        }

        // 门窗
        let control = ciVal(cache, "control")
        let doorOpen = (ciNumber(control, ["Door"]) ?? 0) > 0
        let windowOpen = (ciNumber(control, ["Window"]) ?? 0) > 0
        if doorOpen || windowOpen {
            result.append(VehicleTip(
                category: .safety,
                icon: "lock.open.fill",
                title: "门窗未关",
                body: "检测到车门或车窗未关闭，请及时处理",
                action: "远程关闭",
                severity: .warning
            ))
        }

        // 胎压
        let tyres = VM.tyreStatus(cache)
        if tyres.warnAny {
            let lowCount = tyres.items.filter { $0.warn }.count
            result.append(VehicleTip(
                category: .safety,
                icon: "circle.dashed",
                title: "胎压异常",
                body: "\(lowCount)个轮胎胎压不足",
                action: "充气建议",
                severity: .warning
            ))
        }

        // 维保提醒（取最近一次保养周期）
        if let next = ServiceReminderManager.shared.reminders.map({ $0.nextMileageKm }).min() {
            let kmToService = Int(next) - store.totalMileage
            if kmToService > 0 && kmToService < 1000 {
                result.append(VehicleTip(
                    category: .maintenance,
                    icon: "wrench.fill",
                    title: "即将保养",
                    body: "距下次保养仅剩 \(kmToService) km",
                    action: "预约保养",
                    severity: .info
                ))
            }
        }

        // 天气相关
        result.append(VehicleTip(
            category: .weather,
            icon: "cloud.sun.fill",
            title: "出行提示",
            body: "今日天气晴，适合出行",
            action: nil,
            severity: .info
        ))

        // 节能技巧
        if store.totalMileage > 1000 {
            result.append(VehicleTip(
                category: .efficiency,
                icon: "leaf.fill",
                title: "节能技巧",
                body: "保持匀速行驶可降低能耗约10%",
                action: nil,
                severity: .info
            ))
        }

        return result.filter { tip in
            !dismissedTips.contains(tip.id)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 分类筛选
                categoryPicker

                // 提示列表
                if tips.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 10) {
                        ForEach(filteredTips) { tip in
                            tipRow(tip)
                        }
                    }
                }
            }
            .padding(.horizontal, TokensSpacing.lg)
            .padding(.vertical, TokensSpacing.md)
        }
        .navigationTitle("车辆提示")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: dismissAll) {
                    Text("全部已读")
                        .font(.caption)
                        .foregroundStyle(TokensPalette.ambient)
                }
            }
        }
        .accessibilityLabel(Text("车辆智能提示"))
    }

    // MARK: - 分类筛选
    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(TipCategory.allCases) { cat in
                    Button(action: { selectedCategory = cat }) {
                        Text(cat.rawValue)
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(selectedCategory == cat ? TokensPalette.ambient.opacity(0.2) : Color.clear)
                            .foregroundStyle(selectedCategory == cat ? TokensPalette.ambient : TokensPalette.secondary)
                            .cornerRadius(16)
                    }
                }
            }
        }
    }

    private var filteredTips: [VehicleTip] {
        if selectedCategory == .all { return tips }
        return tips.filter { $0.category == selectedCategory }
    }

    // MARK: - 提示行
    private func tipRow(_ tip: VehicleTip) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // 严重度图标（原来是纯色小圆点，只靠颜色区分 critical / warning / info）
                Image(safeSymbol: tip.severity.iconName, fallback: "info.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tip.severity.color)
                    .frame(width: 14)
                    .accessibilityLabel(Text(tip.severity.label))

                // 图标
                Image(safeSymbol: tip.icon, fallback: "info.circle.fill")
                    .font(.caption)
                    .foregroundStyle(tip.severity.color)
                    .frame(width: 28, height: 28)
                    .background(tip.severity.color.opacity(0.1))
                    .cornerRadius(6)

                VStack(alignment: .leading, spacing: 2) {
                    Text(tip.title).font(TokensTypo.subheadline).foregroundStyle(.primary)
                    Text(tip.body).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()

                if let action = tip.action {
                    Button(action: { handleAction(tip) }) {
                        Text(action)
                            .font(.caption)
                            .foregroundStyle(TokensPalette.ambient)
                    }
                }

                Button(action: { dismiss(tip) }) {
                    Image(systemName: "xmark")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding()
        .glassCard(corner: TokensRadius.small)
        .onTapGesture {
            if tip.severity != .info { dismiss(tip) }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48))
                .foregroundStyle(TokensPalette.success.opacity(0.5))
            Text("一切正常")
                .font(TokensTypo.subheadline)
                .foregroundStyle(.secondary)
            Text("车辆状态良好，暂无新提示")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - 操作
    private func dismiss(_ tip: VehicleTip) {
        dismissedTips.insert(tip.id)
        persistDismissed()
    }

    private func dismissAll() {
        for tip in filteredTips { dismissedTips.insert(tip.id) }
        persistDismissed()
    }

    private func persistDismissed() {
        UserDefaults.standard.set(Array(dismissedTips), forKey: "dismissed_tips")
    }

    private func handleAction(_ tip: VehicleTip) {
        switch tip.title {
        case "电量较低":
            // Navigate to charging
            break
        case "故障警告":
            // Navigate to fault detail
            break
        default:
            EnhancedToastManager.shared.show(tip.body, icon: tip.icon)
        }
        dismiss(tip)
    }
}

// MARK: - 提示分类
enum TipCategory: String, CaseIterable, Identifiable {
    case all = "全部"
    case safety = "安全"
    case efficiency = "节能"
    case maintenance = "维保"
    case weather = "天气"
    var id: String { rawValue }
}

// MARK: - Vehicle Tip Model
struct VehicleTip: Identifiable {
    let id = UUID().uuidString
    let category: TipCategory
    let icon: String
    let title: String
    let body: String
    let action: String?
    let severity: TipSeverity
}

enum TipSeverity {
    case critical, warning, info

    var color: Color {
        switch self {
        case .critical: return .red
        case .warning: return .orange
        case .info: return .blue
        }
    }

    /// 严重度图标（替代原来只靠颜色区分的纯色小圆点）
    var iconName: String {
        switch self {
        case .critical: return "exclamationmark.octagon.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }

    /// 无障碍朗读用的文字
    var label: String {
        switch self {
        case .critical: return "严重"
        case .warning: return "警告"
        case .info: return "提示"
        }
    }
}

// MARK: - Preview
struct VehicleTipsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            VehicleTipsView()
        }
    }
}
