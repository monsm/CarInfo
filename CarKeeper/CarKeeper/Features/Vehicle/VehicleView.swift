import SwiftUI

// 车辆档案 —— iOS 27 Liquid Glass：
// 车辆名片（渐变标牌 + VIN 复制条 + 三项时效徽章）+ 分组档案卡。

struct VehicleView: View {
    private let store = AppStore.shared

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.cardSpacing) {
                if let sum = VM.vehicleSummary(store.car) { plateCard(sum) }
                ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                    CardBox(title: group.name) {
                        VStack(spacing: 0) {
                            ForEach(Array(group.rows.enumerated()), id: \.offset) { idx, row in
                                KVRow(k: row.k, v: row.v)
                                    .padding(.vertical, 8)
                                if idx < group.rows.count - 1 { ListDivider() }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .scrollBounceBehavior(.basedOnSize)
        .pageBackground(.accentColor)
        .navigationTitle("车辆档案")
    }

    // MARK: 名片
    private func plateCard(_ sum: VehicleSummary) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.7)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 88, height: 56)
                        .shadow(color: Color.accentColor.opacity(0.35), radius: 10, y: 4)
                    VStack(spacing: 2) {
                        Text("新能源").font(.system(size: 8, weight: .semibold)).foregroundStyle(.white.opacity(0.9))
                        Text(sum.plate).font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(sum.name.isEmpty ? "未绑定车辆" : sum.name)
                        .font(.system(size: 22, weight: .bold))
                    Text(sum.model).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
            }
            vinBar(sum)
            HStack(spacing: 10) {
                badgeRow("控车码", sum.pinText, cls: sum.pinCls)
                if let d = sum.insuranceDays {
                    badgeRow("保险", d < 0 ? "已到期" : "剩 \(d) 天", cls: d < 0 ? "bad" : "ok")
                }
                if let d = sum.serviceDays {
                    badgeRow("服务", d < 0 ? "已到期" : "剩 \(d) 天", cls: d < 0 ? "bad" : "ok")
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func vinBar(_ sum: VehicleSummary) -> some View {
        Button {
            if !sum.vin.isEmpty {
                UIPasteboard.general.string = sum.vin
                NotificationCenter.default.post(name: .vinCopied, object: nil)
            }
        } label: {
            HStack {
                Text("VIN \(sum.vin.isEmpty ? "--" : sum.vin)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "doc.on.doc.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.accentColor)
            }
            .padding(10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func badgeRow(_ k: String, _ v: String, cls: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(k).font(.system(size: 10)).foregroundStyle(.secondary)
            Text(v).font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.statusColor(cls) == Color.secondary ? Color.primary : Theme.statusColor(cls))
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: 档案分组（数据不变）
    private struct Row { let k: String; let v: String }
    private struct Grp { let name: String; let rows: [Row] }

    private var groups: [Grp] {
        guard let c = store.car else { return [] }
        func s2(_ k: String) -> String? {
            let v = ciString(c, [k])
            return (v?.isEmpty ?? true) ? nil : v
        }
        func row(_ k: String, _ label: String, suffix: String = "") -> Row? {
            guard let v = s2(k) else { return nil }
            return Row(k: label, v: v + suffix)
        }
        var out: [Grp] = []
        let idRows = [row("CarId", "车辆 ID"), row("CarName", "车辆名称"), row("PlateNumber", "车牌号"),
                      row("IsNev", "能源类型", suffix: "")]
            .compactMap { $0 }
        if !idRows.isEmpty { out.append(Grp(name: "身份信息", rows: idRows)) }

        let basic = [row("ModelCode", "车型代码"), row("ConfName", "配置名称"), row("BrandCode", "品牌代码"),
                     row("SeriesCode", "车系代码"), row("CarType", "车辆类型"), row("Color", "车身颜色"),
                     row("EngineNo", "发动机编号"), row("TenantId", "租户标识")].compactMap { $0 }
        if !basic.isEmpty { out.append(Grp(name: "车型配置", rows: basic)) }

        let ins = [row("InsuranceEndDate", "保险到期"), row("InsuranceCompany", "保险公司"),
                   row("InsurancePhone", "保险电话"), row("RegisterTime", "注册时间"),
                   row("ProductTime", "生产时间")].compactMap { $0 }
        if !ins.isEmpty { out.append(Grp(name: "注册与保险", rows: ins)) }

        let svc = [row("MaintainSpaceMileage", "保养间隔", suffix: " km"),
                   row("LastMaintainMileage", "上次保养里程", suffix: " km"),
                   row("LastOnlineTime", "最后在线"), row("ActiveTime", "激活时间")].compactMap { $0 }
        if !svc.isEmpty { out.append(Grp(name: "服务与保养", rows: svc)) }
        return out
    }
}
