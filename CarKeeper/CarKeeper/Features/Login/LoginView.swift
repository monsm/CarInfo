import SwiftUI
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
                    VStack(alignment: .leading, spacing: Kansei.Spacing.xxl) {
                        // 品牌区
                        brandHeader
                            .padding(.top, Kansei.Spacing.xxxl)

                        // 表单卡片
                        formCard

                        if !statusText.isEmpty {
                            DSNotice(
                                kind: statusErr ? .error : .success,
                                text: statusText
                            )
                        }

                        VStack(spacing: Kansei.Spacing.md) {
                            loginButton
                            if biometricAvailable {
                                biometricButton
                            }
                        }
                    }
                    .padding(.bottom, Kansei.Spacing.xxxl)
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
        VStack(alignment: .leading, spacing: Kansei.Spacing.lg) {
            HStack {
                Image(systemName: "car.side.fill")
                    .font(.system(size: 40, weight: .medium))
                    .foregroundColor(Kansei.Color.primary)
                    .frame(width: 80, height: 80)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Kansei.Color.ambient)
                    )
                    .shadow(color: Kansei.Color.ambient.opacity(0.4), radius: 12, y: 4)

                VStack(alignment: .leading, spacing: 4) {
                    Text("长安车管家")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(Kansei.Color.primary)
                    Text("CHANGAN CONNECT")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Kansei.Color.tertiary)
                        .tracking(2)
                }
                .padding(.leading, Kansei.Spacing.md)
            }

            Text("登录以管理您的爱车")
                .font(Kansei.Type.caption)
                .foregroundColor(Kansei.Color.secondary)
        }
    }

    // MARK: - 表单卡片
    private var formCard: some View {
        GlassCard {
            VStack(spacing: Kansei.Spacing.lg) {
                // 手机号输入
                VStack(alignment: .leading, spacing: Kansei.Spacing.xs) {
                    Text("手机号")
                        .font(Kansei.Type.caption)
                        .foregroundColor(Kansei.Color.secondary)
                    TextField("请输入手机号", text: $phone)
                        .keyboardType(.phonePad)
                        .foregroundColor(Kansei.Color.primary)
                        .font(Kansei.Type.subtitle)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: Kansei.Radius.small, style: .continuous)
                                .fill(Kansei.Color.glassLight)
                        )
                        .onChange(of: phone) { phone = String(phone.prefix(11)) }
                }
                .focused($focused, equals: .phone)

                DSDivider()

                // 图形验证码
                VStack(alignment: .leading, spacing: Kansei.Spacing.xs) {
                    Text("图形验证码")
                        .font(Kansei.Type.caption)
                        .foregroundColor(Kansei.Color.secondary)
                    HStack(spacing: Kansei.Spacing.sm) {
                        TextField("输入验证码", text: $picCode)
                            .foregroundColor(Kansei.Color.primary)
                            .font(Kansei.Type.subtitle)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: Kansei.Radius.small, style: .continuous)
                                    .fill(Kansei.Color.glassLight)
                            )

                        if let data = captchaData {
                            AsyncImage(data: data) { phase in
                                if let image = phase.image {
                                    image.resizable().aspectRatio(contentMode: .fit)
                                } else {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Kansei.Color.glassLight)
                                        .frame(width: 80, height: 40)
                                }
                            }
                            .frame(width: 80, height: 40)
                            .onTapGesture { loadCaptcha() }
                        }
                    }
                }
                .focused($focused, equals: .pic)

                DSDivider()

                // 短信验证码
                VStack(alignment: .leading, spacing: Kansei.Spacing.xs) {
                    Text("短信验证码")
                        .font(Kansei.Type.caption)
                        .foregroundColor(Kansei.Color.secondary)
                    HStack(spacing: Kansei.Spacing.sm) {
                        TextField("6位数字", text: $smsCode)
                            .keyboardType(.numberPad)
                            .foregroundColor(Kansei.Color.primary)
                            .font(Kansei.Type.hero)
                            .letterSpacing(8)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: Kansei.Radius.small, style: .continuous)
                                    .fill(Kansei.Color.glassLight)
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Button {
                            sendSMS()
                        } label: {
                            Text(smsBtnText)
                                .font(Kansei.Type.caption)
                                .foregroundColor(smsBtnDisabled ? Kansei.Color.tertiary : Kansei.Color.ambient)
                                .padding(.horizontal, Kansei.Spacing.md)
                                .padding(.vertical, Kansei.Spacing.sm)
                                .background(
                                    Kansei.Color.ambient.opacity(smsBtnDisabled ? 0.3 : 1)
                                )
                                .cornerRadius(Kansei.Radius.small)
                        }
                        .disabled(smsBtnDisabled)
                    }
                }
                .focused($focused, equals: .sms)
            }
            .padding(Kansei.Spacing.lg)
        }
    }

    // MARK: - 登录按钮
    private var loginButton: some View {
        Button {
            performLogin()
        } label: {
            HStack {
                if busy {
                    ProgressView().tint(.white)
                }
                Text(busy ? "登录中…" : "登录")
                    .font(Kansei.Type.title)
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Kansei.Spacing.lg)
            .background(Kansei.Color.ambient)
            .cornerRadius(Kansei.Radius.medium)
            .shadow(color: Kansei.Color.ambient.opacity(0.4), radius: 12, y: 4)
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
                    .font(Kansei.Type.subtitle)
                    .foregroundColor(Kansei.Color.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Kansei.Spacing.md)
            .background(Kansei.Color.glassHighlight)
            .cornerRadius(Kansei.Radius.medium)
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
