
import SwiftUI

struct MaintenanceMoneyView: View {
    private let store = AppStore.shared
    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())
    @State private var showAddService = false

    @AppStorage("serviceHistory") private var services: String = "[]"

    struct ServiceEntry: Codable, Identifiable, Equatable {
        var id = UUID()
        let date: Date
        let mileage: Int
        let type: String
        let cost: Double
        let description: String
        let nextMileage: Int?
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
        VStack(alignment: .leading, spacing: 0) {
            if !upcomingServices.isEmpty {
                upcomingCard
            }
            InspectionSection()

            DSSectionHeader(title: "保养记录")
            statsCard
            yearFilter
            timelineCard
            addServiceButton

            VehicleValuationSection()

            ExportDataSection()
        }
        .sheet(isPresented: $showAddService) {
            AddServiceView(onSave: addEntry)
        }
        .accessibilityLabel(Text("保养"))
    }

    private var addServiceButton: some View {
        Button { showAddService = true } label: {
            Label("添加记录", systemImage: "plus.circle.fill")
                .font(TokensTypo.body.weight(.semibold))
        }
        .buttonStyle(DSPrimaryButtonStyle())
        .padding(.top, TokensSpacing.sm)
    }

    private var statsCard: some View {
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

    private var upcomingCard: some View {
        VStack(alignment: .leading, spacing: TokensSpacing.xs) {
            DSSectionHeader(title: "即将到期", trailing: "\(upcomingServices.count) 项")

            DSGroup {
                ForEach(upcomingServices.prefix(3)) { entry in
                DSGroupRow {
                    HStack(spacing: TokensSpacing.md) {
                        typeIcon(entry.type)
                        VStack(alignment: .leading, spacing: TokensSpacing.xxs) {
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
            .font(TokensTypo.caption)
            .foregroundStyle(TokensPalette.ambient)
            .frame(width: 28, height: 28)
            .background(TokensPalette.ambient.opacity(0.1),
                        in: RoundedRectangle(cornerRadius: TokensRadius.small, style: .continuous))
    }

    private var yearFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: TokensSpacing.sm) {
                let years = Set(entries.map { Calendar.current.component(.year, from: $0.date) })
                    .union([selectedYear])
                    .sorted(by: >)
                ForEach(years, id: \.self) { y in
                    Button(action: { selectedYear = y }) {
                        Text("\(y)年")
                            .font(TokensTypo.caption)
                            .padding(.horizontal, TokensSpacing.snug)
                            .padding(.vertical, TokensSpacing.sm)
                            .background(Capsule().fill(selectedYear == y
                                                       ? TokensPalette.ambient.opacity(0.2)
                                                       : Color.clear))
                            .foregroundStyle(selectedYear == y ? TokensPalette.ambient : TokensPalette.secondary)
                    }
                }
            }
        }
    }

    private var timelineCard: some View {
        let filtered = entries
            .filter { Calendar.current.component(.year, from: $0.date) == selectedYear }
            .sorted { $0.date > $1.date }

        return DSCard(padding: 0, radius: TokensRadius.medium) {
            if filtered.isEmpty {
                DSPlaceholder(icon: "calendar.badge.minus",
                              title: "还没有维保记录",
                              message: "还没有保养记录。")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(filtered.enumerated()), id: \.element.id) { idx, entry in
                        timelineRow(entry, idx: idx, total: filtered.count)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func timelineRow(_ entry: ServiceEntry, idx: Int, total: Int) -> some View {
        VStack(alignment: .leading, spacing: TokensSpacing.xs) {
            HStack {
                typeIcon(entry.type)
                VStack(alignment: .leading, spacing: TokensSpacing.xxs) {
                    Text(entry.type).font(TokensTypo.subheadline).foregroundStyle(TokensPalette.primary)
                    Text(entry.description)
                        .font(TokensTypo.caption)
                        .foregroundStyle(TokensPalette.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Text("¥\(Int(entry.cost))")
                    .font(TokensTypo.subheadline.weight(.bold))
                    .foregroundStyle(TokensPalette.ambient)
            }
            HStack {
                Text(entry.date, style: .date)
                    .font(TokensTypo.caption2)
                    .foregroundStyle(TokensPalette.tertiary)
                if let next = entry.nextMileage {
                    Text("· 下次 \(next)km").font(TokensTypo.caption2).foregroundStyle(TokensPalette.tertiary)
                }
            }
        }
        .padding(.horizontal, TokensSpacing.snug)
        .padding(.vertical, TokensSpacing.snug)
        if idx < total - 1 {
            Divider().padding(.leading, TokensSpacing.row)
        }
    }

    private func addEntry(_ entry: ServiceEntry) {
        var list = entries
        list.append(entry)
        if let data = try? JSONEncoder().encode(list) {
            services = String(data: data, encoding: .utf8) ?? "[]"
        }
        showAddService = false
        ToastManager.shared.show("记录已保存", icon: "checkmark.circle.fill")
    }
}

struct AddServiceView: View {
    let onSave: (MaintenanceMoneyView.ServiceEntry) -> Void
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
        let entry = MaintenanceMoneyView.ServiceEntry(
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

struct MaintenanceMoneyView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            MaintenanceMoneyView()
        }
    }
}
