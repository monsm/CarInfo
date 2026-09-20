// =============================================================================
// N30 车辆共享临时钥匙 + N31 家庭多车管理
// =============================================================================

import Foundation
import SwiftUI
import UIKit

// MARK: - N30 临时共享钥匙
struct TemporaryKey: Identifiable, Codable {
    var id = UUID()
    let recipientName: String
    let code: String           // 6位数字 PIN
    let createdAt: Date
    let expiresAt: Date
    let maxUses: Int
    var usedCount: Int
    var isActive: Bool

    var remainingUses: Int { max(0, maxUses - usedCount) }
    var isExpired: Bool { Date() > expiresAt }
}

class TempKeyManager: ObservableObject {
    static let shared = TempKeyManager()

    @Published var keys: [TemporaryKey] = []

    private init() {
        loadKeys()
    }

    /// 生成临时钥匙
    func createKey(recipient: String, days: Int = 7, maxUses: Int = 10) -> TemporaryKey {
        let code = String(format: "%06d", Int.random(in: 100000...999999))
        let expiresAt = Calendar.current.date(byAdding: .day, value: days, to: Date())!
        let key = TemporaryKey(
            recipientName: recipient,
            code: code,
            createdAt: Date(),
            expiresAt: expiresAt,
            maxUses: maxUses,
            usedCount: 0,
            isActive: true
        )
        keys.insert(key, at: 0)
        saveKeys()
        return key
    }

    /// 使用钥匙（减少剩余次数）
    func useKey(_ id: UUID) {
        if let idx = keys.firstIndex(where: { $0.id == id }) {
            var key = keys[idx]
            key.usedCount += 1
            if key.usedCount >= key.maxUses || key.isExpired {
                key.isActive = false
            }
            keys[idx] = key
            saveKeys()
        }
    }

    /// 撤销钥匙
    func revokeKey(_ id: UUID) {
        keys.removeAll { $0.id == id }
        saveKeys()
    }

    /// 退出登录时清空（内存 + 磁盘）：临时钥匙是跟账号绑定的数据
    func resetAll() {
        keys = []
        UserDefaults.standard.removeObject(forKey: "carkeeper_temp_keys")
    }

    private func saveKeys() {
        if let data = try? JSONEncoder().encode(keys) {
            UserDefaults.standard.set(data, forKey: "carkeeper_temp_keys")
        }
    }

    private func loadKeys() {
        guard let data = UserDefaults.standard.data(forKey: "carkeeper_temp_keys"),
              let decoded = try? JSONDecoder().decode([TemporaryKey].self, from: data) else { return }
        keys = decoded.filter { !$0.isExpired }
    }
}

// MARK: - N31 家庭多车管理
struct FamilyMember: Identifiable, Codable {
    var id = UUID()
    let name: String
    let phone: String
    let avatar: String
    var roles: [String] = ["驾驶员"]  // 驾驶员 / 管理员 / 只读
    var sharedCars: [String] = []     // 共享的车辆 ID
    var lastSeen: Date?
}

class FamilyManager: ObservableObject {
    static let shared = FamilyManager()

    @Published var members: [FamilyMember] = []
    @Published var ownerName: String = "我"

    private init() {
        loadMembers()
    }

    func addMember(name: String, phone: String, roles: [String] = ["驾驶员"]) {
        let member = FamilyMember(name: name, phone: phone, avatar: String(name.first ?? "M"), roles: roles)
        members.append(member)
        saveMembers()
    }

    func removeMember(_ id: UUID) {
        members.removeAll { $0.id == id }
        saveMembers()
    }

    func shareCar(_ carId: String, with member: FamilyMember) {
        var m = member
        if !m.sharedCars.contains(carId) {
            m.sharedCars.append(carId)
        }
        if let idx = members.firstIndex(where: { $0.id == member.id }) {
            members[idx] = m
            saveMembers()
        }
    }

    /// 退出登录时清空（内存 + 磁盘）：家庭成员列表是跟账号绑定的数据
    func resetAll() {
        members = []
        ownerName = "我"
        UserDefaults.standard.removeObject(forKey: "carkeeper_family_members")
    }

    private func saveMembers() {
        if let data = try? JSONEncoder().encode(members) {
            UserDefaults.standard.set(data, forKey: "carkeeper_family_members")
        }
    }

    private func loadMembers() {
        guard let data = UserDefaults.standard.data(forKey: "carkeeper_family_members"),
              let decoded = try? JSONDecoder().decode([FamilyMember].self, from: data) else { return }
        members = decoded
    }
}

// MARK: - UI: 临时钥匙卡片
struct TempKeyCard: View {
    let key: TemporaryKey
    let onUse: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(key.recipientName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("有效期: \(key.expiresAt, format: .dateTime.month().day().year())")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                if key.remainingUses > 0 {
                    Text("剩余 \(key.remainingUses) 次")
                        .font(.caption2)
                        .foregroundColor(.green)
                }
            }
            Spacer()

            if key.isActive && !key.isExpired && key.remainingUses > 0 {
                Button(action: onUse) {
                    Text("使用")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Kansei.Color.ambient)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
            } else {
                Text(key.isExpired ? "已过期" : key.remainingUses <= 0 ? "已用完" : "已撤销")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .glassCard()
    }
}

// MARK: - UI: 家庭成员列表
struct FamilyMemberRow: View {
    let member: FamilyMember
    var body: some View {
        HStack {
            Circle()
                .fill(Kansei.Color.ambient.opacity(0.2))
                .frame(width: 40, height: 40)
                .overlay(Text(member.avatar).font(.title3).fontWeight(.bold)                .foregroundColor(Kansei.Color.ambient))

            VStack(alignment: .leading) {
                Text(member.name)
                    .font(.subheadline).fontWeight(.semibold)
                Text(member.roles.joined(separator: " · "))
                    .font(.caption2).foregroundColor(.secondary)
            }
            Spacer()
            Text(member.sharedCars.count > 0 ? "\(member.sharedCars.count) 辆车" : "")
                .font(.caption).foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - UI: 临时钥匙列表页
struct TempKeyListView: View {
    @StateObject private var manager = TempKeyManager.shared
    @State private var showCreate = false
    @State private var recipientName = ""
    @State private var days = 7
    @State private var maxUses = 10

    var body: some View {
        List {
            Section("当前有效钥匙") {
                if manager.keys.isEmpty {
                    Text("暂无共享钥匙")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(manager.keys) { key in
                        TempKeyCard(key: key) {
                            manager.useKey(key.id)
                        }
                    }
                }
            }

            Section("创建新钥匙") {
                VStack(spacing: 12) {
                    TextField(" recipient 姓名", text: $recipientName)
                    HStack {
                        Text("有效期:")
                        Slider(value: Binding(
                            get: { Double(days) },
                            set: { days = Int($0) }
                        ), in: 1...30)
                        Text("\(days)天")
                    }
                    Button("生成钥匙") {
                        let key = manager.createKey(
                            recipient: recipientName,
                            days: days,
                            maxUses: maxUses
                        )
                        // 复制 PIN 到剪贴板
                        UIPasteboard.general.string = key.code
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.vertical, 8)
            }
        }
    }
}

// MARK: - UI: 家庭管理页
struct FamilyManagementView: View {
    @StateObject private var manager = FamilyManager.shared
    @State private var showAdd = false
    @State private var newName = ""
    @State private var newPhone = ""

    var body: some View {
        List {
            Section("家庭成员") {
                ForEach(manager.members) { member in
                    FamilyMemberRow(member: member)
                }
                if manager.members.isEmpty {
                    Text("暂无成员")
                        .foregroundColor(.secondary)
                }
            }

            Section("添加成员") {
                VStack(spacing: 12) {
                    TextField("姓名", text: $newName)
                    TextField("手机号", text: $newPhone)
                        .keyboardType(.phonePad)
                    Button("添加成员") {
                        guard !newName.isEmpty else { return }
                        manager.addMember(name: newName, phone: newPhone)
                        newName = ""
                        newPhone = ""
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(newName.isEmpty)
                }
                .padding(.vertical, 8)
            }
        }
    }
}
