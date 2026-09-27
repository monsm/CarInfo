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

    //  `expiringPolicies`（60 天内到期）/ `expiredPolicies` / `totalPremium` 已删
    //  （2026-09-26 第三十一轮审核）：三个都**零个读者**。
    //  到期提醒走的是另一条链 —— `InsuranceReminderScheduler` 自己算窗口并发本地通知，
    //  保单那一屏只列「保单」与「到期日」，没有「即将到期」分组，也没有保费合计。
    //  留着它们的代价是下一个人会以为界面上已经有这两栏（而屏幕上一个也没有）。
}

