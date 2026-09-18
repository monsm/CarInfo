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

    private init() {}

    func popToRoot() { path = [] }
}

// MARK: - 主 Tab

/// Tab 切换时的 Liquid Glass 卡片形变转场修饰符
/// 当 isActive 变为 true 时，触发 slide-in + scale + opacity 弹簧入场动效
struct TabCardTransition: ViewModifier {
    let tabId: Int
    let isActive: Bool

    func body(content: Content) -> some View {
        content
            .offset(y: isActive ? 0 : 40)
            .scaleEffect(isActive ? 1.0 : 0.92)
            .opacity(isActive ? 1.0 : 0.0)
            .animation(
                .spring(response: 0.55, dampingFraction: 0.62, blendDuration: 0.35),
                value: isActive
            )
    }
}

struct MainTabView: View {
    @StateObject private var nav = NavState.shared
    @State private var prevSelectedTab: Int = 0

    var body: some View {
        TabView(selection: $nav.selectedTab) {
            NavigationStack(path: $nav.path) {
                HomeView()
                    .navigationDestination(for: Deeplink.self) { link in
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
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity)
                            .animation(.spring(response: 0.45, dampingFraction: 0.6, blendDuration: 0.3)),
                        removal: .move(edge: .leading).combined(with: .opacity)
                            .animation(.easeInOut(duration: 0.25))
                    ))
            }
            .tabItem { Label("车况", systemImage: "car.fill") }
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
            .tabItem { Label("车控", systemImage: "slider.horizontal.3") }
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
            .tabItem { Label("消息", systemImage: "bubble.left.fill") }
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
            .tabItem { Label("我的", systemImage: "person.fill") }
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

/// TabBar 底部脉冲光晕视图
private class TabBarGlowOverlay: UIView {
    private let glowLayer = CAShapeLayer()
    private var selectedItemIndex: Int = -1

    override func layoutSubviews() {
        super.layoutSubviews()
        updateGlow()
    }

    func selectItem(at index: Int, tabBarItemCount count: Int) {
        guard index != selectedItemIndex else { return }
        selectedItemIndex = index
        updateGlow()
    }

    private func updateGlow() {
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

        // 光晕叠加层
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

