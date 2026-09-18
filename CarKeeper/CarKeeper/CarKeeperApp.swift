import SwiftUI

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

struct MainTabView: View {
    @StateObject private var nav = NavState.shared

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
            }
            .tabItem { Label("车况", systemImage: "car.fill") }
            .tag(0)

            NavigationStack {
                ControlView()
            }
            .tabItem { Label("车控", systemImage: "slider.horizontal.3") }
            .tag(1)

            NavigationStack {
                MessagesView()
            }
            .tabItem { Label("消息", systemImage: "bubble.left.fill") }
            .tag(2)

            NavigationStack {
                MineView()
            }
            .tabItem { Label("我的", systemImage: "person.fill") }
            .tag(3)
        }
        .accentColor(.accentColor)
        .overlay(alignment: .bottom) {
            if nav.showCopiedToast {
                Label("VIN 已复制", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .background(.thin, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
                    .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
                    .offset(y: -10)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.25), value: nav.showCopiedToast)
    }
}
