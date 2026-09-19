// =============================================================================
// #NEW-130 锁屏专注模式 — 专注驾驶时隐藏敏感数据，仅显示关键信息
// =============================================================================

import SwiftUI

/// 专注模式配置
struct FocusModeConfig: Codable, Identifiable {
    let id = UUID()
    var enabled: Bool
    var hideSensitiveData: Bool  // 隐藏车牌/ VIN/ 联系人
    var showEssentialOnly: Bool  // 只显示 SOC/锁车/空调
    var doNotDisturb: Bool       // 勿扰模式
    var autoStartDriving: Bool   // 驾驶时自动启动
    var customMessage: String    // 自定义锁屏文字
}

class FocusModeManager: ObservableObject {
    static let shared = FocusModeManager()
    
    var config: FocusModeConfig {
        if let data = UserDefaults.standard.data(forKey: "carkeeper_focus_mode"),
           let decoded = try? JSONDecoder().decode(FocusModeConfig.self, from: data) {
            return decoded
        }
        return defaultConfig
    }
    
    func saveConfig(_ config: FocusModeConfig) {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: "carkeeper_focus_mode")
        }
    }
    
    /// 检测是否正在驾驶（基于速度）
    var isDriving: Bool {
        // 简化：检查最近一次心跳速度
        UserDefaults.standard.double(forKey: "carkeeper_current_speed") > 5
    }
    
    var defaultConfig: FocusModeConfig {
        FocusModeConfig(
            enabled: false,
            hideSensitiveData: true,
            showEssentialOnly: true,
            doNotDisturb: true,
            autoStartDriving: true,
            customMessage: ""
        )
    }
}

// MARK: - 专注模式下的简化视图
struct FocusModeHomeView: View {
    let car: CarModel?
    @StateObject private var focusManager = FocusModeManager.shared
    
    var body: some View {
        if !focusManager.config.enabled {
            EmptyView()
        } else {
            VStack(spacing: Theme.Spacing.lg) {
                // 自定义消息
                if !focusManager.config.customMessage.isEmpty {
                    Text(focusManager.config.customMessage)
                        .font(.headline)
                        .foregroundColor(Color.accent)
                        .padding(.horizontal)
                        .glassCard()
                        .padding(.horizontal)
                }
                
                // 仅显示关键信息
                if focusManager.config.showEssentialOnly {
                    essentialInfoView
                }
                
                Spacer()
                
                // 关闭专注模式按钮
                Button {
                    withAnimation(.spring()) {
                        focusManager.saveConfig(
                            FocusModeConfig(
                                enabled: false,
                                hideSensitiveData: focusManager.config.hideSensitiveData,
                                showEssentialOnly: focusManager.config.showEssentialOnly,
                                doNotDisturb: focusManager.config.doNotDisturb,
                                autoStartDriving: focusManager.config.autoStartDriving,
                                customMessage: focusManager.config.customMessage
                            )
                        )
                    }
                } label: {
                    HStack {
                        Image(systemName: "moon.fill")
                        Text("退出专注模式")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red.opacity(0.8))
                    .foregroundColor(.white)
                    .cornerRadius(Theme.Radius.medium)
                }
                .padding(.horizontal)
            }
            .padding()
        }
    }
    
    private var essentialInfoView: some View {
        VStack(spacing: Theme.Spacing.md) {
            // SOC 大圆环（必须）
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 8)
                Circle()
                    .stroke(style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .foregroundStyle(
                        LinearGradient(colors: [.green, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .rotationEffect(.degrees(270))
                    .animation(.easeInOut, value: car?.energy?.socPct)
                
                VStack {
                    Text("\(car?.energy?.socPct ?? 0)%")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                    Text("剩余续航")
                        .font(.caption)
                        .foregroundColor(.secondaryLabel)
                    Text("\(car?.energy?.rangeKm ?? 0) km")
                        .font(.title3)
                        .fontWeight(.semibold)
                }
            }
            .frame(width: 160, height: 160)
            
            // 空调温度（必须）
            HStack {
                Image(systemName: "fan.fill")
                    .foregroundColor(.blue)
                Text("\(car?.climate?.tempC ?? 22)°C")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Image(systemName: car?.climate?.acOn == true ? "snowflake" : "sun.max.fill")
                    .foregroundColor(car?.climate?.acOn == true ? .blue : .orange)
            }
            .glassCard()
            
            // 锁车状态（必须）
            HStack {
                Image(systemName: car?.control?.doorLocked == true ? "lock.fill" : "lock.open.fill")
                    .foregroundColor(car?.control?.doorLocked == true ? .green : .orange)
                    .font(.title2)
                Text(car?.control?.doorLocked == true ? "已上锁" : "未上锁")
                    .font(.subheadline)
                    .foregroundColor(.primary)
            }
            .glassCard()
        }
    }
}

// MARK: - 设置页
struct FocusModeSettingsView: View {
    @StateObject private var manager = FocusModeManager.shared
    @State private var config: FocusModeConfig
    
    init() {
        _config = State(initialValue: FocusModeManager.shared.config)
    }
    
    var body: some View {
        Form {
            Section("基础设置") {
                Toggle("启用专注模式", isOn: $config.enabled)
                Toggle("驾驶时自动启动", isOn: $config.autoStartDriving)
            }
            
            Section("数据隐藏") {
                Toggle("隐藏敏感数据（车牌/VIN）", isOn: $config.hideSensitiveData)
                Toggle("仅显示关键信息", isOn: $config.showEssentialOnly)
                Toggle("勿扰模式（静音通知）", isOn: $config.doNotDisturb)
            }
            
            Section("自定义") {
                TextField("锁屏提示文字", text: $config.customMessage)
                    .textInputAutocapitalization(.sentences)
            }
        }
        .navigationTitle("专注模式")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("完成") {
                    manager.saveConfig(config)
                }
            }
        }
    }
}
