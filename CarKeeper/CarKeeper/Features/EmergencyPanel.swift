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
            VStack(spacing: 20) {
                // SOS 紧急呼叫
                sosButton
                
                // 快捷操作
                quickActions
                
                // 紧急联系人
                contactCard
                
                // 位置共享
                locationShareCard
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.md)
        }
        .pageBackground(Color(.systemRed).opacity(0.05))
        .navigationTitle("紧急求助")
        .navigationBarTitleDisplayMode(.inline)
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
                    .fill(Color.red.opacity(0.15))
                    .frame(width: 100, height: 100)
                Circle()
                    .strokeBorder(Color.red, lineWidth: 3)
                    .frame(width: 100, height: 100)
                    .opacity(activeEmergency ? 0.3 : 1)
                    .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: activeEmergency)
                
                VStack(spacing: 4) {
                    Image(systemName: "siren.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.red)
                    Text("SOS")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.red)
                }
            }
        }
        .accessibilityLabel(Text("紧急呼叫"))
        .accessibilityHint(Text("长按拨打紧急电话"))
    }
    
    // MARK: - 快捷操作
    private var quickActions: some View {
        VStack(spacing: 12) {
            Text("快捷操作").font(Theme.font(.subheadline).bold())
            HStack(spacing: 12) {
                actionButton(icon: "car.fill", title: "远程锁车", color: .blue, action: lockCar)
                actionButton(icon: "horn.fill", title: "鸣笛寻车", color: .orange, action: honkCar)
                actionButton(icon: "lightbulb.fill", title: "闪灯", color: .yellow, action: flashLights)
                actionButton(icon: "fan.fill", title: "开空调", color: .cyan, action: turnOnAC)
            }
        }
        .glassCard(corner: Theme.Radius.medium)
    }
    
    private func actionButton(icon: String, title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(color.opacity(0.08))
            .cornerRadius(Theme.Radius.small)
        }
        .PressFeedback()
    }
    
    // MARK: - 紧急联系人
    private var contactCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("紧急联系人").font(Theme.font(.subheadline).bold())
            HStack {
                Image(systemName: "person.fill")
                    .foregroundStyle(.accent)
                TextField("输入紧急电话", text: $emergencyContact)
                    .keyboardType(.phonePad)
                Button(action: saveContact) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
            .padding()
            .background(Color.primary.opacity(0.05))
            .cornerRadius(Theme.Radius.small)
        }
        .glassCard(corner: Theme.Radius.medium)
    }
    
    // MARK: - 位置共享
    private var locationShareCard: some View {
        Button(action: shareLocation) {
            HStack {
                Image(systemName: "location.fill")
                    .foregroundStyle(.red)
                VStack(alignment: .leading) {
                    Text("共享当前位置")
                        .font(Theme.font(.subheadline).bold())
                    Text("发送坐标给紧急联系人")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .glassCard(corner: Theme.Radius.medium)
    }
    
    // MARK: - 紧急叠加层
    private var emergencyOverlay: some View {
        ZStack {
            Color.black.opacity(0.8).ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "siren.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.red)
                    .animation(.spring(response: 0.4).repeatForever(autoreverses: true), value: activeEmergency)
                
                Text("紧急呼叫中...")
                    .font(Theme.h2.bold())
                    .foregroundStyle(.white)
                
                Text("正在联系 \(emergencyContact)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                Button(action: cancelEmergency) {
                    Text("取消")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 12)
                        .background(Color.gray.opacity(0.5))
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
    
    private func lockCar() {
        store.sendControlCommand("lock")
        EnhancedToastManager.shared.show("锁车指令已发送", icon: "lock.fill")
    }
    
    private func honkCar() {
        store.sendControlCommand("honk")
        EnhancedToastManager.shared.show("鸣笛中...", icon: "horn.fill")
    }
    
    private func flashLights() {
        store.sendControlCommand("flash")
        EnhancedToastManager.shared.show("闪灯中...", icon: "lightbulb.fill")
    }
    
    private func turnOnAC() {
        store.sendControlCommand("ac_on")
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
