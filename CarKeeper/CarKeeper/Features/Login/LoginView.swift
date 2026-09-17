import SwiftUI
import Combine

// 登录：手机号 + 图形验证码 + 短信验证码（60s 倒计时）
// 直连长安官方接口，无代理。

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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // 品牌
                    VStack(spacing: 6) {
                        Text("长安车管家")
                            .font(.system(size: 34, weight: .semibold))
                        Text("CHANGAN CONNECT")
                            .font(.system(size: 12, weight: .medium))
                            .tracking(3)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 40)

                    // 表单卡片
                    VStack(spacing: 16) {
                        TextField("手机号", text: $phone)
                            .keyboardType(.numberPad)
                            .onChange(of: phone) { _ in loadCaptcha() }

                        HStack(spacing: 12) {
                            TextField("图形验证码", text: $picCode)
                            if let img = UIImage(data: captchaData ?? Data()) {
                                Image(uiImage: img)
                                    .resizable()
                                    .frame(height: 40)
                                    .frame(width: 100)
                                    .background(Color(.systemGray6))
                                    .cornerRadius(6)
                                    .onTapGesture { loadCaptcha() }
                            } else {
                                Rectangle()
                                    .fill(Color(.systemGray6))
                                    .frame(height: 40)
                                    .frame(width: 100)
                                    .cornerRadius(6)
                                    .overlay(Text("点击刷新").font(.caption).foregroundStyle(.secondary))
                                    .onTapGesture { loadCaptcha() }
                            }
                        }

                        HStack(spacing: 12) {
                            TextField("6位短信验证码", text: $smsCode)
                                .keyboardType(.numberPad)
                            Button(smsBtnText) { sendSms() }
                                .buttonStyle(.borderedProminent)
                                .disabled(smsBtnDisabled)
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    .padding(20)
                    .background(Color(.systemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                    if !statusText.isEmpty {
                        Text(statusText)
                            .font(.system(size: 14))
                            .foregroundStyle(statusErr ? Color.red : Color.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button {
                        doLogin()
                    } label: {
                        Text(busy ? "登录中…" : "登 录")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(busy)
                    .padding(.top, 8)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("登录")
            .navigationBarTitleDisplayMode(.inline)
            .onReceive(countdownTimer) { _ in
                if countdown > 0 {
                    countdown -= 1
                    smsBtnText = "重新获取(\(countdown))"
                } else if countdown == 0 && smsBtnDisabled {
                    smsBtnDisabled = false
                    smsBtnText = "获取验证码"
                }
            }
            .onAppear { loadCaptcha() }
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

    @MainActor
    private func sendSms() {
        let trimmed = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !picCode.isEmpty else {
            showStatus("请填写手机号和图形验证码", isErr: true); return
        }
        Task { [store = AppStore.shared] in
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
        // Task 在 @MainActor 的 doLogin 里创建，继承 MainActor，直接改 @State 安全。
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
