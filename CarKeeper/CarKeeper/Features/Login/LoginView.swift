import SwiftUI
import Combine

// 登录：手机号 + 图形验证码 + 短信验证码（60s 倒计时）
// iOS 27 视觉：品牌区 + 玻璃表单卡 + 渐变登录大按钮，直连长安官方接口。

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

    private var countdownTimer: Publishers.Autoconnect<Timer.TimerPublisher> {
        Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    }

    private var phoneValid: Bool { phone.trimmingCharacters(in: .whitespaces).count >= 11 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    brandHeader
                        .padding(.top, 56)
                    formCard
                    if !statusText.isEmpty { statusBanner }
                    loginButton
                    Spacer(minLength: 12)
                }
                .padding(16)
                .safeAreaPadding(.bottom, 12)
            }
            .scrollBounceBehavior(.basedOnSize)
            .pageBackground(.accentColor)
            .navBarStyle()
            .onReceive(countdownTimer) { _ in
                if countdown > 0 {
                    countdown -= 1
                    smsBtnText = "\(countdown)s"
                } else if countdown == 0 && smsBtnDisabled {
                    smsBtnDisabled = false
                    smsBtnText = "获取验证码"
                }
            }
            .onAppear { loadCaptcha() }
        }
    }

    // MARK: 品牌区 — Apple Store Style
    private var brandHeader: some View {
        VStack(spacing: 16) {
            ZStack {
                // 外发光层
                Circle()
                    .fill(AngularGradient(colors: [Color.accentColor.opacity(0.25), Color.accentColor.opacity(0.05)],
                                          center: .center, startAngle: .degrees(-90), endAngle: .degrees(270)))
                    .frame(width: 108, height: 108)
                // 主体圆
                Circle()
                    .fill(LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.65)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 92, height: 92)
                    .shadow(color: Color.accentColor.opacity(0.4), radius: 20, y: 8)
                // 图标
                Image(systemName: "car.side.fill")
                    .font(Theme.d3) weight: .medium))
                    .foregroundStyle(.white)
            }
            VStack(spacing: 6) {
                Text("长安车管家")
                    .font(Theme.h1)
                    .letterSpacing(2)
                Text("CHANGAN CONNECT")
                    .font(Theme.footnote.bold())))
                    .tracking(5)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: 表单玻璃卡
    private var formCard: some View {
        VStack(spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "phone.fill")
                    .font(Theme.body))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 24)
                TextField("手机号", text: $phone)
                    .keyboardType(.numberPad)
                    .font(.title.design(.rounded)))
                    .onChange(of: phone) { _, _ in loadCaptcha() }
                if phoneValid {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.ok)
                        .font(Theme.body))
                }
            }
            ListDivider()
            HStack(spacing: 12) {
                Image(systemName: "photo.on.rectangle")
                    .font(Theme.body))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 24)
                TextField("图形验证码", text: $picCode)
                    .font(.title.design(.rounded)))
                captchaView
            }
            ListDivider()
            HStack(spacing: 12) {
                Image(systemName: "message.badge.fill")
                    .font(Theme.body))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 24)
                TextField("6 位短信验证码", text: $smsCode)
                    .keyboardType(.numberPad)
                    .font(.title.design(.rounded)))
                smsButton
            }
        }
        .padding(Theme.Spacing.xl)
        .glassCard()
    }

    private var smsButton: some View {
        Button {
            sendSms()
        } label: {
            Text(smsBtnText)
                .font(Theme.caption.bold())))
                .foregroundStyle(smsBtnDisabled ? Color.secondary : Color.accentColor)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(.thin, in: Capsule())
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
                        .frame(height: 40).frame(width: 104)
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.tertiarySystemFill))
                        .frame(height: 40).frame(width: 104)
                        .overlay(Text("点我刷新").font(Theme.footnote)).foregroundStyle(.secondary))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: 状态条
    @ViewBuilder
    private var statusBanner: some View {
        if !statusText.isEmpty {
            Label(statusText, systemImage: statusErr ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                .font(Theme.caption))
                .foregroundStyle(statusErr ? Theme.bad : Theme.ok)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.thin, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    // MARK: 登录按钮
    private var loginButton: some View {
        Button {
            doLogin()
        } label: {
            HStack(spacing: 8) {
                if busy { ProgressView().tint(.white) }
                Text(busy ? "登录中…" : "登 录")
                    .font(.title.weight(.bold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.72)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .shadow(color: Color.accentColor.opacity(0.4), radius: 16, y: 6)
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .padding(.top, 4)
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
