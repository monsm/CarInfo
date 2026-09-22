import SwiftUI
import UIKit

// App 入口：未登录 → 登录页；已登录 → **地图主屏（唯一的屏）**。
//
// 导航模型（2026-09-22 定案）：**没有 Tab 栏**。地图是家，功能是「地点上的层」：
//   • 四个图层 = 四个真实问题（现在 / 行程 / 停车 / 充电）
//   • 地图右上角的索引页 = **唯一**的功能目录
//   • 深潜页仍然 push 到同一个 NavigationStack，返回手势与返回按钮交给系统
//
// 为什么删掉 5 Tab 骨架：Tab 栏建立的是「五个平行 App」的心智，而地图主屏建立的是
// 「一切都在地点上」。两套 IA 同时存在时，同一个功能最多有 4 个入口
// （Tab / 地图图层 / 索引页 / 「我的」的 27 个磁贴）—— 那就是「缝合怪」的来源。
// `MainTab`、`selectedTab`、每 Tab 一个 path、Tab 角标与切 Tab 朗读都已整体删除。

extension Notification.Name {
    static let navToVehicle = Notification.Name("navToVehicle")
    static let pinConfirmed = Notification.Name("car_pin_confirmed")
    static let tempConfirmed = Notification.Name("car_temp_confirmed")
    static let navToDev = Notification.Name("navToDev")
    static let navToData = Notification.Name("navToData")
    static let navToHealth = Notification.Name("navToHealth")
    static let navToBattery = Notification.Name("navToBattery")
    static let navToMessages = Notification.Name("navToMessages")
    static let navHome = Notification.Name("navHome")
    static let didLogout = Notification.Name("didLogout")
    static let locationUpdated = Notification.Name("locationUpdated")
}

// MARK: - 深潜页（唯一的导航目标）

/// 所有深潜页。**它们不再归属任何 Tab** —— 地图是家，索引页是唯一的目录。
///
/// `.dashboard` 与 `.parking` 保留为深链别名（`carkeeper://dashboard`、
/// `carkeeper://parking` 仍然可用），但它们**指向的页面与 `.score` / `.trips` 是同一个**，
/// 所以索引页不列这两个入口：同一页摆两个入口，正是「缝合怪」的第一来源。
enum Deeplink: Hashable, CaseIterable {
    case vehicle, health, battery, data, dev, messages, control, dashboard
    // `.commands`（指令历史页）已删：历史就是车控页里「做过什么」那一节，
    // 同一件事不再有两个界面（详情见 ControlView 的 historyCard 注释）。
    // `.tips`（车辆提示页）已删：提示是从这辆车的读数推出来的，已并入车辆档案
    // （`VehicleTipsSection`），不再单占一个深链。
    // `.export`（导出数据页）已并入保养与钱（`ExportDataSection`）。
    case trips, service, parking, emergency, score
    /// 「车与账号」（原「我的」Tab 的根页）。设置类内容的去处 —— 它不是功能目录，
    /// 功能目录归地图右上角的索引页；这个深链保证它不再依附于 Tab 才能到达。
    case mine

    /// 深链 key，对应 carkeeper://<key>
    var key: String {
        switch self {
        case .vehicle: return "vehicle"
        case .health: return "health"
        case .battery: return "battery"
        case .data: return "data"
        case .dev: return "dev"
        case .messages: return "messages"
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
        // #NEW-109 后台刷新注册：必须在 App 启动完成前完成。
        // 内部会先校验 Info.plist 是否声明了对应标识符，未声明则安静跳过（避免直接崩进程）。
        BackgroundTaskManager.shared.registerTasks()
    }

    var body: some Scene {
        WindowGroup {
            root
                // 艺术主题：明暗由主题自带（`.native` = nil，跟随系统，与切换前一致）
                .preferredColorScheme(ArtThemeStore.current.spec.preferredScheme)
                // 令牌是静态计算值，不产生 SwiftUI 依赖 —— 靠 .id 换值重建整棵树，
                // 否则切主题后界面不会立刻重绘（要等下一次状态变化才生效）。
                .id(artThemeRaw)
        }
        // #47 iPad 分屏：第二个窗口（原写成 `os(iOS) && os(macOS)` 恒为假，导致该场景从未注册）。
        // 能否真正被打开由「平台 + Info.plist 的 UIApplicationSceneManifest.UIApplicationSupportsMultipleScenes」
        // 共同决定；入口在地图主屏的工具栏，用 supportsMultipleWindows 判定。
        //
        // ⚠️ 两个场景当前共用 NavState.shared（详见 DetailSplitView 的说明）：副窗口与主窗口是
        //    同一份导航状态 —— 同一条路径。即“能同时看两个窗口”，但还不是两块独立画布。
        WindowGroup(id: SceneID.detail) {
            DetailSplitView()
                .preferredColorScheme(ArtThemeStore.current.spec.preferredScheme)
                .id(artThemeRaw)
        }
    }

    // #NEW-112 启动画面控制
    @State private var showSplash = true
    @State private var isAppLoading = false
    // #NEW-113 Onboarding 引导状态
    @AppStorage("carkeeper_onboarding_seen") private var onboardingSeen = false
    /// 艺术主题（键见 ArtThemeStore.key）。它存在的意义只有一个：
    /// **产生 SwiftUI 依赖** —— 令牌本身是静态计算值，不订阅任何东西，
    /// 所以切换主题时靠它变化去驱动 root 上的 `.id(...)` 重建。
    @AppStorage(ArtThemeStore.key) private var artThemeRaw: String = ArtTheme.native.rawValue

    /// 处理 carkeeper:// 深链。
    /// 此前 Info.plist 注册了 scheme，但全项目没有任何 onOpenURL 接收方 —— 扫二维码/点链接豪无反应。
    /// 现在只有一个栈，所以深链就是「把它设为根之下的那一页」。
    private func openDeeplink(_ url: URL) {
        guard let link = Deeplink(url: url) else { return }
        guard store.isLoggedIn else { return }   // 未登录时先让用户完成登录，登录后可从界面进入
        nav.path = [link]
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
                    }
            } else if !onboardingSeen && !store.isLoggedIn {
                // #NEW-113 Onboarding 引导
                OnboardingView()
            } else if store.isLoggedIn {
                MapShellView()
                    .environmentObject(nav)
                    .onReceive(NotificationCenter.default.publisher(for: .navToVehicle)) { _ in nav.path = [.vehicle] }
                    .onReceive(NotificationCenter.default.publisher(for: .navToHealth)) { _ in nav.path = [.health] }
                    .onReceive(NotificationCenter.default.publisher(for: .navToBattery)) { _ in nav.path = [.battery] }
                    .onReceive(NotificationCenter.default.publisher(for: .navToData)) { _ in nav.path = [.data] }
                    .onReceive(NotificationCenter.default.publisher(for: .navToDev)) { _ in nav.path = [.dev] }
                    .onReceive(NotificationCenter.default.publisher(for: .navToMessages)) { _ in nav.path = [.messages] }
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
            // 启动时若已登录，拉取一次数据
            if store.isLoggedIn && store.cars.isEmpty {
                Task { await store.bootstrap() }
            }
            // 天气实况（光需要云量）：有车的位置就取一次。
            // 取不到就退回「晴空模型」，界面上照实写明 —— 不拿默认值冒充实况。
            if let c = store.currentLocation?.coordinate {
                Task { await WeatherService.shared.refreshIfNeeded(coordinate: c) }
            }
            // #NEW-111 CloudKit 同步
            Task { await store.triggerCloudSync() }
            // #N38 崩溃上报初始化
            CrashReporter.shared.setup()
            // #N39 内存监控启动
            MemoryMonitor.shared.startMonitoring(interval: 10)
            // #N37 网络质量监控
            _ = NetworkQualityMonitor.shared
            // #N41 离线模式监听
            _ = OfflineModeManager.shared
            // #N15-N20 通知权限请求
            Task { await SmartNotificationManager.shared.requestAuthorization() }
            SmartNotificationManager.shared.registerCategories()
            // #N14 远程锁定监听
            RemoteLockManager.shared.startMonitoring()
            // #N46 摇一摇锁车
            // 锁车动作现在由 ShakeDetector 自己在触发时完成（验 PIN → 发 CentralLock）；
            // 这里那层只弹提示的闭包已经去掉 —— 它让「摇一摇已触发」看起来像做了事。
            ShakeDetector.shared.startMonitoring()
            // #NEW-118/N119 维保+保险提醒调度器初始化
            _ = MaintenanceReminderScheduler.shared
            _ = InsuranceReminderScheduler.shared
            // #NEW-120 Siri/快捷指令：真正的 AppIntent 在 Features/SiriShortcuts.swift。
            // 旧的那份 `AppIntentsManager`（空桩）已删；旧的 INIntent 子类也没有
            // Intent Extension target 去注册，永远不可能被唤起。
            // E17-E18 触觉反馈 + E47 性能监控启动
            _ = PerformanceTracker.shared
            // E38 专注模式监听
            _ = FocusModeManager.shared
            // E40 充电状态监控（此前只写了 `_ = ChargingStatusMonitor.shared`，
            // 连 startMonitoring 都没调，而那个方法本身也是空的）
            ChargingStatusMonitor.shared.startMonitoring()
            // N10 车牌加密初始化
            DataEncryption.ensureKey()
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
    /// 全局搜索是否展开（地图工具栏与「车与账号」都能把它打开）
    @Published var showSearch = false

    private init() {}

    func popToRoot() { path = [] }

    /// 统一导航：从任意位置 push 深潜页。
    ///
    /// 旧的 `targetTab:` 参数已删 —— 没有 Tab 可切，导航只有一个栈。
    func pushNavigation(_ link: Deeplink) {
        path.append(link)
    }
}

// MARK: - 地图外壳（唯一的屏）

// 壳层约定（取代此前 5 Tab 骨架）：
//   • **一个** NavigationStack：根是地图主屏，深潜页 push 在上面；
//     返回手势、返回按钮、转场动画全部交给系统。
//   • **一个**目录：地图右上角的索引页（不再与 Tab 栏、「我的」磁贴三套并存）。
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

    /// 深潜页目标视图（独立函数避免巨型 switch 拖慢类型检查）
    @ViewBuilder
    private func deeplinkDestination(_ link: Deeplink) -> some View {
        switch link {
        case .vehicle: VehicleView().environmentObject(nav)
        case .health: HealthView().environmentObject(nav)
        case .battery: BatteryView().environmentObject(nav)
        case .data: DataView(kind: .status).environmentObject(nav)
        case .dev: DevView().environmentObject(nav)
        case .messages: MessagesView().environmentObject(nav)
        case .control: ControlView().environmentObject(nav)
        // 仪表盘（DashboardView）已删除：它的三块内容（SOC 曲线 / 三个指标块 /
        // 评分环）分别由电池页的趋势、地图主屏的「现在」层和评分页承接，
        // 而它那三个子分数是用总分做算术编出来的（score / 3、+10、+20）。
        case .dashboard: DrivingScorePage().environmentObject(nav)
        case .trips: TripsTimelineView().environmentObject(nav)
        case .service: MaintenanceMoneyView().environmentObject(nav)
        // .parking 已并入行程时间轴（同一份停车史：时间轴列旅程，地图「停车」层
        // 画常停圈，两处同源）。深链指向时间轴，不再指向已删除的页面。
        case .parking: TripsTimelineView().environmentObject(nav)
        // .export（导出数据页）已并入保养与钱（ExportDataSection）——
        // 导出的就是那几类记录，它和钱/保养在同一屏里更短一步。
        case .emergency: EmergencyPanel().environmentObject(nav)
        // .tips（车辆提示页）已并入车辆档案 —— 见 `Deeplink` 枚举上的注释。
        case .score: DrivingScorePage().environmentObject(nav)
        // 「车与账号」（原「我的」Tab 的根页）。**它必须在这里有一个 case** ——
        // 它就是设置类内容的唯一去处；批 3 会把它从 27 个磁贴的功能目录
        // 改成「车 / 账号 / 数据与隐私 / 关于与工具」四组。
        case .mine: MineView().environmentObject(nav)
        }
    }

    /// 唯一的栈：根是地图主屏（Features/Map/MapSpineView.swift）。
    /// 车的一切都发生在某个地方，所以导航长在地方上；
    /// 四个图层 = 四个真实问题，功能目录在右上角的索引页里。
    private var mapStack: some View {
        NavigationStack(path: $nav.path) {
            MapSpineView()
                .navigationDestination(for: Deeplink.self) { link in
                    deeplinkDestination(link)
                }
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
        .task { await store.bootstrap() }
        // VoiceOver：这是一个「地图 + 索引页」的外壳，不再是一条 Tab 栏
        .accessibilityLabel(Text("地图主屏"))
        .accessibilityHint(Text("地图是主屏，右上角的全部功能可以到达每一个页面"))
        .accessibilitySortPriority(0)
        // #4 网络状态指示器 + #NEW-3 离线模式提示
        .overlay(alignment: .top) {
            if store.networkStatus != .online || store.isOfflineMode {
                NetworkStatusIndicator(status: store.isOfflineMode ? .offline : store.networkStatus)
                    .padding(.top, 0)
            }
        }
        // Toast 浮层：底部中央的液态玻璃胶囊（由 NavState.currentToast 驱动）
        .overlay(alignment: .bottom) {
            if let t = nav.currentToast {
                ToastView(text: t.text, icon: t.icon)
                    .id(UUID())
            }
        }
        .animation(.easeOut(duration: 0.2), value: nav.currentToast?.text)
        // 全局搜索：用 fullScreenCover 而不是 sheet —— 它本来就是一个盖住全程的 HUD，
        // 半屏 sheet 会把那个压暗背景拆成两段。
        .fullScreenCover(isPresented: $nav.showSearch) {
            GlobalSearchHUD(isPresented: $nav.showSearch)
                .environmentObject(nav)
        }
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
        Text("网络: " + status.rawValue).font(.caption).foregroundColor(.secondary)
    }
}

// MARK: - ToastView
struct ToastView: View {
    let text: String
    let icon: String?
    var body: some View {
        HStack(spacing: 8) {
            if let icon = icon { Image(systemName: icon) }
            Text(text)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(TokensPalette.glassLight.opacity(0.9), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .foregroundColor(TokensPalette.primary)
    }
}


