
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
                ("维保记录", "累计 \(store.totalMileage) km", "本机")
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

extension AppStore {
    func clearAllData() {
        let defaults = UserDefaults.standard
        if let domain = defaults.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "") {
            for key in domain.keys where key.hasPrefix("carkeeper_") || key == tokenStorageKey {
                defaults.removeObject(forKey: key)
            }
        }

        TokenStore.clear()
        deletePin()

        isLoggedIn = false
        phone = ""
        cars = []
        carId = ""
        car = nil
        user = nil
        energyHistory = []
        tripHistory = []
        commandHistory = []
        clearCache()

        NotificationCenter.default.post(name: .didLogout, object: nil)
    }
}
