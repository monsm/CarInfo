import SwiftUI

// 我的：用户卡 + 车辆卡 + 常用入口 + 退出登录
struct MineView: View {
    private let store = AppStore.shared
    @State private var showAboutAlert = false
    // 检查更新状态
    @State private var updateBusy = false
    @State private var updateMsg: String? = nil
    @State private var downloadPct: Double = 0
    @State private var downloadPctDisplay: Int = 0    // 下载进度数字滚动计数
    @State private var showDownload = false
    @State private var showToken = false
    @State private var tokenDraft: String = ""
    @State private var downloadFile: URL? = nil
    @State private var shareItems: [Any] = []
    @State private var shareSheetFlag = false
    @State private var isRefreshing = false     // 下拉刷新标志（触发玻璃涟漪动效）
    @State private var isChecking = false        // OTA 检查中（不含下载）
    @EnvironmentObject var nav: NavState            // C3: 用于 pushNavigation

    // MARK: 生命周期
    var body: some View {
        ScrollView {
            VStack(spacing: DynamicTypeScale.spacing(Theme.cardSpacing, dynamicTypeSize)) {
                profileCard
                if let car = store.car { carCard(car) }
                tilesCard
                updateCard
            }
            .adaptivePagePadding(dynamicTypeSize)
            .adaptiveSafeAreaBottom(12, dynamicTypeSize)
        }
        .scrollBounceBehavior(.basedOnSize)
        .pageBackground(.accentColor)
        .navigationTitle("我的")
            .navBarStyle()
            .accessibilityLabel(Text("我的"))
            .accessibilityHint(Text("账号设置、个人信息和应用程序管理"))
        .onReceive(NotificationCenter.default.publisher(for: .didLogout)) { _ in
            // 其他 Tab 退出登录时，重置 OTA 状态，避免残留下载进度
            updateBusy = false
            updateMsg = nil
            downloadPct = 0
            downloadPctDisplay = 0
            showDownload = false
            downloadFile = nil
            shareItems = []
        }
        .refreshable {
            isRefreshing = true
            try? await Task.sleep(nanoseconds: 600_000_000)  // 0.6s 模拟刷新延迟
            isRefreshing = false
        }
        .glassRefreshRipple(isRefreshing: $isRefreshing)
        .alert("关于 长安车管家", isPresented: $showAboutAlert) {
            Button("关闭", role: .cancel) { }
        } message: {
            Text(aboutText)
        }
        .alert("GitHub Token", isPresented: $showToken) {
            TextField("粘贴 Token", text: $tokenDraft)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.asciiCapable)
            Button("保存") {
                UpdateService.githubToken = tokenDraft
                updateMsg = tokenDraft.isEmpty ? "已清空 Token" : "Token 已保存，点「检查更新」获取最新构建"
            }
            Button("取消", role: .cancel) { }
        }
        .sheet(isPresented: $shareSheetFlag) { ShareSheet(items: shareItems) }
    }

    // MARK: 身份卡 — Apple Profile Card
    private var profileCard: some View {
        let um = VM.userModel(store.user)
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                // 头像
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.65)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 68, height: 68)
                        .shadow(color: Color.accentColor.opacity(0.35), radius: 12, y: 5)
                    Text(um?.avatar ?? "主")
                        .font(Theme.d4) weight: .bold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(um?.name ?? "车主").font(Theme.d5) weight: .bold))
                    HStack(spacing: 10) {
                        Text(um?.mobile ?? "--")
                            .font(Theme.mono))
                            .foregroundStyle(.secondary)
                        if um?.authed == true {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(Theme.micro))
                                    .foregroundStyle(Theme.ok)
                                Text("已实名")
                                    .font(Theme.footnote.bold())))
                                    .foregroundStyle(Theme.ok)
                            }
                        }
                    }
                }
                Spacer()
            }
            // 分割线
            Divider().opacity(0.4)
            // 底部统计
            HStack(spacing: 16) {
                HStack(spacing: 6) {
                    Image(systemName: "car.fill").font(Theme.caption)).foregroundStyle(Color.accentColor)
                    Text(String(store.cars?.count ?? 0) + " 辆车")
                        .font(Theme.caption)))
                }
                Spacer()
                if let gt = um?.gender, !gt.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: gt == "男" ? "person.fill" : "person.circle.fill")
                            .font(Theme.footnote)).foregroundStyle(.secondary)
                        Text(gt).font(Theme.caption)).foregroundStyle(.secondary)
                    }
                }
            }
            HStack(spacing: 12) {
                if let bt = um.birthday, !bt.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar").font(Theme.micro)).foregroundStyle(.secondary)
                        Text(bt).font(Theme.footnote)).foregroundStyle(.secondary)
                    }
                }
                if let lt = um.lastLoginTime, !lt.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "clock").font(Theme.micro)).foregroundStyle(.secondary)
                        Text(lt).font(Theme.footnote)).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(Theme.Spacing.xl)
        .dynamicTypeCompress()
        .glassHeroCard()
        .glassLongPressDeform()
    }

    // MARK: 车辆卡
    private func carCard(_ car: [String: Any]) -> some View {
        let sum = VM.vehicleSummary(car)
        return Button {
            NotificationCenter.default.post(name: .navToVehicle, object: nil)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "car.fill")
                    .font(Theme.d4))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 52, height: 52)
                    .background(.thin, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(sum?.name ?? "未绑定车辆").font(Theme.h3)))
                    Text(sum?.plate ?? "暂无车牌").font(Theme.caption)).foregroundStyle(.secondary)
                }
                Spacer()
                if let d = sum?.insuranceDays {
                    Pill(text: d < 0 ? "保险到期" : "保险剩 \(d) 天",
                         cls: d < 0 ? "bad" : (d <= 30 ? "warn" : "ok"), dot: false)
                }
                Image(systemName: "chevron.right")
                    .font(Theme.footnote.bold()))).foregroundStyle(.tertiary)
            }
            .padding(16)
            .dynamicTypeCompress()
            .glassCard()
            .glassLongPressDeform()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: 常用磁贴
    private var tilesCard: some View {
        CardBox(title: "常用功能") {
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    tile("shield.lefthalf.filled", "健康报告", tint: .green) { nav.pushNavigation(.health, targetTab: 0) }
                    tile("battery.100", "电池充电", tint: .green) { nav.pushNavigation(.battery, targetTab: 0) }
                }
                HStack(spacing: 10) {
                    tile("chart.bar.xaxis", "全量数据", tint: .indigo) { nav.pushNavigation(.data, targetTab: 0) }
                    tile("doc.text.fill", "车辆档案", tint: .orange) { nav.pushNavigation(.vehicle, targetTab: 0) }
                }
                HStack(spacing: 10) {
                    tile("bubble.left.fill", "消息中心", tint: .blue) { nav.pushNavigation(.messages, targetTab: 2) }
                    tile("wrench.adjustable", "开发者工具", tint: .purple) { nav.pushNavigation(.dev, targetTab: 0) }
                }
                // #31 省电模式
                PowerSavingToggle()
                    .padding(.horizontal, 4)
                // #45 驾驶行为评分
                if let score = calculateDriveBehaviorScore(store.caches) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("驾驶行为评分").font(Theme.h4)
                            Text("急加速 \(score.aggressiveAccel) 次 · 急刹车 \(score.harshBrake) 次")
                                .font(Theme.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(score.score)")
                                .font(Theme.d4).foregroundStyle(score.color)
                            Text(score.label)
                                .font(Theme.caption).foregroundStyle(score.color)
                        }
                    }
                    .padding(16)
                    .glassCard()
                    .glassLongPressDeform()
                }
                // #44 充电站地图入口
                ChargingStationFinder()
                    .padding(.horizontal, 4)
                // #39 月度驾驶报告入口
                MonthlyReportGenerator()
            }
        }
    }

    // MARK: 检查更新
    private var updateCard: some View {
        CardBox(title: "检查更新", side: nil) {
            VStack(alignment: .leading, spacing: 10) {
                Text("下载最新 GitHub 构建的 ipa，分享后用自签工具安装")
                    .font(Theme.caption)).foregroundStyle(.secondary)
                // OTA 检查中：骨架旋转指示器
                if isChecking {
                    HStack(spacing: 10) {
                        ProgressView()
                            .tint(.accentColor)
                        Text("正在检查最新版本…")
                            .font(Theme.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                } else if showDownload {
                    // 下载中：进度条 + 百分比数字
                    VStack(spacing: 6) {
                        ProgressView(value: downloadPct)
                            .tint(.accentColor)
                        Text("正在下载… \(downloadPctDisplay)%")
                            .font(Theme.caption)).foregroundStyle(.secondary)
                    }
                } else if let m = updateMsg {
                    // 错误或提示消息
                    HStack(spacing: 6) {
                        Image(systemName: m.hasPrefix("❌") ? "exclamationmark.triangle" : "info.circle")
                            .font(Theme.caption)
                            .foregroundStyle(m.hasPrefix("❌") ? Theme.warn : .accentColor)
                        Text(m)
                            .font(Theme.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
                HStack(spacing: 12) { updateButtons() }
            }
        }
        // 下载进度数字滚动：从当前 display 值弹性过渡到目标百分比
        .onChange(of: downloadPct) { pct in
            let target = max(0, min(100, Int(pct * 100)))
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6, blendDuration: 0.5)) {
                downloadPctDisplay = target
            }
        }
    }

    // 常用入口大尺寸磁贴
    private func tile(_ symbol: String, _ label: String, tint: Color,
                      _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(tint.opacity(0.10))
                        .frame(width: 48, height: 48)
                    Image(systemName: symbol)
                        .font(Theme.d5) weight: .medium))
                        .foregroundStyle(tint)
                }
                Text(label)
                    .font(Theme.caption.bold())))
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(.thin, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.8))
        .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
    }

    @ViewBuilder
    private func updateButtons() -> some View {
        HStack(spacing: 10) {
            mainUpdateButton
            if downloadFile != nil { shareButton }
            tokenButton
        }
    }

    private var mainUpdateButton: some View {
        Button {
            checkUpdate()
        } label: {
            HStack(spacing: 6) {
                if updateBusy { ProgressView().controlSize(.mini).tint(.white) }
                Text(updateBusy ? "检查中…" : "检查更新")
                    .font(Theme.caption.bold())))
            }
            .foregroundStyle(.white)
            .adaptivePagePadding(dynamicTypeSize).padding(.vertical, 10)
            .background(Capsule().fill(Color.accentColor))
        }
        .buttonStyle(.plain)
        .disabled(updateBusy)
    }

    private var shareButton: some View {
        Button {
            shareItems = [downloadFile as Any]
            shareSheetFlag = true
        } label: {
            Label("分享安装包", systemImage: "square.and.arrow.up")
                .font(Theme.caption.bold())))
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(.thin, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var tokenButton: some View {
        Button {
            tokenDraft = UpdateService.githubToken
            showToken = true
        } label: {
            Label("Token", systemImage: "key.fill")
                .font(Theme.caption))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(.thin, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func post(_ name: Notification.Name) {
        NotificationCenter.default.post(name: name, object: nil)
    }

    private var aboutText: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "长安车管家 v\(v) (\(b))\n网络通道：直连（iOS 原生）\n\n车况数据实时来自车辆车联网服务，仅用于本人车辆管理。"
    }

    private func logout() {
        store.logout()
        // RootView 监听 isLoggedIn 变化后自动切回登录页
    }

    private func checkUpdate() {
        updateBusy = true
        isChecking = true
        updateMsg = "正在检查最新构建…"
        shareItems = []
        downloadPct = 0
        downloadPctDisplay = 0
        showDownload = false
        Task { @MainActor in
            do {
                if UpdateService.githubToken.isEmpty {
                    updateMsg = "请先点「GitHub Token」填入私库访问 Token"
                    isChecking = false
                    updateBusy = false
                    return
                }
                let rel = try await UpdateService.fetchLatestRelease(token: UpdateService.githubToken)
                updateMsg = "发现构建 \(rel.name) · \(rel.displaySize)，开始下载…"
                isChecking = false
                showDownload = true
                let file = try await UpdateService.downloadIPA(url: rel.ipaUrl) { pct in downloadPct = pct }
                downloadFile = file
                updateMsg = nil
                showDownload = false
                shareItems = [file as Any]
                shareSheetFlag = true
                ToastManager.shared.show("下载完成，点分享安装", icon: "checkmark.circle.fill")
            } catch {
                updateMsg = "❌ \(error.localizedDescription)"
                showDownload = false
                ToastManager.shared.show(error.localizedDescription, icon: "xmark.circle.fill")
            }
            isChecking = false
            updateBusy = false
        }
    }
}
