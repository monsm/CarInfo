import SwiftUI

// =============================================================================
//  HomeMode —— 底部模式条里的每一档 = 一个功能界面
// =============================================================================
//
//  换模式**不换屏**：地图永远是取景框，纸永远是同一张纸（同一个高度、同一个位置），
//  变的只是纸里装的内容 —— 这与相机 App 里「换档位不离开取景框」是同一条规则。
//
//  为什么入口只有这一条：此前的入口有四套（Tab 栏 / 地图图层 / 右上角索引页 /
//  「我的」的磁贴），同一个功能最多能从四个地方进去，这就是「缝合怪」的来源。
//  这条规则不靠自觉：`scan/oneentry.py` 会在 CI 上拦下任何一处绕过条子去 push 页面。
//
//  **2026-09-23：档位从 10 收到 6。** 收掉的四档不是删功能，是同一件事拆成了两屏：
//    · 健康 / 保养 → 并进「车辆」：档案、体检、保养回答的是同一个问题（这辆车怎么了），
//      此前要拨三次条子才看得完，而三次里换的其实是同一份报文。
//    · 应急 / 诊断 → 并进「我的」：一个是「出事时打给谁」，一个是「出问题时看什么」，
//      都是少数时刻才用、但必须能到的东西；它们此前各占一整档，条子上 4/10 的位置
//      被低频内容占着。
//  档内怎么分：各 hub 页用分段控件（`HomeSub`），深链落到哪一段由
//  `destination(for:)` 决定 —— 搜索里点「健康」不该落在「档案」上。
//
//  顺序不是按功能分类排的，也不是按字母 —— 是**地图在正中**：
//    出行 · 车辆 · 【现在】 · 充电 · 车控 · 我的
//  地图主屏是默认档（每次上车先看的就是它），它必须停在条子的正中：
//  静止只露三档时，左右各有一个邻居可以往两边拖 —— 而首页顶在最左边时，
//  左边是空的，第一眼看上去像「到头了」。
//  两翼按用的频率排：左侧「出行 / 车辆」是一天看一两次的，
//  右侧「充电 / 车控 / 我的」是常按的与收尾的。
enum HomeMode: String, CaseIterable, Identifiable {
    case trips
    case vehicle
    /// 车现在在哪、什么状态 —— 也就是地图主屏本来的那张纸（含四个地图图层）。
    /// **它必须排在正中**（6 档里的第 3 档）：条子的静止形态、默认档、
    /// 以及「左右各一个邻居」这三件事都从 case 顺序推出来，写错了不会有任何报错。
    case now
    /// 充电（含电池读数与趋势）。它原来叫「电池」，可这一页回答的是「现在充得怎么样」，
    /// 电池只是它的一个读数域。
    case charge
    case control
    case mine

    var id: String { rawValue }

    /// 条子上显示的文字。**只有文字，没有图标** —— 相机那条也没有图标，
    /// 图标会把这几个档挤成一条图标墙，反而认不出哪个是哪个。
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

    /// 这一档的代表深链（搜索的「去这一档」与文档用它当 key）。
    /// `.now` 没有独立页面（它就是地图本身），所以没有代表深链。
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

    /// 深链 → 档位 + 档内段落。**每个深链都落到某一档**：
    /// 全库不再有「push 出来的功能页」——同一个功能只有一种存在方式。
    static func destination(for link: Deeplink) -> (mode: HomeMode, sub: HomeSub?) {
        switch link {
        case .vehicle: return (.vehicle, .profile)
        case .health: return (.vehicle, .health)
        case .service: return (.vehicle, .service)
        case .battery: return (.charge, nil)
        case .control: return (.control, nil)
        // `.dashboard` / `.parking` / `.score` 是别名：它们指向的页面与 `.trips` 是同一个。
        case .trips, .parking, .score, .dashboard: return (.trips, nil)
        case .mine: return (.mine, .settings)
        case .emergency: return (.mine, .emergency)
        case .dev: return (.mine, .dev)
        }
    }

    /// 记住上次停在哪一档：地图主屏的「当前位置」应当被记住，
    /// 每次冷启动都跳回第一档等于让用户每天重新选一次。
    static let storageKey = "carkeeper_home_mode"

    /// 供 `DSSwipeStrip` 用的档位表
    static var stripItems: [DSSwipeStrip.Item] {
        allCases.map { DSSwipeStrip.Item(id: $0.rawValue, title: $0.title) }
    }

    /// 这一档的个性色。
    ///
    /// 取值不在这里：它在主题表（`ArtThemeSpec.pageAccents`）里 ——
    /// 四套艺术主题下它自动是四套配色，而调用点一行不改（与全 App 的颜色纪律一致）。
    /// 下标取 **case 顺序**而不是 rawValue：色相是跟着在条子上的位置走的，
    /// 第几档就应该是第几个色（换名字不会把配色也换掉）。
    var accent: Color {
        let all = TokensPalette.pageAccents
        let i = Self.allCases.firstIndex(of: self) ?? 0
        return all.indices.contains(i) ? all[i] : TokensPalette.accent
    }

    /// 这一档在叠叠乐里的**第一张卡**：巨字头。
    ///
    /// 「现在」那一档没有头 —— 那张纸本身就是地图的面板（车名 + 地址 + 状态行），
    /// 再叠一个巨字就是两层标题（见 `HomeModeHead` 的第 ③ 条自约束）。
    var headCards: [StackCard] {
        self == .now ? [] : [StackCard(id: "head", content: AnyView(HomeModeHead(mode: self)))]
    }
}

// =============================================================================
//  HomeSub —— 档内的段落（只有两个 hub 页用它）
// =============================================================================
//  它不是导航层级：没有第二层返回按钮、没有 push —— 只是同一张纸上的一段。
//  深链（`carkeeper://health`）落到的是「车辆」这一档的「健康」那一段。
enum HomeSub: String, CaseIterable, Identifiable {
    // 车辆档
    case profile
    case health
    case service
    // 我的档
    case settings
    case emergency
    case dev

    var id: String { rawValue }

    var title: String {
        switch self {
        case .profile: return "档案"
        case .health: return "健康"
        case .service: return "保养"
        case .settings: return "设置"
        case .emergency: return "应急"
        case .dev: return "诊断"
        }
    }

    /// 车辆档的三段（顺序即显示顺序）
    static let vehicleTabs: [HomeSub] = [.profile, .health, .service]
    /// 「我的」档的三段
    static let mineTabs: [HomeSub] = [.settings, .emergency, .dev]
}
