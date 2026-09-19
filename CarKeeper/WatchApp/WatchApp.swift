// =============================================================================
// Watch App — #29 Apple Watch 支持（简化版）
// 显示 SOC、锁车状态，提供一键锁车功能
// 注：实际 Watch App 需要创建 WatchKit Extension Target
// =============================================================================

import SwiftUI

// MARK: - Watch App Entry Point
struct CarKeeper_WatchApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                WatchHomeView()
            }
        }
    }
}

// MARK: - Watch Home View
struct WatchHomeView: View {
    @State private var soc = 65
    @State private var locked = true
    @State private var temp = 22
    @State private var isCharging = false
    
    var body: some View {
        ZStack {
            // 背景
            Color.black.ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 20) {
                    // SOC 圆环
                    ZStack {
                        Circle()
                            .stroke(Color.gray.opacity(0.3), lineWidth: 8)
                            .frame(width: 120, height: 120)
                        Circle()
                            .trim(from: 0, to: CGFloat(soc) / 100)
                            .stroke(
                                LinearGradient(
                                    colors: soc > 50 ? [.green, .teal] : [.orange, .red],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                style: StrokeStyle(lineWidth: 8, lineCap: .round)
                            )
                            .frame(width: 120, height: 120)
                            .rotationEffect(.degrees(-90))
                        VStack {
                            Text("\(soc)%")
                                .font(.system(size: 32, weight: .bold))
                            Text("剩余续航")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            Text("\(Int(Double(soc) * 4.5)) km")
                                .font(.system(size: 14, weight: .semibold))
                        }
                    }
                    
                    // 状态信息
                    HStack(spacing: 20) {
                        StatusItem(icon: "thermometer", value: "\(temp)°C", label: "车内温度")
                        StatusItem(icon: locked ? "lock.fill" : "lock.open.fill", value: locked ? "已锁" : "未锁", label: "车锁")
                    }
                    
                    // 操作按钮
                    HStack(spacing: 20) {
                        WatchActionCard(
                            icon: locked ? "lock.open.fill" : "lock.fill",
                            title: locked ? "解锁" : "锁车",
                            color: locked ? .red : .green,
                            action: { locked.toggle() }
                        )
                        WatchActionCard(
                            icon: "snowflake",
                            title: "空调",
                            color: .blue,
                            action: {}
                        )
                    }
                    
                    // 快速控制
                    VStack(spacing: 12) {
                        WatchMiniCard(icon: "car.2.fill", title: "寻车", action: {})
                        WatchMiniCard(icon: "lightbulb", title: "闪灯", action: {})
                    }
                    
                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 16)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Status Item
struct StatusItem: View {
    let icon: String
    let value: String
    let label: String
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(.accentColor)
            Text(value)
                .font(.system(size: 14, weight: .semibold))
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Action Card
struct WatchActionCard: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(color.opacity(0.2))
                    .frame(height: 80)
                VStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 28))
                        .foregroundStyle(color)
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                }
            }
        }
    }
}

// MARK: - Mini Card
struct WatchMiniCard: View {
    let icon: String
    let title: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(.accentColor)
                Text(title)
                    .font(.system(size: 14))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        }
    }
}
