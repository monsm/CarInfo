import SwiftUI
import UIKit

// App 入口：未登录 → 登录页；已登录 → 主 Tab（车况 / 车控 / 消息 / 我的）。
// 深潜页（车辆档案 / 健康报告 / 电池与充电 / 全量数据 / 开发者工具）通过 shared NavigationStack path 从任意 tab 打开。

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

// MARK: - 主 Tab 的类型化标识

/// 底部导航的五个 Tab。
///
/// 取代此前裸 `Int` 索引（0…4）：标题、图标、无障碍朗读名都挂在枚举上，
/// 深链、角标、切 Tab 因此共用同一份定义 —— `selectedTab = 7` 这种越界值
/// 在编译期就不存在，标签与选中值也不可能再对不上。
enum MainTab: Int, Hashable, CaseIterable, Sendable {
    // 声明顺序即底部导航从左到右的顺序
    case home = 0
    case control = 1
    case charge = 2
    case trips = 3
    case mine = 4

    /// 底部导航标题（同时是 VoiceOver 朗读名）
    var title: String {
        switch self {
        case .home: return "车况"
        case .control: return "车控"
        case .charge: return "充电"
        case .trips: return "行程"
        case .mine: return "我的"
        }
    }

    /// 底部导航图标（行程图标走 SafeSymbol 兜底：写错的 symbol 会渲染成空白，
    /// 在 Tab 上就表现为「没有图标」）
    var systemImage: String {
        switch self {
        case .home: return "car.fill"
        case .control: return "slider.horizontal.3"
        case .charge: return "bolt.fill"
        case .trips: return SafeSymbol.name("point.topleft.down.to.point.bottomright.curvepath", fallback: "map.fill")
        case .mine: return "person.fill"
        }
    }

    /// VoiceOver 在导航栏内的朗读顺序（与底部从左到右一致）
    var sortRank: Double { Double(rawValue) }
}

enum Deeplink: Hashable, CaseIterable {
    case vehicle, health, battery, data, dev, messages, control, dashboard
    case trips, commands, service, parking, export, emergency, tips, score

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
        case .commands: return "commands"
        case .service: return "service"
        case .parking: return "parking"
        case .export: return "export"
        case .emergency: return "emergency"
        case .tips: return "tips"
        case .score: return "score"
        }
    }

    /// 该页所属的 Tab（打开时先切到对应 Tab）
    /// 穷举（无 default）：新增深链时编译器会强制在这里表态。
    var hostTab: MainTab {
        switch self {
        case .control: return .control
        case .battery: return .charge
        case .trips: return .trips
        case .messages: return .mine
        case .vehicle, .health, .data, .dev, .dashboard, .commands,
             .service, .parking, .export, .emergency, .tips, .score:
            return .home
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
        //    同一份导航状态 —— 同一个 Tab、同一条路径。即“能同时看两个窗口”，但还不是两块独立画布。
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
    private func openDeeplink(_ url: URL) {
        guard let link = Deeplink(url: url) else { return }
        guard store.isLoggedIn else { return }   // 未登录时先让用户完成登录，登录后可从界面进入
        nav.selectedTab = link.hostTab
        // 按目标 Tab 写入对应路径（枚举穷举，不存在写错的索引）
        switch link.hostTab {
        case .control: nav.controlPath = [link]
        case .charge: nav.chargePath = [link]
        case .trips: nav.tripsPath = [link]   // 行程 Tab；此前误写进 minePath，深链打不开
        case .mine: nav.minePath = [link]
        case .home: nav.path = [link]
        }
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
                MainTabView()
                    .environmentObject(nav)
                    .onReceive(NotificationCenter.default.publisher(for: .navToVehicle)) { _ in nav.path = [.vehicle] }
                    .onReceive(NotificationCenter.default.publisher(for: .navToHealth)) { _ in nav.path = [.health] }
                    .onReceive(NotificationCenter.default.publisher(for: .navToBattery)) { _ in
                        nav.selectedTab = .charge
                        nav.chargePath = []
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .navToData)) { _ in nav.path = [.data] }
                    .onReceive(NotificationCenter.default.publisher(for: .navToDev)) { _ in nav.path = [.dev] }
                    .onReceive(NotificationCenter.default.publisher(for: .navToMessages)) { _ in
                        nav.selectedTab = .mine
                        nav.minePath = [.messages]
                    }
                    .onReceive(ToastManager.shared.$currentItem) { item in
                        nav.currentToast = item
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .didLogout)) { _ in
                        nav.path = []
                        nav.selectedTab = .home
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
            ShakeDetector.shared.startMonitoring()
            ShakeDetector.shared.onShake = { _ in
                if store.carId.isEmpty == false {
                    // 触发锁车提示
                    EnhancedToastManager.shared.show("摇一摇已触发", icon: "shake")
                }
            }
            // #NEW-118/N119 维保+保险提醒调度器初始化
            _ = MaintenanceReminderScheduler.shared
            _ = InsuranceReminderScheduler.shared
            // #NEW-120 App Intents 注册（Siri 对话入口）
            _ = AppIntentsManager.shared
            // E17-E18 触觉反馈 + E47 性能监控启动
            _ = PerformanceTracker.shared
            // E38 专注模式监听
            _ = FocusModeManager.shared
            // E40 充电状态监控
            _ = ChargingStatusMonitor.shared
            // N10 车牌加密初始化
            DataEncryption.ensureKey()
        }
        .onOpenURL { url in
            openDeeplink(url)
        }
        // 注意：根视图上不得再挂任何「无限循环动画」修饰符。
        // 它们会让整棵视图树反复失效，深色模式下表现为整屏发暗发黏，且持续耗电。
    }
}

// 全局导航状态（深潜页 push 与 tab 切换共享）
final class NavState: ObservableObject, @unchecked Sendable {
    static let shared = NavState()
    @Published var path: [Deeplink] = []
    @Published var selectedTab: MainTab = .home
    @Published var currentToast: (text: String, icon: String)? = nil
    @Published var controlPath: [Deeplink] = []
    @Published var chargePath: [Deeplink] = []
    @Published var tripsPath: [Deeplink] = []
    @Published var minePath: [Deeplink] = []

    private init() {}

    func popToRoot() { path = [] }

    /// 统一导航：从任意 Tab push 深潜页，自动切换到对应 Tab（若有）
    /// - Parameters:
    ///   - link: 目标深潜页
    ///   - targetTab: 目标 Tab（nil = 保持当前 Tab）
    func pushNavigation(_ link: Deeplink, targetTab: MainTab? = nil) {
        // 先切换到目标 Tab（如有）
        if let t = targetTab { selectedTab = t }
        // 根据当前 Tab 写入对应路径
        switch selectedTab {
        case .home: path.append(link)
        case .control: controlPath.append(link)
        case .charge: chargePath.append(link)
        case .trips: tripsPath.append(link)
        case .mine: minePath.append(link)
        }
    }

    func clearTabPaths() {
        controlPath = []
        chargePath = []
        tripsPath = []
        minePath = []
    }

    /// 获取当前选中 Tab 的无障碍朗读文本
    var selectedTabVoiceOverLabel: String { selectedTab.title }
}

// MARK: - 主 Tab

// 壳层约定：
//   • 每个 Tab 用 iOS 18+ 的 `Tab(value:content:label:)` 声明：选中值是类型化的 MainTab，
//     标签文案/图标/朗读名都取自 MainTab 本身 —— 标题、选中值、角标不再各写一份。
//     旧写法（在子视图上挂 .tabItem/.tag）必须挂在最外层，一旦外面套了容器就会丢标题、
//     选中态被弹回首页；新写法从结构上排除了这一类问题。
//   • 每个 Tab 是标准 NavigationStack + navigationDestination
//   • 返回手势、返回按钮、转场动画全部交给系统（系统同款动画做得更稳）
//   • 导航栏用系统液态玻璃材质（浮在内容之上，是玻璃唯一该出现的地方）

struct MainTabView: View {
    @StateObject private var nav = NavState.shared
    @State private var lastAnnouncedTab: MainTab = .home
    private let store = AppStore.shared
    @State private var lowBatteryBadge: Bool = false
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
        case .commands: CommandHistoryView().environmentObject(nav)
        case .service: ServiceHistoryView().environmentObject(nav)
        // .parking 已并入行程时间轴（同一份停车史：时间轴列旅程，地图「停车」层
        // 画常停圈，两处同源）。深链指向时间轴，不再指向已删除的页面。
        case .parking: TripsTimelineView().environmentObject(nav)
        case .export: ExportDataView().environmentObject(nav)
        case .emergency: EmergencyPanel().environmentObject(nav)
        case .tips: VehicleTipsView().environmentObject(nav)
        case .score: DrivingScorePage().environmentObject(nav)
        }
    }

    /// Tab 标签：文案/图标取自 MainTab（不再是手写字符串）。
    /// sortRank 仅用于 VoiceOver 朗读顺序（与底部从左到右一致）；hint 只有行程 Tab 用。
    private func tabLabel(_ tab: MainTab, hint: String? = nil) -> some View {
        Label(tab.title, systemImage: tab.systemImage)
            .accessibilitySortPriority(tab.sortRank)
            .accessibilityHint(hint ?? "")
    }

    private var homeTab: some View {
        NavigationStack(path: $nav.path) {
            // 首页**以地图为主屏**（Features/Map/MapSpineView.swift）。
            // 车的一切都发生在某个地方，所以导航长在地方上；四个图层 = 四个真实问题，
            // 全部功能在右上角的索引页里（去掉 Tab 栏的代价补在那里）。
            // 旧版列表首页已随重设计删除（它的 LocationMapView 还依赖已删的 MapView，
            // 本身就是断链页面）—— 回退 = git revert，不再保留两套真相。
            MapSpineView()
                .navigationDestination(for: Deeplink.self) { link in
                    deeplinkDestination(link)
                }
                // 导航栏材质交给系统：iOS 26/27 会在内容滚动到其下方时自动给出材质。
                // 手写 .toolbarBackground 反而会把系统行为覆盖掉。
        }
            // #5 低电量角标：由统一的数据变更通知驱动
            .onReceive(NotificationCenter.default.publisher(for: .locationUpdated)) { _ in
                let energy = VM.energy(store.caches, store.car)
                lowBatteryBadge = energy.socPct < 20
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

    private var controlTab: some View {
            NavigationStack(path: $nav.controlPath) {
                ControlView()
                    .navigationDestination(for: Deeplink.self) { link in
                        deeplinkDestination(link)
                    }
            }
    }

    private var chargeTab: some View {
            NavigationStack(path: $nav.chargePath) {
                BatteryView()
                    .navigationDestination(for: Deeplink.self) { link in
                        deeplinkDestination(link)
                    }
            }
    }

    private var tripsTab: some View {
            NavigationStack(path: $nav.tripsPath) {
                TripsTimelineView()
                    .navigationDestination(for: Deeplink.self) { link in
                        deeplinkDestination(link)
                    }
            }
    }

    private var mineTab: some View {
            NavigationStack(path: $nav.minePath) {
                MineView()
                    .navigationDestination(for: Deeplink.self) { link in
                        deeplinkDestination(link)
                    }
            }
    }

    var body: some View {
        // iOS 18+ Tab 语法：选中值换成类型化的 MainTab（替代 .tag(0…4)），
        // 标签文案与图标同样取自 MainTab —— 手写字符串与裸索引一并消失。
        TabView(selection: $nav.selectedTab) {
            Tab(value: MainTab.home) {
                homeTab
            } label: {
                tabLabel(.home)
            }
            // 低电量时在 Tab 上给出角标（只有真需要用户注意时才出现）
            .badge(lowBatteryBadge ? Text("低") : nil)

            Tab(value: MainTab.control) {
                controlTab
            } label: {
                tabLabel(.control)
            }

            Tab(value: MainTab.charge) {
                chargeTab
            } label: {
                tabLabel(.charge)
            }

            Tab(value: MainTab.trips) {
                tripsTab
            } label: {
                tabLabel(.trips, hint: "里程、能耗与每一次出行记录")
            }

            Tab(value: MainTab.mine) {
                mineTab
            } label: {
                tabLabel(.mine)
            }
        }
        // 情感化配色：时间感知主色调
        .tint(TokensPalette.ambient)
        // VoiceOver：切换 Tab 时朗读当前页面名称（仅首次切换到新 Tab）
        .onChange(of: nav.selectedTab) { _, newTab in
            if newTab != lastAnnouncedTab {
                lastAnnouncedTab = newTab
                UIAccessibility.post(notification: .announcement, argument: "已切换到\(newTab.title)页")
            }
        }
        // #5 低电量角标检测：每次车控数据更新时检查
        .onReceive(NotificationCenter.default.publisher(for: .locationUpdated)) { _ in
            let energy = VM.energy(store.caches, store.car)
            lowBatteryBadge = energy.socPct < 20
        }
        .task { await store.bootstrap() }
        // 设置 TabView 整体无障碍描述和朗读顺序
        .accessibilityLabel(Text("主导航栏"))
        .accessibilityHint(Text("五个主要功能模块：车况、车控、充电、行程、我的。左右滑动可切换标签页"))
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
    }
}

// MARK: - #47 iPad Split View 支持

/// 第二个窗口（`WindowGroup(id: SceneID.detail)`）的根视图，由 iPad 分屏入口打开。
///
/// ⚠️ 它用的是共用的 `NavState.shared`，所以副窗口与主窗口是**同一份导航状态**：
///    `MainTabView` 内部是 `@StateObject private var nav = NavState.shared`（读单例、不读环境），
///    两个场景因此绑定到同一个实例，Tab 选中与各 Tab 的路径完全同步。
///    要让两个窗口真正各走各的：NavState 去掉单例、由每个 Scene 各建一个实例并通过
///    `.environmentObject` 注入（代码里已没有直接写 `NavState.shared.selectedTab` 的地方）。
struct DetailSplitView: View {
    @StateObject private var nav = NavState.shared
    private let store = AppStore.shared

    var body: some View {
        Group {
            if store.isLoggedIn {
                MainTabView()
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


