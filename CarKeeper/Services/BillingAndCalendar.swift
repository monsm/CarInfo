// =============================================================================
// N33 车辆估值 + N34 年检日历
// =============================================================================
//
// ⚠️ 这里曾有 N32「充电历史账单 PDF」：`ChargeRecord` + `ChargeBillGenerator`
//    + 页面上的 `ChargeBillSection`。整块随**充电账本**一起删除（2026-09-23）。
//
//    为什么删：账本算的是「这几次充电花了多少钱」——它的两个输入一个是 App 自己
//    采的功率、另一个是用户手填的电价，服务端**没有**任何账单接口。用户的要求是
//    「全局删掉缓存机制，任何数据都是 api 数据」，账本正是「本机算出来的数」，
//    于是整条链路（本机积分 → 折钱 → 出 PDF）一并去掉。
//
//    连带不见的：充电页的「充电账单」段与导出按钮、地图「充电」层的那块账、
//    搜索里的「充电记录」、月报里的充电次数/度数两行，以及「电价」这个设置项
//    （它唯一的用途就是折算账本上的钱）。`import PDFKit` 也随之删除 ——
//    全库不再有任何 PDF 渲染。

import Foundation
import SwiftUI
import UIKit

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

    /// 退出登录时清空。**两半都要清**：
    ///
    /// 2026-09-25 第八轮（地毯式对抗式审核）：年检记录是手填的账号数据，
    /// 而 `AppStore.logout()` 上一版只删了 `carkeeper_inspections` 这个**键** ——
    /// 内存里那份 `@Published var inspections` 还活着，于是同一次运行里换账号后，
    /// 年检日历上仍然是前一个账号的记录（下次启动才“自动消失”，而那是重启的功劳）。
    /// 这正是本文件自己记载过的那个坑的另一面：`addInspection` 曾经只写盘、
    /// 不写回 `@Published`，于是“保存年检”在当次运行里看上去毫无反应。
    /// —— 一处数据两个住处（磁盘 + 内存）时，**任一侧漏了都会说谎**。
    func resetAll() {
        inspections = []
        UserDefaults.standard.removeObject(forKey: "carkeeper_inspections")
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
                        footer: "\u{201C}即将到期\u{201D}按 60 天算。") {
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
                        footer: "只存你填的内容；保费合计 = 保单之和。") {
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
                         text: "按下方折旧规则算的估算值，不是市场价。")

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

                // 「系数写在 VehicleValuation.estimateValue 里，可直接改」这句页脚已删：
                // 它是给改代码的人看的一句话，对车主没有意义 —— 而下面两行已经
                // 把规则本身说清楚了。
                DSGroup(title: "用的是什么规则") {
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

// MARK: - UI: 充电账单
//
// ChargeBillSection 曾住在这里（充电页的「充电账单」段 + 导出 PDF 按钮）。
// 整块随充电账本删除（2026-09-23）—— 理由见文件开头 N32 那段说明。
// 删掉它之后，本文件只剩两件与**用户自己填的记录**有关的事：车辆估值与年检日历。
