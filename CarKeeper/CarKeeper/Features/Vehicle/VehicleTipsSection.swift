// =============================================================================
// 用车提示 — 由车上报的读数推出的提醒
//
// 原为独立页面（`VehicleTipsView`，深链 `carkeeper://tips`）。批 3 把它并进
// **车辆档案**：提示是从这辆车的读数推出来的，它属于车，不属于另一个页面。
// 它现在只提供内容（`VehicleTipsSection`），页面外壳归 `VehicleView`。
// =============================================================================

import SwiftUI

struct VehicleTipsSection: View {
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
                body: "车门或车窗未关",
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
            body: "今天天气晴",
            action: nil,
            severity: .info
        ))

        // 节能技巧
        if store.totalMileage > 1000 {
            result.append(VehicleTip(
                category: .efficiency,
                icon: "leaf.fill",
                title: "节能技巧",
                body: "匀速行驶省电约 10%",
                action: nil,
                severity: .info
            ))
        }

        return result.filter { tip in
            !dismissedTips.contains(tip.id)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TokensSpacing.lg) {
            sectionHeader

            // 分类筛选
            categoryPicker

            // 提示列表：一个分组（原来是一叠各自带底的卡）
            if tips.isEmpty {
                emptyState
            } else {
                DSGroup(title: "提示", trailing: "\(filteredTips.count) 条") {
                    ForEach(filteredTips) { tip in
                        DSGroupRow {
                            tipRow(tip)
                        }
                    }
                }
            }
        }
        .accessibilityLabel(Text("车辆智能提示"))
    }

    /// 「全部已读」挂在分组标题的最右侧。
    ///
    /// 原来它在导航栏的工具栏里 —— 并入车辆档案之后这一节没有自己的导航栏，
    /// 所以动作必须落在内容里；凭空造一个按钮反而会让这一节看起来又像一个页面。
    private var sectionHeader: some View {
        DSSectionHeader(title: "用车提示",
                        trailing: tips.isEmpty ? nil : "全部已读",
                        action: tips.isEmpty ? nil : { dismissAll() })
    }

    // MARK: - 分类筛选
    private var categoryPicker: some View {
        // 五个互斥的分类 → 系统的分段语法（自造药丸撑不住「选中」这个状态）
        DSSegmented(options: TipCategory.allCases.map { (value: $0, title: $0.rawValue) },
                    selection: $selectedCategory)
    }

    private var filteredTips: [VehicleTip] {
        if selectedCategory == .all { return tips }
        return tips.filter { $0.category == selectedCategory }
    }

    // MARK: - 提示行
    private func tipRow(_ tip: VehicleTip) -> some View {
        // 一行只有一个图标（原来同一行里有严重度小图标 + 提示图标两个，
        // 它们指向同一个意思，只是把「红黄蓝」说两通）。
        HStack(spacing: TokensSpacing.md) {
            Image(safeSymbol: tip.icon, fallback: "info.circle.fill")
                .font(TokensTypo.caption)
                .foregroundStyle(tip.severity.color)
                .frame(width: TokensSize.iconColumn, alignment: .center)
                .accessibilityLabel(Text(tip.severity.label))

            VStack(alignment: .leading, spacing: 2) {
                Text(tip.title)
                    .font(TokensTypo.subheadline)
                    .foregroundStyle(TokensPalette.primary)
                Text(tip.body)
                    .font(TokensTypo.caption)
                    .foregroundStyle(TokensPalette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: TokensSpacing.sm)

            if let action = tip.action {
                Button(action: { handleAction(tip) }) {
                    Text(action)
                        .font(TokensTypo.caption)
                        .foregroundStyle(TokensPalette.ambient)
                }
            }

            Button(action: { dismiss(tip) }) {
                Image(safeSymbol: "xmark", fallback: "xmark")
                    .font(TokensTypo.caption2)
                    .foregroundStyle(TokensPalette.tertiary)
            }
            .accessibilityLabel(Text("忽略这条提示"))
        }
    }

    private var emptyState: some View {
        DSPlaceholder(icon: "checkmark.seal.fill",
                      title: "一切正常",
                      message: "暂无新提示",
                      cls: "ok")
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
        // 原来这里有两支空实现（`// Navigate to charging` + break）：
        // 按「去充电」或「查看详情」**什么都不发生**，然后提示就被标记已读 ——
        // 用户以为处理过了，其实只是被藏起来了。这一节没有自己的导航目标，
        // 所以先把话说清楚：给一个可见的回应，再标记已读。
        EnhancedToastManager.shared.show(tip.body, icon: tip.icon)
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
        // 三个系统色名 → 三个语义令牌：换主题（纸/夜光）时它们必须跟着变，
        // 而 `.red` 在任何主题下都只是红色。
        case .critical: return TokensPalette.error
        case .warning: return TokensPalette.warning
        case .info: return TokensPalette.info
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
struct VehicleTipsSection_Previews: PreviewProvider {
    static var previews: some View {
        ScrollView { VehicleTipsSection() }
    }
}
