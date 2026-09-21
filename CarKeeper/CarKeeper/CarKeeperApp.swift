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
    var hostTab: Int {
        switch self {
        case .control: return 1
        case .battery: return 2
        case .trips: return 3
        case .messages: return 4
        default: return 0
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
        }
        // #47 iPad Split View 支持（原写成 `os(iOS) && os(macOS)` 恒为假，导致该场景从未注册）
        WindowGroup(id: "detail") { DetailSplitView() }
    }

    // #NEW-112 启动画面控制
    @State private var showSplash = true
    @State private var isAppLoading = false
    // #NEW-113 Onboarding 引导状态
    @AppStorage("carkeeper_onboarding_seen") private var onboardingSeen = false

    /// 处理 carkeeper:// 深链。
    /// 此前 Info.plist 注册了 scheme，但全项目没有任何 onOpenURL 接收方 —— 扫二维码/点链接豪无反应。
    private func openDeeplink(_ url: URL) {
        guard let link = Deeplink(url: url) else { return }
        guard store.isLoggedIn else { return }   // 未登录时先让用户完成登录，登录后可从界面进入
        nav.selectedTab = link.hostTab
        switch link.hostTab {
        case 1: nav.controlPath = [link]
        case 2: nav.chargePath = [link]
        case 3: nav.tripsPath = [link]   // hostTab 3 = 行程；此前误写进 minePath，深链打不开
        case 4: nav.minePath = [link]
        default: nav.path = [link]
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
                        nav.selectedTab = 2
                        nav.chargePath = []
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .navToData)) { _ in nav.path = [.data] }
                    .onReceive(NotificationCenter.default.publisher(for: .navToDev)) { _ in nav.path = [.dev] }
                    .onReceive(NotificationCenter.default.publisher(for: .navToMessages)) { _ in
                        nav.selectedTab = 4
                        nav.minePath = [.messages]
                    }
                    .onReceive(ToastManager.shared.$currentItem) { item in
                        nav.currentToast = item
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .didLogout)) { _ in
                        nav.path = []
                        nav.selectedTab = 0
                    }
            } else {
                LoginView()
            }
        }
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
            // E9-E16 位置智能功能启动
            LocationSmartFeatures.shared.startMonitoring()
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
    @Published var selectedTab: Int = 0
    @Published var currentToast: (text: String, icon: String)? = nil
    @Published var controlPath: [Deeplink] = []
    @Published var chargePath: [Deeplink] = []
    @Published var tripsPath: [Deeplink] = []
    @Published var minePath: [Deeplink] = []

    /// 每个 Tab 的 VoiceOver 描述（用于动态朗读切换时的页面名称）
    static let tabAccessibilityLabels: [Int: String] = [
        0: "车况", 1: "车控", 2: "充电", 3: "行程", 4: "我的"
    ]

    private init() {}

    func popToRoot() { path = [] }

    /// 统一导航：从任意 Tab push 深潜页，自动切换到对应 Tab（若有）
    /// - Parameters:
    ///   - link: 目标深潜页
    ///   - targetTab: 目标 Tab 索引（nil = 保持当前 Tab）
    func pushNavigation(_ link: Deeplink, targetTab: Int? = nil) {
        // 先切换到目标 Tab（如有）
        if let t = targetTab { selectedTab = t }
        // 根据当前 Tab 写入对应路径
        switch selectedTab {
        case 0: path.append(link)
        case 1: controlPath.append(link)
        case 2: chargePath.append(link)
        case 3: tripsPath.append(link)
        case 4: minePath.append(link)
        default: path.append(link)
        }
    }

    func clearTabPaths() {
        controlPath = []
        chargePath = []
        tripsPath = []
        minePath = []
    }

    /// 获取当前选中 Tab 的无障碍朗读文本
    var selectedTabVoiceOverLabel: String {
        Self.tabAccessibilityLabels[selectedTab] ?? "Tab \(selectedTab)"
    }
}

// MARK: - 主 Tab

// 壳层约定：
//   • Tab 内容直接作为画布，不套任何自定义容器（容器会让 TabView 读不到 .tabItem/.tag），
//     否则底部导航会丢标题、点其他 Tab 又被弹回第一个。
//   • 每个 Tab 是标准 NavigationStack + navigationDestination
//   • 返回手势、返回按钮、转场动画全部交给系统（系统同款动画做得更稳）
//   • 导航栏用系统液态玻璃材质（浮在内容之上，是玻璃唯一该出现的地方）

struct MainTabView: View {
    @StateObject private var nav = NavState.shared
    @State private var lastAnnouncedTab: Int = 0
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
        case .dashboard: DashboardView().environmentObject(nav)
        case .trips: TripAnalyticsView().environmentObject(nav)
        case .commands: CommandHistoryView().environmentObject(nav)
        case .service: ServiceHistoryView().environmentObject(nav)
        case .parking: ParkingMapView().environmentObject(nav)
        case .export: ExportDataView().environmentObject(nav)
        case .emergency: EmergencyPanel().environmentObject(nav)
        case .tips: VehicleTipsView().environmentObject(nav)
        case .score: DrivingScorePage().environmentObject(nav)
        }
    }

    private var homeTab: some View {
        NavigationStack(path: $nav.path) {
            HomeView()
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
            .accessibilitySortPriority(0)
            // ⚠️ .tabItem / .tag 必须留在子视图的最外层：TabView 靠 trait 读取它们，
            // 而 trait 不会穿透 ZStack 这类容器 —— 之前外面被套了一层 ZStack，
            // 于是标题丢失（底部导航没文字）、选中态被弹回第一个 Tab。
            // 另外 .tabItem 的内容只认 Label / Text / Image，塞 ZStack 同样会丢标题。
            .tabItem {
                Label("车况", systemImage: "car.fill")
                    .accessibilityLabel(Text("车况"))
            }
            // 低电量时在 Tab 上给出角标（只有真需要用户注意时才出现）
            .badge(lowBatteryBadge ? "低" : nil)
            .tag(0)
    }

    private var controlTab: some View {
            NavigationStack(path: $nav.controlPath) {
                ControlView()
                    .navigationDestination(for: Deeplink.self) { link in
                        deeplinkDestination(link)
                    }
            }
            .accessibilitySortPriority(1)
            // ⚠️ 同 tab 0：.tabItem / .tag 必须最外层，否则标题与选中态都会失效
            .tabItem {
                Label("车控", systemImage: "slider.horizontal.3")
                    .accessibilityLabel(Text("车控"))
            }
            .tag(1)

    }

    private var chargeTab: some View {
            NavigationStack(path: $nav.chargePath) {
                BatteryView()
                    .navigationDestination(for: Deeplink.self) { link in
                        deeplinkDestination(link)
                    }
            }
            .accessibilitySortPriority(2)
            // ⚠️ 同 tab 0：.tabItem / .tag 必须最外层，否则标题与选中态都会失效
            .tabItem {
                Label("充电", systemImage: "bolt.fill")
                    .accessibilityLabel(Text("充电"))
            }
            .tag(2)

    }

    private var tripsTab: some View {
            NavigationStack(path: $nav.tripsPath) {
                TripAnalyticsView()
                    .navigationDestination(for: Deeplink.self) { link in
                        deeplinkDestination(link)
                    }
            }
            .accessibilitySortPriority(3)
            .tabItem {
                // 图标名走 SafeSymbol：写错的 symbol 会渲染成空白（Tab 上就是“没图标”）
                Label("行程", systemImage: SafeSymbol.name("point.topleft.down.to.point.bottomright.curvepath", fallback: "map.fill"))
                    .accessibilityLabel(Text("行程"))
                    .accessibilityHint(Text("里程、能耗与每一次出行记录"))
            }
            .tag(3)

    }

    private var mineTab: some View {
            NavigationStack(path: $nav.minePath) {
                MineView()
                    .navigationDestination(for: Deeplink.self) { link in
                        deeplinkDestination(link)
                    }
            }
            .accessibilitySortPriority(4)
            // ⚠️ 同 tab 0：.tabItem / .tag 必须最外层
            .tabItem {
                Label("我的", systemImage: "person.fill")
                    .accessibilityLabel(Text("我的"))
            }
            .tag(4)
    }

    var body: some View {
        TabView(selection: $nav.selectedTab) {
            homeTab
            controlTab
            chargeTab
            tripsTab
            mineTab
        }
        // 情感化配色：时间感知主色调
        .tint(Kansei.Color.ambient)
        // VoiceOver：切换 Tab 时朗读当前页面名称（仅首次切换到新 Tab）
        .onChange(of: nav.selectedTab) { _, newTab in
            if newTab != lastAnnouncedTab {
                lastAnnouncedTab = newTab
                let label = NavState.tabAccessibilityLabels[newTab] ?? "Tab \(newTab)"
                UIAccessibility.post(notification: .announcement, argument: "已切换到\(label)页")
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
struct DetailSplitView: View {
    @StateObject private var nav = NavState.shared
    private let store = AppStore.shared

    var body: some View {
        if store.isLoggedIn {
            MainTabView()
                .environmentObject(nav)
        } else {
            LoginView()
        }
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
        .background(Kansei.glassLight.opacity(0.9), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .foregroundColor(Kansei.primary)
    }
}


