// =============================================================================
// 里程记账 — 记录加油/充电/保养花费明细
//
// 原为独立页面（`MileageJournalView`，从「我的」里以 sheet 打开）。批 3 把它
// 并进**车辆档案**：花在车上的钱是这辆车的一部分，不是另一个功能目录。
// 它现在只提供内容（`MileageJournalSection`），页面外壳归 `VehicleView`。
// =============================================================================

import Foundation
import SwiftUI

enum TripCostType: String, CaseIterable, Identifiable, Codable {
    case charge = "charging"
    case fuel = "refuel"
    case parking = "parking"
    case maintenance = "maintenance"
    case toll = "toll"
    case wash = "carwash"
    case insurance = "insurance"

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .charge: return "充电"
        case .fuel: return "加油"
        case .parking: return "停车"
        case .maintenance: return "保养"
        case .toll: return "过路费"
        case .wash: return "洗车"
        case .insurance: return "保险"
        }
    }
    var icon: String {
        switch self {
        case .charge: return "bolt.fill"
        case .fuel: return "fuelpump.fill"
        case .parking: return "parkingsign.fill"
        case .maintenance: return "wrench.and.screwdriver.fill"
        case .toll: return "building.columns.fill"
        case .wash: return "drop.fill"
        case .insurance: return "shield.fill"
        }
    }
}

struct CostEntry: Identifiable, Codable {
    var id = UUID()
    let date: Date
    let type: TripCostType
    let amount: Double
    let note: String
    let odometerKm: Double?
}

class MileageTracker : ObservableObject {
    static let shared = MileageTracker()

    var entries: [CostEntry] {
        if let data = UserDefaults.standard.data(forKey: "carkeeper_mileage_entries"),
           let decoded = try? JSONDecoder().decode([CostEntry].self, from: data) {
            return decoded.sorted { $0.date > $1.date }
        }
        return []
    }

    func addEntry(_ entry: CostEntry) {
        var list = entries
        list.insert(entry, at: 0)
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: "carkeeper_mileage_entries")
        }
    }

    func deleteEntry(_ id: UUID) {
        let list = entries.filter { $0.id != id }
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: "carkeeper_mileage_entries")
        }
    }

    //  `totalThisMonth()` 与 `totalByType(_:)` 已删（2026-09-26 第三十一轮审核）：
    //  全仓零个读者 —— 里程账本那一屏只列明细，没有「本月合计」那一行。
    //  留着它们的代价是下一个人会以为「已经有地方在算合计数了」（而屏幕上一个也没有）。

    /// 清空全部记录。按键上的「清空历史」此前是个**空闭包**（点了什么都不发生），
    /// 现在真的能清，且调用方必须先确认。
    func clearAll() {
        UserDefaults.standard.removeObject(forKey: "carkeeper_mileage_entries")
    }
}

struct MileageJournalSection: View {
    @StateObject private var tracker = MileageTracker.shared
    @State private var showAddSheet = false
    @State private var showClearConfirm = false
    @State private var selectedType: TripCostType = .charge
    @State private var amountText: String = ""
    @State private var noteText: String = ""

    private let months = ["本月", "上月", "全部"]
    @State private var currentPeriod = 0

    var body: some View {
        VStack(alignment: .leading, spacing: TokensSpacing.lg) {
            //  这里原来有一行 `DSSectionHeader(title: "里程记账")` —— 而这张卡就叫
            //  「里程记账」，卡头已经写了名字（用户 2026-09-25：「全局看重复内容」）。
            //  正文直接从第一件东西（周期分段）开始。

            // 周期：三个互斥的口径 → 系统的分段语法
            DSSegmentPicker(options: months.indices.map { (value: $0, title: months[$0]) },
                            selection: $currentPeriod,
                            label: "账期")

            // 统计：一组键值行，不是一个彩色方块矩阵（口径跟着上面的分段走）
            DSGroup(footer: "与上面同口径") {
                ForEach(Array(TripCostType.allCases.prefix(4)), id: \.self) { type in
                    DSGroupRow {
                        DSKeyValueRow(key: type.displayName,
                                      value: String(format: "¥%.1f", total(type)))
                    }
                }
            }

            // 明细
            entriesSection

            // 添加
            Button { showAddSheet = true } label: {
                Label("添加记录", systemImage: "plus.circle.fill")
                    .font(TokensTypo.body.weight(.semibold))
            }
            .buttonStyle(DSPrimaryButtonStyle())

            // 清空：原来它挂在工具栏上，闭包是**空的** —— 点了什么都不发生。
            // 账目不可撤销，所以真清之前必须先确认。
            if !tracker.entries.isEmpty {
                Button("清空全部记录", role: .destructive) { showClearConfirm = true }
                    .font(TokensTypo.caption)
                    .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddCostEntrySheet(selectedType: $selectedType, amountText: $amountText, noteText: $noteText)
                .onAppear { amountText = "" ; noteText = "" }
        }
        .confirmationDialog("清空全部里程记账？",
                            isPresented: $showClearConfirm,
                            titleVisibility: .visible) {
            Button("清空 \(tracker.entries.count) 条记录", role: .destructive) {
                tracker.clearAll()
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text("只存本机，清空不可恢复")
        }
    }

    // MARK: - 口径

    /// 周期口径：0 = 本月，1 = 上月，其它 = 全部。
    ///
    /// 原来这个分段控件**只换选中态**：统计读全量、明细也读全量，
    /// 切到「上月」数字纹丝不动 —— 一个不会改变任何东西的控件。
    private var periodRange: (start: Date, end: Date?)? {
        let cal = Calendar.current
        let now = Date()
        switch currentPeriod {
        case 0:
            guard let start = cal.date(from: cal.dateComponents([.year, .month], from: now)) else { return nil }
            return (start, nil)
        case 1:
            guard let thisMonth = cal.date(from: cal.dateComponents([.year, .month], from: now)),
                  let start = cal.date(byAdding: .month, value: -1, to: thisMonth) else { return nil }
            return (start, thisMonth)
        default:
            return nil
        }
    }

    private var periodEntries: [CostEntry] {
        guard let range = periodRange else { return tracker.entries }
        return tracker.entries.filter { entry in
            if let end = range.end, entry.date >= end { return false }
            return entry.date >= range.start
        }
    }

    private func total(_ type: TripCostType) -> Double {
        periodEntries.filter { $0.type == type }.map(\.amount).reduce(0, +)
    }

    /// 明细：一组长按可删的行。
    ///
    /// 原来这里写的是「VStack 里的 ForEach + .swipeActions(edge:) + .listStyle(.plain)」——
    /// `swipeActions` 只在 `List` 的行内生效，所以那条滑动删除**从来没有工作过**
    /// （`.listStyle` 加在 VStack 上也是空转）。现在删除挂在长按菜单上，并在页脚说明。
    private var entriesSection: some View {
        DSGroup(title: "明细",
                trailing: "\(periodEntries.count)",
                footer: periodEntries.isEmpty ? "还没有记录" : "长按可删除") {
            ForEach(periodEntries) { entry in
                DSGroupRow {
                    CostEntryRow(entry: entry)
                }
                .contextMenu {
                    Button("删除", role: .destructive) { tracker.deleteEntry(entry.id) }
                }
            }
        }
    }
}

struct AddCostEntrySheet: View {
    @Binding var selectedType: TripCostType
    @Binding var amountText: String
    @Binding var noteText: String
    @Environment(\.dismiss) private var dismiss
    @State private var showTypePicker = false
    @State private var selectedDate = Date()
    @State private var odometerText: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("类型") {
                    Picker("费用类型", selection: $selectedType) {
                        ForEach(TripCostType.allCases) { type in
                            // 原先把 symbol 名当文字拼在标签里（会显示成 "fuelpump.fill 加油"），
                            // 改成真正的图标 + 文字
                            Label {
                                Text(type.displayName)
                            } icon: {
                                Image(safeSymbol: type.icon, fallback: "doc.text.fill")
                            }
                            .tag(type)
                        }
                    }
                }
                Section("金额") {
                    TextField("金额（元）", text: $amountText)
                        .keyboardType(.decimalPad)
                    TextField("备注（可选）", text: $noteText)
                }
                Section("日期") {
                    DatePicker("日期", selection: $selectedDate, displayedComponents: .date)
                }
                Section("里程（可选）") {
                    TextField("当前里程 km", text: $odometerText)
                        .keyboardType(.decimalPad)
                }
            }
            .navigationTitle("添加记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        if let amount = Double(amountText), amount > 0 {
                            let entry = CostEntry(
                                date: selectedDate,
                                type: selectedType,
                                amount: amount,
                                note: noteText,
                                odometerKm: Double(odometerText)
                            )
                            MileageTracker.shared.addEntry(entry)
                            dismiss()
                        }
                    }
                    .disabled(Double(amountText) == nil || Double(amountText)! <= 0)
                }
            }
        }
    }
}

struct CostEntryRow: View {
    let entry: CostEntry
    var body: some View {
        HStack(spacing: TokensSpacing.sm) {
            Image(safeSymbol: entry.type.icon, fallback: "doc.text.fill")
                .font(TokensTypo.headline)
                .frame(width: 36, height: 36)
                .background(TokensPalette.ambient.opacity(0.15))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: TokensSpacing.xxs) {
                Text(entry.type.displayName)
                    .font(TokensTypo.body)
                    .foregroundStyle(TokensPalette.primary)
                Text(entry.note.isEmpty
                     ? entry.date.formatted(date: .omitted, time: .standard)
                     : entry.note)
                    .font(TokensTypo.caption)
                    .foregroundStyle(TokensPalette.secondary)
            }

            Spacer(minLength: TokensSpacing.sm)

            VStack(alignment: .trailing, spacing: TokensSpacing.xxs) {
                // 金额走等宽数字：一列金额的右边缘才是齐的
                Text("-¥\(entry.amount, specifier: "%.2f")")
                    .font(TokensTypo.data)
                    .foregroundStyle(TokensPalette.error)
                if let km = entry.odometerKm {
                    Text(String(format: "%.0f km", km))
                        .font(TokensTypo.caption2)
                        .foregroundStyle(TokensPalette.tertiary)
                }
            }
        }
    }
}
