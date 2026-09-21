// =============================================================================
// N32 充电历史账单 PDF + N33 车辆估值 + N34 年检日历
// =============================================================================

import Foundation
import PDFKit
import SwiftUI
import UIKit

// MARK: - N32 充电历史账单 PDF
struct ChargeRecord: Codable {
    let date: Date
    let kWh: Double
    let cost: Double
    let socStart: Int
    let socEnd: Int
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
                let row = [dateStr, "\(record.socStart)%", "\(record.socEnd)%",
                           String(format: "%.1f", record.kWh), String(format: "%.2f", record.cost)]
                row.enumerated().forEach { i, text in
                    text.draw(at: CGPoint(x: colX[i], y: rowY), withAttributes: rowAttrs)
                }
            }

            // 底部说明
            let note = "本账单由 CarKeeper 自动生成，仅供参考。"
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

    /// 车辆信息卡片
    func valuationCard(initialPrice: Double, years: Int, mileageKm: Double) -> (currentValue: Double, depreciationRate: Double) {
        let value = estimateValue(initialPrice: initialPrice, years: years, mileageKm: mileageKm)
        let depRate = (1 - value / initialPrice) * 100
        return (value, depRate)
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
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: "carkeeper_inspections")
        }
    }

    /// 获取即将到期的年检（60天内）
    var upcomingInspections: [Inspection] {
        let now = Date()
        let sixtyDays = Calendar.current.date(byAdding: .day, value: 60, to: now)!
        return inspections
            .filter { $0.date >= now && $0.date <= sixtyDays }
            .sorted { $0.date < $1.date }
    }

    /// 已过期
    var expiredInspections: [Inspection] {
        inspections.filter { $0.date < Date() }
    }

    /// 距离下次年检天数
    func daysUntilInspection(for inspection: Inspection) -> Int {
        Calendar.current.dateComponents([.day], from: Date(), to: inspection.date).day ?? 0
    }

    private func saveInspections(_ list: [Inspection]) {
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: "carkeeper_inspections")
        }
    }
    func updateInspection(_ inspection: Inspection) {
        var list = inspections
        if let idx = list.firstIndex(where: { $0.id == inspection.id }) {
            list[idx] = inspection
        }
        inspections = list
        saveInspections(list)
    }
}

// MARK: - UI 组件
struct InspectionRow: View {
    let inspection: Inspection
    let currentMileage: Double

    var body: some View {
        let days = InspectionCalendar.shared.daysUntilInspection(for: inspection)
        let isExpired = days < 0
        let isUrgent = days > 0 && days <= 30

        HStack {
            Image(systemName: isExpired ? "exclamationmark.triangle.fill" : "calendar.fill")
                .foregroundColor(isExpired ? .red : isUrgent ? .orange : .blue)
                .font(.title2)
                .frame(width: 36, height: 36)
                .background(isExpired ? TokensPalette.error.opacity(0.1) : isUrgent ? TokensPalette.warning.opacity(0.1) : TokensPalette.info.opacity(0.1))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(inspection.vehicleName)
                    .font(.subheadline).fontWeight(.medium)
                Text(inspection.date.formatted(date: .numeric, time: .omitted))
                    .font(.caption).foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing) {
                Text(isExpired ? "已过期" : "\(days)天后到期")
                    .font(.caption).fontWeight(.semibold)
                    .foregroundColor(isExpired ? .red : isUrgent ? .orange : .green)
            }
        }
        .padding(.vertical, 8)
        .glassCard()
    }
}

struct InspectionCard: View {
    let inspection: Inspection
    @State private var showEdit = false

    var body: some View {
        InspectionRow(inspection: inspection, currentMileage: 0)
            .onTapGesture { showEdit = true }
            .sheet(isPresented: $showEdit) {
                NavigationStack {
                    InspectionEditForm(inspection: inspection)
                        .navigationTitle("编辑年检")
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
    }
}

struct InspectionEditForm: View {
    let inspection: Inspection
    @State private var name: String
    @State private var date: Date
    @Environment(\.dismiss) private var dismiss

    init(inspection: Inspection) {
        self.inspection = inspection
        _name = State(initialValue: inspection.vehicleName)
        _date = State(initialValue: inspection.date)
    }

    var body: some View {
        Form {
            Section("车辆信息") {
                TextField("车辆名称", text: $name)
                DatePicker("年检日期", selection: $date, displayedComponents: .date)
            }
        }
        .navigationTitle("编辑年检")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    var updated = inspection
                    updated = Inspection(id: inspection.id, vehicleName: name, date: date, notes: inspection.notes)
                    InspectionCalendar.shared.updateInspection(updated)
                    dismiss()
                }
            }
        }
    }
}

// MARK: - UI: 年检日历视图
struct InspectionCalendarView: View {
    @State private var calendar = InspectionCalendar.shared
    @State private var showAdd = false
    @State private var vehicleName = ""
    @State private var inspectionDate = Date()

    var body: some View {
        List {
            Section("即将到期（60天内）") {
                if calendar.upcomingInspections.isEmpty {
                    Text("暂无即将到期的年检")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(calendar.upcomingInspections) { inspection in
                        InspectionRow(inspection: inspection, currentMileage: 0)
                    }
                }
            }

            Section("历史记录") {
                ForEach(calendar.inspections.filter { $0.date < Date() }) { inspection in
                    InspectionRow(inspection: inspection, currentMileage: 0)
                        .opacity(0.5)
                }
                if calendar.inspections.filter({ $0.date < Date() }).isEmpty {
                    Text("暂无历史记录")
                        .foregroundColor(.secondary)
                }
            }

            Section("添加年检") {
                VStack(spacing: 12) {
                    TextField("车辆名称", text: $vehicleName)
                    DatePicker("年检日期", selection: $inspectionDate, displayedComponents: .date)
                    Button("保存") {
                        guard !vehicleName.isEmpty else { return }
                        calendar.addInspection(Inspection(
                            vehicleName: vehicleName,
                            date: inspectionDate,
                            notes: ""
                        ))
                        vehicleName = ""
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(vehicleName.isEmpty)
                }
                .padding(.vertical, 8)
            }
        }
    }
}

// MARK: - UI: 车辆估值视图
struct VehicleValuationView: View {
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
        Form {
            Section("车辆信息") {
                TextField("购车价格（元）", text: $initialPrice)
                    .keyboardType(.decimalPad)
                DatePicker("购车日期", selection: $purchaseDate, displayedComponents: .date)
                TextField("当前里程（km）", text: $currentMileage)
                    .keyboardType(.decimalPad)
            }

            Section("估值结果") {
                HStack {
                    VStack(alignment: .leading) {
                        Text("当前估值")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("¥\(String(format: "%.0f", estimatedValue))")
                            .font(.title).fontWeight(.bold)
                            .foregroundColor(.green)
                    }
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text("折旧率")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        let price = Double(initialPrice) ?? 200000
                        let rate = (1 - estimatedValue / price) * 100
                        Text(String(format: "%.1f%%", rate))
                            .font(.title3)
                            .foregroundColor(rate > 60 ? .red : rate > 30 ? .orange : .green)
                    }
                }
                .padding(.vertical, 8)
            }

            Section("折旧说明") {
                Text("前3年每年折旧15%，之后每年10%。里程折旧每万公里2%，上限30%。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("车辆估值")
    }
}

// MARK: - UI: 充电账单 Sheet
struct ChargeBillSheet: View {
    private let store = AppStore.shared
    @State private var showingPDF = false

    var chargeRecords: [ChargeRecord] {
        // 从 energyHistory 估算充电记录（实际应从后端获取）
        return []
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: TokensSpacing.lg) {
                if chargeRecords.isEmpty {
                    EmptyStateView(
                        icon: "bolt.slash",
                        title: "暂无充电记录",
                        message: "完成首次充电后将自动生成月度账单",
                        actionTitle: "去充电",
                        action: {}
                    )
                } else {
                    ForEach(chargeRecords, id: \.date) { record in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(record.date, format: .dateTime.day().month())
                                    .font(.subheadline)
                                Text("¥\(String(format: "%.2f", record.cost))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Text("\(record.kWh) kWh")
                                .font(.subheadline)
                                .foregroundColor(TokensPalette.ambient)
                        }
                    }
                }

                Button {
                    // 生成 PDF
                    if ChargeBillGenerator.shared.generatePDF(
                        records: chargeRecords,
                        vehiclePlate: store.car?["plate"] as? String ?? "车辆"
                    ) != nil {
                        showingPDF = true
                    }
                } label: {
                    Label("导出 PDF 账单", systemImage: "doc.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(TokensPalette.ambient)
                        .foregroundColor(TokensPalette.labelOnTint)
                        .cornerRadius(TokensRadius.medium)
                }
                .padding(.horizontal)

                if showingPDF {
                    Text("PDF 已保存到文件 App")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
            .sheet(isPresented: $showingPDF) {
                // 展示 PDF
            }
        }
    }
}
