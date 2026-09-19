// =============================================================================
// #NEW-128 里程记账本 — 记录加油/充电/保养花费明细
// =============================================================================

import Foundation
import SwiftUI

enum TripCostType: String, CaseIterable, Identifiable {
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
        case .toll: return "bank.fill"
        case .wash: return "drop.fill"
        case .insurance: return "shield.fill"
        }
    }
}

struct CostEntry: Identifiable, Codable {
    let id = UUID()
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
        var list = entries.filter { $0.id != id }
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
        NavigationStack {
            VStack(spacing: Theme.Spacing.md) {
                // 周期选择
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Spacing.sm) {
                        ForEach(months.indices, id: \.self) { i in
                            Text(months[i])
                                .font(.subheadline)
                                .foregroundColor(currentPeriod == i ? .white : .secondary)
                                .padding(.horizontal, Theme.Spacing.md)
                                .padding(.vertical, Theme.Spacing.xs)
                                .background(currentPeriod == i ? Theme.Colors.accent : Color.clear)
                                .cornerRadius(Theme.Radius.sm)
                                .onTapGesture { currentPeriod = i }
                        }
                    }
                }
                
                // 统计卡片
                HStack(spacing: Theme.Spacing.sm) {
                    for type in TripCostType.allCases.prefix(4) {
                        CostSummaryTile(type: type, total: tracker.totalByType(type))
                    }
                }
                
                Divider().opacity(0.3)
                
                // 明细列表
                VStack(spacing: 0) {
                    ForEach(tracker.entries) { entry in
                        CostEntryRow(entry: entry)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { tracker.deleteEntry(entry.id) }
                                    .labelStyle(.iconOnly)
                                    .tint(.red)
                            }
                    }
                }
                .listStyle(.plain)
                
                Spacer()
                
                // 添加按钮
                Button { showAddSheet = true } label: {
                    Label("添加记录", systemImage: "plus.circle.fill")
                        .font(.body)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Theme.Colors.accent)
                        .foregroundColor(.white)
                        .cornerRadius(Theme.Radius.md)
                }
                .padding(.top, Theme.Spacing.sm)
            }
            .sheet(isPresented: $showAddSheet) {
                AddCostEntrySheet(selectedType: $selectedType, amountText: $amountText, noteText: $noteText)
                    .onAppear { amountText = "" ; noteText = "" }
            }
            .navigationTitle("里程记账")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("清空历史", role: .destructive) {
                        // 清空所有记录（需确认）
                    }
                    .font(.caption)
                }
            }
        }
    }
}

struct CostSummaryTile: View {
    let type: TripCostType
    let total: Double
    var body: some View {
        VStack(spacing: Theme.Spacing.xs) {
            Image(systemName: type.icon)
                .font(.title2)
                .foregroundColor(.accent)
            Text("\(total, specifier: "%.1f")")
                .font(.callout)
                .fontWeight(.semibold)
            Text(type.displayName)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.sm)
        .glassCard()
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
                            Text("\(type.icon) \(type.displayName)").tag(type)
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
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: entry.type.icon)
                .font(.headline)
                .frame(width: 36, height: 36)
                .background(.accent.opacity(0.15))
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.type.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(entry.note.isEmpty ? entry.date.formatted(date: .omitted, time: .standard) : entry.note)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text("-¥\(entry.amount, specifier: "%.2f")")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.red)
                if let km = entry.odometerKm {
                    Text(String(format: "%.0f km", km))
                        .font(.caption2)
                        .foregroundColor(.tertiaryLabel)
                }
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
    }
}
