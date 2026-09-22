// =============================================================================
// #NEW-128 里程记账本 — 记录加油/充电/保养花费明细
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

    func totalThisMonth() -> Double {
        let now = Date()
        let cal = Calendar.current
        let startOfMonth = cal.date(from: cal.dateComponents([.year, .month], from: now))!
        return entries.filter { $0.date >= startOfMonth }.map { $0.amount }.reduce(0, +)
    }

    func totalByType(_ type: TripCostType) -> Double {
        entries.filter { $0.type == type }.map { $0.amount }.reduce(0, +)
    }
}

struct MileageJournalView: View {
    @StateObject private var tracker = MileageTracker.shared
    @State private var showAddSheet = false
    @State private var selectedType: TripCostType = .charge
    @State private var amountText: String = ""
    @State private var noteText: String = ""

    private let months = ["本月", "上月", "全部"]
    @State private var currentPeriod = 0

    var body: some View {
        // 不再套一层 NavigationStack：本页是「我的」导航栈里打开的浮层，
        // 再套一层会出现两条导航栏、标题说两遍。
        ScrollView {
            LazyVStack(alignment: .leading, spacing: TokensSpacing.lg) {
                DSPageTitle(title: "里程记账", subtitle: "充电、停车、维保 —— 花在车上的每一笔")

                // 周期：三个互斥的口径 → 系统的分段语法
                DSSegmented(options: months.indices.map { (value: $0, title: months[$0]) },
                            selection: $currentPeriod)

                // 统计：一组键值行，不是一个彩色方块矩阵
                DSGroup {
                    ForEach(Array(TripCostType.allCases.prefix(4)), id: \.self) { type in
                        DSGroupRow {
                            DSKeyValueRow(key: type.displayName,
                                          value: String(format: "¥%.1f", tracker.totalByType(type)))
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
            }
            .padding(.horizontal, TokensSpacing.page)
            .padding(.vertical, TokensSpacing.lg)
        }
        .scrollBounceBehavior(.basedOnSize)
            .sheet(isPresented: $showAddSheet) {
                AddCostEntrySheet(selectedType: $selectedType, amountText: $amountText, noteText: $noteText)
                    .onAppear { amountText = "" ; noteText = "" }
                    .dsSheetCanvas()
            }
            .dsPageTitle("里程记账", inline: true)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("清空历史", role: .destructive) {
                        // 清空所有记录（需确认）
                    }
                    .font(TokensTypo.caption)
                    .disabled(tracker.entries.isEmpty)
                }
            }
    }

    /// 明细：一组长按可删的行。
    ///
    /// 原来这里写的是「VStack 里的 ForEach + .swipeActions(edge:) + .listStyle(.plain)」——
    /// `swipeActions` 只在 `List` 的行内生效，所以那条滑动删除**从来没有工作过**
    /// （`.listStyle` 加在 VStack 上也是空转）。现在删除挂在长按菜单上，并在页脚说明。
    private var entriesSection: some View {
        DSGroup(title: "明细",
                footer: tracker.entries.isEmpty ? "还没有记录。" : "长按一条记录可以删除。") {
            ForEach(tracker.entries) { entry in
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
                .font(.headline)
                .frame(width: 36, height: 36)
                .background(TokensPalette.ambient.opacity(0.15))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
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

            VStack(alignment: .trailing, spacing: 2) {
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
