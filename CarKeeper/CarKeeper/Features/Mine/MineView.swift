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
    /// 退出登录二次确认（按钮在 tilesCard 的「应用」组里）
    @State private var logoutConfirm = false
    /// 行内开关的**本地镜像**。
    /// ShakeDetector / VoiceBroadcast / FocusModeManager 三个单例都不是 ObservableObject，
    /// 直接把开关绑到它们的属性上会出现「拨了不动」（值变了但没人通知视图）。
    /// 这一页不是常驻屏，所以镜像一份状态：先改本地（立刻重绘），再写回单例。
    @State private var shakeOn = ShakeDetector.shared.isEnabled
    @State private var voiceOn = UserDefaults.standard.bool(forKey: "carkeeper_voice_enabled")
    @State private var focusOn = FocusModeManager.shared.config.enabled
    // 行程分析 / 指令历史 / 维保记录 / 停车位置 / 紧急求助 / 车辆提示 / 驾驶评分
    // 走 nav.pushNavigation（这些页已在壳层 navigationDestination 注册），
    // 不再保留一堆从未绑定 sheet 的 @State（此前 7 个磁贴设了状态却没人监听 = 死按钮）。
    @EnvironmentObject var nav: NavState            // C3: 用于 pushNavigation
    // #NEW-115 夜间模式管理
    @StateObject private var nightModeManager = NightModeManager.shared

    // MARK: 生命周期
    var body: some View {
        ScrollView {
            VStack(spacing: TokensSpacing.lg) {
                DSPageTitle(title: "车与账号", subtitle: "车辆、账号、数据与工具")
                profileCard
                if let car = store.car { carCard(car) }
                settingsGroups
                updateCard
            }

        }
        .pageBackground()
        .scrollBounceBehavior(.basedOnSize)
        .dsPageTitle("车与账号")
            .accessibilityLabel(Text("车与账号"))
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
                    .dsSheetCanvas()
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        .sheet(isPresented: $showOTAChangelog) {
            NavigationStack {
                OTAChangelogView()
                    .navigationTitle("OTA 版本日志")
                    .dsSheetCanvas()
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        .sheet(isPresented: $showPrivacyDashboard) {
            NavigationStack {
                PrivacyDashboardView()
                    .navigationTitle("隐私与数据")
                    .dsSheetCanvas()
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        .sheet(isPresented: $showTempKeys) {
            NavigationStack {
                TempKeyListView()
                    .navigationTitle("共享钥匙")
                    .dsSheetCanvas()
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        .sheet(isPresented: $showFamily) {
            NavigationStack {
                FamilyManagementView()
                    .navigationTitle("家庭管理")
                    .dsSheetCanvas()
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        .sheet(isPresented: $showInspection) {
            NavigationStack {
                InspectionCalendarView()
                    .navigationTitle("年检日历")
                    .dsSheetCanvas()
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        .sheet(isPresented: $showValuation) {
            NavigationStack {
                VehicleValuationView()
                    .navigationTitle("车辆估值")
                    .dsSheetCanvas()
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        .sheet(isPresented: $showChargeBill) {
            NavigationStack {
                ChargeBillSheet()
                    .navigationTitle("充电账单")
                    .dsSheetCanvas()
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        .alert("退出登录", isPresented: $logoutConfirm) {
            Button("退出", role: .destructive) { logout() }
            Button("取消", role: .cancel) { }
        } message: {
            Text("退出后需要用手机号重新登录。本机的行程、充电与记账记录不会被删除。")
        }
    }

    // MARK: 身份卡 — Apple Profile Card
    private var profileCard: some View {
        let um = VM.userModel(store.user)
        return DSCard(padding: TokensSpacing.md, radius: TokensRadius.large) {
            VStack(alignment: .leading, spacing: TokensSpacing.lg) {
                HStack(spacing: TokensSpacing.lg) {
                    // 头像：系统填充色的圆底 + 首字（iOS 设置顶部的身份区做法）
                    Text(um?.avatar ?? "主")
                        .font(TokensTypo.title2.weight(.semibold))
                        .foregroundStyle(TokensPalette.secondary)
                        .frame(width: 64, height: 64)
                        .background(Circle().fill(TokensPalette.glassLight))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(um?.name ?? "车主")
                            .font(TokensTypo.title2)
                            .foregroundStyle(TokensPalette.primary)
                        Text(um?.mobile ?? "--")
                            .font(TokensTypo.footnote)
                            .foregroundStyle(TokensPalette.secondary)
                        if um?.authed == true {
                            Text("已实名认证")
                                .font(TokensTypo.footnote)
                                .foregroundStyle(TokensPalette.success)
                        }
                    }
                    Spacer(minLength: TokensSpacing.sm)
                    Image(systemName: "chevron.right")
                        .font(TokensTypo.fixed(13, weight: .semibold))
                        .foregroundStyle(TokensPalette.tertiary)
                }

                DSDivider()

                HStack(spacing: TokensSpacing.xl) {
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
                    HStack(spacing: TokensSpacing.xs) {
                        Image(systemName: "clock")
                            .font(TokensTypo.fixed(11))
                        Text("上次登录 \(lt)")
                    }
                    .font(TokensTypo.caption)
                    .foregroundStyle(TokensPalette.tertiary)
                }
            }
        }
    }

    private func profileStat(label: String, value: String, unit: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(TokensTypo.caption2.weight(.medium))
                .foregroundStyle(TokensPalette.tertiary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(TokensTypo.metric(20))
                    .foregroundStyle(TokensPalette.primary)
                if let unit {
                    Text(unit)
                        .font(TokensTypo.caption)
                        .foregroundStyle(TokensPalette.secondary)
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
            nav.pushNavigation(.vehicle)
        } label: {
            HStack(spacing: TokensSpacing.lg) {
                Image(systemName: "car.fill")
                    .font(.system(size: TokensSize.iconLg, weight: .regular))
                    .foregroundStyle(TokensPalette.ambient)
                    .frame(width: 48, height: 48)
                    .background(RoundedRectangle(cornerRadius: TokensRadius.small, style: .continuous)
                        .fill(TokensPalette.ambient))
                VStack(alignment: .leading, spacing: 3) {
                    Text(sum?.name ?? "未绑定车辆")
                        .font(TokensTypo.headline)
                        .foregroundStyle(TokensPalette.primary)
                    Text(sum?.plate ?? "暂无车牌")
                        .font(TokensTypo.dataSmall)
                        .foregroundStyle(TokensPalette.secondary)
                }
                Spacer(minLength: TokensSpacing.sm)
                if let d = sum?.insuranceDays {
                    DSChip(text: d < 0 ? "保险到期" : "保险剩 \(d) 天",
                           cls: d < 0 ? "bad" : (d <= 30 ? "warn" : "ok"))
                }
                Image(systemName: "chevron.right")
                    .font(TokensTypo.fixed(13, weight: .semibold))
                    .foregroundStyle(TokensPalette.tertiary)
            }
            .padding(TokensSpacing.md)
            .dsSurface(padding: 0)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: 设置分组（inset-grouped 行）
    //
    // 旧写法是 6 个 `CardBox`，每个里面再摆 2 列「Tesla 式磁贴」（一共 28 个）——
    // 那是**第三套容器 + 第三套行**：全 App 只有这一页这么排，从别的页面走进来像换了一个 App。
    // 现在它和 iOS 设置一样：分组标题在画布上、行在分组表面上、行与行之间是发丝线。
    private var settingsGroups: some View {
        VStack(spacing: TokensSpacing.xl) {
            DSGroup(title: "车辆", footer: "车况主屏是地图；下面是它的深潜页。") {
                linkRow("shield.lefthalf.filled", "健康报告", .health)
                linkRow("battery.100", "电池与充电", .battery)
                linkRow("doc.text.fill", "车辆档案", .vehicle)
                linkRow("chart.bar.xaxis", "全量数据", .data)
                // 「驾驶总览」原本与「驾驶评分」指向**同一个页面**（`.dashboard` 只是别名），
                // 同一页摆两个入口正是缝合的来源，所以只留一个。
                linkRow("trophy.fill", "驾驶评分", .score, last: true)
            }

            DSGroup(title: "用车") {
                linkRow("chart.bar.fill", "行程分析", .trips)
                linkRow("clock.fill", "指令历史", .commands)
                linkRow("wrench.and.screwdriver.fill", "维保记录", .service)
                linkRow("mappin.circle.fill", "停车位置", .parking)
                linkRow("lightbulb.fill", "车辆提示", .tips)
                linkRow("exclamationmark.octagon.fill", "紧急求助", .emergency)
                // #44 充电站：地图主屏的「充电」层就是这件事 —— 它按**车的位置**实时搜，
                // 这里不再自己搜一份（原来那份搜的是写死的北京坐标 39.9042, 116.4074）。
                actionRow("bolt.fill", "附近充电站", last: true) {
                    MapSpineLayer.charge.makeCurrent()
                    nav.popToRoot()
                }
            }

            DSGroup(title: "钱与证件",
                    footer: "数字来自本机记录（里程记账 / 年检 / 保险的字段由你自己填）。") {
                actionRow("banknote.fill", "里程记账") { showMileageJournal = true }
                actionRow("doc.plaintext.fill", "充电账单") { showChargeBill = true }
                actionRow("dollarsign.circle.fill", "车辆估值") { showValuation = true }
                actionRow("calendar.fill", "年检与保险", last: true) { showInspection = true }
            }

            DSGroup(title: "报告与共享") {
                actionRow("key.fill", "共享钥匙") { showTempKeys = true }
                actionRow("person.2.fill", "家庭管理") { showFamily = true }
                // #39 月度驾驶报告入口：它自己就是一行（内缩与分隔线由 DSGroupRow 给）
                customRow(last: true) { MonthlyReportGenerator() }
            }

            DSGroup(title: "设备与模式",
                    footer: "摇一摇锁车默认关闭 —— 它会真的发一条锁车指令。") {
                customRow { shakeToggle }
                // #31 省电模式
                customRow { PowerSavingToggle() }
                customRow { nightModeRow }
                customRow(last: true) {
                    DSRow(icon: "moon.fill", title: "专注模式",
                          value: focusOn ? "已开启" : "已关闭") { toggleFocus() }
                }
            }

            DSGroup(title: "应用") {
                customRow {
                    DSRow(icon: "magnifyingglass", title: "全局搜索", showsChevron: true) {
                        nav.showSearch = true
                    }
                }
                linkRow("bubble.left.fill", "消息中心", .messages)
                actionRow("eye.fill", "隐私与数据") { showPrivacyDashboard = true }
                actionRow("tray.fill", "OTA 日志") { showOTAChangelog = true }
                // 此前是空操作（VoiceBroadcastManager 自动启动，点这里什么都不发生）。
                // 现在是真能用的开关：翻转 VoiceBroadcastManager 读取的 UserDefaults 键。
                customRow {
                    DSRow(icon: "speaker.wave.3.fill", title: "语音播报",
                          value: voiceOn ? "已开启" : "已关闭") { toggleVoice() }
                }
                linkRow("wrench.adjustable", "开发者工具", .dev)
                customRow(last: true) { logoutRow }
            }
        }
    }

    // MARK: 行的三种写法（与全 App 其余 20 屏同一套 DS 原语）

    /// 跳页行：图标 + 标题 + 箭头
    private func linkRow(_ icon: String, _ title: String, _ link: Deeplink,
                         last: Bool = false) -> some View {
        DSGroupRow(showsSeparator: !last) {
            DSRow(icon: icon, title: title, showsChevron: true) { nav.pushNavigation(link) }
        }
    }

    /// 动作行（开浮层 / 切图层 / 触发一件事）：图标 + 标题 + 箭头
    private func actionRow(_ icon: String, _ title: String, last: Bool = false,
                           _ action: @escaping () -> Void) -> some View {
        DSGroupRow(showsSeparator: !last) {
            DSRow(icon: icon, title: title, showsChevron: true, action: action)
        }
    }

    /// 自定义行（开关 / 选择器 / 第三方视图）：只借用分组的内缩与分隔线
    private func customRow<V: View>(last: Bool = false,
                                    @ViewBuilder _ content: () -> V) -> some View {
        DSGroupRow(showsSeparator: !last) { content() }
    }

    // MARK: 行内的小组件 / 退出登录（都在 settingsGroups 里用）

    /// 摇一摇锁车开关。
    /// 此前这个功能只有一个从未被写入过的 UserDefaults 键（`carkeeper_shake_to_lock`，
    /// bool 默认 false）—— 也就是说它永远是关的，而且没有任何地方能把它打开。
    /// 现在开关真的写到 ShakeDetector，并且**本地镜像**状态（它不是 ObservableObject，
    /// 直接绑定会出现「拨了不动」）。
    private var shakeToggle: some View {
        Toggle(isOn: Binding(
            get: { shakeOn },
            set: { newValue in
                shakeOn = newValue
                ShakeDetector.shared.isEnabled = newValue
                TokensHaptic.select()
            }
        )) {
            VStack(alignment: .leading, spacing: 1) {
                Text("摇一摇锁车")
                    .font(TokensTypo.body)
                    .foregroundStyle(TokensPalette.primary)
                Text("摇一下手机，发一条锁车指令（需 PIN）")
                    .font(TokensTypo.footnote)
                    .foregroundStyle(TokensPalette.secondary)
            }
        }
        .frame(minHeight: TokensSpacing.row)
    }

    /// #NEW-115 夜间模式切换：iOS 设置里的「值选择器」行
    /// （原来是行内分段控件 + 自己的 padding + 第二套卡片底：一整块彩色块嵌在白色分组里）
    private var nightModeRow: some View {
        HStack {
            Text("夜间模式")
                .font(TokensTypo.body)
                .foregroundStyle(TokensPalette.primary)
            Spacer(minLength: TokensSpacing.sm)
            Picker("夜间模式", selection: Binding(
                get: { nightModeManager.currentMode },
                set: { nightModeManager.setMode($0) }
            )) {
                Text("自动").tag(NightModeMode.auto)
                Text("浅色").tag(NightModeMode.light)
                Text("深色").tag(NightModeMode.dark)
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
        .frame(minHeight: TokensSpacing.row)
    }

    /// 退出登录。`logout()` 一直存在，但**没有任何按钮调它** —— 它是一段到不了的代码。
    private var logoutRow: some View {
        Button {
            logoutConfirm = true
        } label: {
            HStack(spacing: TokensSpacing.sm) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(TokensTypo.fixed(15))
                Text("退出登录").font(TokensTypo.headline)
                Spacer()
            }
            .foregroundStyle(TokensPalette.error)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: 检查更新
    private var updateCard: some View {
        // 整块是一行：上面的说明、进度与三个按钮都属于「检查更新」这一件事。
        DSGroup(title: "检查更新") {
            customRow(last: true) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("下载最新 GitHub 构建的 ipa，分享后用自签工具安装")
                        .font(TokensTypo.caption).foregroundStyle(TokensPalette.secondary)
                    // OTA 检查中：骨架旋转指示器
                    if isChecking {
                        HStack(spacing: 10) {
                            ProgressView()
                                .tint(TokensPalette.ambient)
                            Text("正在检查最新版本…")
                                .font(TokensTypo.caption)
                                .foregroundStyle(TokensPalette.secondary)
                        }
                        .padding(.vertical, 8)
                    } else if showDownload {
                        // 下载中：进度条 + 百分比数字
                        VStack(spacing: 6) {
                            ProgressView(value: downloadPct)
                                .tint(TokensPalette.ambient)
                            Text("正在下载… \(downloadPctDisplay)%")
                                .font(TokensTypo.caption).foregroundStyle(TokensPalette.secondary)
                        }
                    } else if let m = updateMsg {
                        // 错误或提示消息（图标由 updateMsgIsError 决定）
                        HStack(spacing: 6) {
                            Image(safeSymbol: updateMsgIsError ? "exclamationmark.triangle.fill" : "info.circle.fill",
                                  fallback: "info.circle.fill")
                                .font(TokensTypo.caption)
                                .foregroundStyle(updateMsgIsError ? TokensPalette.error : TokensPalette.ambient)
                            Text(m)
                                .font(TokensTypo.caption)
                                .foregroundStyle(TokensPalette.secondary)
                            Spacer()
                        }
                    }
                    HStack(spacing: 12) { updateButtons() }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, TokensSpacing.sm)
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
                if updateBusy { ProgressView().controlSize(.mini).tint(TokensPalette.labelOnTint) }
                Text(updateBusy ? "检查中…" : "检查更新")
                    .font(TokensTypo.caption.weight(.bold))
            }
            .foregroundStyle(TokensPalette.labelOnTint)
            .padding(.vertical, 10)
            .background(Capsule().fill(TokensPalette.ambient))
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
                .font(TokensTypo.caption.weight(.bold))
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(TokensPalette.fillSubtle, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var tokenButton: some View {
        Button {
            tokenDraft = UpdateService.githubToken
            showToken = true
        } label: {
            Label("Token", systemImage: "key.fill")
                .font(TokensTypo.caption)
                .foregroundStyle(TokensPalette.secondary)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(TokensPalette.fillSubtle, in: Capsule())
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
        voiceOn = next
        ToastManager.shared.show(next ? "语音播报已开启" : "语音播报已关闭",
                                 icon: next ? "speaker.wave.3.fill" : "speaker.slash.fill")
        TokensHaptic.select()
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
        focusOn = next.enabled
        ToastManager.shared.show(next.enabled ? "专注模式已开启" : "专注模式已关闭",
                                 icon: next.enabled ? "moon.fill" : "moon.zzz.fill")
        TokensHaptic.select()
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
