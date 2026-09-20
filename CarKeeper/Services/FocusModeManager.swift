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
        // 简化：检查最近一次上报的车速
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
    let car: [String: Any]?

    // ⚠️ 报文里没有 car["energy"] / car["climate"]（小程序是现算的），car["control"]["doorLocked"]
    // 这个键也不存在（锁止是 DriverDoorLock）。统一改为走视图模型 + 官方字段名。
    private var cached: [String: Any?] { AppStore.shared.caches }
    private var socPct: Int { VM.energy(cached, car).socPct }
    private var rangeKm: Int { Int(VM.energy(cached, car).range.filter { $0.isNumber }) ?? 0 }
    /// cabinTemp 形如 "23℃"，取数字部分；无数据回落 22
    private var tempC: Int { Int(VM.comfortStatus(cached).cabinTemp.filter { $0.isNumber }) ?? 22 }
    private var acOn: Bool { VM.comfortStatus(cached).acOn ?? false }
    private var doorLocked: Bool {
        ciNumber(cacheObject(cached, "control"), ["DriverDoorLock"]).map { $0 == 0 } ?? false
    }
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
                        .foregroundColor(Theme.Colors.accent)
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
                    .trim(from: 0, to: min(1, max(0, Double(socPct) / 100)))
                    .stroke(DS.Palette.tint, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut, value: socPct)
                
                VStack {
                    Text("\(socPct)%")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                    Text("剩余续航")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(rangeKm) km")
                        .font(.title3)
                        .fontWeight(.semibold)
                }
            }
            .frame(width: 160, height: 160)
            
            // 空调温度（必须）
            HStack {
                Image(systemName: "fan.fill")
                    .foregroundColor(.blue)
                Text("\(tempC)°C")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Image(systemName: acOn ? "snowflake" : "sun.max.fill")
                    .foregroundColor(acOn ? .blue : .orange)
            }
            .glassCard()
            
            // 锁车状态（必须）
            HStack {
                Image(systemName: doorLocked ? "lock.fill" : "lock.open.fill")
                    .foregroundColor(doorLocked ? .green : .orange)
                    .font(.title2)
                Text(doorLocked ? "已上锁" : "未上锁")
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
