import SwiftUI
import UIKit
import Combine
import LocalAuthentication

// =============================================================================
// LoginView.swift — 登录（所有人看到的第一屏）
// =============================================================================
//
// 版面：与全 App 同一套语言 —— 画布 + 发丝线 + 字号层级，表单是 inset-grouped 分组。
//   • **不自己铺底**：旧版这里套了一层 `DSCanvas`（不透明的页面底色），而光在
//     App 根部只画一次 —— 那层底把光整个挡在门外，于是登录页成了全 App 唯一
//     「没有光」的一屏。原生主题本来就没有光，所以去掉它不影响原生。
//   • 表单是 **inset-grouped 分组**（iOS 设置 / 钱包的做法）：不再在卡片里再挖一层
//     填充输入框（那是两层容器说同一件事）。
//   • 一屏只有一个实心胶囊：登录。
//
// 逻辑：**这六个动作函数此前全是空壳** ——
//     `private func performLogin() { /* 保持原有逻辑 */ }`
//   也就是说登录按钮点了什么都不会发生（从 b3af51e 起被删掉，注释却还写着
//   「保持原有逻辑」）。这里按 b3af51e 的历史版本恢复，并保持与 APIClient /
//   AppStore 现有签名一致（`smsSend(phone:picCode:)` / `login(phone:smsCode:picCode:)`）。
//
// 顺带修掉一个一直没生效的东西：倒计时原先用 `Timer.publish(...).autoconnect()`
//   写成**计算属性** —— 每次视图求值都会新建一个定时器并重建订阅，倒计时因此
//   时灵时不灵。改成 Task 循环，取消时机明确（离开页面即取消）。
// =============================================================================

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
        .pageBackground()
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

    // =========================================================================
    // MARK: 品牌
    // =========================================================================

    /// 品牌区：衬线大字 + 疏排小字 + 一条发丝线。
    /// 没有图标砖、没有渐变、没有阴影 —— 第一屏的分量靠字号差，不靠装饰。
    private var brand: some View {
        VStack(alignment: .leading, spacing: TokensSpacing.sm) {
            Text("长安车管家")
                .font(TokensSerif.page(34))
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

    // =========================================================================
    // MARK: 凭据（inset-grouped 分组）
    // =========================================================================

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
                                // 协议里的手机号固定 11 位：多打的字直接不要
                                // （旧写法 `String(phone.prefix(11))` 同样只截断）
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

    /// 一行输入 = 小标签 + 输入框（标签在上，值在下；不做内嵌填充框）
    private func fieldColumn<Content: View>(_ label: String,
                                            @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(TokensTypo.caption)
                .foregroundStyle(TokensPalette.tertiary)
            content()
        }
        .frame(minHeight: TokensSpacing.row, alignment: .center)
    }

    /// 图形验证码。点一下换一张（服务端每次请求都出新图）。
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
            // 还没拿到图（或取图失败）：**说清状态**，不放一个假装是验证码的灰块
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

    // =========================================================================
    // MARK: 操作
    // =========================================================================

    /// 一屏唯一的实心胶囊 = 登录；其余都是次操作。
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
                // 说清为什么按钮是灰的，而不是让用户猜
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
            Text("登录走长安车联网接口（changan.com.cn）；密码不会被保存，控制用的 PIN 存在本机 Keychain。"
                 + "登录令牌存在本机，退出会清除。")
                .font(TokensTypo.caption)
                .foregroundStyle(TokensPalette.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // =========================================================================
    // MARK: - 逻辑（按 b3af51e 的历史版本恢复）
    // =========================================================================

    private func showStatus(_ msg: String, isErr: Bool) {
        statusText = msg
        statusErr = isErr
    }

    /// 倒计时用 Task 循环：取消时机明确，不会像计算属性里的 Timer 那样每次求值重建订阅。
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

    /// 取图形验证码（服务端按手机号出图）
    private func loadCaptcha() {
        let trimmed = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Task {
            if let data = await APIClient.shared.getPicCode(phone: trimmed) {
                captchaData = data
            }
        }
    }

    /// 发短信验证码。返回「无记录」时必须刷新图形验证码 —— 那是服务端的语义，
    /// 不是失败：直接重试会一直撞同一堵墙。
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

    /// 登录：成功后写入令牌状态并 bootstrap（与旧版一致）
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

    /// 生物识别只证明「是本人」—— 它**不换新令牌**：进去之后能不能拉到数据，
    /// 仍由本机已存的令牌决定（令牌失效时会在数据层拿不到东西，不会假装成功）。
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
