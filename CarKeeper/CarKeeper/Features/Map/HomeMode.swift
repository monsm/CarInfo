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
//  档内怎么分：车辆与「我的」这两档用分段控件（`HomeSub`），深链落到哪一段由
//  `destination(for:)` 决定 —— 搜索里点「健康」不该落在「档案」上。
//  注：分段控件与那一叠卡表都住在页面视图**内部**（`VehicleView` / `MineView`），
//  没有外壳 —— 分段的**状态**（车辆照片、保养记录…）在页面里，卡表就必须在同一个视图里。
//  2026-09-23 之前它们是 `VehicleHubView` / `MineHubView`，而外壳拿不到页面实例的
//  状态，只能把卡表当类型成员调 —— 那是编译错，也是「开关点了不动」的来源。
//
//  顺序不是按功能分类排的，也不是按字母 —— 是**地图在正中**：
//    出行 · 充电 · 【现在】 · 车控 · 我的 ·（车辆）
//  地图主屏是默认档（每次上车先看的就是它），它必须停在条子的正中：
//  静止只露三档时，左右各有一个邻居可以往两边拖。
//  两翼按用的频率排：左侧「出行 / 充电」是一天看一两次的，右侧「车控 / 我的」
//  是常按的与收尾的。
//
//  **2026-09-27：`now` 从第 2 个挪到第 3 个（5 档的正中）。** 用户原话：
//  「底部导航『现在』放最中间」+「现在是第二个，放到第三个是不是就是最中间了」——
//  是。而在此之前它并不在正中：档位从 6 收到 5 的那一轮（见下面 `vehicle` 那一段）
//  把「车辆」拿掉之后，条子上剩五档，而「现在」还停在第 2 个 —— 于是
//  静止时它看起来是正的（露三档时它确实在正中），但**条子整条**的重心是偏的：
//  右边有两档、左边只有一档，拖到两端时「现在」离屏幕中轴的距离两边不等。
//  这一次只动顺序，不动任何一档的内容：`stripItems` 是 `allCases` 去掉车辆，
//  所以把 case 顺序改成「地图在正中」就是这次修改的全部。
//
//  **2026-09-25：车辆从条子上删掉（6 → 5 档）。** 用户原话：「底部导航删除车辆，
//  因为左下角已有入口」—— 那个入口就是底条左臂那枚车钮（它一直是「回到车辆那一档」
//  这一个动作，车牌时代就如此，见 `MapSpineView.bottomBar`）。
//  于是「车辆」是唯一**不在条子上**的档：它的层号（case 下标）排在末尾，
//  而条子报的连续位置仍然直接当层号用（identity）—— 见 `vehicle` 那一段的说明。
enum HomeMode: String, CaseIterable, Identifiable {
    case trips
    /// 充电（含电池读数与趋势）。它原来叫「电池」，可这一页回答的是「现在充得怎么样」，
    /// 电池只是它的一个读数域。
    case charge
    /// 车现在在哪、什么状态 —— 也就是地图主屏本来的那张纸（含四个地图图层）。
    /// **它必须排在条子的正中**：条子的静止形态、默认档、以及「左右各有邻居」
    /// 这三件事都从 case 顺序推出来，写错了不会有任何报错。
    ///
    ///  2026-09-25「车辆」从条子上删掉之后（见下面 `vehicle` 那条），条子只剩五档，
    ///  而它当时排在第 2 个位：静止只露三档，第 2 个位在那三档里确实是正中
    ///（出行 · **现在** · 充电），但整条五档的重心是偏的。
    ///  2026-09-27 用户点名要的是**五档的正中**（「现在是第二个，放到第三个是不是
    ///  就是最中间了」）—— 于是它现在排第 3 个，左右各两档。
    case now
    case control
    case mine
    /// 车辆（档案 / 体检 / 保养）。**它不在条子上**（用户 2026-09-25：「底部导航删除车辆，
    /// 因为左下角已有入口」）：进它的入口是地图底条**左臂那枚车钮**
    ///（`MapSpineView.bottomBar`，那里还有「进来了之后显示什么」的说明）。
    ///
    ///  ⚠️ 它必须排在**最后一个**，这不是审美：叠叠乐的层号就是条子报的连续位置
    ///  （identity，见 `MapSpineView.deckPos`），而 `stripItems` 就是 `allCases` 去掉它 ——
    ///  把它排在中游的话，条子上的第 2 档与叠叠乐的第 2 层就不是同一件事，
    ///  拖动时整叠页面会错一位（而那一种错不会报错，只是看起来「页面换错了」）。
    ///  排在末尾还有一件好处：它的层号恰好等于条子的长度，
    ///  而那正是「条子上每一档都淡到 0」的位置。
    case vehicle

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

    /// 供 `DSSwipeStrip` 用的档位表。
    ///
    /// 「车辆」**不在里面**（用户 2026-09-25：「底部导航删除车辆，因为左下角已有入口」）——
    /// 它是唯一一条不经过条子的路（左臂那枚车钮）。
    /// 它必须**恰好是 `allCases` 去掉最后一个**（而不是自己另写一份顺序）：
    /// 叠叠乐拿条子报的连续位置当层号（identity），两份顺序一旦不一致，
    /// 拖动时整叠页面会错一位 —— 而那一种错不报错，只看起来「页面换错了」。
    static var stripItems: [DSSwipeStrip.Item] {
        allCases.filter { $0 != .vehicle }
            .map { DSSwipeStrip.Item(id: $0.rawValue, title: $0.title) }
    }

    /// 这一档的个性色。
    ///
    /// 取值在令牌里（`TokensPalette.pageAccents`：六个系统色），这里只按下标取 ——
    /// 它一度写成「由主题表给」（二十套主题下自动是二十套配色），
    /// 2026-09-25 主题只剩原生，于是它回到一组定值，而调用点一行没改。
    /// 下标取 **case 顺序**而不是 rawValue：色相跟着在条子上的位置走，
    /// 第几档就应该是第几个色（换名字不会把配色也换掉）。
    ///  注：2026-09-27 那次换序（`now` 挪到正中）因此也换了「现在」的色 ——
    ///  这是这条规则本来的意思（色跟位置走），不是副作用。
    var accent: Color {
        let all = TokensPalette.pageAccents
        let i = Self.allCases.firstIndex(of: self) ?? 0
        return all.indices.contains(i) ? all[i] : TokensPalette.accent
    }

    // =========================================================================
    //  MARK: 壁纸 —— 一张横图分成五段（2026-09-27）
    // =========================================================================
    //
    //  用户原话：「因为壁纸基本都是横向的，所以我们能做成 5 屏显示壁纸连贯的不同位置吗？
    //  （地图不需要可跳过）」
    //
    //  于是那张图不再是「每一屏各自铺一份同样的裁切」，而是**一条可平移的横图**：
    //  五个位置各看它的一段，相邻两段接得上 —— 所以从一档拖到下一档就是一次平移。
    //  地图那一档不参与 —— 它铺自己的瓦片，横图在它下面被盖住。
    //
    //  ⚠️ 2026-09-27 第二轮（用户：「全是颗粒，像素很低」）：可平移的**长度**改变了。
    //  上一版把这条横图铺 5 屏宽（于是要求源图有 5895 像素宽，而免密钥那两个源
    //  最多 3840）—— 颗粒就是那一步买来的。现在平移只吃掉**图自己多出来的宽度**：
    //  铺满一屏所需的最小放大不变，而那一段余量全给五屏分
    //（16:9 的源≈三屏宽、4:3≈两屏、竖图为零）。分辨率那一笔账写在
    //  `MapWallpaperLayer` 的文件头 —— 那里是它的家，因为那是画图那一层的事。
    //
    //  为什么「哪一屏是哪一段」要写在这里、而不是写在那张图的代码里：
    //  它**就是档序**（同一件事的第二个说法会漂）。`wallpaperPosition(_:)` 收的是
    //  条子报出来的那个连续位置（`MapSpineView.deckPos`），于是拖动过程中图是
    //  连续平移的，而不是「松手之后换一张」。

    /// 不在地图上的那几档 —— 壁纸的五个位置就在这几档上（顺序即 `allCases` 顺序）。
    static var wallpaperOrder: [HomeMode] { allCases.filter { $0 != .now } }

    /// 横图上的相对位置：`0` = 最左那一段（第一屏），`1` = 最右那一段（最后一屏）。
    ///
    /// - Parameter index: **条子报出来的连续位置**（= `allCases` 的下标，可以是小数）。
    ///
    /// 相邻两屏之间线性插值；地图那一档没有自己的段，所以它的位置由左右邻居插出来 ——
    /// 那一段永远看不见（地图是铺满的不透明层），但**必须连着**：
    /// 从「现在」往两边拖时，图不能跳一下再走。
    static func wallpaperPosition(_ index: Double) -> Double {
        let screens = wallpaperOrder
        guard screens.count > 1 else { return 0 }
        let last = screens.count - 1
        // 每一屏在条子上的位置（`allCases` 下标）。它们是升序的 —— 换序时若不小心
        // 让「现在」夹在中间，这里会因为 `a > b` 而插出一段反着的位移（图倒着滑）。
        let anchors: [Double] = screens.map { Double(allCases.firstIndex(of: $0) ?? 0) }
        if index <= anchors[0] { return 0 }
        for i in 0..<last where index <= anchors[i + 1] {
            let span = anchors[i + 1] - anchors[i]
            let t = span > 0 ? (index - anchors[i]) / span : 0
            return (Double(i) + t) / Double(last)
        }
        return 1
    }

    /// 这一档在叠叠乐里的**第一张卡**：巨字头。
    ///
    /// 「现在」那一档没有头 —— 那张纸本身就是地图的面板（车名 + 地址 + 状态行），
    /// 再叠一个巨字就是两层标题（见 `HomeModeHead` 的第 ③ 条自约束）。
    var headCards: [StackCard] {
        // 卡头写**这一档的名字**：原型的每页首卡都有一行 `.ct` 标出它是什么
        // （`Trips · 今天` / `Charge · 电池` / `Control · 远控`）。
        // 没有它，首卡就是一行没有出处的巨字。
        self == .now ? [] : [StackCard(id: "head", title: title,
                                       content: AnyView(HomeModeHead(mode: self)))]
    }
}

// =============================================================================
//  HomeSub —— 档内的段落（车辆 / 出行 / 「我的」三档用它）
// =============================================================================
//  它不是导航层级：没有第二层返回按钮、没有 push —— 只是同一张纸上的一段。
//  深链（`carkeeper://health`）落到的是「车辆」这一档的「健康」那一段。
//
//  段落状态住在**页面视图内部**（`@State`，不是持久化的键）：它是一次看法的选择，
//  不是「当前位置」—— 位置那一层是 `HomeMode`（它有 `storageKey`）。
//  换句话说：离开出行页再回来，它应该回到第一段（如同车辆档本来那样）。
enum HomeSub: String, CaseIterable, Identifiable {
    // 车辆档
    case profile
    case health
    case service
    // 出行档
    case journeys
    case events
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
        case .journeys: return "行程"
        case .events: return "事件"
        case .settings: return "设置"
        case .emergency: return "应急"
        case .dev: return "诊断"
        }
    }

    /// 车辆档的三段（顺序即显示顺序）
    static let vehicleTabs: [HomeSub] = [.profile, .health, .service]
    /// 出行档的两段：同一份数据（消息流里的点火 / 熄火配成行程）的两种读法。
    /// 用户 2026-09-25：「出行里面行程卡和消息列表的上下布局改为 tab 页」——
    /// 它们此前是同一叠里上下两张卡，滑到车的事件要越过 30 张地图卡。
    static let tripsTabs: [HomeSub] = [.journeys, .events]
    /// 「我的」档的三段
    static let mineTabs: [HomeSub] = [.settings, .emergency, .dev]
}
