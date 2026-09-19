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
    static let vinCopied = Notification.Name("vinCopied")
    static let didLogout = Notification.Name("didLogout")
    static let locationUpdated = Notification.Name("locationUpdated")
}

enum Deeplink: Hashable {
    case vehicle, health, battery, data, dev, messages, control
}

@main
struct CarKeeperApp: App {
    private let store = AppStore.shared
    @StateObject private var nav = NavState.shared

    var body: some Scene {
        WindowGroup {
            root
        }
    }

    private var root: some View {
        Group {
            if store.isLoggedIn {
                MainTabView()
                    .environmentObject(nav)
                    .onReceive(NotificationCenter.default.publisher(for: .navToVehicle)) { _ in nav.path = [.vehicle] }
                    .onReceive(NotificationCenter.default.publisher(for: .navToHealth)) { _ in nav.path = [.health] }
                    .onReceive(NotificationCenter.default.publisher(for: .navToBattery)) { _ in nav.path = [.battery] }
                    .onReceive(NotificationCenter.default.publisher(for: .navToData)) { _ in nav.path = [.data] }
                    .onReceive(NotificationCenter.default.publisher(for: .navToDev)) { _ in nav.path = [.dev] }
                    .onReceive(NotificationCenter.default.publisher(for: .navToMessages)) { _ in
                        nav.path = [.messages]
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .vinCopied)) { _ in
                        nav.showCopiedToast = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { nav.showCopiedToast = false }
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
        }
    }
}

// 全局导航状态（深潜页 push 与 tab 切换共享）
final class NavState: ObservableObject, @unchecked Sendable {
    static let shared = NavState()
    @Published var path: [Deeplink] = []
    @Published var selectedTab: Int = 0
    @Published var showCopiedToast: Bool = false

    /// 每个 Tab 的 VoiceOver 描述（用于动态朗读切换时的页面名称）
    static let tabAccessibilityLabels: [Int: String] = [
        0: "车况", 1: "车控", 2: "消息", 3: "我的"
    ]

    private init() {}

    func popToRoot() { path = [] }

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

// =============================================================================
// NavGlassWrapper —— 深潜页 Liquid Glass 视差容器
// 与 TabCardTransition 同款三层视差，方向改为水平（从右侧滑入）
// 通过 @State _shown 管理触发时机，确保每次导航时仅播放一次入场动画
// =============================================================================

/// 深潜页（VehicleView / HealthView / BatteryView 等）的 Liquid Glass 视差包装器
/// 外层 ZStack 包含：glowLayer（背景散斑）→ glassLayer（磨砂玻璃卡）→ content（前景页面）
/// 每层以不同延迟从右侧滑入，形成真实深度感；退出时由 NavigationStack 标准 pop 转场接管。
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

    // 内部状态：首次 onAppear 时触发入场动画，之后保持激活；pop 时由 NavigationStack 接管退出转场
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
            .offset(x: _shown ? 0 : ox)
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
                .offset(x: _shown ? 0 : gx)
                .scaleEffect(_shown ? 1.0 : 0.94)
                .opacity(_shown ? 1.0 : 0.0)
                .animation(
                    .spring(response: 0.55, dampingFraction: 0.65, blendDuration: 0.4).delay(delay + 0.03),
                    value: _shown
                )

            // ── 第 2 层：前景内容（最快，从右侧 24pt 滑入，最接近导航标准）──
            content
                .offset(x: _shown ? 0 : cx)
                .scaleEffect(_shown ? 1.0 : 0.96)
                .opacity(_shown ? 1.0 : 0.0)
                .animation(
                    .spring(response: 0.55, dampingFraction: 0.62, blendDuration: 0.35).delay(delay),
                    value: _shown
                )
        }
        .edgesIgnoringSafeArea(.all)
        .onAppear {
            // 首次出现：延迟 0.05s 后触发入场动画，与导航滑入同步
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                _shown = true
            }
        }
    }
}

struct MainTabView: View {
    @StateObject private var nav = NavState.shared
    @State private var prevSelectedTab: Int = 0
    // VoiceOver：记录上次朗读的 Tab，避免重复播报
    @State private var lastAnnouncedTab: Int = 0

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
                            }
                        }
                    }
                    // 标准导航转场：push 时从右侧滑入，pop 时返回原位置
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            }
            .tabGlassContainer()
            .tabItem {
                Label("车况", systemImage: "car.fill")
                    .accessibilityLabel(Text("车况"))
                    .accessibilityHint(Text("车辆状态概览，包含行驶里程、胎压、SOC 电量等关键信息"))
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

            NavigationStack {
                ControlView()
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

            NavigationStack {
                MessagesView()
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

            NavigationStack {
                MineView()
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
        // 设置 TabView 整体无障碍描述和朗读顺序
        .accessibilityLabel(Text("主导航栏"))
        .accessibilityHint(Text("四个主要功能模块：车况、车控、消息、我的。左右滑动可切换标签页"))
        .accessibilitySortPriority(0)
        .accentColor(.accentColor)
        // 液态玻璃 TabBar：磨砂背景 + 选中态脉冲光晕
        .overlay(alignment: .bottom) {
            ZStack(alignment: .bottom) {
                LiquidGlassTabBar(selectedTab: $nav.selectedTab)
                    .frame(height: 50)
                    .allowsHitTesting(false)
                if nav.showCopiedToast {
                    Label("VIN 已复制", systemImage: "checkmark.circle.fill")
                        .font(Theme.caption.bold())))
                        .padding(.horizontal, 20).padding(.vertical, 12)
                        .background(.thin, in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
                        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
                        .offset(y: -10)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .transaction { t in
            t.animation = .spring(response: 0.5, dampingFraction: 0.65, blendDuration: 0.3)
        }
        .animation(.easeOut(duration: 0.25), value: nav.showCopiedToast)
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
                break
            }
        }
    }

    func selectItem(at index: Int, tabBarItemCount count: Int) {
        guard index != selectedItemIndex else { return }
        let prevIndex = selectedItemIndex
        selectedItemIndex = index
        updateGlow()
        slideIndicator(from: prevIndex, to: index)
    }

    private func triggerPressGlow(at cx: CGFloat, y cy: CGFloat) {
        // 取消上一次按压动画（若有）
        pressAnimation?.removeFromSuperlayer()

        let radius: CGFloat = 28
        let path = CGPath(ellipseIn: CGRect(x: cx - radius, y: cy - radius, width: radius * 2, height: radius * 2), transform: nil)
        pressLayer.path = path
        pressLayer.fillColor = UIColor.accentColor.withAlphaComponent(0.45).cgColor
        pressLayer.strokeColor = nil
        pressLayer.shadowColor = UIColor.accentColor.withAlphaComponent(0.8).cgColor
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
        selected.selected.iconColor = UIColor.accentColor
        selected.selected.titleTextAttributes = [.foregroundColor: UIColor.accentColor]
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

