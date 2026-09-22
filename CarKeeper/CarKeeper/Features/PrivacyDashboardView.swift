// =============================================================================
// N11 隐私仪表盘 — 展示 App 收集的所有数据，支持一键清除
// =============================================================================

import SwiftUI

struct PrivacyDashboardView: View {
    private let store = AppStore.shared
    @State private var showClearConfirm = false

    private var dataCategories: [(title: String, items: [(name: String, size: String, type: String)])] {
        [
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
                ("夜间模式", UserDefaults.standard.object(forKey: "carkeeper_force_dark_mode") != nil ? "自定义" : "跟随系统",
                 "UserDefaults"),
                ("卡片排序", "\(store.cardOrder.count) 个自定义", "UserDefaults"),
                ("语言", Locale.current.language.languageCode?.identifier ?? "zh", "UserDefaults"),
                ]
        )
    ]
    }

    private var totalRecords: Int {
        store.energyHistory.count + store.tripHistory.count + store.commandHistory.count
    }

    var body: some View {
        // 不再在里面套一层 NavigationStack：这个页面是「我的」的导航栈里打开的浮层，
        // 再套一层就会出现两条导航栏、标题说两遍（而且两个栈各自记一份返回路径）。
        ScrollView {
            LazyVStack(alignment: .leading, spacing: TokensSpacing.lg) {
                DSPageTitle(title: "隐私与数据", subtitle: "本机存了什么，全部列在下边")

                // 汇总：一个数字，不靠一张卡来证明自己重要
                DSGroup {
                    DSGroupRow {
                        DSBigNumber(value: "\(totalRecords)",
                                    unit: "条",
                                    caption: "本机存储的记录总数",
                                    size: 56)
                            .padding(.vertical, TokensSpacing.xs)
                    }
                }

                // 分类详情
                ForEach(dataCategories, id: \.title) { category in
                    PrivacyCategorySection(category: category)
                }

                // 离开本机的数据：「数据去了哪」是隐私披露里最该说清、也最容易被含糊过去的一节。
                // 三处都是代码里真实存在的域名（APIConfig / WeatherService.host / UpdateService）。
                DSGroup(title: "离开本机的数据",
                        footer: "三处都只发该功能需要的最小信息。天气那次只给经纬度，且**保留两位小数**"
                              + "（约 1.1 km 网格）—— 云量不需要比这更准，而精度的每一次增加都是隐私的每一次减少。"
                              + "三个请求都不带车辆标识 / 账号 / 设备号；天气快照只在内存里，不落盘。") {
                    DSGroupRow {
                        DSRow(icon: "car.fill", title: "长安车联网",
                              subtitle: "车辆状态、控制指令、登录 —— 只在你用这些功能时")
                    }
                    DSGroupRow {
                        DSRow(icon: "cloud.sun.fill", title: "Open-Meteo（天气实况）",
                              subtitle: "车的位置（两位小数）；每 \(Int(WeatherService.refreshMinutes)) 分钟最多一次 —— 用来算云量对光的影响")
                    }
                    DSGroupRow(showsSeparator: false) {
                        DSRow(icon: "arrow.down.circle", title: "GitHub（版本检查）",
                              subtitle: "只在你点「检查更新」时")
                    }
                }

                // 清除：后果写在按钮旁边，不藏在确认框里
                DSGroup(title: "清除",
                        footer: "清除后无法恢复：这些记录只在本机，没有云端副本。") {
                    DSGroupRow {
                        Button(role: .destructive) {
                            showClearConfirm = true
                        } label: {
                            Label("清除全部本地数据", systemImage: "trash.fill")
                                .font(TokensTypo.subheadline.weight(.semibold))
                                .foregroundStyle(TokensPalette.error)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    DSGroupRow {
                        Button {
                            // 仅清除行程和能耗数据
                            store.tripHistory = []
                            store.energyHistory = []
                            store.commandHistory = []
                        } label: {
                            Label("清除行程与能耗记录", systemImage: "arrow.triangle.clockwise")
                                .font(TokensTypo.subheadline)
                                .foregroundStyle(TokensPalette.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            .padding(.horizontal, TokensSpacing.page)
            .padding(.vertical, TokensSpacing.lg)
        }
        // v5：不自己铺底 —— 画布与光在 App 根部只画一次（原生主题下逐像素相同）。
        .dsPageTitle("隐私与数据", inline: true)
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

struct PrivacyCategorySection: View {
    let category: (title: String, items: [(name: String, size: String, type: String)])

    var body: some View {
        // 一个分类 = 一个分组（与全 App 其它分组同一件东西：同一个面、同一条发丝线）
        DSGroup(title: category.title) {
            ForEach(Array(category.items.enumerated()), id: \.offset) { _, item in
                DSGroupRow {
                    HStack(alignment: .firstTextBaseline, spacing: TokensSpacing.md) {
                        Text(item.name)
                            .font(TokensTypo.subheadline)
                            .foregroundStyle(TokensPalette.primary)
                        Spacer(minLength: TokensSpacing.sm)
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(item.size)
                                .font(TokensTypo.dataSmall)
                                .foregroundStyle(TokensPalette.secondary)
                            // 存储位置：原来是写死的 Color(.tertiaryLabel)，于是四套主题里都是同一块系统灰
                            Text(item.type)
                                .font(TokensTypo.caption2)
                                .foregroundStyle(TokensPalette.tertiary)
                        }
                    }
                }
            }
        }
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
