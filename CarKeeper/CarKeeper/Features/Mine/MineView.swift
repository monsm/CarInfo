import SwiftUI

// 我的：用户卡 + 车辆卡 + 常用入口 + 退出登录
struct MineView: View {
    private let store = AppStore.shared
    @State private var showAboutAlert = false
    // 检查更新状态
    @State private var updateBusy = false
    @State private var updateMsg: String? = nil
    /// 提示是否为错误。原来是把 "❌" 拼进字符串再用 hasPrefix 反解 —— 用 emoji 当状态码，
    /// 既不可本地化也无法换图标；改成显式布尔值，图标交给系统 symbol。
    @State private var updateMsgIsError = false
    @State private var downloadPct: Double = 0
    @State private var downloadPctDisplay: Int = 0    // 下载进度数字滚动计数
    @State private var showDownload = false
    @State private var showToken = false
    @State private var tokenDraft: String = ""
    @State private var downloadFile: URL? = nil
    @State private var shareItems: [Any] = []
    @State private var shareSheetFlag = false
    @State private var isRefreshing = false     // 下拉刷新进行中标志
    @State private var isChecking = false        // OTA 检查中（不含下载）
    @State private var showMileageJournal = false
    @State private var showOTAChangelog = false
    @State private var showPrivacyDashboard = false
    @State private var showTempKeys = false
    @State private var showFamily = false
    @State private var showInspection = false
    @State private var showValuation = false
    @State private var showChargeBill = false
    // 行程分析 / 指令历史 / 维保记录 / 停车位置 / 紧急求助 / 车辆提示 / 驾驶评分
    // 走 nav.pushNavigation（这些页已在壳层 navigationDestination 注册），
    // 不再保留一堆从未绑定 sheet 的 @State（此前 7 个磁贴设了状态却没人监听 = 死按钮）。
    @EnvironmentObject var nav: NavState            // C3: 用于 pushNavigation
    // #NEW-115 夜间模式管理
    @StateObject private var nightModeManager = NightModeManager.shared

    // MARK: 生命周期
    var body: some View {
        ScrollView {
            VStack(spacing: KanseiSpacing.lg) {
                profileCard
                if let car = store.car { carCard(car) }
                tilesCard
                updateCard
            }

        }
        .scrollBounceBehavior(.basedOnSize)
        .background(KanseiPalette.background)
        .navigationTitle("我的")
            .accessibilityLabel(Text("我的"))
            .accessibilityHint(Text("账号设置、个人信息和应用程序管理"))
        .onReceive(NotificationCenter.default.publisher(for: .didLogout)) { _ in
            // 其他 Tab 退出登录时，重置 OTA 状态，避免残留下载进度
            updateBusy = false
            updateMsg = nil
            updateMsgIsError = false
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
                updateMsgIsError = false
                updateMsg = tokenDraft.isEmpty ? "已清空 Token" : "Token 已保存，点「检查更新」获取最新构建"
            }
            Button("取消", role: .cancel) { }
        }
        .sheet(isPresented: $shareSheetFlag) { ShareSheet(items: shareItems) }
        .sheet(isPresented: $showMileageJournal) {
            NavigationStack {
                MileageJournalView()
                    .navigationTitle("里程记账")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        .sheet(isPresented: $showOTAChangelog) {
            NavigationStack {
                OTAChangelogView()
                    .navigationTitle("OTA 版本日志")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        .sheet(isPresented: $showPrivacyDashboard) {
            NavigationStack {
                PrivacyDashboardView()
                    .navigationTitle("隐私与数据")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        .sheet(isPresented: $showTempKeys) {
            NavigationStack {
                TempKeyListView()
                    .navigationTitle("共享钥匙")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        .sheet(isPresented: $showFamily) {
            NavigationStack {
                FamilyManagementView()
                    .navigationTitle("家庭管理")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        .sheet(isPresented: $showInspection) {
            NavigationStack {
                InspectionCalendarView()
                    .navigationTitle("年检日历")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        .sheet(isPresented: $showValuation) {
            NavigationStack {
                VehicleValuationView()
                    .navigationTitle("车辆估值")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        .sheet(isPresented: $showChargeBill) {
            NavigationStack {
                ChargeBillSheet()
                    .navigationTitle("充电账单")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
    }

    // MARK: 身份卡 — Apple Profile Card
    private var profileCard: some View {
        let um = VM.userModel(store.user)
        return DSCard(padding: DS.Space.cardPadding, radius: DS.Radius.hero) {
            VStack(alignment: .leading, spacing: DS.Space.lg) {
                HStack(spacing: DS.Space.lg) {
                    // 头像：系统填充色的圆底 + 首字（iOS 设置顶部的身份区做法）
                    Text(um?.avatar ?? "主")
                        .font(DS.Typo.title2.weight(.semibold))
                        .foregroundStyle(KanseiPalette.secondary)
                        .frame(width: 64, height: 64)
                        .background(Circle().fill(KanseiPalette.glassLight))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(um?.name ?? "车主")
                            .font(DS.Typo.title2)
                            .foregroundStyle(KanseiPalette.primary)
                        Text(um?.mobile ?? "--")
                            .font(DS.Typo.footnote)
                            .foregroundStyle(KanseiPalette.secondary)
                        if um?.authed == true {
                            Text("已实名认证")
                                .font(DS.Typo.footnote)
                                .foregroundStyle(KanseiPalette.success)
                        }
                    }
                    Spacer(minLength: DS.Space.sm)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(KanseiPalette.tertiary)
                }

                DSDivider()

                HStack(spacing: DS.Space.xl) {
                    profileStat(label: "车辆", value: "\(store.cars.count)", unit: "辆")
                    if let gt = um?.gender, !gt.isEmpty {
                        profileStat(label: "性别", value: gt, unit: nil)
                    }
                    if let bt = um?.birthday, !bt.isEmpty {
                        profileStat(label: "生日", value: bt, unit: nil)
                    }
                    Spacer(minLength: 0)
                }

                if let lt = um?.lastLoginTime, !lt.isEmpty {
                    HStack(spacing: DS.Space.xs) {
                        Image(systemName: "clock")
                            .font(.system(size: 11))
                        Text("上次登录 \(lt)")
                    }
                    .font(DS.Typo.caption)
                    .foregroundStyle(KanseiPalette.tertiary)
                }
            }
        }
        .dynamicTypeCompress()
    }

    private func profileStat(label: String, value: String, unit: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(DS.Typo.caption2.weight(.medium))
                .foregroundStyle(KanseiPalette.tertiary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(DS.Typo.metric(20))
                    .foregroundStyle(KanseiPalette.primary)
                if let unit {
                    Text(unit)
                        .font(DS.Typo.caption)
                        .foregroundStyle(KanseiPalette.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: 车辆卡
    private func carCard(_ car: [String: Any]) -> some View {
        let sum = VM.vehicleSummary(car)
        return Button {
            // 此前发 .navToVehicle 通知，根视图只写首页的 path —— 在「我的」Tab 点了毫无反应，
            // 要再点一次首页 Tab 才“突然出现”。改走统一导航：切到首页 Tab 并 push。
            nav.pushNavigation(.vehicle, targetTab: .home)
        } label: {
            HStack(spacing: DS.Space.lg) {
                Image(systemName: "car.fill")
                    .font(.system(size: DS.Size.iconLg, weight: .regular))
                    .foregroundStyle(KanseiPalette.ambient)
                    .frame(width: 48, height: 48)
                    .background(RoundedRectangle(cornerRadius: DS.Radius.small, style: .continuous)
                        .fill(KanseiPalette.ambient))
                VStack(alignment: .leading, spacing: 3) {
                    Text(sum?.name ?? "未绑定车辆")
                        .font(DS.Typo.headline)
                        .foregroundStyle(KanseiPalette.primary)
                    Text(sum?.plate ?? "暂无车牌")
                        .font(DS.Typo.dataSmall)
                        .foregroundStyle(KanseiPalette.secondary)
                }
                Spacer(minLength: DS.Space.sm)
                if let d = sum?.insuranceDays {
                    DSChip(text: d < 0 ? "保险到期" : "保险剩 \(d) 天",
                           cls: d < 0 ? "bad" : (d <= 30 ? "warn" : "ok"))
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(KanseiPalette.tertiary)
            }
            .padding(DS.Space.cardPadding)
            .dsSurface(padding: 0)
            .dynamicTypeCompress()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: 常用磁贴
    private var tilesCard: some View {
        CardBox(title: "常用功能") {
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    tile("shield.lefthalf.filled", "健康报告", tint: .green) {
                        nav.pushNavigation(.health, targetTab: .home)
                    }
                    tile("battery.100", "电池充电", tint: .green) { nav.pushNavigation(.battery, targetTab: .home) }
                }
                HStack(spacing: 10) {
                    tile("chart.bar.xaxis", "全量数据", tint: .indigo) { nav.pushNavigation(.data, targetTab: .home) }
                    tile("doc.text.fill", "车辆档案", tint: .orange) { nav.pushNavigation(.vehicle, targetTab: .home) }
                }
                HStack(spacing: 10) {
                    tile("bubble.left.fill", "消息中心", tint: .blue) { nav.pushNavigation(.messages) }
                    tile("wrench.adjustable", "开发者工具", tint: .purple) { nav.pushNavigation(.dev, targetTab: .home) }
                }
                // #31 省电模式
                PowerSavingToggle()
                    .padding(.horizontal, 4)
                // #NEW-115 夜间模式切换
                HStack {
                    Text("夜间模式").font(Theme.h4)
                    Spacer()
                    Picker("主题", selection: Binding(
                        get: { nightModeManager.currentMode },
                        set: { nightModeManager.setMode($0) }
                    )) {
                        Text("自动").tag(NightModeMode.auto)
                        Text("浅色").tag(NightModeMode.light)
                        Text("深色").tag(NightModeMode.dark)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .onChange(of: nightModeManager.currentMode) { _, mode in
                        nightModeManager.setMode(mode)
                    }
                }
                .padding(16)
                .glassCard()

                // #45 驾驶行为评分
                if let score = calculateDriveBehaviorScore(store.caches) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("驾驶行为评分").font(Theme.h4)
                            Text("急加速 \(score.aggressiveAccel) 次 · 急刹车 \(score.harshBrake) 次")
                                .font(KanseiTypo.caption).foregroundStyle(KanseiPalette.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(score.score)")
                                .font(Theme.d4).foregroundStyle(score.color)
                            Text(score.label)
                                .font(KanseiTypo.caption).foregroundStyle(score.color)
                        }
                    }
                    .padding(16)
                    .glassCard()
                }
                // #44 充电站地图入口
                ChargingStationFinder()
                    .padding(.horizontal, 4)
                // #39 月度驾驶报告入口
                MonthlyReportGenerator()
                // #NEW-128 里程记账本入口
                HStack(spacing: 10) {
                    tile("banknote.fill", "里程记账", tint: .green) { showMileageJournal = true }
                    tile("clock.fill", "维保提醒", tint: .orange) { nav.pushNavigation(.service) }
                }
                // #NEW-38 OTA 版本日志入口
                HStack(spacing: 10) {
                    tile("tray.fill", "OTA日志", tint: .blue) { showOTAChangelog = true }
                    tile("doc.plaintext.fill", "专注模式", tint: .purple) { toggleFocus() }
                }
                // #N11 隐私仪表盘 + N43 语音播报
                HStack(spacing: 10) {
                    tile("eye.fill", "隐私与数据", tint: .teal) { showPrivacyDashboard = true }
                    // 此前是空操作（VoiceBroadcastManager 自动启动，点这里什么都不发生）。
                    // 现在是真能用的开关：翻转 VoiceBroadcastManager 读取的 UserDefaults 键。
                    tile("speaker.wave.3.fill", "语音播报", tint: .indigo) { toggleVoice() }
                }
                // #N30/N31 临时钥匙 + 家庭管理
                HStack(spacing: 10) {
                    tile("key.fill", "共享钥匙", tint: .pink) { showTempKeys = true }
                    tile("person.2.fill", "家庭管理", tint: .orange) { showFamily = true }
                }
                // #N33/N34 车辆估值 + 年检日历
                HStack(spacing: 10) {
                    tile("dollarsign.circle.fill", "车辆估值", tint: .green) { showValuation = true }
                    tile("calendar.fill", "年检日历", tint: .purple) { showInspection = true }
                }
                // #N32 充电账单 PDF
                tile("doc.plaintext.fill", "充电账单", tint: .cyan) { showChargeBill = true }
                // E新增功能入口
                HStack(spacing: 10) {
                    tile("chart.bar.fill", "行程分析", tint: .blue) { nav.pushNavigation(.trips, targetTab: .trips) }
                    tile("clock.fill", "指令历史", tint: .purple) { nav.pushNavigation(.commands) }
                }
                HStack(spacing: 10) {
                    tile("wrench.and.screwdriver.fill", "维保记录", tint: .orange) { nav.pushNavigation(.service) }
                    tile("mappin.circle.fill", "停车位置", tint: .green) { nav.pushNavigation(.parking) }
                }
                HStack(spacing: 10) {
                    tile("exclamationmark.octagon.fill", "紧急求助", tint: .red) { nav.pushNavigation(.emergency) }
                    tile("lightbulb.fill", "车辆提示", tint: .yellow) { nav.pushNavigation(.tips) }
                }
                    tile("trophy.fill", "驾驶评分",
                          tint: KanseiPalette.ambient) { nav.pushNavigation(.score) }
            }
        }
    }

    // MARK: 检查更新
    private var updateCard: some View {
        CardBox(title: "检查更新", side: nil) {
            VStack(alignment: .leading, spacing: 10) {
                Text("下载最新 GitHub 构建的 ipa，分享后用自签工具安装")
                    .font(Theme.caption).foregroundStyle(.secondary)
                // OTA 检查中：骨架旋转指示器
                if isChecking {
                    HStack(spacing: 10) {
                        ProgressView()
                            .tint(KanseiPalette.ambient)
                        Text("正在检查最新版本…")
                            .font(Theme.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                } else if showDownload {
                    // 下载中：进度条 + 百分比数字
                    VStack(spacing: 6) {
                        ProgressView(value: downloadPct)
                            .tint(KanseiPalette.ambient)
                        Text("正在下载… \(downloadPctDisplay)%")
                            .font(KanseiTypo.caption).foregroundStyle(KanseiPalette.secondary)
                    }
                } else if let m = updateMsg {
                    // 错误或提示消息（图标由 updateMsgIsError 决定）
                    HStack(spacing: 6) {
                        Image(safeSymbol: updateMsgIsError ? "exclamationmark.triangle.fill" : "info.circle.fill",
                              fallback: "info.circle.fill")
                            .font(Theme.caption)
                            .foregroundStyle(updateMsgIsError ? KanseiPalette.error : KanseiPalette.ambient)
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
        .onChange(of: downloadPct) { _, pct in
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
            // Tesla 式磁贴：图标左上 + 标签在左下，表面色不用玻璃、不用圆形底盘。
            VStack(alignment: .leading, spacing: DS.Space.sm) {
                Image(safeSymbol: symbol, fallback: "car.fill")
                    .font(.system(size: DS.Size.tileIcon, weight: .regular))
                    .foregroundStyle(tint)
                    .frame(height: 30)
                Text(label)
                    .font(DS.Typo.subheadline.weight(.semibold))
                    .foregroundStyle(KanseiPalette.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DS.Space.md)
            .frame(minHeight: 84)
            .background(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .fill(KanseiPalette.nightSurface))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .strokeBorder(KanseiPalette.glassBorder, lineWidth: DS.Hair.line))
            .contentShape(Rectangle())
        }
        .buttonStyle(DSCardButtonStyle())
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
                    .font(Theme.font(.caption as Font).bold())
            }
            .foregroundStyle(.white)
            .padding(.vertical, 10)
            .background(Capsule().fill(KanseiPalette.ambient))
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
                .font(Theme.font(.caption as Font).bold())
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(KanseiPalette.fillSubtle, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var tokenButton: some View {
        Button {
            tokenDraft = UpdateService.githubToken
            showToken = true
        } label: {
            Label("Token", systemImage: "key.fill")
                .font(Theme.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(KanseiPalette.fillSubtle, in: Capsule())
        }
        .buttonStyle(.plain)
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

    // MARK: 真开关（此前这两个磁贴一个空操作、一个跳错页）

    /// 语音播报开关：VoiceBroadcastManager 每次播报前都读这个键，翻转后立即生效
    private func toggleVoice() {
        let key = "carkeeper_voice_enabled"
        let next = !UserDefaults.standard.bool(forKey: key)
        UserDefaults.standard.set(next, forKey: key)
        ToastManager.shared.show(next ? "语音播报已开启" : "语音播报已关闭",
                                 icon: next ? "speaker.wave.3.fill" : "speaker.slash.fill")
        DSHaptic.select()
    }

    /// 专注模式开关：与首页 toggleFocusMode 同一套配置结构
    private func toggleFocus() {
        let fm = FocusModeManager.shared
        let next = FocusModeConfig(
            enabled: !fm.config.enabled,
            hideSensitiveData: fm.config.hideSensitiveData,
            showEssentialOnly: fm.config.showEssentialOnly,
            doNotDisturb: fm.config.doNotDisturb,
            autoStartDriving: fm.config.autoStartDriving,
            customMessage: fm.config.customMessage
        )
        fm.saveConfig(next)
        ToastManager.shared.show(next.enabled ? "专注模式已开启" : "专注模式已关闭",
                                 icon: next.enabled ? "moon.fill" : "moon.zzz.fill")
        DSHaptic.select()
    }

    private func checkUpdate() {
        updateBusy = true
        isChecking = true
        updateMsgIsError = false
        updateMsg = "正在检查最新构建…"
        shareItems = []
        downloadPct = 0
        downloadPctDisplay = 0
        showDownload = false
        Task { @MainActor in
            do {
                if UpdateService.githubToken.isEmpty {
                    updateMsgIsError = true
                    updateMsg = "请先点「GitHub Token」填入私库访问 Token"
                    isChecking = false
                    updateBusy = false
                    return
                }
                let rel = try await UpdateService.fetchLatestRelease(token: UpdateService.githubToken)
                updateMsgIsError = false
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
                updateMsgIsError = true
                updateMsg = error.localizedDescription
                showDownload = false
                ToastManager.shared.show(error.localizedDescription, icon: "xmark.circle.fill")
            }
            isChecking = false
            updateBusy = false
        }
    }
}
