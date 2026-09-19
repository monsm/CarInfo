// =============================================================================
// N11 隐私仪表盘 — 展示 App 收集的所有数据，支持一键清除
// =============================================================================

import SwiftUI

struct PrivacyDashboardView: View {
    private let store = AppStore.shared
    @State private var showClearConfirm = false
    
    private let dataCategories: [(title: String, items: [(name: String, size: String, type: String)])] = [
        (
            title: "位置数据",
            items: [
                ("停车位置", "≈ 64B", "CoreLocation"),
                ("行驶轨迹", "≈ 2KB/次", "CoreLocation"),
                ("历史位置", "\(store.tripHistory.count) 条记录", "UserDefaults")
            ]
        ),
        (
            title: "车辆数据",
            items: [
                ("SOC 历史", "\(store.energyHistory.count) 条", "UserDefaults"),
                ("行程记录", "\(store.tripHistory.count) 条", "UserDefaults"),
                ("控制命令", "\(store.commandHistory.count) 条", "UserDefaults"),
                ("维保记录", "\(store.serviceTimestamp != 0 ? "有" : "无")", "UserDefaults")
            ]
        ),
        (
            title: "账户数据",
            items: [
                ("登录凭证", "Keychain", "LocalAuthentication"),
                ("生物识别", store.hasBiometricSetup ? "已启用" : "未启用", "Keychain"),
                ("设备 ID", "UUID", "UserDefaults")
            ]
        ),
        (
            title: "设置偏好",
            items: [
                ("夜间模式", UserDefaults.standard.object(forKey: "carkeeper_force_dark_mode") != nil ? "自定义" : "跟随系统", "UserDefaults"),
                ("卡片排序", "\(store.cardOrder.count) 个自定义", "UserDefaults"),
                ("语言", AppLanguage.current.rawValue, "UserDefaults")
            ]
        )
    ]
    
    private var totalRecords: Int {
        store.energyHistory.count + store.tripHistory.count + store.commandHistory.count
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    // 汇总卡片
                    VStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "shield.checkered")
                            .font(.system(size: 48))
                            .foregroundColor(Color.accent)
                        Text("数据透明度")
                            .font(.title2)
                            .fontWeight(.bold)
                        Text("本应用共存储 \(totalRecords) 条记录")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.md)
                    .glassCard()
                    
                    // 分类详情
                    ForEach(dataCategories, id: \.title) { category in
                        PrivacyCategorySection(category: category)
                    }
                    
                    // 一键清除按钮
                    VStack(spacing: Theme.Spacing.sm) {
                        Button(role: .destructive) {
                            showClearConfirm = true
                        } label: {
                            Label("清除全部本地数据", systemImage: "trash.fill")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.red.opacity(0.15))
                                .foregroundColor(.red)
                                .cornerRadius(Theme.Radius.medium)
                        }
                        
                        Button {
                            // 仅清除行程和能耗数据
                            store.tripHistory = []
                            store.energyHistory = []
                            store.commandHistory = []
                        } label: {
                            Label("清除行程记录", systemImage: "arrow.triangle.clockwise")
                                .font(.subheadline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.orange.opacity(0.1))
                                .foregroundColor(.orange)
                                .cornerRadius(Theme.Radius.medium)
                        }
                    }
                    .padding(.top, Theme.Spacing.sm)
                }
                .padding()
            }
            .navigationTitle("隐私与数据")
            .navigationBarTitleDisplayMode(.inline)
            .alert("确认清除", isPresented: $showClearConfirm) {
                Button("清除所有数据", role: .destructive) {
                    store.clearAllData()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("这将清除所有本地记录，包括行程、能耗和控制历史。此操作不可撤销。")
            }
        }
    }
}

struct PrivacyCategorySection: View {
    let category: (title: String, items: [(name: String, size: String, type: String)])
    
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(category.title)
                .font(.headline)
                .padding(.horizontal)
                .padding(.top, Theme.Spacing.sm)
            
            ForEach(category.items, id: \.name) { item in
                HStack {
                    Text(item.name)
                        .font(.subheadline)
                    Spacer()
                    Text(item.size)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(item.type)
                        .font(.caption2)
                        .foregroundColor(.tertiaryLabel)
                }
                .padding(.horizontal)
                .padding(.vertical, Theme.Spacing.xs)
                if category.items.firstIndex(where: { $0.name == item.name }) != category.items.count - 1 {
                    Divider().opacity(0.3)
                        .padding(.horizontal)
                }
            }
        }
        .glassCard()
        .padding(.vertical, Theme.Spacing.xs)
    }
}

// MARK: - AppStore 扩展
extension AppStore {
    /// 清除全部本地数据（含 Keychain PIN）
    func clearAllData() {
        // 清除 UserDefaults
        let domain = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier!)
        domain?.keys.forEach { key in
            if key.hasPrefix("carkeeper_") || key == tokenStorageKey || key == cacheStorageKey {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        
        // 清除 Keychain
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Bundle.main.bundleIdentifier ?? "com.you.CarKeeper"
        ]
        SecItemDelete(query as CFDictionary)
        
        // 重置状态
        isLoggedIn = false
        phone = ""
        cars = []
        carId = ""
        car = nil
        user = nil
        energyHistory = []
        tripHistory = []
        commandHistory = []
        
        NotificationCenter.default.post(name: .didLogout, object: nil)
    }
}
