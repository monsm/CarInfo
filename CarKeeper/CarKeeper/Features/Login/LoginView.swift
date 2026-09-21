import SwiftUI
import UIKit
import Combine
import LocalAuthentication

struct LoginView: View {
    @State private var phone: String = ""
    @State private var picCode: String = ""
    @State private var smsCode: String = ""
    @State private var captchaData: Data? = nil
    @State private var statusText: String = ""
    @State private var statusErr: Bool = false
    @State private var busy: Bool = false
    @State private var smsBtnDisabled: Bool = false
    @State private var smsBtnText: String = "获取验证码"
    @State private var countdown: Int = 0
    @State private var biometricAvailable = false
    @State private var biometricAuthPending = false
    @State private var showBiometricPrompt = false

    private enum Field: Hashable { case phone, pic, sms }
    @FocusState private var focused: Field?

    private var countdownTimer: Publishers.Autoconnect<Timer.TimerPublisher> {
        Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    }

    private var phoneValid: Bool { phone.trimmingCharacters(in: .whitespaces).count >= 11 }
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        NavigationStack {
            DSCanvas {
                ScrollView {
                    VStack(alignment: .leading, spacing: TokensSpacing.xxl) {
                        // 品牌区
                        brandHeader
                            .padding(.top, TokensSpacing.xxxl)

                        // 表单卡片
                        formCard

                        if !statusText.isEmpty {
                            DSNotice(
                                kind: statusErr ? .error : .success,
                                text: statusText
                            )
                        }

                        VStack(spacing: TokensSpacing.md) {
                            loginButton
                            if biometricAvailable {
                                biometricButton
                            }
                        }
                    }
                    .padding(.bottom, TokensSpacing.xxxl)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollDismissesKeyboard(.interactively)
                .onReceive(countdownTimer) { _ in
                    if countdown > 0 {
                        countdown -= 1
                        smsBtnText = "\(countdown)s"
                    } else if countdown == 0 && smsBtnDisabled {
                        smsBtnDisabled = false
                        smsBtnText = "获取验证码"
                    }
                }
                .onAppear { loadCaptcha(); checkBiometric() }
                .alert("生物识别登录", isPresented: $showBiometricPrompt) {
                    Button("取消") { showBiometricPrompt = false }
                    Button("确认登录") {
                        Task { await biometricLogin() }
                    }
                } message: {
                    Text("使用 Face ID / Touch ID 快速登录")
                }
            }
        }
    }

    // MARK: - 品牌区
    private var brandHeader: some View {
        VStack(alignment: .leading, spacing: TokensSpacing.lg) {
            HStack {
                Image(systemName: "car.side.fill")
                    .font(.system(size: 40, weight: .medium))
                    .foregroundColor(TokensPalette.primary)
                    .frame(width: 80, height: 80)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(TokensPalette.ambient)
                    )
                    .shadow(color: TokensPalette.ambient.opacity(0.4), radius: 12, y: 4)

                VStack(alignment: .leading, spacing: 4) {
                    Text("长安车管家")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(TokensPalette.primary)
                    Text("CHANGAN CONNECT")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(TokensPalette.tertiary)
                        .tracking(2)
                }
                .padding(.leading, TokensSpacing.md)
            }

            Text("登录以管理您的爱车")
                .font(TokensTypo.caption)
                .foregroundColor(TokensPalette.secondary)
        }
    }

    // MARK: - 表单卡片
    // 这里原本是 `GlassCard { … }` —— 那个类型在清理设计文件时被误判为「零引用」删掉了
    // （grep 只看了 `GlassCard(` 这类写法，漏了「类型名 + 尾随闭包」这种容器用法）。
    // 改用 v4 的 DSCard：不透明表面，padding 交给内层 VStack 自己控制。
    private var formCard: some View {
        DSCard(padding: 0, radius: TokensRadius.large) {
            VStack(spacing: TokensSpacing.lg) {
                // 手机号输入
                VStack(alignment: .leading, spacing: TokensSpacing.xs) {
                    Text("手机号")
                        .font(TokensTypo.caption)
                        .foregroundColor(TokensPalette.secondary)
                    TextField("请输入手机号", text: $phone)
                        .keyboardType(.phonePad)
                        .foregroundColor(TokensPalette.primary)
                        .font(TokensTypo.subtitle)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: TokensRadius.small, style: .continuous)
                                .fill(TokensPalette.glassLight)
                        )
                        .onChange(of: phone) { phone = String(phone.prefix(11)) }
                }
                .focused($focused, equals: .phone)

                DSDivider()

                // 图形验证码
                VStack(alignment: .leading, spacing: TokensSpacing.xs) {
                    Text("图形验证码")
                        .font(TokensTypo.caption)
                        .foregroundColor(TokensPalette.secondary)
                    HStack(spacing: TokensSpacing.sm) {
                        TextField("输入验证码", text: $picCode)
                            .foregroundColor(TokensPalette.primary)
                            .font(TokensTypo.subtitle)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: TokensRadius.small, style: .continuous)
                                    .fill(TokensPalette.glassLight)
                            )

                        if let data = captchaData, let captcha = UIImage(data: data) {
                            Image(uiImage: captcha)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 80, height: 40)
                                .onTapGesture { loadCaptcha() }
                        } else {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(TokensPalette.glassLight)
                                .frame(width: 80, height: 40)
                                .onTapGesture { loadCaptcha() }
                        }
                    }
                }
                .focused($focused, equals: .pic)

                DSDivider()

                // 短信验证码
                VStack(alignment: .leading, spacing: TokensSpacing.xs) {
                    Text("短信验证码")
                        .font(TokensTypo.caption)
                        .foregroundColor(TokensPalette.secondary)
                    HStack(spacing: TokensSpacing.sm) {
                        TextField("6位数字", text: $smsCode)
                            .keyboardType(.numberPad)
                            .foregroundColor(TokensPalette.primary)
                            .font(TokensTypo.hero)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: TokensRadius.small, style: .continuous)
                                    .fill(TokensPalette.glassLight)
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Button {
                            sendSMS()
                        } label: {
                            Text(smsBtnText)
                                .font(TokensTypo.caption)
                                .foregroundColor(smsBtnDisabled ? TokensPalette.tertiary : TokensPalette.ambient)
                                .padding(.horizontal, TokensSpacing.md)
                                .padding(.vertical, TokensSpacing.sm)
                                .background(
                                    TokensPalette.ambient.opacity(smsBtnDisabled ? 0.3 : 1)
                                )
                                .cornerRadius(TokensRadius.small)
                        }
                        .disabled(smsBtnDisabled)
                    }
                }
                .focused($focused, equals: .sms)
            }
            .padding(TokensSpacing.lg)
        }
    }

    // MARK: - 登录按钮
    private var loginButton: some View {
        Button {
            performLogin()
        } label: {
            HStack {
                if busy {
                    ProgressView().tint(TokensPalette.labelOnTint)
                }
                Text(busy ? "登录中…" : "登录")
                    .font(TokensTypo.heading)
                    .foregroundColor(TokensPalette.labelOnTint)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, TokensSpacing.lg)
            .background(TokensPalette.ambient)
            .cornerRadius(TokensRadius.medium)
            .shadow(color: TokensPalette.ambient.opacity(0.4), radius: 12, y: 4)
        }
        .buttonStyle(.plain)
        .disabled(busy || !phoneValid)
    }

    // MARK: - 生物识别按钮
    private var biometricButton: some View {
        Button {
            showBiometricPrompt = true
        } label: {
            HStack {
                Image(systemName: "faceid")
                Text("Face ID 登录")
                    .font(TokensTypo.subtitle)
                    .foregroundColor(TokensPalette.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, TokensSpacing.md)
            .background(TokensPalette.glassHighlight)
            .cornerRadius(TokensRadius.medium)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 操作方法
    private func loadCaptcha() { /* 保持原有逻辑 */ }
    private func sendSMS() { /* 保持原有逻辑 */ }
    private func performLogin() { /* 保持原有逻辑 */ }
    private func checkBiometric() { /* 保持原有逻辑 */ }
    private func biometricLogin() async { /* 保持原有逻辑 */ }
}
