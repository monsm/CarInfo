import SwiftUI

// 我的：用户卡 + 车辆卡 + 常用入口 + 退出登录
struct MineView: View {
    private let store = AppStore.shared

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.cardSpacing) {
                // 身份条
                HStack(spacing: 14) {
                    ZStack {
                        Circle().fill(Color.accentColor.opacity(0.15)).frame(width: 56, height: 56)
                        Text(VM.userModel(store.user)?.avatar ?? "主")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.user.map { ciString($0, ["UserFullname", "UserNickname"]) ?? "车主" } ?? "车主")
                            .font(.system(size: 17, weight: .semibold))
                        HStack(spacing: 8) {
                            Text((store.user.map { ciString($0, ["Mobile"]) ?? "" } ?? "")).font(.system(size: 13, design: .monospaced)).foregroundStyle(.secondary)
                            if (store.user.map { ciBool($0, ["RealnameAuthed"]) ?? false } ?? false) == true {
                                Text("已实名").font(.system(size: 12)).foregroundStyle(.green)
                            }
                        }
                    }
                    Spacer()
                }
                .padding(16)
                .background(Color(.systemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))

                // 车辆卡
                if let car = store.car {
                    let sum = VM.vehicleSummary(car)
                    HStack(spacing: 14) {
                        Image(systemName: "car.fill").font(.system(size: 32)).foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(sum?.name ?? "未绑定车辆").font(.system(size: 17, weight: .semibold))
                            Text(sum?.plate ?? "暂无车牌").font(.system(size: 13)).foregroundStyle(.secondary)
                            if let end = sum?.insuranceEnd, !end.isEmpty {
                                HStack(spacing: 6) {
                                    Text("保险至 \(end)").font(.system(size: 12)).foregroundStyle(.secondary)
                                    if let d = sum?.insuranceDays {
                                        Text(d < 0 ? "已到期" : "剩 \(d) 天")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(d < 0 ? Color.red : (d <= 30 ? Color.orange : Color.green))
                                    }
                                }
                            }
                        }
                        Spacer()
                    }
                    .padding(16)
                    .background(Color(.systemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        NotificationCenter.default.post(name: .navToVehicle, object: nil)
                    }
                }

                // 常用入口
                CardBox(title: "常用") {
                    let tiles: [(String, String)] = [
                        ("shield.fill", "健康报告"), ("battery.100", "电池充电"),
                        ("chart.bar", "全量分析"), ("location", "定位记录"), ("person", "账号资料")
                    ]
                    HStack(spacing: 20) {
                        ForEach(Array(tiles.enumerated()), id: \.offset) { _, t in
                            VStack(spacing: 6) {
                                Image(systemName: t.0).font(.system(size: 20)).foregroundStyle(.secondary)
                                Text(t.1).font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }

                // 工程与账户
                CardBox(title: "工程与账户") {
                    VStack(spacing: 0) {
                        utilityRow("gearshape", "开发者工具") { NotificationCenter.default.post(name: .navToDev, object: nil) }
                        utilityRow("doc.text", "全量数据") { NotificationCenter.default.post(name: .navToData, object: nil) }
                        utilityRow("info", "关于") { showAbout() }
                        utilityRow("rectangle.portrait.and.arrow.right", "退出登录") { logout() }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 90)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("我的")
    }

    private func utilityRow(_ symbol: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: symbol).frame(width: 24).foregroundStyle(.secondary)
                Text(label).font(.system(size: 15))
                Spacer()
                if label == "退出登录" {
                    Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(.secondary)
                } else {
                    Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func showAbout() {
        let msg = "长安车管家 v1.0\n网络通道：直连（iOS 原生）\n\n车况数据实时来自车辆车联网服务，仅用于本人车辆管理。"
        print(msg)
    }

    private func logout() {
        store.logout()
        // RootView 监听 isLoggedIn 变化后自动切回登录页
    }
}
