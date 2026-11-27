
import Foundation
import SwiftUI

struct InsurancePolicy: Identifiable, Codable {
    var id = UUID()
    let name: String
    let type: String
    let policyNumber: String
    let startDate: Date
    let endDate: Date
    let premium: Double
    let claimHistory: [String]
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
        Task { await syncReminders() }
    }

    func syncReminders() async {
        let next = policies.map(\.endDate).filter { $0 > Date() }.min()
        await InsuranceReminderScheduler.shared.scheduleInsuranceReminder(insuranceEndDate: next)
    }
}

