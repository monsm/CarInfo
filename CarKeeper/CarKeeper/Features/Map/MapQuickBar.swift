import SwiftUI

// =============================================================================
// 地图上的常驻操作条（批 1）
//
// 为什么它必须存在：批 0 拆掉 Tab 栏之后，「锁车」从「点锁车」变成了
// 「索引页 → 车控 → 点锁车」—— 为了一个动作离开车所在的这张图，是退步。
// 答案不是把 Tab 栏加回来，而是：车就在眼前时，锁车不该需要离开这张图。
//
// 执行路径与车控页**完全相同**（`CommandCenter`）：验身份 → 发指令 → 等回执。
// 这里只负责两件事 —— 在哪里发起、怎么显示进度。
//
// 身份验证有两道，两样都要，不是重复：
//   · Face ID / Touch ID：证明「是本人」；
//   · 控车码（PIN）：车端协议要求的参数，`sendControlCommand(pin:)` 直接带它下发。
// =============================================================================

struct MapQuickBar: View {
    private let store = AppStore.shared
    @ObservedObject private var commands = CommandCenter.shared

    /// 高频四件事。**顺序就是频率**：锁车在最左（拇指最容易够到）。
    private struct QuickAction: Identifiable {
        let cmd: String
        let title: String
        let icon: String
        var id: String { cmd }
    }

    private static let actions: [QuickAction] = [
        QuickAction(cmd: "LockDoor", title: "锁车", icon: "lock.fill"),
        QuickAction(cmd: "UnLockDoor", title: "解锁", icon: "lock.open.fill"),
        QuickAction(cmd: "OpenAir", title: "空调", icon: "snowflake"),
        QuickAction(cmd: "RemoteSearchCar", title: "寻车", icon: "location")
    ]

    @State private var pendingCmd = ""
    @State private var pendingTitle = ""
    @State private var pendingTemp = 24
    @State private var showTemp = false
    @State private var showPin = false
    @State private var showBio = false
    @State private var isAuthenticated = false

    var body: some View {
        Group {
            if store.carId.isEmpty {
                // 没选车时不摆四个按不动的灰块 —— 说清为什么现在不能用
                Text("还没选择车辆，快捷操作要等选好车之后才能用。")
                    .font(TokensTypo.caption)
                    .foregroundStyle(TokensPalette.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, TokensSpacing.sm + 2)
                    .frame(height: 40)
                    .background { Capsule().fill(TokensPalette.surface.opacity(0.94)) }
            } else if let run = commands.running {
                runningStrip(run)
            } else {
                row
            }
        }
        .padding(.horizontal, TokensSpacing.page)
        .padding(.bottom, TokensSpacing.sm)
        .animation(TokensMotion.tap, value: commands.running?.id)
        .sheet(isPresented: $showTemp) { tempSheet }
        .sheet(isPresented: $showPin) { pinSheet }
        .overlay { biometricOverlay }
    }

    // MARK: - 静息态：四个动作

    private var row: some View {
        HStack(spacing: TokensSpacing.sm) {
            ForEach(Self.actions) { item in
                Button {
                    begin(item.cmd, title: item.title)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: item.icon)
                            .font(.system(size: TokensSize.iconSm, weight: .semibold))
                        Text(item.title)
                            .font(TokensTypo.caption)
                            .tracking(TokensTracking.label)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background { Capsule().fill(TokensPalette.surface.opacity(0.94)) }
                    .overlay {
                        Capsule().strokeBorder(TokensPalette.hairline, lineWidth: TokensHair.line)
                    }
                    .foregroundStyle(TokensPalette.primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(item.title))
                .accessibilityHint(Text("在地图上直接下发指令，不会离开地图"))
            }
        }
    }

    // MARK: - 执行态：条子变成那条指令本身

    /// 指令在跑的时候，这一条**变成那条指令**：名字 + 到哪一步了。
    /// 不做全屏遮罩 —— 车就在地图上，发指令时还应该看得见它。
    private func runningStrip(_ run: ControlRun) -> some View {
        HStack(spacing: TokensSpacing.sm) {
            ProgressView()
                .controlSize(.small)
            Text(run.name)
                .font(TokensTypo.caption)
                .foregroundStyle(TokensPalette.primary)
            Text(run.progress.isEmpty ? "已发出，等车辆回执" : run.progress)
                .font(TokensTypo.caption)
                .foregroundStyle(TokensPalette.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            Text(run.startedAt)
                .font(TokensTypo.digits(12))
                .foregroundStyle(TokensPalette.tertiary)
        }
        .padding(.horizontal, TokensSpacing.md)
        .frame(height: 40)
        .frame(maxWidth: .infinity)
        .background { Capsule().fill(TokensPalette.surface.opacity(0.94)) }
        .overlay { Capsule().strokeBorder(TokensPalette.hairline, lineWidth: TokensHair.line) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(run.name) 正在执行"))
    }

    // MARK: - 身份验证

    @ViewBuilder
    private var tempSheet: some View {
        ACStepperView(initialTemp: $pendingTemp)
            .onReceive(NotificationCenter.default.publisher(for: .tempConfirmed)) { note in
                if let t = note.object as? Int {
                    pendingTemp = t
                    showTemp = false
                    showPin = true
                }
            }
            .dsSheetCanvas()
    }

    @ViewBuilder
    private var pinSheet: some View {
        PINKeypadView()
            .onReceive(NotificationCenter.default.publisher(for: .pinConfirmed)) { note in
                if let pin = note.object as? String {
                    showPin = false
                    // 第一次输入控车码就顺手存进 Keychain —— 用户第一次下发指令的地方
                    // 很可能就是这张地图，而不是车控页（与车控页同一套行为）
                    if store.readPin() == nil {
                        store.savePin(pin)
                        EnhancedToastManager.shared.show("PIN码已安全保存", icon: "key.fill")
                    }
                    send(pin)
                }
            }
            .dsSheetCanvas()
    }

    @ViewBuilder
    private var biometricOverlay: some View {
        if showBio {
            BiometricLockOverlay(isAuthenticated: $isAuthenticated)
                .onAppear { isAuthenticated = false }
                .onChange(of: isAuthenticated) { _, auth in
                    if auth {
                        showBio = false
                        showPin = true
                    }
                }
        }
    }

    // MARK: - 动作

    private func begin(_ cmd: String, title: String) {
        guard commands.running == nil, !store.carId.isEmpty else { return }
        TokensHaptic.tap()
        pendingCmd = cmd
        pendingTitle = title
        // 空调必须先定温度，其余动作直接进身份验证
        if cmd == "OpenAir" { showTemp = true; return }
        gate()
    }

    private func gate() {
        if store.canUseBiometric() && store.hasBiometricSetup {
            showBio = true
        } else {
            showPin = true
        }
    }

    private func send(_ pin: String) {
        guard !pendingCmd.isEmpty else { return }
        // 温度只对空调有意义：锁车/寻车带上温度只会给服务端一个多余参数，
        // 所以这里传 API 的默认值 17，与车控页保持一致
        let temperature = pendingCmd == "OpenAir" ? pendingTemp : 17
        commands.send(cmd: pendingCmd, temperature: temperature,
                      pin: pin, displayName: pendingTitle)
    }
}
