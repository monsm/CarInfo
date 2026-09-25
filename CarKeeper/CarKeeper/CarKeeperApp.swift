import SwiftUI
import UIKit

// App 入口：未登录 → 登录页；已登录 → **地图主屏（唯一的屏）**。
//
// 导航模型（2026-09-23 定案）：**没有 Tab 栏，也没有第二份目录**。地图是家：
//   • 底部模式条 = **唯一**的一级入口（6 档 = 6 个功能界面，相机 App 那条的移植）
//   • 「现在」那一档里的四个图层 = 四个真实问题（现在 / 行程 / 停车 / 充电），**二级**选择
//   • 属于某一档的页面不再 push 第二份：拨条子即可（深链也走 `openMode`）
//   • 不是档位的东西（隐私 / OTA / 家庭 / 钥匙）才 push 到同一个 NavigationStack
//
// 为什么删掉 5 Tab 骨架：Tab 栏建立的是「五个平行 App」的心智，而地图主屏建立的是
// 「一切都在地点上」。两套 IA 同时存在时，同一个功能最多有 4 个入口
// （Tab / 地图图层 / 索引页 / 「我的」的 27 个磁贴 —— 这四套已在 09-22 与 09-23
// 两轮里全部改掉／删掉，最后连「索引页」那份目录也删了）—— 那就是「缝合怪」的来源。
// `MainTab`、`selectedTab`、每 Tab 一个 path、Tab 角标与切 Tab 朗读都已整体删除。

// 只有**真的有人 post、也真的有人听**的通知才配留在这里。
//
// 2026-09-23 清掉了五个「有名字、没发射」的：`.navToVehicle` / `.navToHealth` /
// `.navToBattery` / `.navToDev` / `.navHome`。它们各自只有一个观察者（在根视图里
// 写 `nav.path = [...]`），而**全项目没有任何地方 post** —— 既是从未生效的死线，
// 又是与底部模式条并行的第二条导航路径（同一个功能能顺着模式条走，也能顺着通知走）。
// 去功能只有一个走法：`NavState.openMode(_:)`。
extension Notification.Name {
    static let pinConfirmed = Notification.Name("car_pin_confirmed")
    static let tempConfirmed = Notification.Name("car_temp_confirmed")
    static let didLogout = Notification.Name("didLogout")
    /// 车的位置变了。**发射点只有一个**：`AppStore.saveCache`（location 缓存的唯一写入点）。
    static let locationUpdated = Notification.Name("locationUpdated")
}

// MARK: - 深潜页（唯一的导航目标）

/// 所有深潜页。**它们不再归属任何 Tab** —— 地图是家，底部模式条是唯一的目录。
///
/// `.dashboard` 与 `.parking` 保留为深链别名（`carkeeper://dashboard`、
/// `carkeeper://parking` 仍然可用），但它们**指向的页面与 `.score` / `.trips` 是同一个**，
/// 所以模式条上不列这两个入口：同一页摆两个入口，正是「缝合怪」的第一来源。
enum Deeplink: Hashable, CaseIterable {
    // `.data`（全量数据页）已删：原始字段并进体检与数据（`RawDataSection`），
    // 结论与依据同源，不再分两屏。
    // `.messages`（消息页）已删：车的事件并进出行页（`MessagesSection`）——
    // 消息流里的点火/熄火事件本来就是行程的骨架，两页读同一件事。
    case vehicle, health, battery, dev, control, dashboard
    // `.commands`（指令历史页）已删：历史就是车控页里「做过什么」那一节，
    // 同一件事不再有两个界面（详情见 ControlView 的 historyCard 注释）。
    // `.tips`（车辆提示页）已删：提示是从这辆车的读数推出来的，已并入车辆档案
    // （`VehicleTipsSection`），不再单占一个深链。
    // `.export`（导出数据页）已并入保养与钱（`ExportDataSection`）。
    case trips, service, parking, emergency, score
    /// 「车与账号」（原「我的」Tab 的根页）。设置类内容的去处 —— 它不是功能目录，
    /// 功能目录归底部模式条；这个深链保证它不再依附于 Tab 才能到达。
    case mine

    /// 深链 key，对应 carkeeper://<key>
    var key: String {
        switch self {
        case .vehicle: return "vehicle"
        case .health: return "health"
        case .battery: return "battery"
        case .dev: return "dev"
        case .control: return "control"
        case .dashboard: return "dashboard"
        case .trips: return "trips"
        case .service: return "service"
        case .parking: return "parking"
        case .emergency: return "emergency"
        case .score: return "score"
        case .mine: return "mine"
        }
    }

    /// 解析 carkeeper://vehicle 或 carkeeper:///vehicle；无法识别返回 nil
    init?(url: URL) {
        guard url.scheme?.lowercased() == "carkeeper" else { return nil }
        let raw = (url.host ?? url.path)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()
        guard !raw.isEmpty, let match = Self.allCases.first(where: { $0.key == raw }) else { return nil }
        self = match
    }
}

// MARK: - 场景标识

/// 窗口场景标识。
///
/// #47 分屏的「场景声明」与「打开入口」必须用同一个字符串：`openWindow(id:)` 传了
/// 不存在的标识既不会报错、也不会打开任何东西（点了完全没反应），所以收成常量，
/// 避免两处各写一份字面量后打错。
enum SceneID {
    static let detail = "detail"
}

// @main 必须紧贴 App 结构体：属性绑定到「下一个声明」，中间若插入任何类型（哪怕是
// 一行常量枚举）就会静默接管入口 —— CI 曾因此报 SceneID 缺少 main()。注释不算声明，
// 但为避免再踩，这里不再往 @main 与 struct 之间放任何东西。
@main
struct CarKeeperApp: App {
    private let store = AppStore.shared
    @StateObject private var nav = NavState.shared

    init() {
        // 后台刷新（BGTask）已删：免费开发者账号没有 BGTaskScheduler 权限，
        // 调用 register 会抛 ObjC 异常直接杀进程。若将来升级付费账号再恢复。
        //
        // 启动轨迹：**最早的一步**就在这里。用户 2026-09-24 报「载入不到 10 秒就闪退、
        // 系统里没有日志」—— 那类终止不会调用 App 的任何代码，所以路标要在死之前写好。
        StartupJournal.shared.begin()
        // 信号捕获（临时仪器，见 LaunchFence）：与轨迹配套装在这里。
        // 1 秒心跳只能说明「进程在某一秒没了」，纸条才能说明
        // 「是我们自己的代码崩的（带调用栈）还是被系统拿走的（什么都没有）」。
        StartupJournal.shared.catchSignalDeaths()
    }

    var body: some Scene {
        WindowGroup {
            root
                // 明暗：**跟随系统**（用户 2026-09-25 第 4 条：「明暗根据系统获取」）。
                //
                // 这里原本是 `.preferredColorScheme(nightMode.schemeOverride)` ——
                // 「我的 → 夜间模式」是那个值唯一的写者，而它随「设备与模式」一起删了。
                // 不设就是 nil、就是跟随系统，与 iOS 其余部分一致；再留一个空的
                // `.preferredColorScheme(nil)` 只会让人以为还有什么在决定明暗。
        }
        // #47 iPad 分屏：第二个窗口（原写成 `os(iOS) && os(macOS)` 恒为假，导致该场景从未注册）。
        // 能否真正被打开由「平台 + Info.plist 的 UIApplicationSceneManifest.UIApplicationSupportsMultipleScenes」
        // 共同决定；入口在地图主屏的工具栏，用 supportsMultipleWindows 判定。
        //
        // ⚠️ 两个场景当前共用 NavState.shared（详见 DetailSplitView 的说明）：副窗口与主窗口是
        //    同一份导航状态 —— 同一条路径。即“能同时看两个窗口”，但还不是两块独立画布。
        WindowGroup(id: SceneID.detail) {
            DetailSplitView()
        }
    }

    // #NEW-112 启动画面控制
    // 围栏控制（见 LaunchFence）：关掉时直接进主界面，少一次整棵树重建。
    @State private var showSplash = LaunchFence.splash
    @State private var isAppLoading = false
    // #NEW-113 Onboarding 引导状态
    @AppStorage("carkeeper_onboarding_seen") private var onboardingSeen = false

    /// 处理 carkeeper:// 深链。
    /// 此前 Info.plist 注册了 scheme，但全项目没有任何 onOpenURL 接收方 —— 扫二维码/点链接豪无反应。
    /// 现在只有一个栈，所以深链就是「把它设为根之下的那一页」。
    private func openDeeplink(_ url: URL) {
        guard let link = Deeplink(url: url) else { return }
        guard store.isLoggedIn else { return }   // 未登录时先让用户完成登录，登录后可从界面进入
        // 深链也不准开出「第二份页面」：一律拨到对应档位（+ 档内段）。
        // 此前写的是 `nav.path = [link]` —— 于是 `carkeeper://vehicle` 会开出一份
        // 与「车辆」那一档内容完全相同的跳入式页面，两种返回行为、两套排版。
        nav.openMode(for: link)
    }

    private var root: some View {
        Group {
            if showSplash {
                SplashView()
                    .ignoresSafeArea()
                    .onAppear { isAppLoading = true }
                    .task {
                        // 模拟加载延迟后显示主界面
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        showSplash = false
                        StartupJournal.shared.mark("启动动画结束")
                    }
            } else if !onboardingSeen && !store.isLoggedIn {
                // #NEW-113 Onboarding 引导
                OnboardingView()
            } else if store.isLoggedIn {
                MapShellView()
                    .environmentObject(nav)
                    .onReceive(ToastManager.shared.$currentItem) { item in
                        nav.currentToast = item
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .didLogout)) { _ in
                        nav.path = []
                    }
            } else {
                LoginView()
            }
        }
        // 画布与光在**根部只画一次**（Design/Theme.swift 的 AppCanvas）：
        // 全 App 每一屏共用同一束由车所在地算出的光。逐屏去加，一定会有屏幕漏掉。
        .background { AppCanvas() }
        .onAppear {
            StartupJournal.shared.mark("根视图出现")
            // 启动阶段 = 12 秒：走完才在轨迹里写收尾标记。
            // 没有收尾标记 = 上一次没走完 —— 那一条会显示在「我的 → 诊断 → 上一次启动」。
            StartupJournal.shared.scheduleFinish()
            // 启动时若已登录但数据未加载，异步拉取一次数据。
            // ⚠️ 不阻塞 UI：用户可以先看到地图壳，数据在后头悄悄补上。
            if store.isLoggedIn && store.cars.isEmpty {
                Task {
                    StartupJournal.shared.mark("取车辆列表开始")
                    await store.bootstrap()
                    StartupJournal.shared.mark(store.cars.isEmpty ? "取车辆列表没拿到" : "车辆就绪")
                }
                // bootstrap 是异步的：如果它因 token 过期失败了（已处理 logout），
                // 或者因为网络慢还没完成，用户可能先进入了出行页看到空白消息。
                // 这里再加一层兜底：bootstrap 完成后如果 cars 仍然为空，提示用户。
                Task {
                    await store.bootstrap()
                    if store.isLoggedIn && store.cars.isEmpty {
                        Task { @MainActor in
                            ToastManager.shared.show("数据加载失败，请检查网络后重试", icon: "wifi.exclamationmark")
                        }
                    }
                }
            }
            // 天气实况（光需要云量）：有车的位置就取一次。
            // 取不到就退回「晴空模型」，界面上照实写明 —— 不拿默认值冒充实况。
            if let c = store.currentLocation?.coordinate {
                Task {
                    StartupJournal.shared.mark("取天气开始")
                    await WeatherService.shared.refreshIfNeeded(coordinate: c)
                    StartupJournal.shared.mark("取天气结束")
                }
            }
            // #N38 崩溃上报（CrashReporter）已删：它把崩溃历史写进 UserDefaults
            // 只为给「诊断」页看，用户明确要求把这类本机统计一并去掉。
            if LaunchFence.launchServices {
                // #N39 内存监控启动（不落盘，只是此刻的读数）
                MemoryMonitor.shared.startMonitoring(interval: 10)
                // #N37 网络质量监控
                _ = NetworkQualityMonitor.shared
                // #N41 离线模式监听
                _ = OfflineModeManager.shared
                // 通知授权：**向正在发通知的那一条路要**。
                //
                // 2026-09-25 地毯式审核删掉了 `SmartNotificationManager`（N15–N20）：
                // 六个通知类型各自的方法**一处调用都没有**，而它在启动时做的事是
                // 「弹一次授权 + 注册三个分类」—— 那三个分类的动作（立即充电 /
                // 稍后充电 / 查看脸压 / 关闭勿扰）全仓又没有 `UNUserNotificationCenterDelegate`，
                // 点了什么也不会发生。于是它对用户的全部影响就是启动时多一个权限弹窗。
                // 真正会发通知的三条路各自都在：`ChargingStatusMonitor`（充电开始/结束，
                // 报文驱动）、`MaintenanceReminderScheduler`（里程保养）、
                // `InsuranceReminderScheduler`（保险到期）—— 后两条自己申请授权，
                // 充电那条由下面这一行申请（它读的是同一个系统权限，只会弹一次）。
                Task { await ChargingStatusMonitor.shared.requestAuthorization() }
                // #N14 远程锁定监听
                RemoteLockManager.shared.startMonitoring()
                // #NEW-118/N119 维保+保险提醒调度器初始化
                _ = MaintenanceReminderScheduler.shared
                _ = InsuranceReminderScheduler.shared
                // #NEW-120 Siri/快捷指令：真正的 AppIntent 在 Features/SiriShortcuts.swift。
                // 旧的那份 `AppIntentsManager`（空桩）已删；旧的 INIntent 子类也没有
                // Intent Extension target 去注册，永远不可能被唤起。
                // E47 性能监控（PerformanceTracker）已删：页面耗时与接口成功率两项
                // 都是写进 UserDefaults 给「诊断」页看的本机统计，属这一轮要删的东西。
                // E40 充电状态监控（此前只写了 `_ = ChargingStatusMonitor.shared`，
                // 连 startMonitoring 都没调，而那个方法本身也是空的）
                ChargingStatusMonitor.shared.startMonitoring()
                // N10「车牌加密初始化」（`DataEncryption.ensureKey()`）已删：
                // 它生成的那把密钥没有任何代码去读（见 AppStore 里同一处的说明）。
            }
        }
        .onOpenURL { url in
            openDeeplink(url)
        }
        .onReceive(NotificationCenter.default.publisher(for: .locationUpdated)) { _ in
            // 车的位置变了就重取天气（TTL 内且没走远时 refreshIfNeeded 会挡掉，不发请求）
            guard let c = store.currentLocation?.coordinate else { return }
            Task { await WeatherService.shared.refreshIfNeeded(coordinate: c) }
        }
        // 注意：根视图上不得再挂任何「无限循环动画」修饰符。
        // 它们会让整棵视图树反复失效，深色模式下表现为整屏发暗发黏，且持续耗电。
    }
}

// 全局导航状态（深潜页 push 与 tab 切换共享）
final class NavState: ObservableObject, @unchecked Sendable {
    static let shared = NavState()
    /// **唯一**的导航路径。地图主屏与所有深潜页共用它 —— 没有第二个栈。
    @Published var path: [Deeplink] = []
    @Published var currentToast: (text: String, icon: String)? = nil
    // `showSearch`（全局搜索是否展开）已删：全局搜索本身已从项目移除（用户 2026-09-23），
    // 三个入口（地图右臂 / 「我的」那一行 / 这里的状态）一起走 —— 留一个状态量
    // 只会变成一个「点了什么也不发生」的按钮。
    /// 档内段落的提示（深链用，如 `carkeeper://health` = 车辆档的健康段）。
    /// 那一档的页面（`VehicleView` / `MineView`）消费它之后置 nil ——
    /// 消费掉是必须的，否则会反复被拉回那一段。
    @Published var homeSub: HomeSub? = nil

    private init() {}

    /// 回栈顶。现在栈**永远是空的**（见 `path` 上的说明），保留它是因为
    /// 「回到地图」这个动作在几处收尾逻辑里仍然要表达一次。
    func popToRoot() { path = [] }

    /// 进入某一档功能界面 —— **去功能只有这一种走法**。
    ///
    /// 功能界面不是一个「页面」，而是底部模式条上的一档（`HomeMode`）：
    /// 地图是载体，模式条决定纸里装什么。所以「去看车辆」的正确做法是
    /// **拨到那一档**，而不是 push 出第二份同样内容的页面。
    ///
    /// 只做两件事：写 `HomeMode` 的持久化键（`MapSpineView` 用 `@AppStorage`
    /// 订阅它，条子会自己滑过去）+ 清空栈回到地图。
    /// `sub` 是档内段落（车辆：档案/健康/保养；我的：设置/应急/诊断）。
    func openMode(_ mode: HomeMode, sub: HomeSub? = nil) {
        UserDefaults.standard.set(mode.rawValue, forKey: HomeMode.storageKey)
        homeSub = sub
        path = []
    }

    /// 按深链进：**每个深链都落到某一档**（`HomeMode.destination(for:)`）。
    ///
    /// 这里曾有一个 push 分支（「对应不到的：隐私 / OTA / 家庭 / 钥匙」）。
    /// 那些页面现在都住在「我的」档里，而功能界面只有模式条这一种存在方式 ——
    /// 于是全库再没有任何地方 push 页面，栈永远是空的。
    func openMode(for link: Deeplink) {
        let to = HomeMode.destination(for: link)
        openMode(to.mode, sub: to.sub)
    }
}

// MARK: - 地图外壳（唯一的屏）

// 壳层约定（取代此前 5 Tab 骨架）：
//   • **一个** NavigationStack：根是地图主屏，深潜页 push 在上面；
//     返回手势、返回按钮、转场动画全部交给系统。
//   • **一个**目录：底部模式条（索引页那一份「全部功能」清单也已删 —— 它是第二份目录）。
//   • Tab 栏及其附带物（选中值、每 Tab 一个 path、角标、切 Tab 朗读）已删。
//     代价是高频操作会多一次点击 —— 它们应该在批 1 以「地图上的常驻操作条」补回来，
//     而不是把 Tab 栏加回来（「高频操作」的答案在地图上，不在另一层导航上）。

struct MapShellView: View {
    @StateObject private var nav = NavState.shared
    private let store = AppStore.shared
    /// 低电量只提醒一次：跌破 20% 时给一条 Toast，回到 20% 以上才重新武装。
    /// （旧写法是 Tab 上的角标 —— 角标随 Tab 栏一起不存在了，改挂在既有的 Toast 上。）
    @State private var lowBatteryArmed = true
    private let networkMonitorTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    // 这里原有 `deeplinkDestination(_:)`（深链 → push 一份页面）。已删：
    // 现在每个深链都落到模式条上的某一档 + 档内某一段（`HomeMode.destination`），
    // 所以「深潜页」这件事不再存在 —— 功能界面只有一种存在方式。

    /// 唯一的栈：根是地图主屏（Features/Map/MapSpineView.swift）。
    /// 车的一切都发生在某个地方，所以导航长在地方上；
    /// 四个图层 = 四个真实问题（二级选择），一级入口是底部模式条。
    private var mapStack: some View {
        NavigationStack(path: $nav.path) {
            MapSpineView()
                // 没有 `.navigationDestination`：栈里不放任何页面 ——
                // 功能界面是模式条上的一档，不是 push 出来的第二份内容。
                // 导航栏材质交给系统：iOS 26/27 会在内容滚动到其下方时自动给出材质。
                // 手写 .toolbarBackground 反而会把系统行为覆盖掉。
        }
            // 低电量：跌破 20% 给一次提示，回到 20% 以上才重新武装
            .onReceive(NotificationCenter.default.publisher(for: .locationUpdated)) { _ in
                let energy = VM.energy(store.caches, store.car)
                if energy.socPct < 20, lowBatteryArmed {
                    lowBatteryArmed = false
                    nav.currentToast = (text: "电量低于 20%", icon: "battery.25")
                } else if energy.socPct >= 20 {
                    lowBatteryArmed = true
                }
            }
            .onReceive(networkMonitorTimer) { _ in
                // #4 简单网络检测：尝试 ping 一个已知端点
                let api = APIClient.shared
                Task { @MainActor in
                    do {
                        _ = try await api.getCars()
                        store.updateNetworkStatus(.online)
                    } catch {
                        let networkError = error is URLError || (error as? APIError) != nil
                        store.updateNetworkStatus(networkError ? .weak : .offline)
                    }
                }
            }
    }

    var body: some View {
        // 情感化配色：时间感知主色调（系统控件的主色调）
        mapStack
        .tint(TokensPalette.ambient)
        .task {
            StartupJournal.shared.mark("首页外壳出现")
            await store.bootstrap()
            StartupJournal.shared.mark(store.cars.isEmpty ? "首页：车辆列表为空" : "首页：车辆就绪")
            // 自动刷新的节律循环（一个，见 `RefreshLoop`）：地图页 2s/60s，其余档 5 分钟。
            // 放在这里而不是各页的 `.task` —— 六页是同时建出来的，每页一个定时器就是六个循环。
            RefreshLoop.shared.start()
            StartupJournal.shared.mark("自动刷新已起（节律 \(Int(RefreshLoop.shared.interval))s）")
        }
        // VoiceOver：这是一个「地图 + 底部模式条」的外壳，不再是一条 Tab 栏
        .accessibilityLabel(Text("地图主屏"))
        .accessibilityHint(Text("底部的模式条可以到达每个功能界面"))
        .accessibilitySortPriority(0)
        // #4 网络状态指示器 + #NEW-3 离线模式提示
        .overlay(alignment: .top) {
            if store.networkStatus != .online || store.isOfflineMode {
                NetworkStatusIndicator(status: store.isOfflineMode ? .offline : store.networkStatus)
                    .padding(.top, 0)
            }
        }
        // Toast 浮层**已搬进 `MapSpineView`**（2026-09-25 用户第 2 条：
        // 「电量低于 X 的提醒挡住了底部导航」）。
        //
        // 它原来是这里的一个 `.overlay(alignment: .bottom)` —— 对齐到**屏幕底**，
        // 而模式条就长在那里，于是那颗胶囊正好压在条子上。
        // 「要抬多高」只有知道条子几何的那一处答得出（`MapSpineView.barTotal`），
        // 所以浮层跟着条子走，而不是在这里再抄一份条高（抄的那一份一定会漂）。
        // 全局搜索（`GlobalSearchHUD` + 它的 fullScreenCover）已整体删除：
        // 用户 2026-09-23「右下角的搜索功能从项目移除」。
        // 这个 HUD 的两层东西都被更直接的东西接走了：一层是「去找某个功能」——
        // 那是底部模式条的活；一层是把背景压暗的「暗层」——本轮的规则是不再加。
    }
}

// MARK: - #47 iPad Split View 支持

/// 第二个窗口（`WindowGroup(id: SceneID.detail)`）的根视图，由 iPad 分屏入口打开。
///
/// ⚠️ 它用的是共用的 `NavState.shared`，所以副窗口与主窗口是**同一份导航状态**：
///    `MapShellView` 内部是 `@StateObject private var nav = NavState.shared`（读单例、不读环境），
///    两个场景因此绑定到同一个实例，push 出来的页面在两窗口间完全同步。
///    要让两个窗口真正各走各的：NavState 去掉单例、由每个 Scene 各建一个实例并通过
///    `.environmentObject` 注入（代码里已没有直接写 `NavState.shared` 的地方）。
struct DetailSplitView: View {
    @StateObject private var nav = NavState.shared
    private let store = AppStore.shared

    var body: some View {
        Group {
            if store.isLoggedIn {
                MapShellView()
                    .environmentObject(nav)
            } else {
                LoginView()
            }
        }
        // 副窗口也共用同一束光（两个窗口的光方向不一样，比没有光更糟）
        .background { AppCanvas() }
    }
}

// MARK: - NetworkStatusIndicator
struct NetworkStatusIndicator: View {
    let status: AppStore.NetworkStatus
    var body: some View {
        Text("网络: " + status.rawValue).font(TokensTypo.caption).foregroundStyle(TokensPalette.secondary)
    }
}

// MARK: - ToastView
struct ToastView: View {
    let text: String
    let icon: String?
    var body: some View {
        HStack(spacing: TokensSpacing.sm) {
            if let icon = icon { Image(safeSymbol: icon, fallback: icon) }
            Text(text)
        }
        .padding(.horizontal, TokensSpacing.md).padding(.vertical, TokensSpacing.sm)
        // 2026-09-25 材质审核：轻提示浮在**所有内容之上**（它是这一层的定义），
        // 从前却是一块 90% 不透明的扁平色 —— 底下是什么完全看不见。
        // 现在走 `dsGlass`：它飘着的时候，下面的界面真的从它后面透出来。
        .dsGlassRounded(TokensRadius.medium, interactive: false)
        // 字走 `TokensInk`：这一层底下永远是**活的内容**（它浮在整屏之上），
        // 固定标签色在彩色壁纸/地图上会读不出来（用户第 10 条）。
        .foregroundStyle(TokensInk.primary)
    }
}


