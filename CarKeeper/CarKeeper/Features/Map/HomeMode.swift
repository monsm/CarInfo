import SwiftUI

enum HomeMode: String, CaseIterable, Identifiable {
    case trips
    case charge
    case now
    case control
    case mine
    case vehicle

    var id: String { rawValue }

    var title: String {
        switch self {
        case .now: return "现在"
        case .vehicle: return "车辆"
        case .charge: return "充电"
        case .control: return "车控"
        case .trips: return "出行"
        case .mine: return "我的"
        }
    }

    var deeplink: Deeplink? {
        switch self {
        case .now: return nil
        case .vehicle: return .vehicle
        case .charge: return .battery
        case .control: return .control
        case .trips: return .trips
        case .mine: return .mine
        }
    }

    static func destination(for link: Deeplink) -> (mode: HomeMode, sub: HomeSub?) {
        switch link {
        case .vehicle: return (.vehicle, .profile)
        case .health: return (.vehicle, .health)
        case .service: return (.vehicle, .service)
        case .battery: return (.charge, nil)
        case .control: return (.control, nil)
        case .trips, .parking, .score, .dashboard: return (.trips, nil)
        case .mine: return (.mine, .settings)
        case .emergency: return (.mine, .emergency)
        case .dev: return (.mine, .dev)
        }
    }

    static let storageKey = "carkeeper_home_mode"

    static var stripItems: [DSSwipeStrip.Item] {
        allCases.filter { $0 != .vehicle }
            .map { DSSwipeStrip.Item(id: $0.rawValue, title: $0.title) }
    }

    var accent: Color {
        let all = TokensPalette.pageAccents
        let i = Self.allCases.firstIndex(of: self) ?? 0
        return all.indices.contains(i) ? all[i] : TokensPalette.accent
    }


    static var wallpaperOrder: [HomeMode] { allCases.filter { $0 != .now } }

    static func wallpaperPosition(_ index: Double) -> Double {
        let screens = wallpaperOrder
        guard screens.count > 1 else { return 0 }
        let last = screens.count - 1
        let anchors: [Double] = screens.map { Double(allCases.firstIndex(of: $0) ?? 0) }
        if index <= anchors[0] { return 0 }
        for i in 0..<last where index <= anchors[i + 1] {
            let span = anchors[i + 1] - anchors[i]
            let t = span > 0 ? (index - anchors[i]) / span : 0
            return (Double(i) + t) / Double(last)
        }
        return 1
    }

    var headCards: [StackCard] {
        self == .now ? [] : [StackCard(id: "head", title: title,
                                       content: AnyView(HomeModeHead(mode: self)))]
    }
}

enum HomeSub: String, CaseIterable, Identifiable {
    case profile
    case health
    case service
    case journeys
    case events
    case settings
    case emergency
    case dev

    var id: String { rawValue }

    var title: String {
        switch self {
        case .profile: return "档案"
        case .health: return "健康"
        case .service: return "保养"
        case .journeys: return "行程"
        case .events: return "事件"
        case .settings: return "设置"
        case .emergency: return "应急"
        case .dev: return "诊断"
        }
    }

    static let vehicleTabs: [HomeSub] = [.profile, .health, .service]
    static let tripsTabs: [HomeSub] = [.journeys, .events]
    static let mineTabs: [HomeSub] = [.settings, .emergency, .dev]
}
