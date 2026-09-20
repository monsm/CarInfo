// =============================================================================
// N13 敏感页面 FaceID 二次验证
// N14 远程锁定（App 后台超时自动隐藏）
// =============================================================================

import SwiftUI
import LocalAuthentication
import UIKit

// MARK: - N13 敏感页面 FaceID 二次验证
struct BiometricLockOverlay: View {
    @Binding var isAuthenticated: Bool
    @State private var errorMessage: String?
    @State private var showUnlock = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()

            VStack(spacing: Kansei.Spacing.lg) {
                Image(systemName: "faceid")
                    .font(.system(size: 60))
                    .foregroundColor(Kansei.Color.ambient)
                    .symbolEffect(.bounce)

                Text("需要身份验证")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(errorMessage ?? "请使用 Face ID 或 Touch ID 验证身份")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Button {
                    authenticate()
                } label: {
                    Label("解锁", systemImage: "faceid")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Kansei.Color.ambient)
                        .foregroundColor(.white)
                        .cornerRadius(Kansei.Radius.medium)
                }
                .padding(.horizontal, Kansei.Spacing.xl)
            }
            .padding()
            .glassCard()
        }
        .ignoresSafeArea()
    }

    private func authenticate() {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            errorMessage = "此设备不支持生物识别"
            return
        }
        context.evaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            localizedReason: "验证身份以访问敏感信息"
        ) { success, authError in
            DispatchQueue.main.async {
                if success {
                    isAuthenticated = true
                    errorMessage = nil
                } else {
                    errorMessage = authError?.localizedDescription ?? "验证失败"
                }
            }
        }
    }
}

// MARK: - N14 远程锁定（后台超时自动隐藏）
class RemoteLockManager: ObservableObject {
    static let shared = RemoteLockManager()

    @Published var isLocked: Bool = false
    @Published var lockTimeoutMinutes: Int = 5

    private var backgroundTaskId: UIBackgroundTaskIdentifier = .invalid
    private var lockTimer: Timer?

    private init() {}

    func startMonitoring() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }

    @objc private func onEnterBackground() {
        lockTimer?.invalidate()
        lockTimer = Timer.scheduledTimer(withTimeInterval: Double(lockTimeoutMinutes) * 60, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.isLocked = true
            }
        }
    }

    @objc private func onEnterForeground() {
        lockTimer?.invalidate()
        isLocked = false
    }
}
