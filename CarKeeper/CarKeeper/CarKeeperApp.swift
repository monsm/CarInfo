import SwiftUI
import UIKit


extension Notification.Name {
    static let pinConfirmed = Notification.Name("car_pin_confirmed")
    static let tempConfirmed = Notification.Name("car_temp_confirmed")
    static let didLogout = Notification.Name("didLogout")
    static let locationUpdated = Notification.Name("locationUpdated")
}


enum Deeplink: Hashable, CaseIterable {
    case vehicle, health, battery, dev, control, dashboard
    case trips, service, parking, emergency, score
    case mine

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

    init?(url: URL) {
        guard url.scheme?.lowercased() == "carkeeper" else { return nil }
        let raw = (url.host ?? url.path)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()
        guard !raw.isEmpty, let match = Self.allCases.first(where: { $0.key == raw }) else { return nil }
        self = match
    }
}


enum SceneID {
    static let detail = "detail"
}

@main
struct CarKeeperApp: App {
    private let store = AppStore.shared
    @StateObject private var nav = NavState.shared

    init() {
    }

    var body: some Scene {
        WindowGroup {
            root
        }
        WindowGroup(id: SceneID.detail) {
            DetailSplitView()
        }
    }

    @State private var showSplash = true
    @State private var isAppLoading = false
    @AppStorage("carkeeper_onboarding_seen") private var onboardingSeen = false

    private func openDeeplink(_ url: URL) {
        guard let link = Deeplink(url: url) else { return }
        guard store.isLoggedIn else { return }
        nav.openMode(for: link)
    }

    private var root: some View {
        Group {
            if showSplash {
                SplashView()
                    .ignoresSafeArea()
                    .onAppear { isAppLoading = true }
                    .task {
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        showSplash = false
                    }
            } else if !onboardingSeen && !store.isLoggedIn {
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
        .background { AppCanvas() }
        .onAppear {
            if store.isLoggedIn && store.cars.isEmpty {
                Task {
                    await store.bootstrap()
                }
                Task {
                    await store.bootstrap()
                    if store.isLoggedIn && store.cars.isEmpty {
                        Task { @MainActor in
                            ToastManager.shared.show("数据加载失败，请检查网络后重试", icon: "wifi.exclamationmark")
                        }
                    }
                }
            }
            if let c = store.currentLocation?.coordinate {
                Task {
                    await WeatherService.shared.refreshIfNeeded(coordinate: c)
                }
            }
            MemoryMonitor.shared.startMonitoring(interval: 10)
            Task { await ChargingStatusMonitor.shared.requestAuthorization() }
            RemoteLockManager.shared.startMonitoring()
            _ = MaintenanceReminderScheduler.shared
            _ = InsuranceReminderScheduler.shared
            ChargingStatusMonitor.shared.startMonitoring()
        }
        .onOpenURL { url in
            openDeeplink(url)
        }
        .onReceive(NotificationCenter.default.publisher(for: .locationUpdated)) { _ in
            guard let c = store.currentLocation?.coordinate else { return }
            Task { await WeatherService.shared.refreshIfNeeded(coordinate: c) }
        }
    }
}

final class NavState: ObservableObject, @unchecked Sendable {
    static let shared = NavState()
    @Published var path: [Deeplink] = []
    @Published var currentToast: (text: String, icon: String)? = nil
    @Published var homeSub: HomeSub? = nil

    private init() {}

    func popToRoot() { path = [] }

    func openMode(_ mode: HomeMode, sub: HomeSub? = nil) {
        UserDefaults.standard.set(mode.rawValue, forKey: HomeMode.storageKey)
        homeSub = sub
        path = []
    }

    func openMode(for link: Deeplink) {
        let to = HomeMode.destination(for: link)
        openMode(to.mode, sub: to.sub)
    }
}



struct MapShellView: View {
    @StateObject private var nav = NavState.shared
    private let store = AppStore.shared
    @State private var lowBatteryArmed = true


    private var mapStack: some View {
        NavigationStack(path: $nav.path) {
            MapSpineView()
        }
            .onReceive(NotificationCenter.default.publisher(for: .locationUpdated)) { _ in
                let energy = VM.energy(store.caches, store.car)
                if energy.socPct < 20, lowBatteryArmed {
                    lowBatteryArmed = false
                    nav.currentToast = (text: "电量低于 20%", icon: "battery.25")
                } else if energy.socPct >= 20 {
                    lowBatteryArmed = true
                }
            }
    }

    var body: some View {
        mapStack
        .tint(TokensPalette.ambient)
        .task {
            await store.bootstrap()
            RefreshLoop.shared.start()
            KeepAwake.shared.start()
        }
        .accessibilityLabel(Text("地图主屏"))
        .accessibilityHint(Text("底部的模式条可以到达每个功能界面"))
        .accessibilitySortPriority(0)
        .overlay(alignment: .top) {
            if store.networkStatus != .online {
                NetworkStatusIndicator(status: store.networkStatus)
            }
        }
    }
}


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
        .background { AppCanvas() }
    }
}

struct NetworkStatusIndicator: View {
    let status: AppStore.NetworkStatus
    var body: some View {
        Text("网络: " + status.rawValue).font(TokensTypo.caption).foregroundStyle(TokensPalette.secondary)
    }
}

struct ToastView: View {
    let text: String
    let icon: String?
    var body: some View {
        HStack(spacing: TokensSpacing.sm) {
            if let icon = icon { Image(safeSymbol: icon, fallback: icon) }
            Text(text)
        }
        .padding(.horizontal, TokensSpacing.md).padding(.vertical, TokensSpacing.sm)
        .dsGlassRounded(TokensRadius.medium, interactive: false)
        .foregroundStyle(TokensInk.primary)
    }
}


