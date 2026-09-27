// =============================================================================
// N11 隐私与数据 —— 「我的」档里的一节（不是另一屏）
// =============================================================================
//  它原来是一个独立浮层（`PrivacyDashboardView`），由「我的 → 隐私与数据」拉起。
//  2026-09-23 降成一节：**「本机存了什么」本来就是设置的一部分** —— 少一层浮层，
//  也少一条「从设置进入另一个 App」的错觉。
//
//  这一节说的是本机到底存了什么，所以它自己在变短：行程与曲线还在，
//  而充电账本、诊断统计、使用小记录已经不在这一页上了（它们已被删除）。
//
//  ⚠️ 右列（「存在哪」）原本写的是 `CoreLocation` / `UserDefaults` / `Keychain` /
//  `LocalAuthentication` / `UUID` —— 那是**代码里的模块名**，不是给人看的字。
//  现在它是「定位服务 / 本机 / 钥匙串 / 生物识别保护」——同一个事实，用中文说。
//  这一条现在由 `scan/copy.py` 的「开发词」规则守住。
// =============================================================================

import SwiftUI

struct PrivacySection: View {
    private let store = AppStore.shared
    @State private var showClearConfirm = false

    private var dataCategories: [(title: String, items: [(name: String, size: String, type: String)])] {
        [
        (
            title: "位置数据",
            items: [
                ("停车位置", "≈ 64B", "定位服务"),
                ("行驶轨迹", "≈ 2KB/次", "定位服务"),
                ("历史位置", "\(store.tripHistory.count) 条记录", "本机")
            ]
        ),
        (
            title: "车辆数据",
            items: [
                ("SOC 采样", "\(store.energyHistory.count) 条", "本机"),
                ("行程记录", "\(store.tripHistory.count) 条", "本机"),
                ("控制命令", "\(store.commandHistory.count) 条", "本机"),
                ("维保记录", "\(store.serviceTimestamp != 0 ? "有" : "无")", "本机")
            ]
        ),
        (
            title: "账户数据",
            items: [
                ("登录凭证", "钥匙串", "生物识别保护"),
                ("生物识别", store.hasBiometricSetup ? "已启用" : "未启用", "钥匙串"),
                ("设备 ID", "随机", "本机")
            ]
        ),
        (
            title: "设置偏好",
            items: [
                ("夜间模式", UserDefaults.standard.object(forKey: "carkeeper_force_dark_mode") != nil ? "自定义" : "跟随系统",
                 "本机"),
                ("卡片排序", "\(store.cardOrder.count) 个自定义", "本机"),
                ("语言", Locale.current.language.languageCode?.identifier ?? "zh", "本机"),
                ]
        )
    ]
    }

    private var totalRecords: Int {
        store.energyHistory.count + store.tripHistory.count + store.commandHistory.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TokensSpacing.lg) {
            DSSectionHeader(title: "隐私与数据", trailing: "本机 \(totalRecords) 条")

            ForEach(dataCategories, id: \.title) { category in
                PrivacyCategorySection(category: category)
            }

            // 离开本机的数据：「数据去了哪」是隐私披露里最该说清、也最容易被含糊过去的一节。
            // 两处（就两个）都是代码里真实存在的域名：`APIConfig` 与 `WeatherService.host`。
            //
            //  ⚠️ 2026-09-27：第三行「GitHub（版本检查）」删掉了 —— 用户这一轮
            //  把更新相关的东西整体拿走（`UpdateService` / `GithubToken`），
            //  这一个 App 从此**不再访问那一个域名**。一张写着「我们不去那儿」的
            //  披露表比一张少一行的表更糟：它是关于"现在"的陈述，而那句话已经过期。
            DSGroup(title: "离开本机的数据",
                    footer: "天气只给两位小数的经纬度，两处都不带车辆标识。") {
                DSGroupRow {
                    DSRow(icon: "car.fill", title: "长安车联网",
                          subtitle: "只在你用这些功能时")
                }
                DSGroupRow(showsSeparator: false) {
                    DSRow(icon: "cloud.sun.fill", title: "Open-Meteo（天气实况）",
                          subtitle: "车的位置（两位小数）")
                }
            }

            // 清除：后果写在按钮旁边，不藏在确认框里
            DSGroup(title: "清除", footer: "清除后无法恢复，本机没有云端副本。") {
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

                DSGroupRow(showsSeparator: false) {
                    Button {
                        // 仅清除行程与能耗数据
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
        .alert("确认清除", isPresented: $showClearConfirm) {
            Button("清除所有数据", role: .destructive) {
                store.clearAllData()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将清除行程、能耗、控制历史，不可撤销。")
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
