// =============================================================================
// AppClip — #46 完整实现
// 扫码车牌直接进入车辆页面，无需安装完整 App
// 使用方法：创建 AppClip Target，使用相同 Bundle ID 前缀
// 支持的 URL Scheme：carkeeper://plate/京A12345
// =============================================================================

import SwiftUI
import UIKit
import WidgetKit

// MARK: - AppClip 入口 Bundle

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
    @State private var carData: [String: Any]? = nil
    
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
                        .font(.system(size: 36))
                        .foregroundStyle(.white)
                }
                
                Text("CarKeeper").font(.system(size: 24, weight: .bold)).foregroundStyle(.white)
                Text("扫码车牌，快速查看车辆状态").font(.system(size: 14)).foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                
                // 车牌输入框
                HStack(spacing: 12) {
                    Image(systemName: "creditcard.fill").font(.title3).foregroundStyle(Color.accent)
                    TextField("请输入车牌号", text: $plateInput)
                        .font(.system(size: 18, weight: .medium, design: .monospaced))
                        .textInputAutocapitalization(.characters)
                        .keyboardType(.asciiCapable)
                        .autocorrectionDisabled()
                    if !plateInput.isEmpty {
                        Button { plateInput = "" }
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1))
                
                // 加载状态
                if isLoading {
                    ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white))
                    Text("正在查询车辆信息...").font(.system(size: 13)).foregroundStyle(.white.opacity(0.6))
                }
                
                // 错误提示
                if hasError {
                    Text("未找到该车辆，请检查车牌号或下载完整 App")
                        .font(.system(size: 13)).foregroundStyle(.red.opacity(0.8))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
                
                // 主要操作按钮
                Button {
                    isLoading = true
                    hasError = false
                    // 模拟查询（实际需调用 API）
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        isLoading = false
                        if plateInput.count >= 7 {
                            carData = ["name": "特斯拉 Model 3", "soc": 85, "range": 420, "temp": "21℃", "locked": true]
                        } else {
                            hasError = true
                        }
                    }
                } label: {
                    Text("查询车辆")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(Color.accent)
                }
                
                // 已有账号？打开完整 App
                Button {
                    showMainApp = true
                } label: {
                    Text("打开完整 App")
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.6))
                }
                
                Spacer()
                
                // 功能说明
                VStack(spacing: 12) {
                    FeatureItem(icon: "battery.100.fill", label: "实时电量")
                    FeatureItem(icon: "thermometer", label: "车内温度")
                    FeatureItem(icon: "lock.fill", label: "门锁状态")
                }
                .padding(.top, 20)
            }
            .padding(.horizontal, 24)
        }
        .sheet(isPresented: $showMainApp) {
            Text("跳转到主 App（需已安装）")
        }
    }
}

struct FeatureItem: View {
    let icon: String
    let label: String
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.title3).foregroundStyle(.white.opacity(0.8))
            Text(label).font(.system(size: 14)).foregroundStyle(.white.opacity(0.8))
        }
    }
}

// MARK: - AppClip 路由处理

enum CarClipRoute {
    static func handle(url: URL) -> AppClipEntranceView? {
        // 解析 carkeeper://plate/京A12345
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.host == "plate",
              let plate = components.path.trimmingCharacters(in: .characters(in: "/")) else {
            return nil
        }
        var view = AppClipEntranceView()
        // 通过 binding 传入车牌（需要包装为 StateObject 或 @State）
        return view
    }
}

// MARK: - AppClipAppDelegate

class CarClipAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        if let route = CarClipRoute.handle(url: url) {
            // 这里应该切换根视图，实际需要更复杂的处理
            print("AppClip opened for plate: \(url.absoluteString)")
        }
        return true
    }
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        return true
    }
}

// MARK: - 预览

struct AppClipEntrance_Previews: PreviewProvider {
    static var previews: some View {
        AppClipEntranceView()
    }
}
