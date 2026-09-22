// =============================================================================
// EmergencyPanel - 紧急求助面板（SOS 联系人 + 快捷操作）
// =============================================================================

import SwiftUI
import UIKit

struct EmergencyPanel: View {
    private let store = AppStore.shared
    @State private var showConfirm = false
    @State private var emergencyContact: String = UserDefaults.standard.string(forKey: "emergency_contact") ?? "110"
    @State private var activeEmergency = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: TokensSpacing.lg) {
                DSPageTitle(title: "紧急求助", subtitle: "SOS 拨打紧急电话，其余是常用动作")

                // SOS 紧急呼叫
                sosButton

                // 快捷操作
                quickActions

                // 紧急联系人
                contactCard

                // 位置共享
                locationShareCard
            }
            .padding(.horizontal, TokensSpacing.page)
            .padding(.vertical, TokensSpacing.lg)
        }
        .dsPageTitle("紧急求助", inline: true)
        .alert("确认拨打", isPresented: $showConfirm) {
            Button("取消", role: .cancel) {}
            Button("拨打 \(emergencyContact)", role: .destructive) { makeCall() }
        } message: {
            Text("将拨打紧急电话 \(emergencyContact)，是否继续？")
        }
        .overlay(
            Group {
                if activeEmergency {
                    emergencyOverlay
                }
            }
        )
        .accessibilityLabel(Text("紧急求助面板"))
    }

    // MARK: - SOS 按钮
    private var sosButton: some View {
        Button(action: { showConfirm = true }) {
            ZStack {
                Circle()
                    .fill(TokensPalette.error.opacity(0.15))
                    .frame(width: 100, height: 100)
                Circle()
                    .strokeBorder(TokensPalette.error, lineWidth: 3)
                    .frame(width: 100, height: 100)
                    .opacity(activeEmergency ? 0.3 : 1)
                    .animation(.easeInOut(duration: 0.2), value: activeEmergency)

                VStack(spacing: 4) {
                    Image(safeSymbol: "exclamationmark.octagon.fill", fallback: "exclamationmark.octagon.fill")
                        .font(TokensTypo.fixed(28))
                        .foregroundStyle(TokensPalette.error)
                    Text("SOS")
                        .font(TokensTypo.footnote.weight(.bold))
                        .foregroundStyle(TokensPalette.error)
                }
            }
        }
        .accessibilityLabel(Text("紧急呼叫"))
        .accessibilityHint(Text("长按拨打紧急电话"))
    }

    // MARK: - 快捷操作
    private var quickActions: some View {
        // 四个动作 = 四行（图标 + 名称 + 箭头），不是一个彩色按钮矩阵。
        // 原来的蓝/橙/黄/青四个底色跟「状态」毫无关系 —— 它们只是四个动作，
        // 而界面里唯一的「彩色」应该留给真的状态（这里是 SOS 的红）。
        DSGroup(title: "快捷操作") {
            DSGroupRow {
                DSRow(icon: "car.fill", title: "远程锁车", showsChevron: true) {
                    Task { await lockCar() }
                }
            }
            DSGroupRow {
                DSRow(icon: "speaker.wave.3.fill", title: "鸣笛寻车", showsChevron: true) {
                    Task { await honkCar() }
                }
            }
            DSGroupRow {
                DSRow(icon: "lightbulb.fill", title: "闪灯", showsChevron: true) {
                    Task { await flashLights() }
                }
            }
            DSGroupRow {
                DSRow(icon: "fan.fill", title: "开空调", showsChevron: true) {
                    Task { await turnOnAC() }
                }
            }
        }
    }

    // MARK: - 紧急联系人
    private var contactCard: some View {
        DSGroup(title: "紧急联系人", footer: "SOS 会拨打这个号码。") {
            DSGroupRow {
                HStack(spacing: TokensSpacing.md) {
                    Image(safeSymbol: "person.fill", fallback: "person.fill")
                        .foregroundStyle(TokensPalette.ambient)
                    TextField("输入紧急电话", text: $emergencyContact)
                        .keyboardType(.phonePad)
                        .font(TokensTypo.data)
                    Button(action: saveContact) {
                        Image(safeSymbol: "checkmark.circle.fill", fallback: "checkmark.circle.fill")
                            .foregroundStyle(TokensPalette.success)
                    }
                    .accessibilityLabel(Text("保存联系人"))
                }
            }
        }
    }

    // MARK: - 位置共享
    private var locationShareCard: some View {
        DSGroup {
            DSGroupRow {
                DSRow(icon: "location.fill",
                      title: "共享当前位置",
                      subtitle: "发送坐标给紧急联系人",
                      showsChevron: true,
                      action: shareLocation)
            }
        }
    }

    // MARK: - 紧急叠加层
    private var emergencyOverlay: some View {
        ZStack {
            TokensPalette.scrim.opacity(0.8).ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "exclamationmark.octagon.fill")
                    .font(TokensTypo.fixed(64))
                    .foregroundStyle(TokensPalette.error)

                Text("紧急呼叫中...")
                    .font(TokensTypo.title.bold())
                    .foregroundStyle(TokensPalette.labelOnTint)

                Text("正在联系 \(emergencyContact)")
                    .font(TokensTypo.subheadline)
                    .foregroundStyle(TokensPalette.secondary)

                Button(action: cancelEmergency) {
                    Text("取消")
                        .font(TokensTypo.headline)
                        .foregroundStyle(TokensPalette.labelOnTint)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 12)
                        // 原来是写死的「中灰」（#808080 一类）。改用令牌里的中性填充：
                        // 取消本来就是次要动作，它在暗遮罩上比中灰更收敛，且跟随主题。
                        .background(TokensPalette.track)
                        .cornerRadius(24)
                }
            }
        }
    }

    // MARK: - 操作
    private func makeCall() {
        activeEmergency = true
        showConfirm = false
        if let url = URL(string: "tel://\(emergencyContact)"), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
    }

    private func cancelEmergency() {
        activeEmergency = false
    }

    private func lockCar() async {
        _ = await store.sendControlCommand("lock")
        EnhancedToastManager.shared.show("锁车指令已发送", icon: "lock.fill")
    }

    private func honkCar() async {
        _ = await store.sendControlCommand("honk")
        EnhancedToastManager.shared.show("鸣笛中...", icon: "speaker.wave.3.fill")
    }

    private func flashLights() async {
        _ = await store.sendControlCommand("flash")
        EnhancedToastManager.shared.show("闪灯中...", icon: "lightbulb.fill")
    }

    private func turnOnAC() async {
        _ = await store.sendControlCommand("ac_on")
        EnhancedToastManager.shared.show("空调已开启", icon: "fan.fill")
    }

    private func saveContact() {
        UserDefaults.standard.set(emergencyContact, forKey: "emergency_contact")
        EnhancedToastManager.shared.show("联系人已保存", icon: "checkmark.circle.fill")
    }

    private func shareLocation() {
        guard let loc = store.currentLocation else {
            EnhancedToastManager.shared.show("暂无位置数据", icon: "location.slash")
            return
        }
        let text = "我的位置：\(loc.coordinate.latitude), \(loc.coordinate.longitude)"
        let vc = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            scene.windows.first?.rootViewController?.present(vc, animated: true)
        }
    }
}

struct EmergencyPanel_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            EmergencyPanel()
        }
    }
}
