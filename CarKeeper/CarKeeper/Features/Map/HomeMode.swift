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
//  现在索引页降级为二级入口（设置类内容），一级入口只有这条模式条。
//
//  顺序不是按功能分类排的，是按**用的频率**：
//    现在（每次上车看）→ 车辆/电池/车控（常看常按）→ 出行/保养（偶尔）→ 我的/诊断（少见）
enum HomeMode: String, CaseIterable, Identifiable {
    /// 车现在在哪、什么状态 —— 也就是地图主屏本来的那张纸（含四个地图图层）
    case now
    case vehicle
    case health
    case battery
    case control
    case trips
    case service
    case mine
    case dev

    var id: String { rawValue }

    /// 条子上显示的文字。**只有文字，没有图标** —— 相机那条也没有图标，
    /// 图标会让 9 档挤成一条图标墙，反而认不出哪个是哪个。
    var title: String {
        switch self {
        case .now: return "现在"
        case .vehicle: return "车辆"
        case .health: return "健康"
        case .battery: return "电池"
        case .control: return "车控"
        case .trips: return "出行"
        case .service: return "保养"
        case .mine: return "我的"
        case .dev: return "诊断"
        }
    }

    /// 这一档对应的可 push 深潜页；`.now` 没有独立页面（它就是地图本身）。
    var deeplink: Deeplink? {
        switch self {
        case .now: return nil
        case .vehicle: return .vehicle
        case .health: return .health
        case .battery: return .battery
        case .control: return .control
        case .trips: return .trips
        case .service: return .service
        case .mine: return .mine
        case .dev: return .dev
        }
    }

    /// 由深链反查档位。
    ///
    /// 它是「去某件事」这个动作的**唯一翻译层**：全 App 其他地方（搜索、
    /// 卡片里的快捷入口、「我的」里的行）只要想「去看车辆」，写出的都是一个
    /// `Deeplink`，而这里决定它该不该换成拨模式条。
    ///
    /// 为什么不让它们直接 push 一个页面：那样同一个功能就会有两种存在方式
    /// ——卡片里一份、push 出来一份，各有各的返回行为。那就是「缝合怪」。
    init?(link: Deeplink) {
        guard let hit = Self.allCases.first(where: { $0.deeplink == link }) else { return nil }
        self = hit
    }

    /// 记住上次停在哪一档：地图主屏的「当前位置」应当被记住，
    /// 每次冷启动都跳回第一档等于让用户每天重新选一次。
    static let storageKey = "carkeeper_home_mode"

    /// 供 `DSSwipeStrip` 用的档位表
    static var stripItems: [DSSwipeStrip.Item] {
        allCases.map { DSSwipeStrip.Item(id: $0.rawValue, title: $0.title) }
    }
}
