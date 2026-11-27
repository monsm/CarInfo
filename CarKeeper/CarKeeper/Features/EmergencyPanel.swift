
import SwiftUI
import UIKit

struct EmergencyPanel: View {
    private let store = AppStore.shared
    @State private var showConfirm = false
    @State private var emergencyContact: String = UserDefaults.standard.string(forKey: "emergency_contact") ?? "110"
    @State private var activeEmergency = false

    var body: some View {
        VStack(alignment: .leading, spacing: TokensSpacing.lg) {
            sosButton

            quickActions

            contactCard

            locationShareCard
        }
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

                VStack(spacing: TokensSpacing.xs) {
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

    private var quickActions: some View {
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

    private var emergencyOverlay: some View {
        ZStack {
            TokensPalette.scrim.opacity(0.8).ignoresSafeArea()
            VStack(spacing: 20) {
                Image(safeSymbol: "exclamationmark.octagon.fill", fallback: "exclamationmark.octagon.fill")
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
                        .padding(.horizontal, TokensSpacing.xl)
                        .padding(.vertical, TokensSpacing.snug)
                        .background(Capsule().fill(TokensPalette.track))
                }
            }
        }
    }

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
        _ = await store.sendControlCommand("LockDoor")
        ToastManager.shared.show("锁车指令已发送", icon: "lock.fill")
    }

    private func honkCar() async {
        _ = await store.sendControlCommand("Whistle")
        ToastManager.shared.show("鸣笛中...", icon: "speaker.wave.3.fill")
    }

    private func flashLights() async {
        _ = await store.sendControlCommand("FlashLight")
        ToastManager.shared.show("闪灯中...", icon: "lightbulb.fill")
    }

    private func turnOnAC() async {
        _ = await store.sendControlCommand("OpenAir")
        ToastManager.shared.show("空调已开启", icon: "fan.fill")
    }

    private func saveContact() {
        UserDefaults.standard.set(emergencyContact, forKey: "emergency_contact")
        ToastManager.shared.show("联系人已保存", icon: "checkmark.circle.fill")
    }

    private func shareLocation() {
        guard let loc = store.currentLocation else {
            ToastManager.shared.show("暂无位置数据", icon: "location.slash")
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
