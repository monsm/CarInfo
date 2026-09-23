// =============================================================================
// N32 充电历史账单 PDF + N33 车辆估值 + N34 年检日历
// =============================================================================

import Foundation
import PDFKit
import SwiftUI
import UIKit

// MARK: - N32 充电历史账单 PDF
/// 账单里的一行。**数据来自 `ChargeLedger` 的真实会话**（功率采样积分出来的 kWh），
/// 不是人工记账；SOC 取不到就是 nil —— 那一格在 PDF 里印 `--`，不编一个数字。
struct ChargeRecord: Codable {
    let date: Date
    let kWh: Double
    let cost: Double
    let socStart: Int?
    let socEnd: Int?
}

class ChargeBillGenerator {
    static let shared = ChargeBillGenerator()

    func generatePDF(records: [ChargeRecord], vehiclePlate: String) -> URL? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年MM月"
        let monthStr = formatter.string(from: Date())

        let pdfRenderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 595, height: 842))
        let pdfData = pdfRenderer.pdfData { ctx in
            ctx.beginPage()

            // 标题
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 24, weight: .bold),
                .foregroundColor: UIColor.label
            ]
            "充电账单".draw(at: CGPoint(x: 40, y: 60), withAttributes: titleAttrs)

            // 月份
            let subAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 14, weight: .regular),
                .foregroundColor: UIColor.secondaryLabel
            ]
            "\(vehiclePlate) · \(monthStr)".draw(at: CGPoint(x: 40, y: 95), withAttributes: subAttrs)

            // 汇总
            let totalKWh = records.map { $0.kWh }.reduce(0, +)
            let totalCost = records.map { $0.cost }.reduce(0, +)
            let summary = "总计：\(String(format: "%.1f", totalKWh)) kWh · ¥\(String(format: "%.2f", totalCost))"
            let sumAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 16, weight: .semibold),
                .foregroundColor: UIColor.systemGreen
            ]
            summary.draw(at: CGPoint(x: 40, y: 130), withAttributes: sumAttrs)

            // 表格头
            let headerY: CGFloat = 170
            let colX: [CGFloat] = [40, 180, 280, 380, 480]
            let headers = ["日期", "SOC 起始", "SOC 结束", "度数", "费用"]
            headers.enumerated().forEach { i, h in
                h.draw(at: CGPoint(x: colX[i], y: headerY), withAttributes: subAttrs)
            }

            // 分割线
            UIColor.separator.withAlphaComponent(0.3).setStroke()
            let line = UIBezierPath(rect: CGRect(x: 40, y: headerY + 20, width: 515, height: 1))
            line.stroke()

            // 记录行
            let rowAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12),
                .foregroundColor: UIColor.label
            ]
            records.prefix(20).enumerated().forEach { idx, record in
                let rowY = headerY + 35 + CGFloat(idx) * 25
                formatter.dateFormat = "MM/dd"
                let dateStr = formatter.string(from: record.date)
                let row = [dateStr,
                           record.socStart.map { "\($0)%" } ?? "--",
                           record.socEnd.map { "\($0)%" } ?? "--",
                           String(format: "%.1f", record.kWh), String(format: "%.2f", record.cost)]
                row.enumerated().forEach { i, text in
                    text.draw(at: CGPoint(x: colX[i], y: rowY), withAttributes: rowAttrs)
                }
            }

            // 底部说明：把「这些数字是怎么来的」印在纸上，而不是只写在代码里
            let note = "度数由车端功率采样积分得出；费用 = 度数 × 你设的电价（非充电站实际价）。"
            let noteAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 10),
                .foregroundColor: UIColor.tertiaryLabel
            ]
            note.draw(at: CGPoint(x: 40, y: 790), withAttributes: noteAttrs)
        }

        let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = docsDir.appendingPathComponent("charge_bill_\(monthStr).pdf")
        try? pdfData.write(to: fileURL)
        return fileURL
    }
}

// MARK: - N33 车辆估值
class VehicleValuation {
    static let shared = VehicleValuation()

    /// 基于使用年限 + 里程估算残值率
    func estimateValue(initialPrice: Double, years: Int, mileageKm: Double) -> Double {
        // 年折旧：前3年每年15%，之后每年10%
        var depreciation = 1.0
        for year in 1...max(years, 1) {
            if year <= 3 {
                depreciation *= 0.85
            } else {
                depreciation *= 0.90
            }
        }
        // 里程折旧：每万公里降2%，上限30%
        let mileageDep = min(Double(mileageKm / 10000) * 0.02, 0.30)
        return initialPrice * depreciation * (1 - mileageDep)
    }

}

// MARK: - N34 年检日历
struct Inspection: Identifiable, Codable {
    var id = UUID()
    let vehicleName: String
    let date: Date
    var notes: String = ""
}

class InspectionCalendar: ObservableObject {
    @Published var inspections: [Inspection] = []
    static let shared = InspectionCalendar()

    private init() {
        if let data = UserDefaults.standard.data(forKey: "carkeeper_inspections"),
           let decoded = try? JSONDecoder().decode([Inspection].self, from: data) {
            inspections = decoded
        }
    }

    func addInspection(_ inspection: Inspection) {
        var list = inspections
        list.append(inspection)
        // ⚠️ 必须写回 `inspections`：旧版只存了 UserDefaults、没有更新 `@Published` 数组，
        // 于是「保存年检」在本次运行里看上去没任何反应（重启才看得到）——
        // 数据其实存进去了，但界面读的是内存里那份没变的。
        inspections = list
        save(list)
    }

    /// 距离下次年检天数
    func daysUntilInspection(for inspection: Inspection) -> Int {
        Calendar.current.dateComponents([.day], from: Date(), to: inspection.date).day ?? 0
    }

    private func save(_ list: [Inspection]) {
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: "carkeeper_inspections")
        }
    }
}

// 已删（全仓零引用的死 API）：
//   · `upcomingInspections` / `expiredInspections` —— 新页面把年检与保险合在一条
//     时间轴上算，不再需要这两个只算年检的过滤属性
//   · `updateInspection` —— 它唯一的调用方是已删的 `InspectionEditForm`
//   · `VehicleValuation.valuationCard` —— 估值页自己用 `estimateValue` 与购车价算折旧率

// MARK: - UI 组件
//
// 这里原本还有 `InspectionRow` 与 `InspectionEditForm` 两个视图。
// `InspectionCalendarView` 改成 inset-grouped 分组之后，**两者都没有任何引用**了 ——
// 它们只是留在文件里，编译进来但不属于任何一处界面（而且是旧版玻璃卡的写法）。
// 已删；年检行现在由 `DSRow` 渲染，编辑入口就是页面底部那个「保存年检」。

// MARK: - UI: 证件与到期日（年检 + 保险）
/// 年检与保险是同一件事的两面：「哪个证件什么时候到期」。
/// 这一页只存**用户自己填的日期**（本机 UserDefaults，没有云端副本），
/// 并把这些日期交给提醒调度器 —— 提醒这件事以前从来没被调用过（见文件尾注释）。
/// 年检 + 保险。
///
/// 原为独立 sheet（`InspectionCalendarView`，从「车与账号」的「年检与保险」行弹出）。
/// 批 5 并进**保养与钱**：证件到期就是钱与手续的一部分，不再单占一个弹层。
struct InspectionSection: View {
    /// `InspectionCalendar` 是 `ObservableObject`（`@Published` 存的是 inspections）。
    /// 用 `@State` 装一个 class 不会触发重绘 —— 存进去后「添加年检」要等退出重进才看得见。
    @StateObject private var calendar = InspectionCalendar.shared
    /// 保险政策是本机存储的（`InsuranceManager`），所以用一个可刷新的镜像。
    @State private var policies: [InsurancePolicy] = InsuranceManager.shared.policies
    @State private var inspectionName = ""
    @State private var inspectionDate = Date()
    @State private var insurer = ""
    @State private var insuranceType = "交强险"
    @State private var insuranceEnd = Date()
    @State private var premiumText = ""

    private static let insuranceTypes = ["交强险", "商业险", "座位险"]

    var body: some View {
        Group {
            VStack(alignment: .leading, spacing: TokensSpacing.lg) {
                DSSectionHeader(title: "年检与保险")

                // ① 最近要到的（年检 + 保险合在一个时间轴上）
                DSGroup(title: "最近到期",
                        footer: "到期前 30 天、7 天各提醒一次。") {
                    if dueItems.isEmpty {
                        DSGroupRow(showsSeparator: false) {
                            Text("还没有记录，下面添一条。")
                                .font(TokensTypo.footnote)
                                .foregroundStyle(TokensPalette.secondary)
                        }
                    } else {
                        ForEach(Array(dueItems.enumerated()), id: \.offset) { idx, item in
                            DSGroupRow(showsSeparator: idx < dueItems.count - 1) {
                                DSRow(icon: item.icon, title: item.title,
                                      subtitle: item.date.formatted(date: .abbreviated, time: .omitted),
                                      value: item.daysText, valueCls: item.cls)
                            }
                        }
                    }
                }

                // ② 年检
                DSGroup(title: "年检",
                        footer: "\u{201C}即将到期\u{201D}按 60 天算。过期的那条会标红。") {
                    ForEach(calendar.inspections.sorted { $0.date < $1.date }) { inspection in
                        DSGroupRow {
                            DSRow(icon: "calendar",
                                  title: inspection.vehicleName,
                                  subtitle: inspection.date.formatted(date: .abbreviated, time: .omitted),
                                  value: inspectionDaysText(inspection),
                                  valueCls: inspectionDays(inspection) < 0 ? "bad" : (inspectionDays(inspection) <= 30 ? "warn" : "ok"))
                        }
                    }
                    if calendar.inspections.isEmpty {
                        DSGroupRow(showsSeparator: false) {
                            Text("暂无年检记录").font(TokensTypo.footnote)
                                .foregroundStyle(TokensPalette.secondary)
                        }
                    }
                }

                // ③ 保险
                DSGroup(title: "保险",
                        footer: "只存你填的字段；保费合计 = 保单之和。") {
                    ForEach(policies) { p in
                        DSGroupRow {
                            DSKeyValueRow(key: "\(p.name) · \(p.type)",
                                          value: "到期 \(p.endDate.formatted(date: .abbreviated, time: .omitted)) · ¥\(String(format: "%.0f", p.premium))")
                        }
                    }
                    if policies.isEmpty {
                        DSGroupRow(showsSeparator: false) {
                            Text("暂无保单").font(TokensTypo.footnote)
                                .foregroundStyle(TokensPalette.secondary)
                        }
                    }
                    if !policies.isEmpty {
                        DSGroupRow(showsSeparator: false) {
                            DSKeyValueRow(key: "保费合计",
                                          value: "¥\(String(format: "%.0f", policies.map { $0.premium }.reduce(0, +)))")
                        }
                    }
                }

                // ④ 添加
                DSGroup(title: "添加年检", footer: "添加后立即可提醒。") {
                    DSGroupRow {
                        TextField("车辆名称", text: $inspectionName)
                            .font(TokensTypo.subheadline)
                    }
                    DSGroupRow {
                        DatePicker("年检到期日", selection: $inspectionDate, displayedComponents: .date)
                            .font(TokensTypo.subheadline)
                    }
                    DSGroupRow(showsSeparator: false) {
                        Button("保存年检") {
                            guard !inspectionName.isEmpty else { return }
                            calendar.addInspection(Inspection(vehicleName: inspectionName,
                                                              date: inspectionDate, notes: ""))
                            inspectionName = ""
                        }
                        .font(TokensTypo.subheadline.weight(.semibold))
                        .foregroundStyle(inspectionName.isEmpty ? TokensPalette.tertiary : TokensPalette.accent)
                        .disabled(inspectionName.isEmpty)
                    }
                }

                DSGroup(title: "添加保险") {
                    DSGroupRow {
                        TextField("保险公司（如：平安）", text: $insurer)
                            .font(TokensTypo.subheadline)
                    }
                    DSGroupRow {
                        Picker("险种", selection: $insuranceType) {
                            ForEach(Self.insuranceTypes, id: \.self) { Text($0).tag($0) }
                        }
                        .font(TokensTypo.subheadline)
                    }
                    DSGroupRow {
                        DatePicker("到期日", selection: $insuranceEnd, displayedComponents: .date)
                            .font(TokensTypo.subheadline)
                    }
                    DSGroupRow {
                        HStack {
                            Text("保费（元）").font(TokensTypo.subheadline)
                            Spacer()
                            TextField("如 3800", text: $premiumText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .font(TokensTypo.data)
                        }
                    }
                    DSGroupRow(showsSeparator: false) {
                        Button("保存保单") { savePolicy() }
                            .font(TokensTypo.subheadline.weight(.semibold))
                            .foregroundStyle(insurer.isEmpty ? TokensPalette.tertiary : TokensPalette.accent)
                            .disabled(insurer.isEmpty)
                    }
                }
            }
        }
        .task { await syncReminders() }
    }

    // MARK: 计算与动作

    private struct DueItem {
        let title: String
        let date: Date
        let days: Int
        let icon: String
        var daysText: String { days < 0 ? "已过期 \(-days) 天" : "\(days) 天后" }
        var cls: String { days < 0 ? "bad" : (days <= 30 ? "warn" : "ok") }
    }

    private func inspectionDays(_ i: Inspection) -> Int {
        calendar.daysUntilInspection(for: i)
    }

    private func inspectionDaysText(_ i: Inspection) -> String {
        let d = inspectionDays(i)
        return d < 0 ? "已过期" : "\(d) 天后"
    }

    /// 年检 + 保险合起来按到期日排序（只列未来的）
    private var dueItems: [DueItem] {
        let now = Date()
        var out: [DueItem] = []
        for i in calendar.inspections where i.date >= now {
            out.append(DueItem(title: "年检 · \(i.vehicleName)", date: i.date,
                               days: calendar.daysUntilInspection(for: i), icon: "calendar"))
        }
        for p in policies where p.endDate >= now {
            let d = Calendar.current.dateComponents([.day], from: now, to: p.endDate).day ?? 0
            out.append(DueItem(title: "\(p.type) · \(p.name)", date: p.endDate, days: d, icon: "shield.lefthalf.filled"))
        }
        return out.sorted { $0.date < $1.date }
    }

    private func savePolicy() {
        let p = InsurancePolicy(name: insurer,
                                type: insuranceType,
                                policyNumber: "",
                                startDate: Date(),
                                endDate: insuranceEnd,
                                premium: Double(premiumText) ?? 0,
                                claimHistory: [])
        InsuranceManager.shared.addPolicy(p)
        policies = InsuranceManager.shared.policies
        insurer = ""
        premiumText = ""
        Task { await syncReminders() }
    }

    /// 把最近要到期的那张保单交给提醒调度器。
    /// 此前 `scheduleInsuranceReminder` **从来没有调用点** —— 那个提醒永远不可能响。
    private func syncReminders() async {
        guard let next = policies.map(\.endDate).filter({ $0 > Date() }).min() else { return }
        _ = await InsuranceReminderScheduler.shared.requestNotificationPermission()
        await InsuranceReminderScheduler.shared.scheduleInsuranceReminder(insuranceEndDate: next)
    }
}

// MARK: - UI: 车辆估值视图
/// 车辆估值。
///
/// 同样从「车与账号」的弹层并进**保养与钱**（`VehicleValuationSection`）。
struct VehicleValuationSection: View {
    @State private var initialPrice: String = ""
    @State private var purchaseDate = Date()
    @State private var currentMileage: String = ""

    var estimatedValue: Double {
        let price = Double(initialPrice) ?? 200000
        let years = Calendar.current.dateComponents([.year], from: purchaseDate, to: Date()).year ?? 0
        let mileage = Double(currentMileage) ?? 30000
        return VehicleValuation.shared.estimateValue(initialPrice: price, years: max(years, 1), mileageKm: mileage)
    }

    var body: some View {
        Group {
            VStack(alignment: .leading, spacing: TokensSpacing.lg) {
                DSSectionHeader(title: "车辆估值")

                // 先把「这是什么」说在前面：它是**按一条固定规则算出来的估算**，
                // 不是二手车市场价。把规则印在结果的上面，而不是藏在页脚。
                DSNotice(kind: .info,
                         text: "按下方折旧规则算的**估算**，不是市场价。")

                DSGroup(title: "车的条件") {
                    DSGroupRow {
                        HStack {
                            Text("购车价").font(TokensTypo.subheadline)
                            Spacer()
                            TextField("200000", text: $initialPrice)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .font(TokensTypo.data)
                        }
                    }
                    DSGroupRow {
                        DatePicker("购车日期", selection: $purchaseDate, displayedComponents: .date)
                            .font(TokensTypo.subheadline)
                    }
                    DSGroupRow(showsSeparator: false) {
                        HStack {
                            Text("当前里程（km）").font(TokensTypo.subheadline)
                            Spacer()
                            TextField("30000", text: $currentMileage)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .font(TokensTypo.data)
                        }
                    }
                }

                DSGroup(title: "估算") {
                    DSGroupRow {
                        DSBigNumber(value: String(format: "%.0f", estimatedValue), unit: "元",
                                    caption: "按规则算出的估算值", size: 52,
                                    tint: TokensPalette.primary)
                    }
                    DSGroupRow(showsSeparator: false) {
                        DSKeyValueRow(key: "相对购车价的折旧",
                                      value: String(format: "%.1f%%", depreciationPercent))
                    }
                }

                DSGroup(title: "用的是什么规则",
                        footer: "系数写在 `VehicleValuation.estimateValue` 里，"
                              + "可直接改。") {
                    DSGroupRow { DSKeyValueRow(key: "年限折旧", value: "前 3 年每年 −15%，之后每年 −10%") }
                    DSGroupRow(showsSeparator: false) {
                        DSKeyValueRow(key: "里程折旧", value: "每 1 万公里 −2%，上限 −30%")
                    }
                }
            }
        }
    }

    private var depreciationPercent: Double {
        let price = max(1, Double(initialPrice) ?? 200000)
        return (1 - estimatedValue / price) * 100
    }
}

// MARK: - UI: 充电账单 Sheet
/// 充电账单。
///
/// 同样从「车与账号」的弹层并进**保养与钱**（`ChargeBillSection`）。
struct ChargeBillSection: View {
    private let store = AppStore.shared
    @State private var savedFile: URL? = nil

    /// **真实充电记录**：来自 `ChargeLedger`（车端 1 分钟一个的功率采样积分出 kWh），
    /// 费用 = 度数 × 用户自设电价。
    /// 旧版这里写的是 `return []` —— 于是账单页永远显示「暂无充电记录」，
    /// 而下面那句「完成首次充电后将自动生成月度账单」永远等不到。
    private var records: [ChargeRecord] {
        ChargeLedger.shared.sessions.map { s in
            ChargeRecord(date: s.start,
                         kWh: s.kWh,
                         cost: ChargeLedger.shared.cost(s),
                         socStart: s.socStart,
                         socEnd: s.socEnd)
        }
    }

    private var totalKWh: Double { records.map(\.kWh).reduce(0, +) }
    private var totalCost: Double { records.map(\.cost).reduce(0, +) }

    var body: some View {
        Group {
            VStack(alignment: .leading, spacing: TokensSpacing.lg) {
                DSSectionHeader(title: "充电账单")

                if records.isEmpty {
                    DSPlaceholder(icon: "bolt.slash",
                                  title: "还没有充电记录",
                                  message: "App 只在充电中采样，"
                                         + "一次会话满 0.5 kWh 才会出现在这里。")
                } else {
                    DSGroup(title: "合计") {
                        DSGroupRow {
                            DSKeyValueRow(key: "充电次数", value: "\(records.count) 次")
                        }
                        DSGroupRow {
                            DSKeyValueRow(key: "总度数", value: "\(ChargeLedger.kwhText(totalKWh)) kWh")
                        }
                        DSGroupRow(showsSeparator: false) {
                            DSKeyValueRow(key: "总费用",
                                          value: "¥\(ChargeLedger.moneyText(totalCost))（按你设的 \(ChargeLedger.rateText(ChargeLedger.shared.rate)) 元/度）")
                        }
                    }

                    DSGroup(title: "每一次充电",
                            footer: "度数 = ∫功率 dt（梯形法，每分钟一个采样）；"
                                  + "费用按你设的电价算，不是充电站实际价。") {
                        ForEach(Array(records.enumerated()), id: \.offset) { idx, r in
                            DSGroupRow(showsSeparator: idx < records.count - 1) {
                                DSKeyValueRow(key: r.date.formatted(date: .abbreviated, time: .shortened),
                                              value: "\(ChargeLedger.kwhText(r.kWh)) kWh · ¥\(ChargeLedger.moneyText(r.cost))")
                            }
                        }
                    }

                    Button {
                        savedFile = ChargeBillGenerator.shared.generatePDF(
                            records: records,
                            vehiclePlate: store.car?["plate"] as? String ?? "车辆")
                    } label: {
                        Label("导出 PDF 账单", systemImage: "doc.fill")
                    }
                    .buttonStyle(DSPrimaryButtonStyle())

                    if let f = savedFile {
                        // 说清文件到底去哪了（旧版写的是「已保存到文件 App」，而我们写的是沙盒）
                        DSNotice(kind: .success,
                                 text: "已生成 \(f.lastPathComponent)（在 App 的文稿目录里；从「文件」App → 我的 iPhone → 长安车管家 可以看到）。")
                    }
                }
            }
        }
    }
}
