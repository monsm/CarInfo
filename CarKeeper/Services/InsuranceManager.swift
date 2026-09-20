// =============================================================================
// #NEW-119 保险到期提醒 — 交强险/商业险到期管理
// =============================================================================

import Foundation
import SwiftUI

struct InsurancePolicy: Identifiable, Codable {
    var id = UUID()
    let name: String           // 保险公司
    let type: String           // 交强险/商业险/座位险
    let policyNumber: String   // 保单号
    let startDate: Date
    let endDate: Date
    let premium: Double        // 保费
    let claimHistory: [String] // 理赔记录
}

class InsuranceManager {
    static let shared = InsuranceManager()

    var policies: [InsurancePolicy] {
        if let data = UserDefaults.standard.data(forKey: "carkeeper_insurance_policies"),
           let decoded = try? JSONDecoder().decode([InsurancePolicy].self, from: data) {
            return decoded
        }
        return []
    }

    func savePolicies(_ policies: [InsurancePolicy]) {
        if let data = try? JSONEncoder().encode(policies) {
            UserDefaults.standard.set(data, forKey: "carkeeper_insurance_policies")
        }
    }

    func addPolicy(_ policy: InsurancePolicy) {
        var list = policies
        list.append(policy)
        savePolicies(list)
    }

    /// 获取即将到期的保险（60天内）
    var expiringPolicies: [InsurancePolicy] {
        let now = Date()
        let sixtyDays = Calendar.current.date(byAdding: .day, value: 60, to: now)!
        return policies.filter { $0.endDate >= now && $0.endDate <= sixtyDays }
            .sorted { $0.endDate < $1.endDate }
    }

    /// 获取已过期保险
    var expiredPolicies: [InsurancePolicy] {
        policies.filter { $0.endDate < Date() }
    }

    /// 计算总保费
    var totalPremium: Double {
        policies.map { $0.premium }.reduce(0, +)
    }
}

struct InsuranceCard: View {
    let policy: InsurancePolicy
    var body: some View {
        let daysLeft = Calendar.current.dateComponents([.day], from: Date(), to: policy.endDate).day ?? 0
        let isExpired = daysLeft < 0
        let isExpiring = daysLeft > 0 && daysLeft <= 30

        VStack(alignment: .leading, spacing: Kansei.Spacing.sm) {
            HStack {
                VStack(alignment: .leading) {
                    Text(policy.name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text(policy.type)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing) {
                    if isExpired {
                        Text("已过期")
                            .font(.caption)
                            .foregroundColor(.red)
                            .bold()
                    } else if isExpiring {
                        Text("即将到期")
                            .font(.caption)
                            .foregroundColor(.orange)
                            .bold()
                    } else {
                        Text("\(daysLeft)天后到期")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                    Text(policy.policyNumber)
                        .font(.caption2)
                        .foregroundColor(Color(.tertiaryLabel))
                }
            }

            HStack {
                Text("保费")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("¥\(policy.premium, specifier: "%.0f")")
                    .font(.callout)
                    .fontWeight(.semibold)
            }

            HStack {
                Text("有效期")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(policy.startDate.formatted(date: .numeric, time: .omitted))
                    .font(.caption)
                    + Text(" ~ ")
                    .font(.caption)
                    + Text(policy.endDate.formatted(date: .numeric, time: .omitted))
                    .font(.caption)
                    .foregroundColor(isExpired ? .red : .primary)
            }
        }
        .glassCard()
        .overlay(
            RoundedRectangle(cornerRadius: Kansei.Radius.medium)
                .stroke(isExpired ? Color.red : isExpiring ? Color.orange : Color.clear, lineWidth: 2)
        )
    }
}
