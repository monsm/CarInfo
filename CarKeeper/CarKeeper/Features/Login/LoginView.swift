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
    @State private var countdownTask: Task<Void, Never>? = nil
    @State private var biometricAvailable = false
    @State private var biometricAuthPending = false
    @State private var showBiometricPrompt = false

    private enum Field: Hashable { case phone, pic, sms }
    @FocusState private var focused: Field?

    private var phoneValid: Bool { phone.trimmingCharacters(in: .whitespaces).count >= 11 }
    private var canSubmit: Bool { phoneValid && !picCode.isEmpty && !smsCode.isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TokensSpacing.xxl) {
                brand
                creditionalsGroup
                if !statusText.isEmpty {
                    DSNotice(kind: statusErr ? .error : .success, text: statusText)
                }
                actions
                footer
            }
            .padding(.horizontal, TokensSpacing.page)
            .padding(.top, TokensSpacing.xxxl)
            .padding(.bottom, TokensSpacing.xxxl)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .onAppear { loadCaptcha(); checkBiometric() }
        .onDisappear { countdownTask?.cancel() }
        .alert("生物识别登录", isPresented: $showBiometricPrompt) {
            Button("取消", role: .cancel) { showBiometricPrompt = false }
            Button("确认登录") {
                Task { await biometricLogin() }
            }
        } message: {
            Text("使用 Face ID / Touch ID 快速登录")
        }
    }


    private var brand: some View {
        VStack(alignment: .leading, spacing: TokensSpacing.sm) {
            Text("长安车管家")
                .font(TokensTypo.fixed(34, weight: .semibold))
                .tracking(TokensTracking.title)
                .foregroundStyle(TokensPalette.primary)
            Text("CHANGAN CONNECT")
                .font(TokensTypo.caption)
                .tracking(TokensTracking.label)
                .foregroundStyle(TokensPalette.tertiary)
            Text("登录后可以看位置、电量和续航。")
                .font(TokensTypo.footnote)
                .foregroundStyle(TokensPalette.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, TokensSpacing.xs)
                .padding(.bottom, TokensSpacing.sm)
            DSDivider()
        }
    }


    private var creditionalsGroup: some View {
        DSGroup(title: "登录信息") {
            DSGroupRow {
                HStack(alignment: .center, spacing: TokensSpacing.md) {
                    fieldColumn("手机号") {
                        TextField("11 位手机号", text: $phone)
                            .keyboardType(.phonePad)
                            .textContentType(.telephoneNumber)
                            .font(TokensTypo.subtitle)
                            .foregroundStyle(TokensPalette.primary)
                            .onChange(of: phone) { _, new in
                                if new.count > 11 { phone = String(new.prefix(11)) }
                            }
                    }
                    .focused($focused, equals: .phone)
                    if phoneValid {
                        Image(safeSymbol: "checkmark.circle.fill", fallback: "checkmark.circle.fill")
                            .font(TokensTypo.fixed(15))
                            .foregroundStyle(TokensPalette.success)
                            .accessibilityHidden(true)
                    }
                }
            }

            DSGroupRow {
                HStack(alignment: .center, spacing: TokensSpacing.md) {
                    fieldColumn("图形验证码") {
                        TextField("输入图中字符", text: $picCode)
                            .font(TokensTypo.subtitle)
                            .foregroundStyle(TokensPalette.primary)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                    .focused($focused, equals: .pic)

                    captchaView
                }
            }

            DSGroupRow(showsSeparator: false) {
                HStack(alignment: .center, spacing: TokensSpacing.md) {
                    fieldColumn("短信验证码") {
                        TextField("6 位数字", text: $smsCode)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                            .font(TokensTypo.subtitle)
                            .foregroundStyle(TokensPalette.primary)
                    }
                    .focused($focused, equals: .sms)

                    Button { sendSMS() } label: {
                        Text(smsBtnText)
                            .font(TokensTypo.subheadline.weight(.semibold))
                            .foregroundStyle(smsBtnDisabled ? TokensPalette.tertiary : TokensPalette.accent)
                            .padding(.horizontal, TokensSpacing.sm)
                            .frame(minHeight: TokensSize.tap)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(smsBtnDisabled || phone.isEmpty || picCode.isEmpty)
                }
            }
        }
        .disabled(busy)
    }

    private func fieldColumn<Content: View>(_ label: String,
                                            @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: TokensSpacing.xxs) {
            Text(label)
                .font(TokensTypo.caption)
                .foregroundStyle(TokensPalette.tertiary)
            content()
        }
        .frame(minHeight: TokensSpacing.row, alignment: .center)
    }

    @ViewBuilder
    private var captchaView: some View {
        if let data = captchaData, let captcha = UIImage(data: data) {
            Image(uiImage: captcha)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 84, height: 40)
                .onTapGesture { loadCaptcha() }
                .accessibilityLabel(Text("图形验证码，点一下换一张"))
        } else {
            Button { loadCaptcha() } label: {
                Text(phone.isEmpty ? "先填手机号" : "取图失败 · 重试")
                    .font(TokensTypo.caption)
                    .foregroundStyle(TokensPalette.tertiary)
                    .frame(width: 84, height: 40)
                    .overlay {
                        RoundedRectangle(cornerRadius: TokensRadius.small, style: .continuous)
                            .strokeBorder(TokensPalette.hairline, lineWidth: TokensHair.line)
                    }
            }
            .buttonStyle(.plain)
            .disabled(phone.isEmpty)
        }
    }


    private var actions: some View {
        VStack(spacing: TokensSpacing.md) {
            Button { performLogin() } label: {
                HStack(spacing: TokensSpacing.sm) {
                    if busy { ProgressView().tint(TokensPalette.labelOnTint) }
                    Text(busy ? "登录中…" : "登录")
                }
            }
            .buttonStyle(DSPrimaryButtonStyle())
            .disabled(busy || !canSubmit)
            .opacity(canSubmit ? 1 : 0.45)

            if biometricAvailable {
                Button { showBiometricPrompt = true } label: {
                    Label("用 Face ID 登录", systemImage: "faceid")
                }
                .buttonStyle(DSSecondaryButtonStyle())
                .disabled(busy)
            }

            if !canSubmit {
                Text(loginBlocker())
                    .font(TokensTypo.caption)
                    .foregroundStyle(TokensPalette.tertiary)
            }
        }
    }

    private func loginBlocker() -> String {
        if !phoneValid { return "填满 11 位手机号才能登录" }
        if picCode.isEmpty { return "还需要图形验证码" }
        return "还需要短信验证码"
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: TokensSpacing.sm) {
            DSDivider()
            Text("登录走长安车联网；密码不保存，控制 PIN 存在本机。"
                 + "退出登录会清除令牌。")
                .font(TokensTypo.caption)
                .foregroundStyle(TokensPalette.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }


    private func showStatus(_ msg: String, isErr: Bool) {
        statusText = msg
        statusErr = isErr
    }

    private func startCountdown() {
        countdown = 60
        smsBtnDisabled = true
        smsBtnText = "\(countdown)s"
        countdownTask?.cancel()
        countdownTask = Task {
            while !Task.isCancelled, countdown > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                countdown -= 1
                smsBtnText = countdown > 0 ? "\(countdown)s" : "获取验证码"
                if countdown == 0 { smsBtnDisabled = false }
            }
        }
    }

    private func loadCaptcha() {
        let trimmed = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Task {
            if let data = await APIClient.shared.getPicCode(phone: trimmed) {
                captchaData = data
            }
        }
    }

    private func sendSMS() {
        let trimmed = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !picCode.isEmpty else {
            showStatus("请填写手机号和图形验证码", isErr: true)
            return
        }
        Task {
            let r = await APIClient.shared.smsSend(phone: trimmed, picCode: picCode)
            if r.ok {
                showStatus(r.msg, isErr: false)
                startCountdown()
            } else if r.noRecord {
                loadCaptcha()
                picCode = ""
                showStatus("验证码已刷新，请重新输入", isErr: false)
            } else {
                showStatus(r.msg, isErr: true)
            }
        }
    }

    private func performLogin() {
        let trimmedPhone = phone.trimmingCharacters(in: .whitespaces)
        guard !trimmedPhone.isEmpty, !smsCode.isEmpty, !picCode.isEmpty else {
            showStatus("请填写手机号与两个验证码", isErr: true)
            return
        }
        busy = true
        statusText = ""
        Task { [trimmedPhone, smsCode, picCode] in
            do {
                _ = try await APIClient.shared.login(phone: trimmedPhone,
                                                     smsCode: smsCode,
                                                     picCode: picCode)
                AppStore.shared.isLoggedIn = true
                AppStore.shared.phone = phone
                await AppStore.shared.bootstrap()
            } catch {
                showStatus(error.localizedDescription, isErr: true)
            }
            busy = false
        }
    }

    private func checkBiometric() {
        biometricAvailable = AppStore.shared.canUseBiometric()
        if biometricAvailable && AppStore.shared.hasBiometricSetup {
            showBiometricPrompt = true
        }
    }

    private func biometricLogin() async {
        biometricAuthPending = true
        let success = await AppStore.shared.authenticateWithBiometrics(reason: "验证身份以登录账号")
        biometricAuthPending = false
        if success {
            AppStore.shared.isLoggedIn = true
            await AppStore.shared.bootstrap()
        } else {
            showStatus("验证失败，请用短信验证码登录", isErr: true)
        }
    }
}
