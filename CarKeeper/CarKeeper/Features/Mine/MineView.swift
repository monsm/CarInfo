import SwiftUI
import PhotosUI

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
    @State private var showTempKeys = false
    @State private var showFamily = false
    /// 退出登录二次确认（按钮在 tilesCard 的「应用」组里）
    @State private var logoutConfirm = false
    /// 行内开关的**本地镜像**。
    /// ShakeDetector / VoiceBroadcast / FocusModeManager 三个单例都不是 ObservableObject，
    /// 直接把开关绑到它们的属性上会出现「拨了不动」（值变了但没人通知视图）。
    /// 这一页不是常驻屏，所以镜像一份状态：先改本地（立刻重绘），再写回单例。
    @State private var shakeOn = ShakeDetector.shared.isEnabled
    @State private var voiceOn = UserDefaults.standard.bool(forKey: "carkeeper_voice_enabled")
    @State private var focusOn = FocusModeManager.shared.config.enabled
    // 这一页里的「去做某件事」全部走 `nav.openMode(...)`（拨到那一档 / 那段），
    // 不再保留一堆从未绑定 sheet 的 @State（此前 7 个磁贴设了状态却没人监听 = 死按钮）。
    @EnvironmentObject var nav: NavState
    // #NEW-115 夜间模式管理
    @StateObject private var nightModeManager = NightModeManager.shared
    /// 档内段落：设置 / 应急 / 诊断。它不是导航层级（见 `HomeSub`）。
    @State private var tab: HomeSub = .settings
    /// 壁纸状态（相册里选的一张图，子页面铺底；用户 2026-09-24「其他页面的背景全部
    /// 设为当前桌面的背景」）。它改的是 App 自己的背景，不是系统的（iOS 没有读
    /// 主屏壁纸的公开 API）。未选图时铺画布（跟随深浅色），不会黑屏。
    @ObservedObject private var wallpaper = WallpaperService.shared
    /// 相册选择器（PhotosPicker）：从相册选一张图铺底（本地，不依赖网络）。
    @State private var wallpaperPickItem: PhotosPickerItem?

    // MARK: 生命周期
    /// 这一档的叠叠乐：巨字头 → 分段控件 → 当前那一段的卡。
    ///
    /// 与「车辆」同理（也是同一天修的同一个 bug）：分段控件与卡表必须和**状态**
    /// 住在同一个视图里。此前它们住在外壳 `MineHubView`，而这一页的 OTA 状态、
    /// 令牌、退出确认全在这里 —— 外壳调 `MineView.sectionCards` 直接编译不过
    ///（instance member 不能当类型成员用），而绕过去也一样是错的：
    /// 那些 `@State` 永远不会被安装，「检查更新」会变成点了没反应的按钮。
    @MainActor
    private var cards: [StackCard] {
        var out = HomeMode.mine.headCards
        out.append(StackCard(id: "tabs", content: AnyView(
            DSSegmented(options: HomeSub.mineTabs.map { (value: $0, title: $0.title) },
                        selection: $tab))))
        switch tab {
        case .emergency:
            out.append(StackCard(id: "emergency", title: "应急",
                                 content: AnyView(EmergencyPanel())))
        case .dev:
            out.append(StackCard(id: "dev", title: "诊断", content: AnyView(DevView())))
        default:
            out.append(contentsOf: sectionCards)
        }
        return out
    }

    /// 消费深链带来的段落提示（`carkeeper://emergency` → 「我的」档的「应急」段）。
    /// 消费掉（置 nil）是必须的：否则从别的档切回来时会被同一条旧提示再拉回那一段。
    private func consumeHint() {
        guard let hint = nav.homeSub, HomeSub.mineTabs.contains(hint) else { return }
        tab = hint
        nav.homeSub = nil
    }

    /// 「设置」这一段的卡（**不含巨字头**，也不含分段控件 —— 那两张在 `cards` 里）。
    ///
    /// 拆卡按问题分：我是谁（账号）、我的车（车辆）、我能改什么（设置）、
    /// 这个 App 是什么（关于）。
    ///
    /// 「设置」与「检查更新」各占**一张**卡（用户 2026-09-23：超长卡拆小卡）——
    /// 旧版把全部设置组塞进一张卡，叠叠乐里永远读不完。拆开后每屏都有得读。
    ///
    /// `private`：它按本页的实时状态现算，只有本视图的 `cards` 有权调它。
    @MainActor
    private var sectionCards: [StackCard] {
        var out: [StackCard] = [
            StackCard(id: "profile", title: "账号", content: AnyView(profileCard))
        ]
        if let car = store.car {
            out.append(StackCard(id: "car", title: "车辆", content: AnyView(carCard(car))))
        }
        out.append(StackCard(id: "settings", title: "设置", content: AnyView(settingsGroups)))
        out.append(StackCard(id: "about", title: "关于", content: AnyView(updateCard)))
        return out
    }

    var body: some View {
        StackPageView(accent: HomeMode.mine.accent, label: "车与账号", cards: cards)
        .pageBackground()
        .dsPageTitle("车与账号")
            .accessibilityLabel(Text("车与账号"))
            .accessibilityHint(Text("账号、车辆、数据、关于"))
        .onAppear { consumeHint() }
        .onChange(of: nav.homeSub) { _, _ in consumeHint() }
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
        .alert("退出登录", isPresented: $logoutConfirm) {
            Button("退出", role: .destructive) { logout() }
            Button("取消", role: .cancel) { }
        } message: {
            Text("退出后需要重新登录，本机记录不会删除。")
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
                    Image(safeSymbol: "chevron.right", fallback: "chevron.right")
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
                        Image(safeSymbol: "clock", fallback: "clock")
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
        // 里程只在车控报文里（getMyCars 的 totalOdometer 恒为 null），所以要把控制缓存传进去；
        // 这里传的是 `store.car`，即当前选中的那辆车 —— 两者必须是同一辆。
        let sum = VM.vehicleSummary(car, store.controlCache)
        return Button {
            // 去看车辆 = 把底部模式条拨到「车辆」那一档（`nav.openMode`）。
            // 此前是 push 一份车辆页 + 更早是发 .navToVehicle 通知 —— 同一个功能
            // 因此有过三种走法（Tab / 通知 / push），每一种的返回行为都不一样。
            nav.openMode(.vehicle)
        } label: {
            HStack(spacing: TokensSpacing.lg) {
                Image(safeSymbol: "car.fill", fallback: "car.fill")
                    .font(TokensTypo.fixed(TokensSize.iconLg))
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
                Image(safeSymbol: "chevron.right", fallback: "chevron.right")
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
    // 后来改成 iOS 设置式的分组，但它仍然自己列了一份功能目录（车辆 / 用车两组，
    // 与地图上那份目录逐行重复）——同一个页面两个入口，正是缝合怪的来源。
    // 那两组已删：**功能目录只有底部模式条一份**，这一页只留设置。
    private var settingsGroups: some View {
        VStack(spacing: TokensSpacing.xl) {
            DSGroup(title: "报告与共享") {
                actionRow("key.fill", "共享钥匙") { showTempKeys = true }
                actionRow("person.2.fill", "家庭管理", last: true) { showFamily = true }
            }

            DSGroup(title: "设备与模式",
                    footer: "摇一摇会真的发锁车指令。") {
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
                // 「全局搜索」那一行已删：全局搜索从项目移除（用户 2026-09-23，
                // 与地图右臂一起）。要找一个功能，走底部模式条 —— 那是**唯一**的目录；
                // 搜索页本身是第二份目录，而且没有任何一条只能从它到达的功能。
                // 此前是空操作（VoiceBroadcastManager 自动启动，点这里什么都不发生）。
                // 现在是真能用的开关：翻转 VoiceBroadcastManager 读取的 UserDefaults 键。
                customRow {
                    DSRow(icon: "speaker.wave.3.fill", title: "语音播报",
                          value: voiceOn ? "已开启" : "已关闭") { toggleVoice() }
                }
                // 壁纸（非地图子页的背景图，用户 2026-09-24「其他页面的背景全部设为
                // 当前桌面的背景」→ iOS 没有读主屏壁纸的公开 API，只能从相册选一张
                // 本地图铺底 —— 不依赖网络，选完落盘，下次启动还在）。
                // 它是一张小卡（不是 DSRow）：上面是缩略图，下面两个小钮（换一张 / 不铺）。
                customRow { wallpaperRow }
                // 「诊断」是「我的」这一档里的第三段（不是另一个页面，也不再是条子上一格）。
                actionRow("wrench.adjustable", "开发者工具") { nav.openMode(.mine, sub: .dev) }
                customRow(last: true) { logoutRow }
            }

            // 「隐私与数据」以前是一个独立浮层，现在就是这一屏里的一节。
            PrivacySection()
        }
    }

    // MARK: 行的三种写法（与全 App 其余 20 屏同一套 DS 原语）

    /// 动作行（开浮层 / 切图层 / 触发一件事）：图标 + 标题 + 箭头
    private func actionRow(_ icon: String, _ title: String, last: Bool = false,
                           _ action: @escaping () -> Void) -> some View {
        DSGroupRow(showsSeparator: !last) {
            DSRow(icon: icon, title: title, showsChevron: true, action: action)
        }
    }

    /// 自定义行（开关 / 选择器 / 第三方视图）：只借用分组的内缩与分隔线
    /// content 必须 @escaping：DSGroupRow 的 content 是存储属性闭包（会逃逸），
    /// 包进它的非逃逸参数会在编译期直接报错（CI 上踩过）。
    private func customRow<V: View>(last: Bool = false,
                                    @ViewBuilder _ content: @escaping () -> V) -> some View {
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
                Text("摇一下手机，发锁车指令（需 PIN）")
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

    /// 壁纸小卡：缩略图（当前那张）+ 两个小钮（换一张 / 不铺）。
    ///
    /// 选图：`PhotosPicker`（系统相册，本地取，不依赖网络）→ 选中后
    /// 异步加载 `Data` → `wallpaper.setPhoto(data)` 落盘（JPEG 0.82）并立即可见。
    /// 换一张 = 重新选一次；不铺 = `clear()`（清图 + 删文件，回落到画布底色）。
    ///
    /// 为什么放在「应用」组（而不是「设备与模式」）：它改的是 **App 自己的背景**，
    /// 不是系统的（壁纸归 SpringBoard 管，iOS 没有读它的公开 API）—— 所以与
    /// 「夜间模式 / 省电模式」那一组（改系统的）不并列，与「语音播报」这组（改 App 行为）并列。
    private var wallpaperRow: some View {
        VStack(alignment: .leading, spacing: TokensSpacing.sm) {
            // 缩略图：选了就画，没选（或点了「不铺」）就画占位（铺画布，不是黑屏）。
            Group {
                if let img = wallpaper.image {
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 120)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    Rectangle()
                        .fill(TokensPalette.fillSubtle)
                        .frame(height: 120)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay {
                            Text("没有选图（铺画布底色）")
                                .font(TokensTypo.caption)
                                .foregroundStyle(TokensPalette.tertiary)
                        }
                }
            }
            // 两个小钮：左边「选一张」（打开相册），右边「不铺」（清图 + 删文件）。
            // 深色模式下选图偏暗会把玻璃卡底下的底也拖暗，所以选图行旁边多给
            // 一句提示：选偏亮、留白多的图（HIG：背景色应当服务于前景可读性）。
            HStack(spacing: TokensSpacing.sm) {
                PhotosPicker(selection: $wallpaperPickItem, matching: .images) {
                    Text("选一张")
                }
                .buttonStyle(.plain)
                .font(TokensTypo.footnote)
                .foregroundStyle(TokensPalette.accent)

                Spacer(minLength: 0)

                Button("不铺") {
                    TokensHaptic.tap()
                    wallpaper.clear()
                }
                .buttonStyle(.plain)
                .font(TokensTypo.footnote)
                .foregroundStyle(TokensPalette.secondary)
            }
            Text("建议选偏亮、留白多的图（深色模式下玻璃卡压在暗图上读不清）")
                .font(TokensTypo.caption2)
                .foregroundStyle(TokensPalette.tertiary)
        }
        .padding(.horizontal, TokensSpacing.sm)
        .padding(.vertical, TokensSpacing.sm)
        // 相册选中的是 `PhotosPickerItem`，要异步加载成 `Data` 才能存盘（项目照片
        // 入口的既定走法，见 Theme.swift 头注）：加载完立刻交给壁纸服务，缩略图与
        // 子页背景同时换过来。
        .onChange(of: wallpaperPickItem) { _, item in
            Task {
                guard let item else { return }
                if let data = try await item.loadTransferable(type: Data.self) {
                    wallpaper.setPhoto(data)
                    TokensHaptic.select()
                }
                wallpaperPickItem = nil
            }
        }
    }

    /// 退出登录。`logout()` 一直存在，但**没有任何按钮调它** —— 它是一段到不了的代码。
    private var logoutRow: some View {
        Button {
            logoutConfirm = true
        } label: {
            HStack(spacing: TokensSpacing.sm) {
                Image(safeSymbol: "rectangle.portrait.and.arrow.right", fallback: "rectangle.portrait.and.arrow.right")
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
                    Text("下载最新 ipa，分享后用自签工具安装")
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
