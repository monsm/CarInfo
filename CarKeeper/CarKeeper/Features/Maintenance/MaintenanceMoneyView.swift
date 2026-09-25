// =============================================================================
// 保养与钱 —— 保养记录 + 年检保险 + 估值 + 导出
//
// 原为「维保记录」页（`ServiceHistoryView`）。批 5 把它扩成一屏：
// 保养（时间线 / 费用统计）、证件（年检 + 保险）、钱（车辆估值）、
// 以及把自己记录带走的导出 —— 它们此前散在「车与账号」的四个弹层与一个深链里。
//
// 充电账单已搬到「充电」那一档（2026-09-23）：账本是充电本身的一部分。
// =============================================================================

import SwiftUI

struct MaintenanceMoneyView: View {
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
        //  正文只提供内容 —— 页面外壳（滚动 / 纸面底 / 页标题）不在这里，
        //  它是 `VehicleView` 里那张叫「保养」的卡（邻居 `MileageJournalSection`
        //  / `VehicleTipsSection` / `ExportDataSection` 同一条约定）。
        //
        //  此前这里包着 `DSPaperPage`：叠进卡里的是第二层 ScrollView + 第二层
        //  纸面底 + 自己的左右内边距（卡 18pt + 纸 16pt = 34pt，内容比别人窄
        //  一圈）；两层都可滚动时手势塌给内层，而内层拿到的是无限高，永远不会
        //  滚 —— 用户 2026-09-25：「每个卡片仔细核对，内容展开后是否拥挤」。
        //
        //  ⚠️ 与那层纸一起拆掉的还有一个陷阱：添加记录原本只有导航栏工具栏上
        //  那枚「＋」，而全 App 的导航栏是**隐藏**的（地图那一档没有顶栏，
        //  子页继承同一个栈）—— 那个入口从未显示过，等于「加一条保养记录」
        //  没有入口。现在它是内容里的一个按钮（`addServiceButton`）。
        VStack(alignment: .leading, spacing: 0) {
            // ① 即将到期（保养按里程、年检/保险按日期 —— 两套口径各自一组）
            if !upcomingServices.isEmpty {
                upcomingCard
            }
            InspectionSection()

            // ② 保养：统计 → 年份 → 时间线 → 记一笔
            //   「保养记录」这四个字留在这里是对的：这张卡里不止一件事（年检 /
            //   保养 / 估值 / 导出），这一行是**卡内分段**的标题，不是卡的名字。
            DSSectionHeader(title: "保养记录")
            statsCard
            yearFilter
            timelineCard
            addServiceButton

            // ③ 钱：估值（充电账单已搬到「充电」那一档 —— 账本就是充电本身的一部分）
            VehicleValuationSection()

            // ④ 带走你自己的记录
            ExportDataSection()
        }
        .sheet(isPresented: $showAddService) {
            AddServiceView(onSave: addEntry)
        }
        .accessibilityLabel(Text("保养"))
    }

    /// 「记一笔」：保养记录那条动作的**唯一入口**（它原来挂在永不显示的工具栏上）。
    /// 形状与「里程记账」那张卡里的「添加记录」一致：同一件事不在两处长得不一样。
    private var addServiceButton: some View {
        Button { showAddService = true } label: {
            Label("添加记录", systemImage: "plus.circle.fill")
                .font(TokensTypo.body.weight(.semibold))
        }
        .buttonStyle(DSPrimaryButtonStyle())
        .padding(.top, TokensSpacing.sm)
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
            .font(TokensTypo.caption)
            .foregroundStyle(TokensPalette.ambient)
            .frame(width: 28, height: 28)
            // 圆角走令牌（原来是字面量 6；刻度里最接近的是 small = 8）。
            // `.cornerRadius(_:)` 在 iOS 17 起是弃用写法 —— 形状要显式给出来。
            .background(TokensPalette.ambient.opacity(0.1),
                        in: RoundedRectangle(cornerRadius: TokensRadius.small, style: .continuous))
    }

    // MARK: - 年份筛选
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
                            // 这一枚是**药丸**：全 App 的标签/筛选胶囊都是 Capsule（见消息页的
                            // tagChip）。原来用了一个写死的 16 圆角 —— 它在 30pt 高的胶囊上
                            // 看起来像药丸，但换成别的字号的机器就成了圆角矩形。
                            .background(Capsule().fill(selectedYear == y
                                                       ? TokensPalette.ambient.opacity(0.2)
                                                       : Color.clear))
                            .foregroundStyle(selectedYear == y ? TokensPalette.ambient : TokensPalette.secondary)
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

        // 空态走 DSPlaceholder（全 App 的空态只有这一个形状），容器走 DSCard。
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

    // MARK: - 添加记录
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

// MARK: - Add Service Sheet
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

// MARK: - Preview
struct MaintenanceMoneyView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            MaintenanceMoneyView()
        }
    }
}
