
import SwiftUI
import LocalAuthentication
import UIKit

struct BiometricLockOverlay: View {
    @Binding var isAuthenticated: Bool
    @State private var errorMessage: String?
    @State private var showUnlock = false

    var body: some View {
        ZStack {
            TokensPalette.scrim.opacity(0.6)
                .ignoresSafeArea()

            DSCard(padding: TokensSpacing.lg, radius: TokensRadius.large) {
                VStack(spacing: TokensSpacing.lg) {
                    Image(systemName: "faceid")
                        .font(TokensTypo.fixed(60))
                        .foregroundStyle(TokensPalette.ambient)
                        .symbolEffect(.bounce)

                    Text("需要身份验证")
                        .font(TokensTypo.title2)
                        .foregroundStyle(TokensPalette.primary)

                    Text(errorMessage ?? "请使用 Face ID 或 Touch ID 验证身份")
                        .font(TokensTypo.body)
                        .foregroundStyle(TokensPalette.secondary)
                        .multilineTextAlignment(.center)

                    Button {
                        authenticate()
                    } label: {
                        Label("解锁", systemImage: "faceid")
                    }
                    .buttonStyle(DSPrimaryButtonStyle())
                }
                .frame(maxWidth: 320)
            }
            .frame(maxWidth: 320)
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
