// =============================================================================
// AppClip — #46 完整实现
// 扫码车牌直接进入车辆页面，无需安装完整 App
// 使用方法：创建 AppClip Target，使用相同 Bundle ID 前缀
// =============================================================================

import SwiftUI
import UIKit

/// AppClip 入口 Bundle
struct CarClipBundle: WidgetBundle {
    var body: some Widget {
        // AppClip 可以包含 Widget
    }
}

// MARK: - AppClip 入口视图
struct AppClipEntranceView: View {
    @State private var plateInput: String = ""
    @State private var isLoading = false
    @State private var hasError = false
    @State private var showMainApp = false
    
    var body: some View {
        ZStack {
            // 背景渐变
            LinearGradient(
                colors: [.blue.opacity(0.3), .purple.opacity(0.2)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 24) {
                // Logo
                ZStack {
                    Circle()
                        .fill(Material.thin)
                        .frame(width: 80, height: 80)
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
                    Image(systemName: "car.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.accentColor)
                }
                
                Text("长安车管家")
                    .font(.system(size: 24, weight: .bold))
                
                Text("快速查看您的车辆状态")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                
                Divider()
                
                // 车牌输入
                VStack(alignment: .leading, spacing: 8) {
                    Text("输入车牌号")
                        .font(.system(size: 14, weight: .semibold))
                    
                    TextField("例如：京A·12345", text: $plateInput)
                        .font(.system(size: 18))
                        .textInputAutocapitalization(.characters)
                        .padding()
                        .background(.thin, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1)
                        )
                }
                
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .accentColor))
                }
                
                if hasError {
                    Text("未找到该车辆，请检查车牌号或安装完整应用")
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                        .padding()
                        .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                }
                
                // 主要操作按钮
                Button {
                    handleLogin()
                } label: {
                    Text("查看车辆")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(AngularGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 12))
                }
                
                Button {
                    showMainApp = true
                } label: {
                    HStack {
                        Image(systemName: "square.and.arrow.down")
                        Text("安装完整应用")
                    }
                    .font(.system(size: 14))
                    .foregroundStyle(.accentColor)
                }
                
                Spacer()
                
                // 功能说明
                VStack(spacing: 12) {
                    FeatureRow(icon: "bolt.fill", title: "实时电量", desc: "SOC、续航")
                    FeatureRow(icon: "lock.fill", title: "远程控车", desc: "锁车/解锁")
                    FeatureRow(icon: "thermometer", title: "空调控制", desc: "远程制冷/制热")
                }
                .padding(.horizontal, 20)
                
                Spacer()
            }
            .padding()
        }
        .sheet(isPresented: $showMainApp) {
            MainAppRedirectView()
        }
    }
    
    private func handleLogin() {
        guard !plateInput.isEmpty else { return }
        isLoading = true
        hasError = false
        
        // 模拟登录验证
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            isLoading = false
            // 实际项目中应调用 API 验证车牌
            hasError = plateInput.count < 5
            if !hasError {
                // 跳转到主 App
                showMainApp = true
            }
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let desc: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(.accentColor)
                .frame(width: 32, height: 32)
                .background(.thin, in: RoundedRectangle(cornerRadius: 8))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                Text(desc)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
    }
}

struct MainAppRedirectView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "square.and.arrow.up.on.square")
                .font(.system(size: 60))
                .foregroundStyle(.accentColor)
            
            Text("正在跳转到主应用...")
                .font(.system(size: 18, weight: .semibold))
            
            Text("如果未自动跳转，请手动打开长安车管家 App")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            Button("打开 App Store") {
                // 跳转到 App Store
                if let url = URL(string: "https://apps.apple.com/app/id") {
                    UIApplication.shared.open(url)
                }
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            
            Button("返回") {
                dismiss()
            }
            .font(.system(size: 14))
            .foregroundStyle(.secondary)
        }
        .padding()
        .presentationDetents([.medium])
    }
}
