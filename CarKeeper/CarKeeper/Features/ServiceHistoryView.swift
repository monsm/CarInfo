// =============================================================================
// ServiceHistoryView —— 维保历史记录（里程提醒 + 维保时间线 + 费用统计）
// =============================================================================

import SwiftUI

struct ServiceHistoryView: View {
    private let store = AppStore.shared
    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())
    @State private var showAddService = false

    // 维保记录（本地持久化）
    @AppStorage("serviceHistory") private var services: String = "[]"

    struct ServiceEntry: Codable, Identifiable, Equatable {
        var id = UUID()
        let date: Date
        let mileage: Int
        let type: String       // 保养 / 年检 / 保险 / 轮胎
        let cost: Double
        let description: String
        let nextMileage: Int?  // 下次建议
    }

    var entries: [ServiceEntry] {
        if let data = services.data(using: .utf8),
           let list = try? JSONDecoder().decode([ServiceEntry].self, from: data) {
            return list
        }
        return []
    }

    var upcomingServices: [ServiceEntry] {
        entries.filter { e in
            if let next = e.nextMileage {
                return next > 0 && (store.totalMileage + 1000) >= next
            }
            return false
        }
    }

    var totalCost: Double {
        entries.reduce(0) { $0 + $1.cost }
    }

    var avgAnnualCost: Double {
        guard let first = entries.first?.date,
              let last = entries.last?.date,
              last.timeIntervalSince(first) > 0 else { return 0 }
        let years = max(last.timeIntervalSince(first) / (365 * 24 * 3600), 1)
        return totalCost / years
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: TokensSpacing.lg) {
                DSPageTitle(title: "维保记录", subtitle: "每一次保养、每一笔花费都在这里")

                // 统计
                statsCard

                // 即将到期提醒
                if !upcomingServices.isEmpty {
                    upcomingCard
                }

                // 年份筛选
                yearFilter

                // 时间线
                timelineCard
            }
            .padding(.horizontal, TokensSpacing.page)
            .padding(.vertical, TokensSpacing.lg)
        }
        .dsPageTitle("维保记录", inline: true)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showAddService = true }) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(TokensPalette.ambient)
                }
            }
        }
        .sheet(isPresented: $showAddService) {
            AddServiceView(onSave: addEntry)
                .dsSheetCanvas()
        }
        .accessibilityLabel(Text("维保历史记录"))
    }

    // MARK: - 统计卡
    private var statsCard: some View {
        // 三个数字，不要三种颜色：它们都是「钱与次数」，不是三种状态。
        // （原来 总花费=蓝 年均=绿 次数=橙 —— 颜色在这里不携带任何信息）
        DSGroup {
            DSGroupRow {
                HStack(spacing: 0) {
                    statCell(label: "总花费", value: "¥\(Int(totalCost))")
                    statCell(label: "年均", value: "¥\(Int(avgAnnualCost))")
                    statCell(label: "记录", value: "\(entries.count)")
                }
                .padding(.vertical, TokensSpacing.xs)
            }
        }
    }

    private func statCell(label: String, value: String) -> some View {
        VStack(spacing: TokensSpacing.xs) {
            Text(value)
                .font(TokensTypo.title3)
                .foregroundStyle(TokensPalette.primary)
            Text(label)
                .font(TokensTypo.caption2)
                .foregroundStyle(TokensPalette.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 即将到期
    private var upcomingCard: some View {
        VStack(alignment: .leading, spacing: TokensSpacing.xs) {
            // 分组标题走全 App 那一行字；警示色只留给图标（它真是一类状态：待处理）
            DSSectionHeader(title: "即将到期", trailing: "\(upcomingServices.count) 项")

            DSGroup {
                ForEach(upcomingServices.prefix(3)) { entry in
                DSGroupRow {
                    HStack(spacing: TokensSpacing.md) {
                        typeIcon(entry.type)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.type)
                                .font(TokensTypo.subheadline)
                                .foregroundStyle(TokensPalette.primary)
                            Text("里程 \(entry.mileage)km → \(entry.nextMileage ?? 0)km")
                                .font(TokensTypo.caption2)
                                .foregroundStyle(TokensPalette.secondary)
                        }
                        Spacer(minLength: 0)
                        if let next = entry.nextMileage {
                            let remaining = next - store.totalMileage
                            // 「还剩多少公里」是真实余量；接近了就转红（余量本身是状态）
                            Text("\(max(0, remaining))km")
                                .font(TokensTypo.dataSmall)
                                .foregroundStyle(remaining < 500 ? TokensPalette.error : TokensPalette.warning)
                        }
                    }
                }
                }
            }
        }
    }

    private func typeIcon(_ type: String) -> some View {
        let icon: String
        switch type {
        case "保养": icon = "wrench.and.screwdriver"
        case "年检": icon = "calendar.badge.checkmark"
        case "保险": icon = "shield.fill"
        case "轮胎": icon = "circle.dashed"
        default: icon = "circle"
        }
        return Image(safeSymbol: icon, fallback: "wrench.and.screwdriver.fill")
            .font(.caption)
            .foregroundStyle(TokensPalette.ambient)
            .frame(width: 28, height: 28)
            .background(TokensPalette.ambient.opacity(0.1))
            .cornerRadius(6)
    }

    // MARK: - 年份筛选
    private var yearFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                let years = Set(entries.map { Calendar.current.component(.year, from: $0.date) })
                    .union([selectedYear])
                    .sorted(by: >)
                ForEach(years, id: \.self) { y in
                    Button(action: { selectedYear = y }) {
                        Text("\(y)年")
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(selectedYear == y ? TokensPalette.ambient.opacity(0.2) : Color.clear)
                            .foregroundStyle(selectedYear == y ? TokensPalette.ambient : TokensPalette.secondary)
                            .cornerRadius(16)
                    }
                }
            }
        }
    }

    // MARK: - 时间线
    private var timelineCard: some View {
        let filtered = entries
            .filter { Calendar.current.component(.year, from: $0.date) == selectedYear }
            .sorted { $0.date > $1.date }

        return VStack(spacing: 0) {
            if filtered.isEmpty {
                VStack(spacing: 12) {
                    Image(safeSymbol: "calendar.badge.minus", fallback: "calendar")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary.opacity(0.3))
                    Text("暂无记录").font(.subheadline).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            } else {
                ForEach(Array(filtered.enumerated()), id: \.element.id) { idx, entry in
                    timelineRow(entry, idx: idx, total: filtered.count)
                }
            }
        }
        .glassCard(corner: TokensRadius.medium)
    }

    @ViewBuilder
    private func timelineRow(_ entry: ServiceEntry, idx: Int, total: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                typeIcon(entry.type)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.type).font(TokensTypo.subheadline).foregroundStyle(.primary)
                    Text(entry.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Text("¥\(Int(entry.cost))")
                    .font(Theme.font(.subheadline as Font).bold())
                    .foregroundStyle(TokensPalette.ambient)
            }
            HStack {
                Text(entry.date, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                if let next = entry.nextMileage {
                    Text("· 下次 \(next)km").font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        if idx < total - 1 {
            Divider().padding(.leading, 44)
        }
    }

    // MARK: - 添加记录
    private func addEntry(_ entry: ServiceEntry) {
        var list = entries
        list.append(entry)
        if let data = try? JSONEncoder().encode(list) {
            services = String(data: data, encoding: .utf8) ?? "[]"
        }
        showAddService = false
        EnhancedToastManager.shared.show("记录已保存", icon: "checkmark.circle.fill")
    }
}

// MARK: - Add Service Sheet
struct AddServiceView: View {
    let onSave: (ServiceHistoryView.ServiceEntry) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var type = "保养"
    @State private var mileage = ""
    @State private var cost = ""
    @State private var description = ""
    @State private var nextMileage = ""

    let types = ["保养", "年检", "保险", "轮胎"]

    var body: some View {
        NavigationStack {
            Form {
                Section("类型") {
                    Picker("类型", selection: $type) {
                        ForEach(types, id: \.self) { Text($0) }
                    }
                }
                Section("详情") {
                    TextField("当前里程（km）", text: $mileage)
                        .keyboardType(.numberPad)
                    TextField("费用（元）", text: $cost)
                        .keyboardType(.decimalPad)
                    TextField("说明", text: $description)
                    TextField("下次建议里程", text: $nextMileage)
                        .keyboardType(.numberPad)
                }
            }
            .navigationTitle("添加记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(mileage.isEmpty)
                }
            }
        }
    }

    private func save() {
        let entry = ServiceHistoryView.ServiceEntry(
            date: Date(),
            mileage: Int(mileage) ?? 0,
            type: type,
            cost: Double(cost) ?? 0,
            description: description,
            nextMileage: Int(nextMileage)
        )
        onSave(entry)
    }
}

// MARK: - Preview
struct ServiceHistoryView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            ServiceHistoryView()
        }
    }
}
