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

enum Deeplink: Hashable {
    case vehicle, health, battery, data, dev, messages, control, dashboard
}

@main
struct CarKeeperApp: App {
    private let store = AppStore.shared
    @StateObject private var nav = NavState.shared

    var body: some Scene {
        WindowGroup {
            root
        }
        #if os(iOS) && os(macOS)
        // #47 iPad Split View 支持
        WindowGroup(id: "detail") { DetailSplitView() }
        #endif
    }

    // #NEW-112 启动画面控制
    @State private var showSplash = true
    @State private var isAppLoading = false
    // #NEW-113 Onboarding 引导状态
    @AppStorage("carkeeper_onboarding_seen") private var onboardingSeen = false
    
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
                    .onReceive(NotificationCenter.default.publisher(for: .navToBattery)) { _ in nav.path = [.battery] }
                    .onReceive(NotificationCenter.default.publisher(for: .navToData)) { _ in nav.path = [.data] }
                    .onReceive(NotificationCenter.default.publisher(for: .navToDev)) { _ in nav.path = [.dev] }
                    .onReceive(NotificationCenter.default.publisher(for: .navToMessages)) { _ in
                        nav.selectedTab = 2
                        messagesPath = [.messages]
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
            PerformanceTracker.shared.start()
            // E38 专注模式监听
            _ = FocusModeManager.shared
            // E9-E16 位置智能功能启动
            LocationSmartFeatures.shared.startMonitoring()
            // E40 充电状态监控
            _ = ChargingStatusMonitor.shared
            // N10 车牌加密初始化
            _ = DataEncryption.shared
        }
        .nightModeBreathing(enabled: store.isNightMode)
    }
}

// 全局导航状态（深潜页 push 与 tab 切换共享）
final class NavState: ObservableObject, @unchecked Sendable {
    static let shared = NavState()
    @Published var path: [Deeplink] = []
    @Published var selectedTab: Int = 0
    @Published var currentToast: (text: String, icon: String)? = nil

    /// 每个 Tab 的 VoiceOver 描述（用于动态朗读切换时的页面名称）
    static let tabAccessibilityLabels: [Int: String] = [
        0: "车况", 1: "车控", 2: "消息", 3: "我的"
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
        case 2: messagesPath.append(link)
        case 3: minePath.append(link)
        default: path.append(link)
        }
    }

    /// 获取当前选中 Tab 的无障碍朗读文本
    var selectedTabVoiceOverLabel: String {
        Self.tabAccessibilityLabels[selectedTab] ?? "Tab \(selectedTab)"
    }
}

// MARK: - 主 Tab

// =============================================================================
// TabCardTransition —— iOS 27 Liquid Glass 视差位移动效
// 三层深度：前景内容层 + 玻璃背景卡层 + 品牌光晕散斑层
// 各层以不同速率/延迟响应同一 spring 事务，形成真实视差深度感
// =============================================================================

/// 三层视差转场：contentLayer(快) / glassLayer(中) / glowLayer(慢)
/// 当 isActive 为 true 时，三层依次从下方滑入，形成深度差；
/// 关闭时三层同步滑出，保留玻璃质感。
struct TabCardTransition: ViewModifier {
    let tabId: Int
    let isActive: Bool

    // 各层位移量（pt）：越靠后的层起始位置越低，视觉越靠后
    private static let layers: [(contentY: CGFloat, glassY: CGFloat, glowY: CGFloat, delay: CGFloat)] = [
        // tab 0: 车况（最前）
        (0,   36,  72,  0.0),
        // tab 1: 车控
        (0,   42,  84,  0.02),
        // tab 2: 消息
        (0,   48,  96,  0.04),
        // tab 3: 我的（最后）
        (0,   54, 108,  0.06),
    ]

    private var contentY: CGFloat { layers[tabId].contentY }
    private var glassY:   CGFloat { layers[tabId].glassY   }
    private var glowY:    CGFloat { layers[tabId].glowY    }
    private var delay:    CGFloat { layers[tabId].delay    }

    func body(content: Content) -> some View {
        ZStack(alignment: .top) {
            // ── 第 0 层：品牌光晕散斑（最慢、最深、最先淡入）──
            // 在 isActive=true 之前即开始显示，作为背景氛围
            if isActive {
                ZStack {
                    // 左上角青色散斑
                    Circle()
                        .fill(.green.opacity(0.08))
                        .frame(width: 200, height: 200)
                        .offset(x: -60, y: -30)
                    // 右下角品牌色散斑
                    Circle()
                        .fill(Theme.brand.opacity(0.07))
                        .frame(width: 180, height: 180)
                        .offset(x: 50, y: 40)
                    // 右上角微光
                    Circle()
                        .fill(.white.opacity(0.05))
                        .frame(width: 120, height: 120)
                        .offset(x: 70, y: -50)
                }
                .offset(y: glowY)
                .opacity(isActive ? 1.0 : 0.0)
                .scaleEffect(isActive ? 1.0 : 0.88)
                .animation(
                    .spring(response: 0.6, dampingFraction: 0.7, blendDuration: 0.5).delay(delay + 0.08),
                    value: isActive
                )
            }

            // ── 第 1 层：Liquid Glass 背景卡（中等速度）──
            // 磨砂玻璃质感，随 spring 事务从下方滑入
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Material.thin)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.22), .white.opacity(0.04)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.9
                        )
                )
                .shadow(color: .black.opacity(0.10), radius: 18, y: 6)
                .offset(y: glassY)
                .scaleEffect(isActive ? 1.0 : 0.94)
                .opacity(isActive ? 1.0 : 0.0)
                .animation(
                    .spring(response: 0.55, dampingFraction: 0.65, blendDuration: 0.4).delay(delay + 0.03),
                    value: isActive
                )

            // ── 第 2 层：前景内容（最快、最高优先级，跟随 spring transaction）──
            content
                .offset(y: contentY)
                .scaleEffect(isActive ? 1.0 : 0.92)
                .opacity(isActive ? 1.0 : 0.0)
                .animation(
                    .spring(response: 0.55, dampingFraction: 0.62, blendDuration: 0.35).delay(delay),
                    value: isActive
                )
        }
        .edgesIgnoringSafeArea(.all)
    }
}

// =============================================================================// NavGlassWrapper —— 深潜页 Liquid Glass 视差容器
// 与 TabCardTransition 同款三层视差，方向改为水平（从右侧滑入）
// 入场和退场均由 NavigationStack spring transaction 统一驱动，
// 确保 push 从右侧滑入、pop 从左侧滑出，动画完全对称。
// =============================================================================

/// 深潜页（VehicleView / HealthView / BatteryView 等）的 Liquid Glass 视差包装器
/// 外层 ZStack 包含：glowLayer（背景散斑）→ glassLayer（磨砂玻璃卡）→ content（前景页面）
/// 每层以不同延迟从右侧滑入；pop 时由 liquidGlassPopTransition 驱动向左滑出。
struct NavGlassWrapper<Content: View>: View {
    private let content: Content

    // 深潜页方向参数（水平而非垂直）：
    //   contentX: 内容位移（快、最近）
    //   glassX:   玻璃卡位移（中）
    //   glowX:    光晕位移（慢、最远）
    private static let params: [(contentX: CGFloat, glassX: CGFloat, glowX: CGFloat, delay: CGFloat)] = [
        (24,  56,  96,  0.0),   // 车辆档案（第一级）
        (28,  64, 112,  0.02),  // 健康报告
        (32,  72, 128,  0.04),  // 电池充电
        (36,  80, 140,  0.06),  // 全量数据
        (40,  88, 152,  0.08),  // 开发者工具
        (24,  56,  96,  0.0),   // 消息
        (24,  56,  96,  0.0),   // 车控（直接从 Tab 打开）
    ]

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    // 内部状态：首次 onAppear 时触发入场动画，pop 时由 NavigationStack 接管退出转场
    @State private var _shown: Bool = false

    private var cx: CGFloat { params[0].contentX }
    private var gx: CGFloat { params[0].glassX }
    private var ox: CGFloat { params[0].glowX }
    private var delay:   CGFloat { params[0].delay }

    var body: some View {
        ZStack(alignment: .leading) {
            // ── 第 0 层：品牌光晕散斑（最深、最慢，从右侧 96pt 滑入）──
            ZStack {
                Circle().fill(.green.opacity(0.08)).frame(width: 200, height: 200).offset(x: 80, y: -40)
                Circle().fill(Theme.brand.opacity(0.07)).frame(width: 180, height: 180).offset(x: 60, y: 50)
                Circle().fill(.white.opacity(0.05)).frame(width: 120, height: 120).offset(x: 100, y: -60)
            }
            .offset(x: _shown ? 0 : -ox)   // 退出：0 → -96（向左滑出，与入场对称）
            .scaleEffect(_shown ? 1.0 : 0.92)
            .opacity(_shown ? 1.0 : 0.0)
            .animation(
                .spring(response: 0.6, dampingFraction: 0.7, blendDuration: 0.5).delay(delay + 0.08),
                value: _shown
            )

            // ── 第 1 层：Liquid Glass 玻璃背景卡（中等速度，从右侧 56pt 滑入）──
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Material.thin)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.22), .white.opacity(0.04)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.9
                        )
                )
                .shadow(color: .black.opacity(0.10), radius: 18, y: 6)
                .offset(x: _shown ? 0 : -gx)   // 退出：0 → -56（向左滑出，与入场对称）
                .scaleEffect(_shown ? 1.0 : 0.94)
                .opacity(_shown ? 1.0 : 0.0)
                .animation(
                    .spring(response: 0.55, dampingFraction: 0.65, blendDuration: 0.4).delay(delay + 0.03),
                    value: _shown
                )

            // ── 第 2 层：前景内容（最快，从右侧 24pt 滑入；退出时向左 -24pt 滑出）──
            content
                .offset(x: _shown ? 0 : -cx)   // 退出：0 → -24（向左滑出）
                .scaleEffect(_shown ? 1.0 : 0.96)
                .opacity(_shown ? 1.0 : 0.0)
                .animation(
                    .spring(response: 0.55, dampingFraction: 0.62, blendDuration: 0.35).delay(delay),
                    value: _shown
                )
        }
        .edgesIgnoringSafeArea(.all)
        .onAppear {
            // 首次出现：延迟 50ms 后触发入场动画，与导航滑入同步
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                _shown = true
            }
        }
        .onDisappear {
            // 页面即将被移除：重置 _shown，让三层快速弹回初始位置
            // 随后 liquidGlassPopTransition 的 removal modifier 统一负责向左滑出
            _shown = false
        }
    }
}

// MARK: - Liquid Glass 退出转场
/// pop 时：向左滑出 + 弹性缩放 + 淡出，与入场动画对称
/// spring spring: response 0.6 / damping 0.7 / blend 0.5s
private let liquidGlassPopTransition: AnyTransition = .asymmetric(
    insertion: .modifier { content in
        content
            .offset(x: 60)
            .scaleEffect(0.93)
            .opacity(0.0)
    },
    removal: .modifier { content in
        // 退出时 offset 由内部 _shown=false 弹簧动画驱动（三层依次从右→左滑出）
        // 此处仅保留 scale + opacity，不叠加 offset 避免双重位移
        content
            .scaleEffect(0.93)
            .opacity(0.0)
    }
)

/// 液态玻璃风格返回按钮（隐藏系统默认，自定义样式）
struct BackGlassButton: View {
    @Binding var navigationPath: [Deeplink]

    var body: some View {
        Button {
            guard !navigationPath.isEmpty else { return }
            withAnimation(.spring(response: 0.55, dampingFraction: 0.65, blendDuration: 0.35)) {
                navigationPath.removeLast()
            }
        } label: {
            Label("返回", systemImage: "chevron.left")
                .font(Theme.subheadline)
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5)
                        )
                        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
                )
        }
    }
}

struct MainTabView: View {
    @StateObject private var nav = NavState.shared
    @State private var prevSelectedTab: Int = 0
    // VoiceOver：记录上次朗读的 Tab，避免重复播报
    @State private var lastAnnouncedTab: Int = 0
    // 各 Tab 独立的深潜导航路径（不共享 Home 的 nav.path）
    @State private var controlPath:  [Deeplink] = []
    @State private var messagesPath: [Deeplink] = []
    @State private var minePath:     [Deeplink] = []
    // NavBar 液态玻璃反光扫过相位（周期性动画）
    @State private var navBarSweepPhase: CGFloat = 0
    // 定时刷新反射扫过相位
    private let sweepTimer = Timer.publish(every: 4, on: .main, in: .common).autoconnect()
    // #5 低电量 Tab 角标：SOC < 20% 时红色脉冲
    @State private var lowBatteryBadge: Bool = false
    // #4 网络状态监测定时器（每 30 秒检查一次）
    private let networkMonitorTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        TabView(selection: $nav.selectedTab) {
            NavigationStack(path: $nav.path) {
                HomeView()
                    .navigationDestination(for: Deeplink.self) { link in
                        NavGlassWrapper {
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
                    }
                    .transition(liquidGlassPopTransition)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            BackGlassButton(navigationPath: $nav.path)
                        }
                    }
                    .navigationBarBackButtonHidden()
                    // D1: NavBar 液态玻璃反光扫过
                    .overlay(alignment: .top) {
                        if navBarSweepPhase > 0 {
                            LinearGradient(colors: [.clear, .white.opacity(0.06 * navBarSweepPhase), .white.opacity(0.10 * navBarSweepPhase), .white.opacity(0.06 * navBarSweepPhase), .clear],
                                           startPoint: .leading, endPoint: .trailing)
                            .frame(height: 44)
                            .offset(x: navBarSweepPhase * UIScreen.main.bounds.width - UIScreen.main.bounds.width / 2)
                        }
                    }
                    .gesture(
                        // C2: swipe-to-back 手势（从左边滑出触发返回）
                        DragGesture(minimumDistance: 50, coordinateSpace: .global)
                            .onEnded { v in
                                if v.startLocation.x < 30 && v.location.x > v.startLocation.x + 50 {
                                    // 从左侧向右滑动，触发返回
                                    var newPath = nav.path
                                    if !newPath.isEmpty { newPath.removeLast() }
                                    nav.path = newPath
                                }
                            }
                    )
            }
            .transaction { t in
                t.animation = .spring(response: 0.5, dampingFraction: 0.65, blendDuration: 0.3)
            }
            .tabGlassContainer()
            .tabItem {
                ZStack(alignment: .topTrailing) {
                    Label("车况", systemImage: "car.fill")
                        .accessibilityLabel(Text("车况"))
                        .accessibilityHint(Text("车辆状态概览，包含行驶里程、胎压、SOC 电量等关键信息"))
                    if lowBatteryBadge {
                        LowBatteryBadge(socPct: 0)
                    }
                }
            }
            .accessibilitySortPriority(0)
            .tag(0)
            .transaction { t in
                t.animation = .spring(response: 0.5, dampingFraction: 0.65, blendDuration: 0.3)
                t.labelSize = .medium
            }
            .modifier(TabCardTransition(tabId: 0, isActive: nav.selectedTab == 0 && prevSelectedTab != 0))
            .onChange(of: nav.selectedTab) { newTab in
                prevSelectedTab = nav.selectedTab
            }
            .onReceive(NotificationCenter.default.publisher(for: .locationUpdated)) { _ in
                // #5 更新低电量角标状态
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
                        let isNetwork = (error as? APIError)?.statusCode != nil || error is URLError
                        store.updateNetworkStatus(isNetwork ? .weak : .offline)
                    }
                }
            }

            NavigationStack(path: $controlPath) {
                ControlView()
                    .navigationDestination(for: Deeplink.self) { link in
                        NavGlassWrapper {
                            switch link {
                            case .vehicle:  VehicleView().environmentObject(nav)
                            case .health:   HealthView().environmentObject(nav)
                            case .battery:  BatteryView().environmentObject(nav)
                            case .data:     DataView(kind: .status).environmentObject(nav)
                            case .dev:      DevView().environmentObject(nav)
                            case .messages: MessagesView().environmentObject(nav)
                            case .control:  ControlView().environmentObject(nav)
                            }
                        }
                    }
                    .transition(liquidGlassPopTransition)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            BackGlassButton(navigationPath: $controlPath)
                        }
                    }
                    .navigationBarBackButtonHidden()
                    .overlay(alignment: .top) {
                        if navBarSweepPhase > 0 {
                            LinearGradient(colors: [.clear, .white.opacity(0.06 * navBarSweepPhase), .white.opacity(0.10 * navBarSweepPhase), .white.opacity(0.06 * navBarSweepPhase), .clear],
                                           startPoint: .leading, endPoint: .trailing)
                            .frame(height: 44)
                            .offset(x: navBarSweepPhase * UIScreen.main.bounds.width - UIScreen.main.bounds.width / 2)
                        }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 50, coordinateSpace: .global)
                            .onEnded { v in
                                if v.startLocation.x < 30 && v.location.x > v.startLocation.x + 50 {
                                    var newPath = controlPath
                                    if !newPath.isEmpty { newPath.removeLast() }
                                    controlPath = newPath
                                }
                            }
                    )
            }
            .transaction { t in
                t.animation = .spring(response: 0.5, dampingFraction: 0.65, blendDuration: 0.3)
            }
            .tabGlassContainer()
            .tabItem {
                Label("车控", systemImage: "slider.horizontal.3")
                    .accessibilityLabel(Text("车控"))
                    .accessibilityHint(Text("远程控制车辆，包括锁车、解锁、空调控制等功能"))
            }
            .accessibilitySortPriority(1)
            .tag(1)
            .transaction { t in
                t.animation = .spring(response: 0.5, dampingFraction: 0.65, blendDuration: 0.3)
                t.labelSize = .medium
            }
            .modifier(TabCardTransition(tabId: 1, isActive: nav.selectedTab == 1 && prevSelectedTab != 1))
            .onChange(of: nav.selectedTab) { newTab in
                prevSelectedTab = nav.selectedTab
            }

            NavigationStack(path: $messagesPath) {
                MessagesView()
                    .navigationDestination(for: Deeplink.self) { link in
                        NavGlassWrapper {
                            switch link {
                            case .vehicle:  VehicleView().environmentObject(nav)
                            case .health:   HealthView().environmentObject(nav)
                            case .battery:  BatteryView().environmentObject(nav)
                            case .data:     DataView(kind: .status).environmentObject(nav)
                            case .dev:      DevView().environmentObject(nav)
                            case .messages: MessagesView().environmentObject(nav)
                            case .control:  ControlView().environmentObject(nav)
                            }
                        }
                    }
                    .transition(liquidGlassPopTransition)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            BackGlassButton(navigationPath: $messagesPath)
                        }
                    }
                    .navigationBarBackButtonHidden()
                    .overlay(alignment: .top) {
                        if navBarSweepPhase > 0 {
                            LinearGradient(colors: [.clear, .white.opacity(0.06 * navBarSweepPhase), .white.opacity(0.10 * navBarSweepPhase), .white.opacity(0.06 * navBarSweepPhase), .clear],
                                           startPoint: .leading, endPoint: .trailing)
                            .frame(height: 44)
                            .offset(x: navBarSweepPhase * UIScreen.main.bounds.width - UIScreen.main.bounds.width / 2)
                        }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 50, coordinateSpace: .global)
                            .onEnded { v in
                                if v.startLocation.x < 30 && v.location.x > v.startLocation.x + 50 {
                                    var newPath = messagesPath
                                    if !newPath.isEmpty { newPath.removeLast() }
                                    messagesPath = newPath
                                }
                            }
                    )
            }
            .transaction { t in
                t.animation = .spring(response: 0.5, dampingFraction: 0.65, blendDuration: 0.3)
            }
            .tabGlassContainer()
            .tabItem {
                Label("消息", systemImage: "bubble.left.fill")
                    .accessibilityLabel(Text("消息"))
                    .accessibilityHint(Text("车辆通知和消息中心"))
            }
            .accessibilitySortPriority(2)
            .tag(2)
            .transaction { t in
                t.animation = .spring(response: 0.5, dampingFraction: 0.65, blendDuration: 0.3)
                t.labelSize = .medium
            }
            .modifier(TabCardTransition(tabId: 2, isActive: nav.selectedTab == 2 && prevSelectedTab != 2))
            .onChange(of: nav.selectedTab) { newTab in
                prevSelectedTab = nav.selectedTab
            }

            NavigationStack(path: $minePath) {
                MineView()
                    .navigationDestination(for: Deeplink.self) { link in
                        NavGlassWrapper {
                            switch link {
                            case .vehicle:  VehicleView().environmentObject(nav)
                            case .health:   HealthView().environmentObject(nav)
                            case .battery:  BatteryView().environmentObject(nav)
                            case .data:     DataView(kind: .status).environmentObject(nav)
                            case .dev:      DevView().environmentObject(nav)
                            case .messages: MessagesView().environmentObject(nav)
                            case .control:  ControlView().environmentObject(nav)
                            }
                        }
                    }
                    .transition(liquidGlassPopTransition)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            BackGlassButton(navigationPath: $minePath)
                        }
                    }
                    .navigationBarBackButtonHidden()
                    .overlay(alignment: .top) {
                        if navBarSweepPhase > 0 {
                            LinearGradient(colors: [.clear, .white.opacity(0.06 * navBarSweepPhase), .white.opacity(0.10 * navBarSweepPhase), .white.opacity(0.06 * navBarSweepPhase), .clear],
                                           startPoint: .leading, endPoint: .trailing)
                            .frame(height: 44)
                            .offset(x: navBarSweepPhase * UIScreen.main.bounds.width - UIScreen.main.bounds.width / 2)
                        }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 50, coordinateSpace: .global)
                            .onEnded { v in
                                if v.startLocation.x < 30 && v.location.x > v.startLocation.x + 50 {
                                    var newPath = minePath
                                    if !newPath.isEmpty { newPath.removeLast() }
                                    minePath = newPath
                                }
                            }
                    )
            }
            .transaction { t in
                t.animation = .spring(response: 0.5, dampingFraction: 0.65, blendDuration: 0.3)
            }
            .tabGlassContainer()
            .tabItem {
                Label("我的", systemImage: "person.fill")
                    .accessibilityLabel(Text("我的"))
                    .accessibilityHint(Text("账号设置和个人信息管理"))
            }
            .accessibilitySortPriority(3)
            .tag(3)
            .transaction { t in
                t.animation = .spring(response: 0.5, dampingFraction: 0.65, blendDuration: 0.3)
                t.labelSize = .medium
            }
            .modifier(TabCardTransition(tabId: 3, isActive: nav.selectedTab == 3 && prevSelectedTab != 3))
            .onChange(of: nav.selectedTab) { newTab in
                prevSelectedTab = nav.selectedTab
            }
        }
        // VoiceOver：切换 Tab 时朗读当前页面名称（仅首次切换到新 Tab）
        .onChange(of: nav.selectedTab) { newTab in
            if newTab != lastAnnouncedTab {
                lastAnnouncedTab = newTab
                let label = NavState.tabAccessibilityLabels[newTab] ?? "Tab \(newTab)"
                UIAccessibility.post(notification: .announcement, argument: "已切换到\(label)页")
            }
        }
        // NavBar 反光扫过定时器
        .onReceive(sweepTimer) { _ in
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false)) {
                navBarSweepPhase = 1.0
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
        .accessibilityHint(Text("四个主要功能模块：车况、车控、消息、我的。左右滑动可切换标签页"))
        .accessibilitySortPriority(0)
        .accent(.accent)
        // #4 网络状态指示器 + #NEW-3 离线模式提示
        .overlay(alignment: .top) {
            if store.networkStatus != .online || store.isOfflineMode {
                NetworkStatusIndicator(status: store.isOfflineMode ? .offline : store.networkStatus)
                    .padding(.top, 0)
            }
        }
        // 液态玻璃 TabBar：磨砂背景 + 选中态脉冲光晕
        .overlay(alignment: .bottom) {
            ZStack(alignment: .bottom) {
                LiquidGlassTabBar(selectedTab: $nav.selectedTab)
                    .frame(height: 50)
                    .allowsHitTesting(false)
                if let t = nav.currentToast {
                    ToastView(text: t.text, icon: t.icon)
                        .id(UUID())
                }
            }
        }
        .transaction { t in
            t.animation = .spring(response: 0.5, dampingFraction: 0.65, blendDuration: 0.3)
        }
        .animation(.easeOut(duration: 0.2), value: nav.currentToast)
    }
}

// =============================================================================
// LiquidGlassTabBar —— iOS 27 液态玻璃 TabBar
// 选中态图标带脉冲光晕，未选中态带微光，整体磨砂玻璃背景
// =============================================================================

/// TabBar 底部脉冲光晕 + 液态玻璃指示条视图
private class TabBarGlowOverlay: UIView {
    private let glowLayer = CAShapeLayer()
    private let pressLayer = CAShapeLayer()
    private let indicatorLayer = CAShapeLayer()   // Liquid Glass 胶囊指示条
    private let indicatorGlowLayer = CAShapeLayer() // 指示条外部光晕
    private let floatRingLayer = CAShapeLayer()       // 选中图标上浮光环
    private var selectedItemIndex: Int = -1
    private var pressAnimation: CABasicAnimation?

    override func layoutSubviews() {
        super.layoutSubviews()
        updateGlow()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        guard let tabBar = superview as? UITabBar, let touch = touches.first else { return }
        let point = touch.location(in: self)
        for (idx, frame) in tabBar.items?.enumerated().map { ($0, $1.frame) } ?? [] {
            if frame.contains(point) {
                triggerPressGlow(at: frame.midX, y: frame.midY)
                triggerIconBounce(at: frame.midX, y: frame.midY - 14)
                break
            }
        }
    }

    /// 图标按压缩放弹跳：选中图标瞬间弹簧放大后回弹
    private func triggerIconBounce(at cx: CGFloat, y cy: CGFloat) {
        let radius: CGFloat = 14
        let path = CGPath(ellipseIn: CGRect(x: cx - radius, y: cy - radius, width: radius * 2, height: radius * 2), transform: nil)
        let bounceLayer = CAShapeLayer()
        bounceLayer.path = path
        bounceLayer.fillColor = UIColor.accent.withAlphaComponent(0.25).cgColor
        bounceLayer.strokeColor = nil
        bounceLayer.opacity = 1.0

        // 缩放：0.5 → 1.3 → 0.95 → 1.0（弹簧过冲）
        let scaleAnim = CABasicAnimation(keyPath: "transform.scale")
        scaleAnim.fromValue = 0.5
        scaleAnim.toValue = 1.0
        scaleAnim.duration = 0.35
        scaleAnim.fillMode = .both
        scaleAnim.isRemovedOnCompletion = false
        bounceLayer.add(scaleAnim, forKey: "iconBounce")

        layer.addSublayer(bounceLayer)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            withAnimation(.easeOut(duration: 0.1)) {
                bounceLayer.opacity = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                bounceLayer.removeFromSuperlayer()
            }
        }
    }

    func selectItem(at index: Int, tabBarItemCount count: Int) {
        guard index != selectedItemIndex else { return }
        let prevIndex = selectedItemIndex
        selectedItemIndex = index
        updateGlow()
        slideIndicator(from: prevIndex, to: index)
        animateFloatRing(to: index)
    }

    /// 图标上浮光环动画：spring 从 0→1 scale + 轻微上移，模拟选中时图标弹起
    private func animateFloatRing(to index: Int) {
        guard index >= 0, index < items.count else { return }
        let frame = items[index]
        let cx = frame.midX
        let cy = frame.midY - 8  // 环中心略高于图标中心
        let radius: CGFloat = 16

        let path = CGPath(ellipseIn: CGRect(x: cx - radius, y: cy - radius, width: radius * 2, height: radius * 2), transform: nil)
        floatRingLayer.path = path
        floatRingLayer.fillColor = UIColor.clear.cgColor
        floatRingLayer.strokeColor = UIColor.accent.withAlphaComponent(0.5).cgColor
        floatRingLayer.lineWidth = 2.0
        floatRingLayer.shadowColor = UIColor.accent.withAlphaComponent(0.6).cgColor
        floatRingLayer.shadowRadius = 8
        floatRingLayer.shadowOffset = .zero
        floatRingLayer.opacity = 0

        if layer.sublayers?.contains(floatRingLayer) == false {
            layer.addSublayer(floatRingLayer)
        }

        // 入场：scale 0→1 + opacity 0→1（弹簧回弹）
        let scaleAnim = CABasicAnimation(keyPath: "transform.scale")
        scaleAnim.fromValue = 0.3
        scaleAnim.toValue = 1.0
        scaleAnim.duration = 0.4
        scaleAnim.fillMode = .both
        scaleAnim.isRemovedOnCompletion = false
        floatRingLayer.add(scaleAnim, forKey: "floatScale")

        let opacityAnim = CABasicAnimation(keyPath: "opacity")
        opacityAnim.fromValue = 0.0
        opacityAnim.toValue = 1.0
        opacityAnim.duration = 0.4
        opacityAnim.fillMode = .both
        opacityAnim.isRemovedOnCompletion = false
        floatRingLayer.add(opacityAnim, forKey: "floatOpacity")

        // 持续呼吸脉动（选中后每 2s 一次）
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 0.5
        pulse.toValue = 1.0
        pulse.duration = 1.0
        pulse.autoreverses = true
        pulse.repeatCount = .greatestFiniteMagnitude
        floatRingLayer.add(pulse, forKey: "floatPulse")

        // 位置上移弹跳
        let posAnim = CABasicAnimation(keyPath: "position")
        posAnim.fromValue = NSValue(cgPoint: CGPoint(x: cx, y: cy + 12))
        posAnim.toValue = NSValue(cgPoint: CGPoint(x: cx, y: cy))
        posAnim.duration = 0.45
        posAnim.fillMode = .both
        posAnim.isRemovedOnCompletion = false
        floatRingLayer.add(posAnim, forKey: "floatPos")
    }

    private func triggerPressGlow(at cx: CGFloat, y cy: CGFloat) {
        // 取消上一次按压动画（若有）
        pressAnimation?.removeFromSuperlayer()

        let radius: CGFloat = 28
        let path = CGPath(ellipseIn: CGRect(x: cx - radius, y: cy - radius, width: radius * 2, height: radius * 2), transform: nil)
        pressLayer.path = path
        pressLayer.fillColor = UIColor.accent.withAlphaComponent(0.45).cgColor
        pressLayer.strokeColor = nil
        pressLayer.shadowColor = UIColor.accent.withAlphaComponent(0.8).cgColor
        pressLayer.shadowRadius = 10
        pressLayer.shadowOffset = .zero
        pressLayer.opacity = 1.0

        if layer.sublayers?.contains(pressLayer) == false {
            layer.addSublayer(pressLayer)
        }

        // 弹簧缩放：从 0.6 膨胀到 1.2，模拟 Liquid Glass 压缩回弹
        let scaleAnim = CABasicAnimation(keyPath: "transform.scale")
        scaleAnim.fromValue = 0.5
        scaleAnim.toValue = 1.15
        scaleAnim.duration = 0.35
        scaleAnim.fillMode = .both
        scaleAnim.isRemovedOnCompletion = false
        pressLayer.add(scaleAnim, forKey: "pressScale")
        pressAnimation = scaleAnim

        // 脉冲淡出：0.4s 内从 opacity=1 到 opacity=0
        let fadeOut = CABasicAnimation(keyPath: "opacity")
        fadeOut.fromValue = 1.0
        fadeOut.toValue = 0.0
        fadeOut.duration = 0.4
        fadeOut.fillMode = .both
        fadeOut.isRemovedOnCompletion = false
        pressLayer.add(fadeOut, forKey: "pressFade")

        // 延迟移除 layer
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeOut(duration: 0.15)) {
                self.pressLayer.opacity = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.pressLayer.removeFromSuperlayer()
            }
        }
    }

    private func updateGlow() {
        // 移除之前的脉冲动画
        glowLayer.removeAllAnimations()

        guard selectedItemIndex >= 0, selectedItemIndex < items.count else {
            glowLayer.opacity = 0
            return
        }
        let itemFrame = items[selectedItemIndex]
        let cx = itemFrame.midX
        let cy = bounds.height * 0.45
        let radius: CGFloat = 18

        let path = CGPath(ellipseIn: CGRect(x: cx - radius, y: cy - radius, width: radius * 2, height: radius * 2), transform: nil)
        glowLayer.path = path
        glowLayer.fillColor = UIColor.systemBlue.withAlphaComponent(0.35).cgColor
        glowLayer.strokeColor = nil
        glowLayer.shadowColor = UIColor.systemBlue.withAlphaComponent(0.6).cgColor
        glowLayer.shadowRadius = 12
        glowLayer.shadowOffset = .zero
        glowLayer.opacity = 1

        if layer.sublayers?.contains(glowLayer) == false {
            layer.addSublayer(glowLayer)
        }
        // 脉冲动画
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 0.3
        pulse.toValue = 1.0
        pulse.duration = 0.6
        pulse.autoreverses = true
        pulse.repeatCount = .greatestFiniteMagnitude
        glowLayer.add(pulse, forKey: "pulse")
    }

    private func slideIndicator(from prevIndex: Int, to newIndex: Int) {
        guard prevIndex >= 0, prevIndex < items.count, newIndex >= 0, newIndex < items.count else { return }
        let fromFrame = items[prevIndex]
        let toFrame = items[newIndex]
        let tabBarHeight = bounds.height

        // 指示条尺寸：宽度 40pt，高度 4pt，胶囊形
        let barWidth: CGFloat = 40.0
        let barHeight: CGFloat = 4.0
        let barRadius: CGFloat = barHeight / 2

        // 位置：位于图标正下方，距 TabBar 底边约 8pt
        let targetY = tabBarHeight - 12 - barHeight / 2
        let targetX = toFrame.midX

        // 创建胶囊形路径（椭圆近似）
        let path = CGPath(ellipseIn: CGRect(x: targetX - barWidth / 2, y: targetY - barRadius, width: barWidth, height: barHeight), transform: nil)

        // ── 主指示条层 ──
        indicatorLayer.removeAllAnimations()
        indicatorLayer.path = path
        // Liquid Glass 风格：白色填充 + 高光描边 + 柔和阴影
        indicatorLayer.fillColor = UIColor.white.withAlphaComponent(0.85).cgColor
        indicatorLayer.strokeColor = UIColor.white.withAlphaComponent(0.5).cgColor
        indicatorLayer.lineWidth = 0.5
        indicatorLayer.shadowColor = UIColor.white.withAlphaComponent(0.6).cgColor
        indicatorLayer.shadowOpacity = 0.6
        indicatorLayer.shadowRadius = 4
        indicatorLayer.shadowOffset = .zero
        indicatorLayer.opacity = 1.0

        // ── 光晕扩散层（稍大、更透明，营造玻璃折射感）──
        indicatorGlowLayer.removeAllAnimations()
        let glowPath = CGPath(ellipseIn: CGRect(x: targetX - barWidth / 2 - 4, y: targetY - barRadius - 2, width: barWidth + 8, height: barHeight + 4), transform: nil)
        indicatorGlowLayer.path = glowPath
        indicatorGlowLayer.fillColor = UIColor.systemBlue.withAlphaComponent(0.15).cgColor
        indicatorGlowLayer.strokeColor = nil
        indicatorGlowLayer.shadowColor = UIColor.systemBlue.withAlphaComponent(0.4).cgColor
        indicatorGlowLayer.shadowRadius = 8
        indicatorGlowLayer.shadowOffset = .zero
        indicatorGlowLayer.opacity = 0.8

        if layer.sublayers?.contains(indicatorLayer) == false {
            layer.addSublayer(indicatorLayer)
        }
        if layer.sublayers?.contains(indicatorGlowLayer) == false {
            layer.addSublayer(indicatorGlowLayer)
        }

        // ── 弹簧滑动动画（CAKeyframeAnimation 实现过冲 + 回弹）──
        let prevY = tabBarHeight - 12 - barHeight / 2
        let prevX = fromFrame.midX

        let keyTimes: [CGFloat] = [0.0, 0.5, 0.75, 1.0]
        let values: [NSValue] = [
            NSValue(cgPoint: CGPoint(x: prevX, y: prevY)),
            NSValue(cgPoint: CGPoint(x: targetX, y: targetY)),
            NSValue(cgPoint: CGPoint(x: targetX, y: targetY)),
            NSValue(cgPoint: CGPoint(x: targetX, y: targetY)),
        ]
        let posAnim = CAKeyframeAnimation(keyPath: "position")
        posAnim.values = values
        posAnim.keyTimes = keyTimes.map { $0 as NSNumber }
        posAnim.duration = 0.45
        posAnim.fillMode = .both
        posAnim.isRemovedOnCompletion = false
        indicatorLayer.add(posAnim, forKey: "slidePos")
        indicatorGlowLayer.add(posAnim.copy() as? CABasicAnimation ?? posAnim, forKey: "slidePosGlow")

        // 缩放弹性：0.6 → 1.05 → 0.98 → 1.0
        let scaleAnim = CABasicAnimation(keyPath: "transform.scale")
        scaleAnim.fromValue = 0.65
        scaleAnim.toValue = 1.0
        scaleAnim.duration = 0.45
        scaleAnim.fillMode = .both
        scaleAnim.isRemovedOnCompletion = false
        indicatorLayer.add(scaleAnim, forKey: "slideScale")

        // 光晕层缩放：更慢更柔和
        let glowScale = CABasicAnimation(keyPath: "transform.scale")
        glowScale.fromValue = 0.75
        glowScale.toValue = 1.0
        glowScale.duration = 0.55
        glowScale.fillMode = .both
        glowScale.isRemovedOnCompletion = false
        indicatorGlowLayer.add(glowScale, forKey: "glowScale")
    }

    private var items: [CGRect] {
        guard let tabBar = superview as? UITabBar else { return [] }
        return tabBar.items?.enumerated().map { $1.frame } ?? []
    }
}

/// 液态玻璃 TabBar —— 通过 UITabBarController 注入到 TabView
struct LiquidGlassTabBar: UIViewRepresentable {
    @Binding var selectedTab: Int

    func makeUIView(context: Context) -> UIView {
        // 配置全局 TabBar 外观（磨砂玻璃 + 选中色）
        let appearance = UITabBarAppearance()
        // 磨砂玻璃背景
        appearance.backgroundEffect = UIBlurEffect(style: .regular)
        appearance.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.72)
        // 分隔线
        appearance.shadowColor = UIColor.white.withAlphaComponent(0.15)
        appearance.shadowImage = UIImage()
        // 未选中图标 / 文字
        let unselected = UITabBarItemAppearance()
        unselected.normal.iconColor = UIColor.secondaryLabel
        unselected.normal.titleTextAttributes = [.foregroundColor: UIColor.secondaryLabel]
        appearance.stackedLayoutAppearance = unselected
        appearance.inlineLayoutAppearance = unselected
        appearance.compactLayoutAppearance = unselected
        // 选中图标 / 文字
        let selected = UITabBarItemAppearance()
        selected.selected.iconColor = UIColor.accent
        selected.selected.titleTextAttributes = [.foregroundColor: UIColor.accent]
        appearance.stackedLayoutAppearance = selected
        appearance.inlineLayoutAppearance = selected
        appearance.compactLayoutAppearance = selected
        UITabBar.appearance().standardAppearance = appearance
        if #available(iOS 15.0, *) {
            UITabBar.appearance().scrollEdgeAppearance = appearance
        }

        // 光晕 + 指示条叠加层
        let overlay = TabBarGlowOverlay()
        overlay.isHidden = true
        return overlay
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let overlay = uiView as? TabBarGlowOverlay else { return }
        overlay.isHidden = false
        overlay.selectItem(at: selectedTab, tabBarItemCount: 4)
    }
}

// MARK: - #47 iPad Split View 支持
#if os(iOS) && os(macOS)
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
#endif

