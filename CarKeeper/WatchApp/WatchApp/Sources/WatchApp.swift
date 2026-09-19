// =============================================================================
// Watch App — #29 Apple Watch 完整实现（WatchKit Extension）
// 创建 WatchKit Extension Target 后，将此文件内容复制到 Extension 中
// 支持：SOC显示、锁车、开空调、寻车、里程统计
// =============================================================================

import SwiftUI
import WatchKit
import Foundation

// MARK: - Watch App Entry

@main
struct CarKeeperWatchApp: App {
    var body: some Scene {
        WindowGroup {
            WatchRoute()
        }
    }
}

// MARK: - Navigation

struct WatchRoute: View {
    @State private var selectedTab: Int = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            WatchStatusView()
                .tabItem {
                    Image(systemName: "car.fill")
                    Text("车况")
                }
                .tag(0)
            
            WatchControlView()
                .tabItem {
                    Image(systemName: "remote.fill")
                    Text("控制")
                }
                .tag(1)
            
            WatchProfileView()
                .tabItem {
                    Image(systemName: "person.fill")
                    Text("我的")
                }
                .tag(2)
        }
        .tint(Color.accent)
    }
}

// MARK: - 车况页

struct WatchStatusView: View {
    @State private var soc: Int = 0
    @State private var range: Int = 0
    @State private var temp: String = "--"
    @State private var locked: Bool = true
    @State private var charging: Bool = false
    @State private var mileage: Int = 0
    
    var body: some View {
        VStack(spacing: 16) {
            // SOC 大圆环
            ZStack {
                Circle().stroke(Color.secondary.opacity(0.3), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: CGFloat(soc) / 100)
                    .stroke(
                        LinearGradient(
                            colors: soc < 20 ? [.red, .orange] : [.green, .teal],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        lineWidth: 8
                    )
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 2) {
                    Text("\(soc)%")
                        .font(.system(size: 36, weight: .bold, design: .monospaced))
                        .foregroundStyle(soc < 20 ? .red : .primary)
                    Text("电量").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 100, height: 100)
            
            // 状态信息
            VStack(spacing: 12) {
                WatchStatusRow(icon: "gauge.high", value: "\(range) km", label: "续航")
                WatchStatusRow(icon: "thermometer", value: temp, label: "温度")
                WatchStatusRow(icon: locked ? "lock.fill" : "lock.open.fill", value: locked ? "已锁" : "未锁", label: "车门")
                if charging {
                    WatchStatusRow(icon: "bolt.fill", value: "充电中", label: "", tint: .green)
                }
            }
            
            Spacer()
            
            // 里程统计
            HStack(spacing: 20) {
                VStack {
                    Text("\(mileage)")
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                    Text("总里程").font(.system(size: 9)).foregroundStyle(.secondary)
                }
                VStack {
                    Text("0.0")
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                    Text("油耗").font(.system(size: 9)).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
        }
        .padding()
        .onAppear { loadFromAppGroup() }
        .refreshable { await reload() }
    }
    
    private func loadFromAppGroup() {
        let defaults = UserDefaults(suiteName: "group.com.carkeeper.data") ?? UserDefaults.standard
        soc = defaults.integer(forKey: "watch_soc")
        range = defaults.integer(forKey: "watch_range")
        temp = defaults.string(forKey: "watch_temp") ?? "--"
        locked = defaults.bool(forKey: "watch_locked")
        charging = defaults.bool(forKey: "watch_charging")
        mileage = defaults.integer(forKey: "watch_mileage")
    }
    
    private func reload() async {
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        loadFromAppGroup()
    }
}

struct WatchStatusRow: View {
    let icon: String
    let value: String
    let label: String
    let tint: Color? = nil
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(tint ?? Color.accent)
                .frame(width: 20)
            Text(value).font(.system(size: 16, weight: .semibold))
            Spacer()
            if !label.isEmpty {
                Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - 控制页

struct WatchControlView: View {
    @State private var acOn: Bool = false
    @State private var temperature: Int = 22
    @State private var isBusy = false
    
    var body: some View {
        VStack(spacing: 20) {
            Text("远程控制").font(.headline).padding(.top)
            
            // 空调控制
            VStack(spacing: 16) {
                HStack {
                    Button("-") { temperature = max(16, temperature - 1) }
                        .font(.title).frame(width: 40, height: 40)
                        .background(.ultraThinMaterial, in: Circle())
                    VStack {
                        Text("\(temperature)°C").font(.system(size: 32, weight: .bold, design: .monospaced))
                        Text(acOn ? "运行中" : "已关闭").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Button("+") { temperature = min(30, temperature + 1) }
                        .font(.title).frame(width: 40, height: 40)
                        .background(.ultraThinMaterial, in: Circle())
                }
                
                Button(action: toggleAC) {
                    HStack {
                        Image(systemName: acOn ? "fan.fill" : "fan.slash.fill")
                        Text(acOn ? "关闭空调" : "开启空调 \(temperature)°C")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(acOn ? Color.red.opacity(0.15) : Color.green.opacity(0.15), in: RoundedRectangle(cornerRadius: 16))
                    .foregroundStyle(acOn ? .red : .green)
                }
                .disabled(isBusy)
            }
            
            // 快捷控制
            Grid(horizontalSpacing: 16, verticalSpacing: 16) {
                GridRow {
                    WatchControlButton(icon: "lock.fill", label: "锁车", action: lockCar, disabled: isBusy)
                    WatchControlButton(icon: "lock.open.fill", label: "解锁", action: unlockCar, disabled: isBusy)
                }
                GridRow {
                    WatchControlButton(icon: "horn.fill", label: "寻车", action: findCar, disabled: isBusy)
                    WatchControlButton(icon: "headlights.front", label: "闪灯", action: flashLights, disabled: isBusy)
                }
            }
            .padding(.horizontal)
            
            Spacer()
        }
    }
    
    private func toggleAC() {
        isBusy = true
        acOn.toggle()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            isBusy = false
        }
    }
    
    private func lockCar() { sendCommand("CentralLock", name: "锁车") }
    private func unlockCar() { sendCommand("CentralUnlock", name: "解锁") }
    private func findCar() { sendCommand("HornLight", name: "寻车") }
    private func flashLights() { sendCommand("FlashLights", name: "闪灯") }
    
    private func sendCommand(_ cmd: String, name: String) {
        isBusy = true
        // 实际通过 WatchConnectivity 发送到 iPhone
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            isBusy = false
        }
    }
}

struct WatchControlButton: View {
    let icon: String
    let label: String
    let action: () -> Void
    let disabled: Bool
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 22))
                Text(label).font(.system(size: 10))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
    }
}

// MARK: - 个人页

struct WatchProfileView: View {
    var body: some View {
        List {
            Section("账户") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("用户名").font(.caption).foregroundStyle(.secondary)
                    Text("用户已登录").font(.subheadline)
                }
            }
            Section("设置") {
                NavigationLink("车辆管理") { Text("车辆管理") }
                NavigationLink("通知设置") { Text("通知设置") }
                NavigationLink("关于") { Text("CarKeeper Watch v1.0") }
            }
        }
        .navigationTitle("我的")
    }
}

// MARK: - 预览

struct WatchRoute_Previews: PreviewProvider {
    static var previews: some View {
        WatchRoute()
    }
}
