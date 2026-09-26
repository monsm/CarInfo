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
    @State private var downloadFile: URL? = nil
    @State private var shareItems: [Any] = []
    @State private var shareSheetFlag = false
    @State private var isRefreshing = false     // 下拉刷新进行中标志
    @State private var isChecking = false        // OTA 检查中（不含下载）
    /// 退出登录二次确认（按钮在 tilesCard 的「应用」组里）
    @State private var logoutConfirm = false
    // 这一页里的「去做某件事」全部走 `nav.openMode(...)`（拨到那一档 / 那段），
    // 不再保留一堆从未绑定 sheet 的 @State（此前 7 个磁贴设了状态却没人监听 = 死按钮）。
    @EnvironmentObject var nav: NavState
    /// 档内段落：设置 / 应急 / 诊断。它不是导航层级（见 `HomeSub`）。
    @State private var tab: HomeSub = .settings
    /// 壁纸状态（相册里选的一张图，子页面铺底；用户 2026-09-24「其他页面的背景全部
    /// 设为当前桌面的背景」）。它改的是 App 自己的背景，不是系统的（iOS 没有读
    /// 主屏壁纸的公开 API）。未选图时铺画布（跟随深浅色），不会黑屏。
    @ObservedObject private var wallpaper = WallpaperService.shared
    //  「显示」那一组（文字发光程度 / 玻璃通透度 / 界面实度）已整组删除：
    //  用户 2026-09-26 第 2、3 条 —— 「完全删除文字发光和文字发光功能」与
    //  「玻璃就默认选更透，界面实度默认 50%，删除默认对应的设置入口」。
    //  三个键（`carkeeper_display_glow` / `carkeeper_glass_level` /
    //  `carkeeper_glass_fill`）连它们唯一的读者 `DisplaySettings` 一起删掉：
    //  留着键名而没有人读，是这一仓反复清理的那类「只有写者、没有读者」。
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
    ///
    ///  2026-09-25（用户第 7 条：「我的 去掉电车，因为有车辆入口」）：
    ///  这里原来还有一张 `StackCard(id: "car")` —— 一张写着车名与车牌的「去看车辆」按钮。
    ///  它已经被删。它唯一的动作是 `nav.openMode(.vehicle)`，而 车辆就是模式条上的一档
    ///  （相隔一次拖拽）；一个只用来「跳到隔壁那一档」的入口，在底下导航就摆在屏幕上的
    ///  界面里是纯重复 —— 而它占的是这一页第二张卡的位置（用户看到的「电车」就是它：
    ///  车名来自服务端，不是我们写的字，全仓搜「电车」一处都搜不到）。
    ///  它顺带展示的信息（保险剩多少天）在车辆那一档里本来就有，且更完整。
    @MainActor
    private var sectionCards: [StackCard] {
        var out: [StackCard] = [
            StackCard(id: "profile", title: "账号", content: AnyView(profileCard))
        ]
        out.append(StackCard(id: "settings", title: "设置", content: AnyView(settingsGroups)))
        out.append(StackCard(id: "about", title: "关于", content: AnyView(updateCard)))
        return out
    }

    var body: some View {
        StackPageView(accent: HomeMode.mine.accent, label: "车与账号", cards: cards)
        .dsPageTitle("车与账号")
            .accessibilityLabel(Text("车与账号"))
            .accessibilityHint(Text("账号、设置、应急、诊断、关于"))
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
        .sheet(isPresented: $shareSheetFlag) { ShareSheet(items: shareItems) }
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
                        .background(Circle().fill(TokensPalette.fillSubtle))

                    VStack(alignment: .leading, spacing: TokensSpacing.xs) {
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
        VStack(alignment: .leading, spacing: TokensSpacing.xxs) {
            Text(label)
                .font(TokensTypo.caption2.weight(.medium))
                .foregroundStyle(TokensPalette.tertiary)
            HStack(alignment: .firstTextBaseline, spacing: TokensSpacing.xxs) {
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

    // MARK: 设置分组（inset-grouped 行）
    //
    // 旧写法是 6 个 `CardBox`，每个里面再摆 2 列「Tesla 式磁贴」（一共 28 个）——
    // 那是**第三套容器 + 第三套行**：全 App 只有这一页这么排，从别的页面走进来像换了一个 App。
    // 后来改成 iOS 设置式的分组，但它仍然自己列了一份功能目录（车辆 / 用车两组，
    // 与地图上那份目录逐行重复）——同一个页面两个入口，正是缝合怪的来源。
    // 那两组已删：**功能目录只有底部模式条一份**，这一页只留设置。
    private var settingsGroups: some View {
        VStack(spacing: TokensSpacing.xl) {
            //  这里原本有两组：「报告与共享」（共享钥匙 / 家庭管理）与
            //  「设备与模式」（摇一摇锁车 / 省电模式 / 夜间模式 / 专注模式）。
            //
            //  用户 2026-09-25 第 4 与第 7 条要求删掉它们，明暗改由系统决定
            //（「全部删除 明暗根据系统获取」）。删的不是几个开关，是四个功能：
            //    · 共享钥匙 / 家庭管理 → `TempKeyManager` / `FamilyManager` 与两个页面
            //    · 摇一摇锁车 → `ShakeDetector`
            //    · 省电模式 → `PowerSavingToggle`
            //    · 专注模式 → `FocusModeManager`
            //    · 夜间模式 → `NightModeManager`（App 根部不再有 `.preferredColorScheme`，
            //      nil 就是跟随系统 —— 与 iOS 其余部分一致）
            //  只服务它们的那几个文件、启动时那几行初始化、以及它们各自的键，
            //  一起删干净 —— 留下「代码在、没人能到」正是这个仓库一直在删的东西。

            DSGroup(title: "应用") {
                // 「全局搜索」那一行已删：全局搜索从项目移除（用户 2026-09-23，
                // 与地图右臂一起）。要找一个功能，走底部模式条 —— 那是**唯一**的目录；
                // 搜索页本身是第二份目录，而且没有任何一条只能从它到达的功能。
                // 「语音播报」那一行已删（用户 2026-09-25 第 7 条）。
                // 更值得记的是它为什么删得掉：它翻转的是 `carkeeper_voice_enabled`，
                // 而**全仓没有一个读者** —— `VoiceBroadcastManager` 这个类型早就不存在了，
                // 车控页那枚也没有显示过（那一页的导航栏是隐藏的）。
                // 一个只有写者、没有读者的开关，是这个仓库里最贵的一种摆设。
                // 壁纸（非地图子页的背景图，用户 2026-09-24「其他页面的背景全部设为
                // 当前桌面的背景」→ iOS 没有读主屏壁纸的公开 API，只能从相册选一张
                // 本地图铺底 —— 不依赖网络，选完落盘，下次启动还在）。
                // 它是一张小卡（不是 DSRow）：上面是缩略图，下面两个小钮（换一张 / 不铺）。
                customRow { wallpaperRow }
                // 「诊断」是「我的」这一档里的第三段（不是另一个页面，也不再是条子上一格）。
                actionRow("wrench.adjustable", "开发者工具") { nav.openMode(.mine, sub: .dev) }
                customRow(last: true) { logoutRow }
            }

            // 「显示」那一节（三行观感开关）已整组删除，见页头那一段。

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
            // 图源：相册自选 / 必应每日 / Windows 聚焦。
            // 三条里相册那条不联网；另外两条是免密钥的公开取图口，每天自动换一张。
            //
            //  ⚠️ 2026-09-26 第一次改：从 `Picker(.menu)` 换成自己写的 `Menu`。
            //  起因是用户报「选了 Windows 聚焦就无法再下拉选其他了」。
            //
            //  ⚠️⚠️ 同一天第二次改（同一句话没修好）：用户补了更完整的复现 ——
            //  「图源不换页面的情况下可以一直换，但是换了其他页面回来，如果上次是
            //   windows 聚焦，那就再也点不动，重开软件都不行，只能点不铺，再重新选」。
            //  两个事实加起来把嫌疑从**那一档**移到了**那一下弹窗**：
            //    · 「重开软件都不行」= 状态是持久的（`source` 落盘）——所以不是某一次
            //      手势丢了，而是「一进来就是这个样子」；
            //    · 「只能点不铺」= 同一张卡里别的按钮还能按 ——所以不是整片被挡住。
            //  两次换的都是**弹窗**（先是系统的 `Picker` 菜单，后是自己写的 `Menu`）。
            //  本机没有编译器、也没有那台设备，这个机制我复现不了 —— 所以这一版
            //  **不再依赖「弹窗能不能打开」**：三个选项直接**摆在行里**，一下就是一下
            //  （分段控件是系统控件里对「三道门」这件事的标准答案：没有第四种东西
            //  要弹出来，也就没有「弹不出来」这回事）。
            //
            //  代价写在这里：段名只能短（一行装不下三个全名），所以全名留在上面那一行
            //  的当前值里，而「它是什么」在下面那行说明里（`note`）。
            HStack {
                Text("背景图")
                    .font(TokensTypo.body)
                    .foregroundStyle(TokensPalette.primary)
                Spacer(minLength: TokensSpacing.sm)
                Text(wallpaper.source.title)
                    .font(TokensTypo.body)
                    .foregroundStyle(TokensPalette.secondary)
            }
            .frame(minHeight: TokensSpacing.row)
            DSSegmented(options: WallpaperSource.allCases.map { (value: $0, title: $0.segmentTitle) },
                        selection: Binding(get: { wallpaper.source },
                                           set: { pickSource($0) }))
                .accessibilityLabel(Text("背景图来源"))

            // 缩略图：铺的就是这一张。没图（没选 / 没取到 / 点了「不铺」）画占位。
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

            // 两个小钮：相册那一档才需要「选一张」；有图时才给「不铺」。
            HStack(spacing: TokensSpacing.sm) {
                if wallpaper.source == .photo {
                    PhotosPicker(selection: $wallpaperPickItem, matching: .images) {
                        Text("选一张")
                    }
                    .buttonStyle(.plain)
                    .font(TokensTypo.footnote)
                    .foregroundStyle(TokensPalette.accent)
                    // 三个小钮都按 HIG 的最小触控目标给足 44pt（2026-09-25）：
                    // 它们原本只有一行 13pt 高的字，按中全靠运气。
                    .frame(minHeight: TokensSpacing.row)
                    .contentShape(Rectangle())
                }

                Spacer(minLength: 0)

                // 取图失败时给一个出口：否则「取图没成功」就是一句没有下文的话。
                if wallpaper.failed {
                    Button("重试") {
                        TokensHaptic.tap()
                        wallpaper.reload()
                    }
                    .buttonStyle(.plain)
                    .font(TokensTypo.footnote)
                    .foregroundStyle(TokensPalette.accent)
                    .frame(minHeight: TokensSpacing.row)
                    .contentShape(Rectangle())
                }

                if wallpaper.image != nil {
                    Button("不铺") {
                        TokensHaptic.tap()
                        wallpaper.clear()
                    }
                    .buttonStyle(.plain)
                    .font(TokensTypo.footnote)
                    .foregroundStyle(TokensPalette.secondary)
                    .frame(minHeight: TokensSpacing.row)
                    .contentShape(Rectangle())
                }
            }

            // 一句来源说明 + （相册档才有的）选图提示 + 取图失败时的一句人话。
            // 深色模式下选图偏暗会把玻璃卡底下的底也拖暗：HIG 说背景色应当服务于
            // 前景可读性，所以相册那一档多给一句。
            Text(wallpaper.source.note)
                .font(TokensTypo.caption2)
                .foregroundStyle(TokensPalette.tertiary)
            if wallpaper.source == .photo {
                Text("选偏亮、留白多的图（深色模式下玻璃卡压在暗图上读不清）")
                    .font(TokensTypo.caption2)
                    .foregroundStyle(TokensPalette.tertiary)
            }
            if wallpaper.failed {
                Text("取图没成功，先铺画布底色")
                    .font(TokensTypo.caption2)
                    .foregroundStyle(TokensPalette.warning)
            }
            if !wallpaper.credit.isEmpty {
                Text(wallpaper.credit)
                    .font(TokensTypo.caption2)
                    .foregroundStyle(TokensPalette.tertiary)
                    .lineLimit(2)
            }
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

    /// 选一档图源。**已经是这一档时**不是「什么都不发生」—— 那是「再取一次」
    /// （分段控件会把同一个值再写一次，所以「点当前那一档」自然走到这里）。
    /// 用户第 1 条那句「只能点不铺，再重新选」的另一面就是这个：这一行不该有死路口。
    private func pickSource(_ s: WallpaperSource) {
        TokensHaptic.select()
        if s == wallpaper.source { wallpaper.reload() } else { wallpaper.use(s) }
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
            .padding(.vertical, TokensSpacing.snug)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: 检查更新
    private var updateCard: some View {
        // 整块是一行：上面的说明、进度与三个按钮都属于「检查更新」这一件事。
        DSGroup(title: "检查更新") {
            customRow(last: true) {
                VStack(alignment: .leading, spacing: TokensSpacing.snug) {
                    Text("下载最新 ipa，分享后用自签工具安装")
                        .font(TokensTypo.caption).foregroundStyle(TokensPalette.secondary)
                    // OTA 检查中：骨架旋转指示器
                    if isChecking {
                        HStack(spacing: TokensSpacing.snug) {
                            ProgressView()
                                .tint(TokensPalette.ambient)
                            Text("正在检查最新版本…")
                                .font(TokensTypo.caption)
                                .foregroundStyle(TokensPalette.secondary)
                        }
                        .padding(.vertical, TokensSpacing.sm)
                    } else if showDownload {
                        // 下载中：进度条 + 百分比数字
                        VStack(spacing: TokensSpacing.sm) {
                            ProgressView(value: downloadPct)
                                .tint(TokensPalette.ambient)
                            Text("正在下载… \(downloadPctDisplay)%")
                                .font(TokensTypo.caption).foregroundStyle(TokensPalette.secondary)
                        }
                    } else if let m = updateMsg {
                        // 错误或提示消息（图标由 updateMsgIsError 决定）
                        HStack(spacing: TokensSpacing.sm) {
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
                    HStack(spacing: TokensSpacing.snug) { updateButtons() }
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
        HStack(spacing: TokensSpacing.snug) {
            mainUpdateButton
            if downloadFile != nil { shareButton }
        }
    }

    private var mainUpdateButton: some View {
        Button {
            checkUpdate()
        } label: {
            HStack(spacing: TokensSpacing.sm) {
                if updateBusy { ProgressView().controlSize(.mini).tint(TokensPalette.labelOnTint) }
                Text(updateBusy ? "检查中…" : "检查更新")
                    .font(TokensTypo.caption.weight(.bold))
            }
            .foregroundStyle(TokensPalette.labelOnTint)
            .padding(.vertical, TokensSpacing.snug)
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
                .padding(.horizontal, TokensSpacing.md).padding(.vertical, TokensSpacing.snug)
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
                //  这里原本有一道「令牌为空就先退出」的早返回（一句「没有配访问令牌」）。
                //  2026-09-25 第 9 条实测后删掉：仓库是**公开库**，匿名就能读 Release
                //（`curl` 的返回记在 `GithubToken.swift`），所以令牌为空是**默认状态**，
                //  不是一种失败。留着那一道，按钮按下去就只会吐一句话，而明明能办成。
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
