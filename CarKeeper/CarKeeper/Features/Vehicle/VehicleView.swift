import SwiftUI

// 车辆档案：名片 + 分组档案行
struct VehicleView: View {
    private let store = AppStore.shared

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.cardSpacing) {
                // 名片
                if let sum = VM.vehicleSummary(store.car) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(sum.name.isEmpty ? "未绑定车辆" : sum.name)
                                .font(.system(size: 22, weight: .semibold))
                            if sum.isNev {
                                Text("新能源").font(.system(size: 11, weight: .medium))
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        Text(sum.plate).font(.system(size: 15)).foregroundStyle(.secondary)

                        // VIN 复制条
                        HStack {
                            Text(sum.vin.isEmpty ? "--" : sum.vin)
                                .font(.system(size: 13, design: .monospaced))
                            Spacer()
                            Button {
                                if !sum.vin.isEmpty {
                                    UIPasteboard.general.string = sum.vin
                                    NotificationCenter.default.post(name: .vinCopied, object: nil)
                                }
                            } label: {
                                Image(systemName: "doc.on.doc").font(.system(size: 14)).foregroundStyle(.secondary)
                            }
                        }
                        .padding(10)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("控车码").font(.system(size: 11)).foregroundStyle(.secondary)
                                Text(sum.pinText).font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(sum.pinCls == "ok" ? .primary : .orange)
                            }
                            if let insDays = sum.insuranceDays {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("保险").font(.system(size: 11)).foregroundStyle(.secondary)
                                    Text(insDays < 0 ? "已到期" : "剩 \(insDays) 天")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(insDays < 0 ? Color.red : .primary)
                                }
                            }
                            if let srvDays = sum.serviceDays {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("服务").font(.system(size: 11)).foregroundStyle(.secondary)
                                    Text(srvDays < 0 ? "已到期" : "剩 \(srvDays) 天")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(srvDays < 0 ? Color.red : .primary)
                                }
                            }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }

                // 分组档案
                for group in groups {
                    CardBox(title: group.name) {
                        VStack(spacing: 0) {
                            ForEach(group.rows, id: \.k) { row in
                                HStack {
                                    Text(row.k).font(.system(size: 13)).foregroundStyle(.secondary)
                                    Spacer()
                                    Text(row.v).font(.system(size: 13)).foregroundStyle(.primary)
                                }
                                .padding(.vertical, 8)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("车辆档案")
    }

    private struct Row { let k: String; let v: String }
    private struct Grp { let name: String; let rows: [Row] }

    private var groups: [Grp] {
        guard let c = store.car else { return [] }
        func s(_ k: String) -> String? {
            let v = ciString(c, [k])
            return (v?.isEmpty ?? true) ? nil : v
        }
        func numRow(_ k: String, suffix: String = "") -> Row? {
            guard let v = s(k) else { return nil }
            return Row(k: k, v: v + suffix)
        }
        var out: [Grp] = []
        let idRows = [numRow("CarId"), numRow("CarName"), numRow("PlateNumber"), numRow("IsNev", suffix: " = 1 ? 新能源 : 燃油车")]
            .compactMap { $0 }
        if !idRows.isEmpty { out.append(Grp(name: "身份信息", rows: idRows)) }

        let basic = [numRow("ModelCode"), numRow("ConfName"), numRow("BrandCode"), numRow("SeriesCode"),
                     numRow("CarType"), numRow("Color"), numRow("EngineNo"), numRow("TenantId")].compactMap { $0 }
        if !basic.isEmpty { out.append(Grp(name: "车型配置", rows: basic)) }

        let ins = [numRow("InsuranceEndDate"), numRow("InsuranceCompany"), numRow("InsurancePhone"),
                   numRow("RegisterTime"), numRow("ProductTime")].compactMap { $0 }
        if !ins.isEmpty { out.append(Grp(name: "注册与保险", rows: ins)) }

        let svc = [numRow("MaintainSpaceMileage", suffix: " km"), numRow("LastMaintainMileage", suffix: " km"),
                   numRow("LastOnlineTime"), numRow("ActiveTime")].compactMap { $0 }
        if !svc.isEmpty { out.append(Grp(name: "服务与保养", rows: svc)) }
        return out
    }
}
