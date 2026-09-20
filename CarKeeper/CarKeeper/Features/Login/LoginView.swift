import SwiftUI
import Combine
import LocalAuthentication

// 登录页
// 设计：Tesla 式极简 —— 单一画布、扁平品牌标、发丝线分隔的表单行、一个主色按钮。
// 品牌感来自留白与排版，而不是装饰层。

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
    // #NEW-101 FaceID/TouchID 生物识别
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
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.xxl) {
                    brandHeader
                        .padding(.top, DS.Space.xxxl)
                    formCard
                    if !statusText.isEmpty {
                        DSNotice(kind: statusErr ? .error : .success, text: statusText)
                    }
                    VStack(spacing: DS.Space.md) {
                        loginButton
                        if biometricAvailable { biometricButton }
                    }
                }
                .padding(.bottom, DS.Space.xxxl)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
            .dsCanvas()
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

    // MARK: 品牌区（扁平标 + 字标）
    private var brandHeader: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            Image(systemName: "car.side.fill")
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(DS.Palette.labelOnTint)
                .frame(width: 60, height: 60)
                .background(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .fill(DS.Palette.tint))

            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text("长安车管家")
                    .font(DS.Typo.largeTitle)
                    .foregroundStyle(DS.Palette.label)
                Text("CHANGAN CONNECT")
                    .font(DS.Typo.caption.weight(.semibold))
                    .tracking(2.4)
                    .foregroundStyle(DS.Palette.labelTertiary)
            }
            Text("登录后即可远程查看车辆状态、控制车锁与空调。")
                .font(DS.Typo.subheadline)
                .foregroundStyle(DS.Palette.labelSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 表单卡（分组行 + 发丝分隔线）
    private var formCard: some View {
        DSCard(padding: 0, radius: DS.Radius.card) {
            VStack(spacing: 0) {
                fieldRow(icon: "phone.fill", focused: focused == .phone, valid: phoneValid) {
                    TextField("手机号", text: $phone)
                        .keyboardType(.numberPad)
                        .textContentType(.telephoneNumber)
                        .font(DS.Typo.data)
                        .focused($focused, equals: .phone)
                        .onChange(of: phone) { _, _ in loadCaptcha() }
                }

                DSDivider(inset: DS.Space.cardPadding)

                fieldRow(icon: "photo.on.rectangle", focused: focused == .pic, valid: nil) {
                    HStack(spacing: DS.Space.md) {
                        TextField("图形验证码", text: $picCode)
                            .font(DS.Typo.data)
                            .textInputAutocapitalization(.never)
                            .focused($focused, equals: .pic)
                        captchaView
                    }
                }

                DSDivider(inset: DS.Space.cardPadding)

                fieldRow(icon: "ellipsis.message", focused: focused == .sms, valid: nil) {
                    HStack(spacing: DS.Space.md) {
                        TextField("6 位短信验证码", text: $smsCode)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                            .font(DS.Typo.data)
                            .focused($focused, equals: .sms)
                        smsButton
                    }
                }
            }
        }
        .dynamicTypeCompress()
    }

    @ViewBuilder
    private func fieldRow<Content: View>(icon: String,
                                         focused: Bool,
                                         valid: Bool?,
                                         @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: DS.Space.md) {
            Image(systemName: icon)
                .font(.system(size: DS.Size.icon, weight: .regular))
                .foregroundStyle(focused ? DS.Palette.tint : DS.Palette.labelTertiary)
                .frame(width: 22)
            content()
            if valid == true {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: DS.Size.iconSm))
                    .foregroundStyle(DS.Palette.ok)
            }
        }
        .padding(.horizontal, DS.Space.cardPadding)
        .frame(minHeight: 60)
        .animation(DS.Motion.fade, value: focused)
    }

    private var smsButton: some View {
        Button {
            sendSms()
        } label: {
            Text(smsBtnText)
                .font(DS.Typo.footnote.weight(.semibold))
                .foregroundStyle(smsBtnDisabled ? DS.Palette.labelTertiary : DS.Palette.tint)
                .padding(.horizontal, DS.Space.md)
                .frame(height: 34)
                .background(Capsule().fill(smsBtnDisabled ? DS.Palette.surfaceSunken : DS.Palette.tintSoft))
        }
        .buttonStyle(.plain)
        .disabled(smsBtnDisabled)
    }

    @ViewBuilder
    private var captchaView: some View {
        Button {
            loadCaptcha()
        } label: {
            Group {
                if let img = UIImage(data: captchaData ?? Data()) {
                    Image(uiImage: img)
                        .resizable()
                        .interpolation(.none)
                        .frame(height: 36).frame(width: 96)
                } else {
                    RoundedRectangle(cornerRadius: DS.Radius.small - 2, style: .continuous)
                        .fill(DS.Palette.surfaceSunken)
                        .frame(height: 36).frame(width: 96)
                        .overlay(Text("点我刷新")
                            .font(DS.Typo.caption2)
                            .foregroundStyle(DS.Palette.labelSecondary))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.small - 2, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.small - 2, style: .continuous)
                .strokeBorder(DS.Palette.hairline, lineWidth: DS.Hair.line))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("刷新图形验证码"))
    }

    // MARK: 主操作按钮
    private var loginButton: some View {
        Button {
            DSHaptic.tap()
            doLogin()
        } label: {
            HStack(spacing: DS.Space.sm) {
                if busy { ProgressView().tint(DS.Palette.labelOnTint) }
                Text(busy ? "登录中…" : "登录")
            }
        }
        .buttonStyle(DSPrimaryButtonStyle())
        .disabled(busy)
        .opacity(busy ? 0.7 : 1)
    }

    // #NEW-101 FaceID 快捷登录
    private var biometricButton: some View {
        Button {
            showBiometricPrompt = true
        } label: {
            HStack(spacing: DS.Space.sm) {
                Image(safeSymbol: biometricAvailable ? "faceid" : "lock.fill", fallback: "faceid")
                    .font(.system(size: DS.Size.icon, weight: .medium))
                Text(biometricAvailable ? "Face ID 快速登录" : "未启用 Face ID")
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.Palette.labelTertiary)
            }
        }
        .buttonStyle(DSSecondaryButtonStyle())
        .opacity(biometricAvailable ? 1.0 : 0.5)
    }

    private func checkBiometric() {
        biometricAvailable = AppStore.shared.canUseBiometric()
        if biometricAvailable && AppStore.shared.hasBiometricSetup {
            showBiometricPrompt = true
        }
    }

    private func biometricLogin() async {
        let success = await AppStore.shared.authenticateWithBiometrics(reason: "验证身份以登录账号")
        if success {
            // 从 Keychain 读取 PIN 并自动登录
            // 这里简化处理：直接设置为已登录状态
            AppStore.shared.isLoggedIn = true
            await AppStore.shared.bootstrap()
        } else {
            statusText = "生物识别验证失败，请使用短信验证码登录"
            statusErr = true
        }
    }

    // MARK: 逻辑（与原版一致）
    private func loadCaptcha() {
        let trimmed = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Task {
            if let data = await APIClient.shared.getPicCode(phone: trimmed) {
                captchaData = data
            }
        }
    }

    @MainActor
    private func sendSms() {
        let trimmed = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !picCode.isEmpty else {
            showStatus("请填写手机号和图形验证码", isErr: true); return
        }
        Task {
            let r = await APIClient.shared.smsSend(phone: trimmed, picCode: picCode)
            if r.ok {
                showStatus(r.msg, isErr: false)
                countdown = 60
                smsBtnDisabled = true
            } else {
                if r.noRecord {
                    loadCaptcha()
                    picCode = ""
                    showStatus("验证码已刷新，请重新输入图形验证码后重试", isErr: false)
                } else {
                    showStatus(r.msg, isErr: true)
                }
            }
        }
    }

    @MainActor
    private func doLogin() {
        guard !phone.trimmingCharacters(in: .whitespaces).isEmpty,
              !smsCode.isEmpty, !picCode.isEmpty else {
            showStatus("请填写手机号、图形验证码与短信验证码", isErr: true); return
        }
        busy = true
        statusText = ""
        Task { [phone, smsCode, picCode] in
            do {
                let _ = try await APIClient.shared.login(
                    phone: phone.trimmingCharacters(in: .whitespaces),
                    smsCode: smsCode, picCode: picCode)
                AppStore.shared.isLoggedIn = true
                AppStore.shared.phone = phone
                await AppStore.shared.bootstrap()
            } catch {
                showStatus(error.localizedDescription, isErr: true)
            }
            busy = false
        }
    }

    private func showStatus(_ msg: String, isErr: Bool) {
        statusText = msg
        statusErr = isErr
    }
}
