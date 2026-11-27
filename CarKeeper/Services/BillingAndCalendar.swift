
import Foundation
import SwiftUI
import UIKit

class VehicleValuation {
    static let shared = VehicleValuation()

    func estimateValue(initialPrice: Double, years: Int, mileageKm: Double) -> Double {
        var depreciation = 1.0
        for year in 1...max(years, 1) {
            if year <= 3 {
                depreciation *= 0.85
            } else {
                depreciation *= 0.90
            }
        }
        let mileageDep = min(Double(mileageKm / 10000) * 0.02, 0.30)
        return initialPrice * depreciation * (1 - mileageDep)
    }

}

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
        inspections = list
        save(list)
    }

    func resetAll() {
        inspections = []
        UserDefaults.standard.removeObject(forKey: "carkeeper_inspections")
    }

    func daysUntilInspection(for inspection: Inspection) -> Int {
        Calendar.current.dateComponents([.day], from: Date(), to: inspection.date).day ?? 0
    }

    private func save(_ list: [Inspection]) {
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: "carkeeper_inspections")
        }
    }
}



struct InspectionSection: View {
    @StateObject private var calendar = InspectionCalendar.shared
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

    private func syncReminders() async {
        guard let next = policies.map(\.endDate).filter({ $0 > Date() }).min() else { return }
        _ = await InsuranceReminderScheduler.shared.requestNotificationPermission()
        await InsuranceReminderScheduler.shared.scheduleInsuranceReminder(insuranceEndDate: next)
    }
}

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

