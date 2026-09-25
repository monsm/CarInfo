// =============================================================================
// MapSpineView.swift — 以地图为主屏（落地版）
// =============================================================================
//
// 这是「以地图为核心」那个方向的**真机实现**，不是样品：
//   • 地图是 MapKit 的 `Map`（真瓦片、真坐标、真手势），不是手绘 SVG
//   • 车钉位置来自 location 接口（Lat/Lng），车头朝向来自 Heading —— 都不是猜的
//   • 行程线来自 tripHistory 的起终点；**没有轨迹点就不画轨迹**（照实写"起终点连线"）
//   • 充电曲线与常停热区也都是真数据：功率采样积分成会话，停车史聚成"生活圈"
//   • 「为什么」每一行都由真实字段推出；推不出来就不显示
//
// =============================================================================
// 主框架（2026-09-22 定，取代了 Tab 骨架与顶部图层胶囊条）
// =============================================================================
// 主框架是**两个原生 App 的融合**，不是自创的导航结构：
//
//   Apple Maps —— 一张满屏地图 + 一张贴底的纸（sheet）。地图是唯一的岗位，
//                 页面全从它身上长出来，没有 Tab、没有平行的一等公民。
//   相机 App   —— 换档**不离开取景框**：模式条紧贴在内容的上沿，
//                 每一档只有文字、选中只靠颜色；条子可手拖、松手吸附、中心项放大。
//                 实现见 `Design/DSSwipeStrip.swift`，档位定义见 `HomeMode.swift`。
//
// 模式条是**一级**：`DSSwipeStrip`（`HomeMode`，6 档）= 看哪个功能界面。
// 全站唯一的入口。此前四套入口（Tab 栏 / 顶部图层胶囊 / 右上角索引页 /
// 「我的」磁贴）已收归这一条。
//
// 2026-09-23：**一级「现在」这一档按原型 `design-preview/stack.html` 重排**。
// 原型 `pageNow()` 的全部元素是：`.map` + `.plate{left:20;top:62}` +
// `.float{left:16;bottom:98;gap:12}`（两张卡）+ `.compass` + `.scale`。
// 上一版在这一屏多摆了五样原型没有的东西（顶栏三枚钮、图层选择卡、
// 常驻操作条、光名药丸、回到车浮钮），于是「首页」看起来像一块控制面板。
// 这一轮把它们全部收进**车牌徽标**（原型本来就有的那个位置，点开是菜单），
// 并把二级图层选择从一张卡改成菜单里的一项 —— 图上看的仍然是四个图层，
// 但默认状态与原型逐项对齐。
//
// 2026-09-23（第二轮）：**六页同屏的交叉过渡**。
// 上一版只画当前那一档，过渡是「变暗 + 横移 26pt」—— 那与原型是两回事。
// 原型 `render()` 的过渡是**原地交叉**：`scale(1 − 0.035a)` / `opacity(1 − 1.6a)`，
// `a = |页下标 − 条子连续位置|`，`a ≥ 0.62` 隐藏；六页从装配起就一直在那里。
// 三处真错处都是量出来的：横移是原型明确否掉的做法（档距 65.6pt vs 页宽 390pt）、
// 五页各留着一条空标题的顶栏（把卡片窗压低 44pt，而原型六页都没有顶栏）、
// 条子按安全区底放在离底 60pt（原型 `bottom:26` 是从**屏幕**量的）。
// 与之一起来的改动：地图回到「现在」那一页**里面**（原型 `#page-now` 里的 `.map`），
// 于是换走时它跟着淡出缩小，而不是「别的页浮在一张活地图上」。
//
// 三条架构规则（写错就出问题，不是风格问题）：
//   ① 钉 = 屏幕空间（`Annotation`），面积/轨迹 = 地理空间（`MapPolyline`）。
//   ② 「现在」这一档**没有顶栏**（`.toolbar(.hidden, for: .navigationBar)`）：
//      地图一直画到屏幕最上沿，车牌在安全区下 8pt、浮动两卡贴底 98pt。
//   ② 内容层不透明：模式条与底部纸用 `TokensPalette.surface`，
//      玻璃只允许出现在导航栏 / 弹层 / 底部操作条（这是 v4 就定下的规则；
//      macOS 的那条「Tab 栏」实例随 5 Tab 骨架一起删了 —— 现在没有 Tab 栏）。
//   ③ 地图样式是**系统地图原样**（`.standard`）：没有蒙版、没有自定义车钉。
//      它以前由 `ArtTheme.mapSpec` 决定（二十套艺术方向各一套 MapKit 配置：
//      瓦片压暗 + 色温蒙版 + 三种车钉），随艺术主题一起删掉 —— 那些配置只在
//      对应的方向下出现，方向没了，它们就是一张没人读的表。
//
// 已知缺口（故意不做假）：
//   • 行程没有 GPS 轨迹点（TripRecord 只有 start/end），所以线是**起终点连线**。
//   • 异常没有"发现地点"，只能挂在车当前坐标，文案照实写。
//   • 充电站来自 MKLocalSearch 的实时搜索（按车的位置），不是数据库里的固定列表。
// =============================================================================
import SwiftUI
import MapKit
import CoreLocation

/// 底条上那两枚圆钮的「让位」。
///
/// 展开时**宽度真的收掉**，不是「看不见但还占着 50pt」——后者会把条子压到装不下六档，
/// 于是条子只能压间距，而压间距正是原型明确否掉的那一件事。
/// （原型 `.bottom.open .arm{opacity:0;transform:scale(.86)}`。）
private struct ArmSlot: ViewModifier {
    let open: Bool
    let size: CGFloat

    func body(content: Content) -> some View {
        content
            .frame(width: open ? 0 : size, height: size)
            .opacity(open ? 0 : 1)
            .scaleEffect(open ? 0.86 : 1)
            .clipped()
    }
}

struct MapSpineView: View {
    /// 不是 `private`：`MapSpineReadouts.swift` 里的四格读数要用它取车速与车锁。
    let store = AppStore.shared
    /// 不是 `private`：`MapSpineLayers.swift` 里那几个图层内容要用它换档。
    @EnvironmentObject var nav: NavState
    /// iPad 分栏用（SceneID.detail 的场景声明在 CarKeeperApp.swift）
    @Environment(\.openWindow) private var openWindow
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// 天气实况（光需要云量）：**订阅**它 —— 快照是异步到达的，不订阅这一屏就不会重画。
    @ObservedObject private var weather = WeatherService.shared

    /// 记住上次看的图层（地图主屏的"当前位置"应该被记住，不该每次回到默认）
    // 键名定义在 MapSpineLayer.storageKey（别处把地图开到某一层也用同一个键）
    @AppStorage(MapSpineLayer.storageKey) private var layerRaw: String = MapSpineLayer.now.rawValue
    /// 底部模式条停在哪一档（`HomeMode`）。
    /// 它与 `layerRaw` 是**两个层级**：档位 = 我在看哪个功能界面；
    /// 图层 = 「现在」那一档内部的第二级选择（现在 / 行程 / 停车 / 充电）。
    @AppStorage(HomeMode.storageKey) private var homeModeRaw: String = HomeMode.now.rawValue
    /// 模式条的**连续**位置（3.0 = 停在第四档，2.4 = 拖在第二、三档之间）。
    /// 宿主只用它做内容过渡 —— 条子自己不用它排版。
    /// 初值 `-1` 是**哨兵**：条子的回调要等 `onAppear`，而第一帧已经画了。
    /// 用 0 当初值会让冷启动先闪一帧第一档（「出行」）再到记住的那一档。
    ///
    /// ⚠️ 它只有**一个**写者：条子的 `onPosition`。2026-09-25 之前这里还有第二个
    /// （宿主自己的整行拖动按自己节距算一个位置写进来），两个写者的后果写在
    /// `DSSwipeStrip.RowDrag` 上：条子不跟手、松手后页面停在两页之间。
    @State private var modePosition: Double = -1

    /// 整条底条上那次横拖（`nil` = 手指不在条上）。它只是**转发**给条子：
    /// 条子仍是位置的唯一计算者（跟手、越界阻尼、吸附都在那里，见 `RowDrag`）。
    /// 状态与手势必须住在同一个文件里：Swift 的 `private` 作用域是**文件**，
    /// 把状态拆到另一个文件里的扩展要么看不见它、要么就得把它降级成模块级可见
    ///（2026-09-25 的 CI 就是这么红的）。
    @State private var barRowDrag: DSSwipeStrip.RowDrag?
    /// 底条是否正在展开（手指按在条子上）。
    /// 它只服务一件事：展开时把两侧的两枚圆钮**让出宽度并淡出** ——
    /// 原型 `.bottom.open .arm{opacity:0;transform:scale(.86)}`，
    /// 而“让出宽度”比单单淡出更要紧：条子展开后要 374pt（屏宽 390），
    /// 留给两枚圆钮就只能把间距压扁，而压间距正是原型明确否掉的那一件事。
    @State private var barOpen = false

    /// 镜头。**不是 `private`**：右侧那两枚快速钮（`MapQuickButtons.swift`）里
    /// 「回到车 / 手机的位置」都要把它移过去 —— 而 `private` 的作用域是**文件**，
    /// 另一个文件里的扩展看不见（2026-09-25 那次 CI 红就是同一个原因）。
    @State var camera: MapCameraPosition = .automatic
    @State private var didCenterOnce = false
    /// 不是 `private`：同上，充电那一层的内容在 `MapSpineLayers.swift` 里读它。
    @State var chargers: [MapCharger] = []
    @State private var chargerCenterKey = ""
    @State private var isRefreshing = false
    /// 「此刻的光」表 —— 这一屏的光是怎么算出来的（药丸点开）
    @State private var showSky = false
    /// 时刻滑块：`skyLive` = 看此刻；一旦拖过滑块就变成「看那一刻的光」
    @State private var skyLive = true
    @State private var skyHour: Double = 12

    /// 底部那张卡**拉出来了没有**（默认收起：只有「一横」—— 三个数 + 图层胶囊）。
    /// **不是 `private`**：拉手、拖动与抽屉里的内容都住在 `MapSpineReadouts.swift`
    ///（与读数同一份文件），而 `private` 的作用域是文件 —— 那个文件看不见它。
    /// 同一个诉求这是第三次了，三代的写法与代价记在那个文件的头注里。
    ///
    ///  2026-09-25「给它一点记忆」：`@State` → `@AppStorage`，键是 `drawerKey`
    ///  （一个**设备**键：它是「这台手机上我把这张卡拉出来了没有」，与谁登录无关，
    ///  见 HANDOFF §6 那张分类表）。
    ///  「默认只有一横」没有被推翻：**没人拉过时它仍然是收起的**（默认值 false）；
    ///  用户自己拉出来之后，下次打开地图它还在那儿 —— 那是他上一步的意图。
    ///
    ///  写法照抄隔壁那两行（`MapSpineLayer.storageKey` / `HomeMode.storageKey`）：
    ///  键名只一个出处，`@AppStorage` 里写字面量是这一层唯一被重复过的那种写法。
    @AppStorage(MapSpineView.drawerKey) var drawerOpen = false

    /// 壁纸状态（非地图子页铺的底）。**必须订阅它**：图是异步到达的，
    /// 不订阅的话 `换一张 / 不铺` 要等到下一次换档才生效（body 才重新求值）。
    /// 与 MineView 那行订阅的是同一个单例，两处的更新永远同步。
    @ObservedObject private var wallpaper = WallpaperService.shared

    /// 手机自己的位置（右侧那枚钮的图形 + 后面那条 `onChange`）。
    /// **必须订阅它**，理由与 `weather` / `wallpaper` 同一类：坐标与权限是
    /// `CLLocationManager` **异步**回调送来的，不订阅这一屏就不会重画 ——
    /// 于是「拿到点就把镜头移过去」那条 `onChange` 不会触发，而那枚钮的图形
    ///（`location` → `location.fill`）也不会自己变。两者的实现分别在
    /// `MapQuickButtons.swift` 与下面的 `onChange`。
    @ObservedObject private var phone = PhoneLocation.shared

    /// 算光用的时刻（实时就是现在）
    var skyDate: Date {
        SkyLight.date(hour: skyLive ? nil : Int(skyHour.rounded()), from: Date())
    }

    /// 镜头距离（米）—— 街区尺度上看自己的车。**不是 `private`**：
    /// `MapQuickButtons.swift` 里把镜头移到手机时要用同一个数 ——
    /// 两处各写一个数就是「同一个几何有两个出处」。
    let cameraDistance: Double = 1_400

    /// 系统那两件仪器（罗盘 / 比例尺）挂在地图上的那条线。
    ///
    /// 2026-09-25 第十一轮（用户：「**我要的是系统罗盘和系统比例尺**，只是他们被时间
    /// 压住了，往下调整下」）：`MapCompass` / `MapScaleView` 可以当**独立视图**用
    ///（`Map(scope:)` + `MapCompass(scope:)` + `.mapScope(_:)`，Apple 文档里就是这写法），
    /// 所以它们的位置**由我们给**，不是 MapKit 定死的。
    ///
    /// 上一轮（第 9 条）的判断在这里被推翻：当时认定「系统控件搬不动」（位置由 MapKit 定），
    /// 于是自己画了一枚罗盘、又自己量了一把尺子 —— 代价是 `MapReader` / `MapProxy.convert`
    /// 一整套测距、两个 `@State` 加一条**每帧回调**（`onMapCameraChange` 喂镜头朝向、
    /// 中心、距离）。那些全都在为躲一个**不存在**的限制服务，这一轮一起删了。
    /// **不是 `private`**：罗盘住在 `MapQuickButtons.swift`，而 `private` 的作用域是文件。
    @Namespace var mapScope
    /// 屏幕顶到这一层的顶 = 系统安全区那一段（见 `body` 末尾那个量探针）。
    /// 它喂给五张子页的滚动内衬（`stackTopInset`）。
    @State private var topSafeGap: CGFloat = 0
    /// **不是 `private`**：抽屉的正文（`MapNowCard.swift`）要按它分发三个图层各自的内容 ——
    /// 而 `private` 的作用域是**文件**。与 `store` / `camera` / `layerMenu` / `skyDate` 同一条。
    var layer: MapSpineLayer { MapSpineLayer(rawValue: layerRaw) ?? .now }
    private var homeMode: HomeMode { HomeMode(rawValue: homeModeRaw) ?? .now }

    /// 条子的连续位置。哨兵（-1）时按记住的那一档画 —— 见 `modePosition` 的说明。
    private var deckPos: Double {
        modePosition >= 0 ? modePosition : Double(modeIndex)
    }

    /// 当前档在 `HomeMode.allCases` 里的下标 = 页面的层号。
    private var modeIndex: Int {
        HomeMode.allCases.firstIndex(of: homeMode) ?? 0
    }

    /// 第 i 层离当前档多远：`0` = 正在看，`1` = 隔一整档 —— 原型 `render()` 里的 `a`。
    private func fade(_ i: Int) -> Double {
        min(1, abs(Double(i) - deckPos))
    }

    /// 数据在 main actor 上组装（AppStore 是 @MainActor @Observable）。
    @MainActor private var data: MapSpineData { MapSpineData.build() }

    /// 抽屉开合那一个键（`@AppStorage` 要常量，不能就地写字面量）。
    /// 一个**设备**键：它是「这台手机上我把这张卡拉出来了没有」，与谁登录、哪辆车无关
    ///（HANDOFF §6 那张分类表）。写法照抄隔壁那两行（`MapSpineLayer.storageKey` 等）：
    /// 键名只有一个出处。
    static let drawerKey = "carkeeper_map_drawer"

    /// 底条占掉的纵向空间：26（离底）+ **54（条高）** + 14（呼吸位）= 94。
    /// **同一个数在原型里是 `.stack{bottom:86px}`** —— 页面内容的窗口正好停在条子上沿。
    /// 真机上它从**安全区底**算起（安全区之上再留 26），所以刘海屏与旧机型都是同一个观感。
    /// 2026-09-25：条高 46 → 54（用户「滑动区变高」，见 `DSSwipeStrip.barHeight`），
    /// 所以这里跟着从 86 涨到 94 —— **它是派生量，不是另一个决定**。
    private static let barTotal: CGFloat = 94
    /// 底条离底多远（原型 `.bottom{bottom:26px}`）
    private static let barGap: CGFloat = 26
    /// 两侧圆钮的直径（原型 `.arm{width:calc(var(--H) + 4px)}`）——
    /// 条高从 46 抬到 54（2026-09-25），圆钮按原型那条关系一起走到 58。
    private static let armSize: CGFloat = 58

    /// 左钮 / 模式条 / 右钮之间的中缝。
    ///
    /// 2026-09-25 材质审核：这个 9 原来只在两处出现 —— `HStack(spacing:)` 与
    /// `DSSwipeStrip` 头注里那句「两侧圆钮各占 50 + 中缝 9×2」。现在它有个名字，
    /// 因为**玻璃层也要用它**（见 `bottomBar` 的 `dsGlassLayer`）：中缝既是视觉上的
    /// 「它们是一组」，也是系统判定「多近才算挨着」的距离。两处用同一个值，
    /// 不能一处改了另一处还在按 9 算宽度。
    ///
    /// ⚠️ 2026-09-25 的 CI：`type 'MapSpineView' has no member 'barSeam'`。
    /// 上面这段注一直在这儿（它与两个使用点都来自 `444ec88`），而**声明那一行不见了** ——
    /// 同一笔编辑里丢的，于是文件里留下「注释在、值不在」。
    ///
    /// 为什么三条现成的判据都没拦住（两道各有一个原因，写在这里免得下一个人以为
    /// 它们管得住）：
    ///   · `delguard.py`（专治「声明没了、使用还在」）要求**旧版本里声明过**这个名字 ——
    ///     而 `barSeam` **从未在任何提交里被声明过**，判据 ① 不成立，它只能绿。
    ///     它管的是「这次编辑删掉了什么」，管不了「这次编辑以为加上了什么」。
    ///   · `scan.py` 的「项目类型的未知成员」看不见 `Self.barSeam`：把 `Self` 当作一个
    ///     类型名之后，那个名字不在类型表里，判据直接跳过。已加固（同一轮）。
    private static let barSeam: CGFloat = 9
    /// 底条两侧留白（原型 `.bottom{padding:0 8px}`）
    private static let barPad: CGFloat = 8
    /// 右臂交出的一条车控请求。它由 `controlCommandFlow` 那道门消费 ——
    /// 验证与温度都在门里，本页只负责把请求交出去（与车控档同一个 modifier）。
    @State private var quickRequest: ControlRequest?
    /// 这一行能分到多宽（由 `bottomBar` 的背景量出；0 = 还没量到）。
    ///
    /// 它是**条子几何的唯一来源**：`DSSwipeStrip` 自己量不到这个数 ——
    /// 它量到的是「两侧圆钮分剩的那一份」（390 的屏上只有 256）。
    @State private var containerWidth: CGFloat = 0
    /// 条子的可用宽度 = 整行宽度 − 两侧留白（兜底 374 = 390 屏宽 − 16）
    private var barRowWidth: CGFloat {
        containerWidth > 0 ? max(160, containerWidth - 2 * Self.barPad) : 374
    }

    var body: some View {
        // `MapSpineData.build()` 在这一次求值里**只跑一次**（2026-09-25 性能轮）。
        //
        // 改之前它在一个 `let d = data` 里、又在 `.onChange` 的条件里、还在 `nowLayer` 里
        // 各算一遍 —— 一次求值建**三套**派生数据。地图页在车动起来时每 2 秒求值一次
        //（节律见 `RefreshLoop.Cadence.moving`），而 `build()` 里含行程映射、停车点映射、
        //胎压、异常点与两处聚类 —— 三份就是三倍。现在：
        //   · 这张 sheet 的那份挪进**闭包**（只有真弹出来时才建）；
        //   · `.onChange` 盯的是车自己的读数，不再要派生数据；
        //   · 剩下的唯一一处是 `nowLayer()`（它本来就是地图那一页的内容，必须有）。
        // 代价为零：三处读的都是同一份状态，不再有“哪一份才算数”的问题 ——
        // 因为它们本来就是同一个函数的返回值。
        ZStack(alignment: .bottom) {
            // ⓪ 六层页面同屏（原型 `.pages > .page{inset:0}` × 6）。
            pageDeck()

            // ① 顶：底条 = 左臂（车牌）｜模式条｜右臂（搜索），贴底 26。
            //    原型 `.bottom{position:absolute;left:0;right:0;bottom:26;gap:9;
            //    height:calc(var(--H) + 14px)}`：模式条就长在**最底**，
            //    内容从它上面长上去 —— 相机就是这么摆的。
            bottomBar

            // ② 顶：Toast 浮层 —— 抬到条子**之上**。
            //    它原来挂在外壳（`MapShellView`）的 `.bottom` 上（那是屏幕底），
            //    而模式条就长在那里，于是「电量低于 20%」正好压住底部导航
            //（用户 2026-09-25 的第 2 条）。抬多高只有这一处答得出：条子自己占
            //    `barTotal`（26 + 54 + 14），上面再留一格呼吸位。
            //    `.id(t.text)` 而不是 `.id(UUID())`（外壳那一版是后者）：
            //    后者会让**每一次 body 求值**都换一个新身份，而拖模式条时每帧都在求值。
            if let t = nav.currentToast {
                ToastView(text: t.text, icon: t.icon)
                    .padding(.bottom, Self.barTotal + TokensSpacing.snug)
                    .id(t.text)
            }
        }
        // 底条离底 26、页面窗到「屏底 − 86」：原型的这两个数都是从**屏幕**量的
        // （`.bottom{bottom:26}` / `.stack{bottom:86}`）。安全区底那 34pt 若不排除，
        // 条子会凭空抬高一截 —— 与原型差出一个手指的宽度。
        .ignoresSafeArea(edges: .bottom)
        // 量「屏幕顶到这一层的顶」= 系统安全区那一段（灵动岛机型 59、涛海 47、老机型 20）。
        // 它只服务一件事：交给五张子页当**滚动内容的顶部内衬**（`stackTopInset`），
        // 让卡片从时钟下面连续滑过、而静止时第一张卡仍让开状态栏。
        // 拿 `frame(in: .global)` 而不是 `safeAreaInsets`：前者是「它到底在屏幕上的哪儿」
        //（就是我们要的那个数），后者在已被父层让开的视图里会读到 0。
        .background {
            GeometryReader { g in
                Color.clear
                    .onAppear { topSafeGap = g.frame(in: .global).minY }
                    .onChange(of: g.frame(in: .global).minY) { _, y in topSafeGap = y }
            }
        }
        .environment(\.stackTopInset, topSafeGap + TokensSpacing.md)
        // Toast 的出现 / 消失（它原来跟在外壳上，随浮层一起搬过来）。
        .animation(.easeOut(duration: 0.2), value: nav.currentToast?.text)
        // 暗层全删（用户 2026-09-24：「每个子界面的暗层都去掉」）：
        // 根上**不再铺** `TokensPalette.canvas` —— 让 AppCanvas（画布+实时光）透出来。
        // 五张子页各自铺**壁纸图**（见 `MapWallpaperLayer`）；地图那一档铺自己的瓦片。
        // 之前那层的理由是「换档过渡时底下不能透出地图」—— 现在的解法：
        // 五张子页各自铺图（铺图的下面就是 AppCanvas，不是地图），
        // 所以过渡期间透出的不再是地图的灰黑，而是壁纸/画布。
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        // 原型里**六页都没有顶栏**：地图画到屏幕最上沿，其余五页的第一张卡是巨字头，
        // 状态栏之下没有任何栏。留一条空标题的栏不只是多一条 chrome ——
        // 它把卡片窗整体压低 44pt，于是「第一张卡落在哪」与原型差出一个卡头。
        // 原来靠它挂着的两件事搬进了页面自己：车控的语音播报在那一叠里（另一张卡），
        // 保养的「添加记录」在那一张卡里（一个动作），见各自文件。
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showSky) {
            // 「光」表已拆成独立文件（`MapSkySheet.swift`，2026-09-25）：
            // 宿主只给它这些 —— 当前数据、两个滑块状态、开合绑定、重取天气那一个动作。
            MapSkySheet(data: MapSpineData.build(),
                        skyHour: $skyHour,
                        skyLive: $skyLive,
                        isOpen: $showSky,
                        retryWeather: { await refreshWeatherIfNeeded(force: true) })
        }
        // 右臂那几条会改车状态的快捷指令走**唯一那道门**：温度 → 生物识别 → 控车码。
        // 它挂在“现在”这一档（右臂就在这里），sheet 盖在地图上 ——
        // 不把用户推到车控页（一条锁车指令不该让人离开地图）。
        .controlCommandFlow($quickRequest)
        .task {
            // 地图出现之后的这几步是启动轨迹里原本的盲区（见 StartupJournal 头注）：
            // 用户报的「地图出来以后几秒就退」正落在这里，所以每一步都留个路标。
            StartupJournal.shared.mark("地图页开始取数")
            // 围栏（见 LaunchFence）：地图页自己的三条取数（车况 / 充电桩 / 天气）。
            if LaunchFence.mapFetches {
                await refresh()
                StartupJournal.shared.mark("地图页取数结束")
                centerOnCar(force: true)
                if layer == .charge { await searchChargersIfNeeded() }
                await refreshWeatherIfNeeded()
            }
            // 背景图的那一次取数（子页铺底用）。**故意留在围栏之外**：它只往
            // Documents 落一张 JPEG，不碰车况/地图状态 —— 与那一轮二分定位的
            // 「启动就退」不是同一类东西。已取过当天那张时它不发网络请求（同一天缓存）。
            await wallpaper.refreshIfStale()
            StartupJournal.shared.mark("地图页就绪")
        }
        .onChange(of: layer) { _, new in
            TokensHaptic.select()
            // 选了一层就把抽屉拉出来：**选层这个动作本身就是「我要看这一层的数据」**，
            // 而收起态里只有那三个数 —— 不拉出来会看起来像「换了层却什么都没发生」。
            setDrawer(open: true)
            if LaunchFence.mapFetches && new == .charge { Task { await searchChargersIfNeeded() } }
        }
        //  这里原本有两条**为自量比例尺服务**的回调：`.onChange(of: camera) { flashScale() }`
        //  与 `.onMapCameraChange(frequency: .continuous) { … }`（后者喂镜头朝向 / 中心 /
        //  距离给**我们自己画的罗盘与尺子**，并带一个 6% 的门槛防止一次拖动留下上百个
        //  待执行的 2 秒计时器）。第十一轮两件仪器都换成系统的，于是这两条连同
        //  `cameraHeading` / `cameraCenter` / `cameraDistanceNow` / `lastScaleDistance`
        //  四个 `@State` 一起删掉：系统罗盘自己知道朝向，系统尺子自己知道地图在动。
        //  （它也是这一屏唯一一条**每帧都来**的回调 —— 删掉它顺带把第七轮性能那一轮
        //   记下的一个隐忧消掉了。）
        // 盯的是**车自己的读数**（同一个 `caches["location"]`），不是派生数据里的那份：
        // 这一条原来写 `.onChange(of: d.carCoordinate?.latitude)`，而 `.onChange` 的条件
        // 每次求值都要算一次 —— 于是它单独又建了一整份派生数据（见 `body` 上的说明）。
        .onChange(of: store.currentLocation?.coordinate.latitude) { _, _ in centerOnCar(force: false) }
        .onChange(of: store.mapFocus) { _, f in if let f { focusOn(f) } }
        .onReceive(NotificationCenter.default.publisher(for: .locationUpdated)) { _ in
            centerOnCar(force: false)
        }
        // 手机的位置取回来了 → 把镜头移过去（按了那枚钮、答应过权限之后自动完成）。
        // 少了这一步，「按一下 → 弹权限 → 答应」之后那一按看起来什么也没发生
        //（点还在路上）—— 而用户已经答应过一次了，不该再按第二次。
        // 镜头那一动只有一处实现（`MapQuickButtons.swift` 的 `fly(to:)`）。        // 盯的是**画在图上用的那个坐标**（`mapCoordinate` = 换算成 GCJ-02），
            // 不是 CoreLocation 的原始读数：镜头要和蓝点落在同一个点上（见 `ChinaDatum`）。
            .onChange(of: PhoneLocation.shared.mapCoordinate?.latitude) { _, _ in
                fly(to: PhoneLocation.shared.mapCoordinate)
            }
    }

    /// 取一次天气（TTL 与「车没走远」两道护栏都在服务里）。
    /// 手动（下拉刷新 / 「光」表里的按钮）用 `force: true` 绕过 TTL。
    @MainActor
    private func refreshWeatherIfNeeded(force: Bool = false) async {
        guard let c = data.carCoordinate else { return }
        await WeatherService.shared.refreshIfNeeded(coordinate: c, force: force)
    }

    // =========================================================================
    // MARK: 地图
    // =========================================================================

    @ViewBuilder
    private func mapCanvas(_ d: MapSpineData) -> some View {
        //  系统那两件仪器（比例尺 / 罗盘）**不挂在这一层**：
        //  地图 `ignoresSafeArea(.top)`，任何挂在它身上的东西都会跟着画到灵动岛底下
        //（第 9 条那枚「自动出现」的罗盘就落在那里 —— 状态栏里，压住电池）。
        //  两件都挂在下一层（`nowLayer`）—— 那里还在安全区里，所以对齐到“顶”就是
        //  **灵动岛下沿**（用户 2026-09-25 第 2 条 + 第十一轮「往下调整下」）。
        Map(position: $camera, scope: mapScope) {
            mapContent(d)
        }
        .mapStyle(.standard)
        // ── 系统控件：位置由**我们**给，不是 MapKit 定死的 ─────────────────────
        //
        // 第十一轮：这两行把**自动摆放的那一套**关掉 —— 两件仪器改由我们在
        // `nowLayer` 那一层亲手摆（`MapCompass(scope:)` / `MapScaleView(anchorEdge:scope:)`，
        // 见那两个调用点）。
        //
        // 为什么必须显式关：第 9 条那一轮把 `.mapControls { MapCompass() }` 整个撤掉，
        // 而**撤掉不等于关掉** —— MapKit 的默认控件集里本来就有罗盘，它在地图**转过之后**
        // 自动出现（Apple 原文：*the default mapControls configuration shows a compass
        // when the map is rotated*）。地图又是 `ignoresSafeArea(edges: .top)`，
        // 于是那枚自动罗盘贴在**地图自己的角**上 —— 正好是状态栏里，压住电池
        //（用户 2026-09-25 的截图：右上角一枚带「西」字的，右列一枚我们画的 —— 两枚罗盘）。
        //
    // 两行都写在 Map **自己**身上（不是外层容器）：`mapControlVisibility` 是一个
    // 向下传的环境值，挂在容器上会把我们摆在别处的那两件也一起隐藏掉。
    //
    // ⚠️ 真机上要盯一眼：如果角落里那枚自动罗盘还在，说明空 builder 没压住默认控件集 ——
    // 那时的下一手是 UIKit 的 `MKMapView.appearance().showsCompass = false`
    //（SwiftUI 的 `Map` 底下就是 MKMapView，这颗开关一定关得掉；代价是全局影响，
    // 而这个 App 只有这一张地图，所以就放在那一手里）。
    .mapControls { }
    .mapControlVisibility(.hidden)
        // 这里原本还有两层浮层：**色温蒙版**（系统瓦片改不了色，只能盖一层 ——
        // 二十套艺术方向各有一个蒙版色与不透明度）与**光层**（光池 / 暗角 / 颗粒，
        // 位置由太阳方位角算）。两层都只在艺术方向下出现，随主题一起删掉（2026-09-25）。
        // 光引擎本身留着：下面车钉的 `lamp` 就是它算的。
        .ignoresSafeArea(edges: .top)
        .accessibilityLabel(Text("地图，车在这张图上"))
    }

    //  这里原本是 `mapPlaceLabel`（图上的大字地名：衬线 29pt、随艺术方向斜排，
    //  挂在左上角、安全区下 108pt）。2026-09-25 删掉 —— 用户第 2 条点名要删它
    //（「地图页最上面的位置没删」）。
    //
    //  删它拿掉的是什么，写在明面上：那一行是**图上的地名**唯一的存在处。
    //  删了之后「车在哪」只剩抽屉里那句地址（`d.address`）。
    //  这不是损失的抵消，而是重复的消除：地图自己就在画地名（听涛观海），
    //  而卡里的地址说的是同一个地方 —— 图上再压一行大字是同一个事实的第三种说法
    //（用户 2026-09-24：「地图页的信息有很多是重复的」。）
    //  它读的那个字段（`MapSpineData.placeLabel` = 地址截到 7 个字）**同一天一起删了**：
    //  删完就没有读者了。这一步只能靠人 grep —— `scan/orphans.py` 只盖系统类型的
    //  扩展成员，看不到项目自己的计算属性（那是它明说的盲区）。

    //  `mapContent` / `tripLines` / `rangeCircle` / `hotspotCircles` / `holdPins` /
    //  `chargerClusters` / `chargerPins` / `issuePins`（「地图上画什么」那一段）
    //  2026-09-25 搬进 `Map/MapSpineAnnotations.swift` —— 同一个阈值的第三次：
    //  本文件这一轮又到 1207 行，越过了 `lintcfg.py` 的 1200 阈值。
    //  按那个阈值的用法是把东西搬出去（不是加排除清单、也不是抬阈值到刚够）——
    //  而搬的这一块是**一件独立的事**：图上那几个东西怎么画（车钉 / 行程线 /
    //  续航圈 / 热区 / 停车点 / 充电桩 / 异常点），与镜头、图层、手势、六页同屏
    //  互不相干。界面一字未改。
    //  连带 `skyDate` 从 `private` 放开（搬出去的那一段要按此刻的光给车钉的灯取数），
    //  理由与 `layer` 那次相同（见下面那段说明）。

    // =========================================================================
    // MARK: 车牌徽标上的那颗状态点
    // =========================================================================

    /// 「在动 / 停了 / 掉线了」那颗点。它是原型 `.plate .st i` 的展开 ——
    /// 车牌徽标是它唯一的使用者（`.st{display:flex;gap:6px}`）。
    private func statusDot(_ online: OnlineState) -> some View {
        Circle()
            .fill(color(for: online.cls))
            .frame(width: 6, height: 6)
    }

    // =========================================================================
    // MARK: 底条（两臂 + 模式条）
    // =========================================================================

    /// 相机 App 的那一行：左臂（车牌）｜模式条｜右臂（快捷车控）。
    ///
    /// 为什么两臂必须在这里：原型那条子**不是**孤零零一根——两边各有一枚玻璃圆钮，
    /// 左边是车、右边是动作。它让「模式条」看起来是相机的那排控件，而不是一根付出代价的浮条。
    private var bottomBar: some View {
        // 展开时中缝归零：条子展开后要占满整行（374），两侧各留 9 的中缝就装不下，
        // 而「压间距」正是原型明确否掉的那一件事（同 `ArmSlot` 的说明）。
        HStack(spacing: barOpen ? 0 : Self.barSeam) {
            arm(text: plateShort) { nav.openMode(.vehicle) }
                .accessibilityLabel(Text("车辆"))

            DSSwipeStrip(items: HomeMode.stripItems,
                         selectedID: $homeModeRaw,
                         // 条子的几何只用「这一行有多宽」这一个输入 ——
                         // 它自己量到的是两侧圆钮分剩的那份（见 `barRowWidth`）。
                         availableWidth: barRowWidth,
                         // 两个闭包都写显式标签：尾随闭包在两个函数参数之间靠扫描规则匹配，
                         // 读的人得翻定义才知道 `{ pos in }` 落在哪个参数上 —— 这正是
                         // `2f088df` 那次 CI 红掉的形态（当时 onExpand 还不存在）。
                         onPosition: { pos in
                             modePosition = pos
                         },
                         onExpand: { open in
                             withAnimation(TokensMotion.fade) { barOpen = open }
                         },
                         // 整条上的横拖（含条子上下那圈空白带）。
                         rowDrag: barRowDrag)

            quickArm
        }
        .padding(.horizontal, Self.barPad)
        .padding(.bottom, Self.barGap)
        .frame(maxWidth: .infinity)
        // 三块玻璃（左钮 / 模式条 / 右钮）是**同一层**里的三个形状：交给
        // `GlassEffectContainer`（见 `DSGlass.swift`），它们的边缘才会互相折射、
        // 出现/消失时才变形接上。间距取中缝那 9 —— 那正是它们看起来「挨着」的距离。
        .dsGlassLayer(spacing: Self.barSeam)
        // 整条（含离底那 26pt 的空白带）都算**滑动区**（用户 2026-09-25：
        // 「滑动区变高」）。少了这一条，手指落在条子上下那圈空白上没有任何反应 ——
        // 而这一圈恰好是拇指自然停放的位置。它不改变任何画出来的东西：
        // `contentShape` 只管命中测试。
        .contentShape(Rectangle())
        // 跟手手势挂整条底条（用户 2026-09-24：「不跟手」）：手指按在**整条**上
        //（不只是胶囊条上）就能拖。挂在容器上（而不是 `DSSwipeStrip` 内部）是因为
        // 两侧圆钮是 `Button`，挂条子内部的 `highPriorityGesture` 会被圆钮的 tap 吃掉。
        // 用 `simultaneousGesture` 让条子自己的拖拽与两侧的 tap 同时生效：
        // 位移 < 8pt = 点按（圆钮 / 条子），位移 > 8pt = 拖（条子展开跟手）。
        .simultaneousGesture(bottomBarDrag)
        // 量这一行（未加留白的宽度）—— 条子的可用宽度从这里来。
        // 用背景量而不是用 GeometryReader 包住整行：背景不参与布局，
        // 所以量宽度不会反过来改变底条的位置（那正是条子上一次的错法）。
        .background {
            GeometryReader { g in
                Color.clear
                    .onAppear { containerWidth = g.size.width }
                    .onChange(of: g.size.width) { _, w in containerWidth = w }
            }
        }
    }

    /// 一枚圆钮（有行为的那两枚用它）。
    /// 底条整行的横向拖（用户 2026-09-24：「不跟手」→ 手指按在条子**任意位置**
    /// 都能拖，不只是胶囊上）。
    ///
    /// 它**只转发**：把「手指的横向增量 + 系统的预测落点」交给条子（`RowDrag`），
    /// 由条子自己改位置、自己吸附、自己写回档位。
    ///
    /// 上一版是在这里自己算档位（按 `barRowWidth / 档数` 当节距写 `modePosition`），
    /// 两个后果都真实存在过，也都在 `DSSwipeStrip.RowDrag` 里写明了：
    ///   · 手指按在条子上下的空白带里拖时，**条子一动不动**（`c` 没人碰），
    ///     动的只有页面 —— 而那条空白带正是拇指自然停放的位置；
    ///   · 松手时没有谁写回 `homeModeRaw`，于是几页停在半透明相叠的状态，
    ///     下一次碰条子才归位（那 26pt 空白带被上一版显式算作「滑动区」，
    ///     所以这不是一条够不着的路）。
    ///
    /// 为什么用 `simultaneousGesture` 而不是 `highPriorityGesture`：两侧圆钮是 `Button`，
    /// 用 `highPriority` 会把圆钮的 tap 也吃掉（点不动了）。`simultaneous` 让两件事并存：
    /// 轻点（位移 < 8pt）= 圆钮的 tap / 条子的点选；横拖（位移 > 8pt）= 条子展开跟手。
    /// 手指落在条子上时，条子自己的手势也在跟（它的 `onChanged` 与这条同时发生）——
    /// 那时条子会把这条转发整个作废（`guard cBase == nil`），两边不打架。
    var bottomBarDrag: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { v in
                // 只有横拖才算（竖向 / 斜向让给地图）。
                guard abs(v.translation.width) > abs(v.translation.height) else { return }
                barRowDrag = DSSwipeStrip.RowDrag(
                    translation: v.translation.width,
                    // `predictedEndTranslation` = 系统按速度算出的「松手后手指将到的地方」。
                    // 它一路传到条子的吸附里 —— 轻甩一下就走过一档，正是 iOS 的手感。
                    predicted: v.predictedEndTranslation.width,
                    moved: abs(v.translation.width) > 8)
            }
            .onEnded { _ in
                // 松手 = 关掉这条通道；吸附发生在「非 nil → nil」这一步里（条子那边）。
                barRowDrag = nil
            }
    }

    private func arm(text: String? = nil, icon: String? = nil,
                     _ run: @escaping () -> Void) -> some View {
        Button {
            TokensHaptic.tap()
            run()
        } label: {
            armLabel(text: text, icon: icon)
        }
        .buttonStyle(.plain)
        .modifier(ArmSlot(open: barOpen, size: Self.armSize))
    }

    /// 圆钮的**外观**（不含行为）：`Menu` 要的是 label 视图，不是 Button。
    private func armLabel(text: String? = nil, icon: String? = nil) -> some View {
        ZStack {
            // 2026-09-25 材质审核：原先这里先铺一层 `glassHighlight` 再挂玻璃 ——
            // 那是自己画的「高光」，而**真正的高光正是玻璃材质自己要产生的东西**：
            // 垫一层假的，系统那层真的就被盖住了。现在只有材质本身，
            // 且可点（`interactive`）—— 按下去的压缩与折射交给系统演。
            Color.clear
                .frame(width: Self.armSize, height: Self.armSize)
                .dsGlass(in: Circle(), interactive: true)
            // 字与图形都走 `TokensInk`：这一枚底是**真玻璃**（上面那行 `dsGlass`），
            // 而它浮在地图/壁纸之上 —— 固定标签色在这里读不出对比度（用户第 10 条）。
            if let text {
                Text(text)
                    .font(TokensTypo.fixed(11, weight: .bold))
                    .foregroundStyle(TokensInk.secondary)
            } else if let icon {
                Image(safeSymbol: icon, fallback: icon)
                    .font(TokensTypo.fixed(17, weight: .medium))
                    .foregroundStyle(TokensInk.primary)
            }
        }
        .frame(width: Self.armSize, height: Self.armSize)
        .contentShape(Circle())
    }

    /// 右臂：**快捷车控**（一键发指令，不离开地图）。
    ///
    /// 它此前是「搜索」——搜索已整体从项目移除（用户 2026-09-23：右下角的搜索功能从项目移除）。
    /// 这一格不该空着，也不该再放一个「去别处」的入口：相机那条右臂本来就是**动作**
    /// （切换镜头），所以这里接的也是动作 —— 而且必须是最高频的那一个。
    /// 指令名取自 `ControlView` 里那几条真指令（同一个 key，不另造一套简写）：
    /// 车控页发什么，这里就发什么。
    private var quickArm: some View {
        Menu {
            ForEach(Self.quickCommands, id: \.key) { c in
                Button {
                    TokensHaptic.tap()
                    if c.changesState {
                        // 会改车状态的那几条 → 交给**唯一那道门**（温度 → 生物识别 → 控车码）。
                        // 用户 2026-09-24：「右下角的控车选了后不用输入密码？不用选温度？」
                        // 之前这里直接调 `store.sendControlCommand`（拿 Keychain 里的旧码就发），
                        // 而车控档要走三步 —— 同一个动作两套强度，安全的那条形同虚设。
                        quickRequest = ControlRequest(key: c.key, name: c.name)
                    } else {
                        Task { await refreshCondition(c) }
                    }
                } label: {
                    Label(c.name, systemImage: c.symbol)
                }
            }
        } label: {
            armLabel(icon: "key.fill")
        }
        .buttonStyle(.plain)
        .modifier(ArmSlot(open: barOpen, size: Self.armSize))
        .accessibilityLabel(Text("快捷车控"))
        .accessibilityHint(Text("锁车、解锁、闪灯、鸣笛、远程寻车（需控车码）、刷新车况"))
    }

    /// 一条快捷指令（key = 真实指令名，与车控页的 `hero` / `moreCommands` 同一套）
    private struct QuickCommand {
        let key: String
        let name: String
        let symbol: String
        /// 会不会改变车的状态。false = 刷新类 —— 它不过那道门，
        /// 因为门的成本是用户手输控车码，而这份成本只该收在「会改变车状态」的动作上。
        var changesState: Bool = true
    }

    private static let quickCommands: [QuickCommand] = [
        QuickCommand(key: "LockDoor", name: "锁车", symbol: "lock.fill"),
        QuickCommand(key: "UnLockDoor", name: "解锁", symbol: "lock.open.fill"),
        QuickCommand(key: "FlashLight", name: "闪灯", symbol: "lightbulb.fill"),
        QuickCommand(key: "Whistle", name: "鸣笛", symbol: "speaker.wave.2.fill"),
        QuickCommand(key: "RemoteSearchCar", name: "远程寻车", symbol: "location.fill"),
        // 它不是「再拉一次接口」：服务端只会回放同一份快照（API-FIELD-MAP §4.9），
        // 想把数字变新只能把车端叫醒 —— 而这是全项目唯一能叫醒车端的那条指令。
        QuickCommand(key: "UpCarCondition", name: "刷新车况", symbol: "arrow.clockwise",
                     changesState: false)
    ]

    /// **刷新车况**：不过那道门。它不改车的任何状态，只是把车端叫醒、让它上报一次。
    /// 成功与失败都照实说一句 —— 遥控制的提示不能只报喜。
    private func refreshCondition(_ c: QuickCommand) async {
        let ok = await store.sendControlCommand(c.key)
        ToastManager.shared.show(ok ? "\(c.name)指令已发送" : "\(c.name)发送失败",
                                         icon: ok ? c.symbol : "exclamationmark.triangle.fill")
    }

    /// 左臂上的字：车牌的前两个字（原型是「鄂A」）。取不到就退回「车」。
    private var plateShort: String {
        let p = VM.vehicleSummary(store.car, store.controlCache)?.plate ?? ""
        return p.isEmpty ? "车" : String(p.prefix(2))
    }

    // =========================================================================
    // MARK: 每一档的页面
    // =========================================================================

    /// 六层同屏（原型 `.pages > .page{inset:0}` × 6）：每一档一直在那里，
    /// 交叉过渡由条子的连续位置直接驱动 —— 过渡是**原地**发生的，不是换页。
    ///
    /// 为什么必须六层同时在：原型装配时把六页全建出来，之后每帧只改
    /// `style.opacity / transform`。只画当前那一页，换档就只能是「旧的变淡、
    /// 新的啪一下出现」，而「从 96.5% 长出来」那点实体感**恰恰在中间那一段**。
    @ViewBuilder
    private func pageDeck() -> some View {
        ZStack {
            // 最底层 = AppCanvas（画布+光）。它**不是暗层**：
            // 它是 App 根上的同一束光（见 `Design/Theme.swift` 的 AppCanvas），
            // 换主题/换光方向都跟着 AppCanvas 走，不会自己又写一套。
            // 之前这里铺过 `TokensPalette.canvas`（用户 2026-09-24：「其他页面的暗层也删除」）
            // 已删 —— 现在过渡期间透出的是画布+光（AppCanvas），不是「上一页的鬼影」。
            ForEach(HomeMode.allCases.indices, id: \.self) { i in
                let a = fade(i)
                // 围栏（见 LaunchFence）：六页同屏是启动时最大的一笔开销 ——
                // 关掉时只建当前那一档，其余五档连 body 都不跑（也就没有它们的取数）。
                if LaunchFence.sixPageDeck || i == modeIndex {
                    pageBody(HomeMode.allCases[i])
                        // 原型 render()：`scale(1 − a*0.035)` —— 进来的从 96.5% 长出。
                        .scaleEffect(1 - a * 0.035)
                        // 原型 render()：`opacity = a ≥ 0.62 ? 0 : 1 − 1.6a`
                        //（0.62 正是 `1 − 1.6a` 到 0 的位置，不夹会算出负数）。
                        .opacity(a >= 0.62 ? 0 : 1 - a * 1.6)
                        // 隐掉的层不吃事件、也不给读屏读：视觉上只有一页，
                        // 读屏却读出六页内容，是六层同屏唯一真正的代价，必须自己挡住。
                        .allowsHitTesting(i == modeIndex)
                        .accessibilityHidden(i != modeIndex)
                }
            }
        }
    }

    /// 一层页面。两个形态与原型的两个 `.page` 形态一一对应：
    ///   · 「现在」＝ `.map{inset:0}` + 浮动两卡，**铺满全屏**（地图画到屏幕最上沿）
    ///   · 其余五档＝ `.stack{top:54;bottom:86}`：不透明的一页，卡片窗停在条子上沿
    @ViewBuilder
    private func pageBody(_ mode: HomeMode) -> some View {
        if mode == .now {
            nowLayer()
                // 真机轨迹（2026-09-24 第五轮）里，内存从 49 MB 涨到 1.7 GB 只要四秒，
                // 而那一轮**没有一行说得出当时亮的是哪一屏** —— 六页同屏关掉以后
                // 只建当前那一档，于是「哪一档在建」直接决定了「谁在吃内存」。
                .onAppear { StartupJournal.shared.mark("亮出屏幕：地图") }
                // 地图卡片底下是**瓦片**（连续的画面）→ `.clear`（见 `photoBackdrop`）。
                .environment(\.photoBackdrop, true)
        } else {
            // 子页的顶：**背景铺到屏顶，内容留在安全区里**。
            //
            // 子页的顶 —— 三代写法，每一代的代价都记在这里：
            //
            //  ① `.ignoresSafeArea(edges: .top)`（内容也顶到屏最上沿）：第一张卡的
            //     圆角正好落在状态栏底下（用户 09-25 第 3 条：「连圆角都看不到」）。
            //  ②  `.safeAreaPadding(.top, 44)` 想把它推回来：但那个 44 是个字面量，
            //     而且加的是「子树已经忽略掉的那条安全区」—— 没推回来。
            //  ③  只让**背景**忽略安全区、内容留在安全区里（上一轮的修法）：圆角回来了，
            //     代价是这一叠上沿变成一道**硬裁线**，而且顶上永远横着一条空白带 ——
            //     地图那一档不是这样的（它画到屏幕最上沿）。
            //
            //  现在（用户 09-25 第 2 条：「顶部的时间和信号应该和地图页一样，不要遮盖」）：
            //  **与地图页同一套行为** —— 内容铺到屏顶，所以卡片是从时钟下面连续滑过的，
            //  不再在半空中被裁断；而静止位置由滚动内容自己的顶部内衬保住
            //（`stackTopInset` = 量出来的安全区 + 一格呼吸位）。两条要求因此不再对立：
            //  圆角看得见，且顶上不横着一条空白带。
            //  顶上那一段的可读性交给系统的滚动边缘效果（`ArcStack` 里那一条），
            //  而不是我们自己再加一层压暗（用户 09-24：「全局不要加暗层」）。
            pageContent(mode)
                .padding(.bottom, Self.barTotal)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                // 五张子页的底色 = 壁纸图（相册选的一张本地图，不依赖网络）。
                // 之前这里是 `TokensPalette.canvas`（暗层，用户 2026-09-24 删）；
                // 现在按「其他页面的背景全部设为当前桌面的背景」的要求：iOS 读不到
                // 主屏壁纸（无公开 API），只能从相册选一张本地图铺底（见 WallpaperService）。
                // 没选图时（或点了「不铺」）回落到画布底色（`TokensPalette.canvas`），
                // 观感上和删暗层之前一样 —— 只是从「暗层」变成「App 自己的画布」。
                .background { MapWallpaperLayer(image: wallpaper.image).ignoresSafeArea() }
                // 卡片底下是**什么**如实交下去：铺了照片 → 真；回落到纯色画布 → 假。
                // `GlassCard` 按它选玻璃变体（要的「液态玻璃的美感」在照片上才成立，
                // 压在一块纯色上会让卡片看起来消失）—— 见 `photoBackdrop` 的说明。
                .environment(\.photoBackdrop, wallpaper.image != nil)
                .onAppear { StartupJournal.shared.mark("亮出屏幕：\(mode.title)") }
        }
    }

    /// 「现在」这一档：地图 + 车牌徽标 + 底部浮动两卡。
    ///
    /// 原型 `pageNow()` 的全部元素就是这些：
    ///   `.map` + `.plate{left:20;top:62}` + `.float{left:16;right:16;bottom:98;gap:12}`
    ///   + `.compass`（罗盘）+ `.scale`（比例尺）。
    /// **再多一样就不是那张图了** —— 上一版在这里摆了四样原型没有的东西
    /// （图层选择卡、常驻操作条、光名药丸、回到车浮钮），加上顶栏一共五样，
    /// 于是「首页」看起来像一个控制面板，而不是原型那张地图。
    /// 那几件事现在都在原型本来就有的位置上：**车牌徽标**（点开是菜单）、
    /// 地图自己的罗盘与比例尺。
    @ViewBuilder
    private func nowLayer() -> some View {
        let d = data
        //  `MapReader`（把屏幕上两点交给 `MapProxy.convert` 换成经纬度、从而量出
        //  「一个点等于多少米」）随**自量比例尺**那一步一起删（2026-09-25 第十一轮）：
        //  系统 `MapScaleView` 可以当独立视图挂、位置由这一层给，
        //  所以那整套测距是在躲一个不存在的限制（见 `mapCanvas` 上的说明）。
        ZStack(alignment: .bottom) {
            // 地图是这一页**本身**（原型 `#page-now` 里的 `.map{inset:0}`），
            // 不是衬在六页底下的背景：换走时它跟着淡出、缩小，
            // 而不是「别的页浮在一张活地图上」（那样两页交界处会露出地图）。
            mapCanvas(d)

            // ── 系统的那两件仪器（第十一轮）────────────────────────────────
            // 比例尺（左上）：`MapScaleView(anchorEdge:scope:)`。**显隐由它自己**——
            // Apple 的行为是「地图在动就露、停下就淡出」，与用户第 2 条要的
            // 「2 秒后消失」是同一个节奇，而上一轮为此写了两个 `@State` + 一条每帧回调。
            // 位置由这一层给：这一层还在安全区里，所以对齐到「顶」就是**灵动岛下沿**
            //（用户第 2 条 + 第十一轮：「被时间压住了，往下调整下」）。
            MapScaleView(anchorEdge: .leading, scope: mapScope)
                .padding(.leading, TokensSpacing.md)
                .padding(.top, TokensSpacing.sm)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                // 尺子不是控件（Apple 地图里它也不接点击）：让它把地图的拖动吃掉，
                // 就成了「一块看不见的挡板」。
                .allowsHitTesting(false)

            // 底图之上**没有任何压暗层**（原型这里有 `.maptop` + `.mapvig` 两层，都已删）。
            //
            // 用户 2026-09-24：「全局不要加暗层」+「地图页顶部的信息挪到下面的玻璃卡片」——
            // 这两条是同一件事的两面：`.maptop` 存在的唯一理由是「车牌徽标压在瓦片上要读得出」，
            // 而徽标已经搬进下面那张玻璃卡。理由消失，层就跟着走。
            // 删干净之后地图上不是瓦片的东西只剩两样：**罗盘**与**比例尺**，
            // 两件都是**系统的**（第十一轮起；它们自带底 / 自带阴影，不靠这层压暗）——
            // 而那一行大字地名已按用户 2026-09-25 第 2 条删掉。

            // `.float{left:16;right:16;bottom:98}`：底边离屏底（条子占 `barTotal` + 12 呼吸位）。
            // 这一档**只有一张卡，而且它是一个抽屉**（用户 2026-09-25 第 2 条：
            // 「默认只显示一横，拉出来才是全部」）：收起 = 拉手 + 续航/电量/车速
            // + 图层胶囊；拉出来才是卡的全部内容（地址 / 副行 / 光带 / 其余读数）。
            nowCard(d)
                .padding(.horizontal, TokensSpacing.md)
                .padding(.bottom, Self.barTotal + 12)
                .frame(maxWidth: .infinity, alignment: .leading)

            // 地图右侧那一列（系统罗盘 / 回到车 / 手机的位置）—— 用户 2026-09-25：
            // 「像 ios 地图 app 右侧的图标一样」。它们贴在**右上角**，
            // 不是贴底：底下那张卡与模式条已经占满了（见 `MapQuickButtons`）。
            quickMapButtons(d)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        .mapScope(mapScope)
        // `.plate{left:20;top:62}`：车牌徽标挂在安全区下的左上角（62 ≈ 54 + 8）。
        // 原来这里挂着**车牌徽标**（车牌 + 状态 + 上报时间 + 菜单），压在安全区下 8pt。
        // 它已搬进下面那张玻璃卡的头（用户 2026-09-24：「顶部的信息挪动到下面的玻璃卡片」）：
        // 地图上只留地名与自己的仪表（罗盘 / 比例尺），不再有一行浮字。
        // 菜单也跟着进去了（卡头上的图层胶囊）—— 它是**控件**，不是信息。
    }

    //  这里原本有 `mapDims`：底图上唯一留的一条顶部压暗（原型 `.maptop`，
    //  0.38 → 0，200pt 高）。它的两个先辈（`.mapvig` 四角压暗、根画布上的暗角）
    //  已按「全局不要加暗层」删掉，而它自己服务的那件事 —— 车牌徽标压在瓦片上
    //  读得出来 —— 也随徽标搬进玻璃卡而消失（用户 2026-09-24）。
    //
    //  留着它只有一个后果：整屏顶部被压掉 38% 亮度，而顶上已经没有字了。
    //  （2026-09-25 起比例尺已是我们自己量的，它靠一层与画布同色的阴影读出来 ——
    //   同样是自带、不靠整屏压暗；罗盘仍然是系统控件。）
    /// 卡头上的**图层胶囊**：写着当前在看哪一层，点开是这张地图的那几件事。
    ///
    /// 它原来是屏幕左上角的车牌徽标（车牌 + 状态 + 上报时间的那个控件），
    /// 徽标的信息已拆进卡头（车牌一行、状态与上报时间一行），菜单留在这里。
    /// 菜单里那几件事都是**不常按但必须能到**的：看哪一层（图上四个图层）、
    /// 重取数据、此刻的光、回到车（iPad 上再加一个新车况窗口）。
    /// 收进一个菜单是**结构决定**：它们原来各占一枚 —— 图层一张卡、光一枚药丸、
    /// 回到车一枚浮钮、顶栏三枚（刷新 / 搜索 / 回到车，而且长在**六页每一页**上）。
    /// **不是 `private`**：抽屉的头（`MapSpineReadouts.swift`）要把它摆在拉手那一行的
    /// 右侧 —— 而 `private` 的作用域是**文件**，另一个文件看不见它。
    /// 它与 `store` / `camera` 是同一条：一件事只有一个实现，跨文件时不复制第二份。
    func layerMenu(_ d: MapSpineData) -> some View {
        Menu {
            ForEach(MapSpineLayer.allCases) { l in
                Button {
                    TokensHaptic.select()
                    layerRaw = l.rawValue
                } label: {
                    // 菜单里没有别的选中态可用 —— 当前那一层自己带勾
                    Label(l.title, systemImage: l == layer ? "checkmark.circle.fill" : "circle")
                }
            }
            Divider()
            // 「全局刷新」= **全部 API**（车况 + 消息 + 体检），不是自动那趟的加强版。
            // 用户 2026-09-25：「地图页的全局刷新可以刷新全部 api」—— 所以它走
            // `RefreshLoop.refreshAll()`（`fetchVehicleData`），而不是页内那个轻的 `refresh()`。
            Button {
                TokensHaptic.tap()
                Task { await RefreshLoop.shared.refreshAll() }
            } label: {
                Label("全局刷新", systemImage: "arrow.clockwise")
            }
            Button {
                TokensHaptic.tap()
                showSky = true
            } label: {
                Label(lightTitle(d), systemImage: "sun.max")
            }
            // 「回到车」原来在这里 —— 2026-09-25 搬去地图右侧那枚常驻圆钮
            //（`MapQuickButtons.swift`，用户：「像 ios 地图 app 右侧的图标一样」）。
            // 菜单里不再留一条：同一个动作两个入口就是重复，而「车在哪」是
            // 迷路时第一个问题 —— 它不该藏在一个要打开才知道有的地方。
            if sizeClass == .regular {
                Button {
                    TokensHaptic.tap()
                    openWindow(id: SceneID.detail)
                } label: {
                    Label("新车况窗口", systemImage: "rectangle.on.rectangle")
                }
            }
        } label: {
            // 胶囊：当前图层名 + 上下箭头。它比一只齿轮图标好认 ——
            // 「这张卡在回答哪个问题」就写在上面，而不是变成一个要背的图标。
            HStack(spacing: TokensSpacing.xs) {
                Text(layer.title)
                    .font(TokensTypo.caption)
                    .tracking(TokensTracking.label)
                Image(safeSymbol: "chevron.up.chevron.down", fallback: "chevron.down")
                    .font(TokensTypo.micro)
            }
            .foregroundStyle(TokensInk.secondary)
            .padding(.horizontal, TokensSpacing.snug)
            .padding(.vertical, TokensSpacing.xs)
            // 图层胶囊浮在**地图**上（连续的画面）→ `.overMedia`（`.clear`）：
            // 画面保持可见，只在边缘留一圈折射。可点 → `interactive`。
            .dsGlassCapsule(variant: .overMedia, interactive: true)
            .contentShape(Capsule())
        }
        .accessibilityLabel(Text("图层：\(layer.title)"))
        .accessibilityHint(Text("点开：看哪一层、重取数据、此刻的光、回到车"))
    }

    /// 车牌。取不到就退回车名 —— 车牌空着不是「没有车」，是「还没取到」。
    private func plateText(_ d: MapSpineData) -> String {
        let p = VM.vehicleSummary(store.car, store.controlCache)?.plate ?? ""
        if !p.isEmpty { return p }
        return d.carName.isEmpty ? "车" : d.carName
    }

    /// 菜单里那一项的标题带上此刻的光名（「此刻的光 · 上午」）。
    /// 原来它是一枚压在右上角的药丸 —— 那是原型里没有的一件东西。
    private func lightTitle(_ d: MapSpineData) -> String {
        guard let sky = d.sky(at: skyDate) else { return "此刻的光" }
        return "此刻的光 · \(sky.phase.title)"
    }

    //  `nowCard` / `drawerContent`（「现在」那一张卡：抽屉的两态 + 三个图层各自的正文）
    //  2026-09-25 搬进 `Map/MapNowCard.swift` —— 同一个阈值的第二次：
    //  本文件加完抽屉之后又到 1201 行，越过了 `lintcfg.py` 的 1200 阈值。
    //  按那个阈值的用法是把东西搬出去（不是把文件加进排除清单，也不是把阈值抬到刚够）——
    //  而搬的这一块是**一件独立的事**：「现在」那一张卡长什么样，
    //  与这一屏的镜头、图层、手势、六页同屏互不相干。界面一字未改。
    //  连带 `layer` 从 `private` 放开（另一个文件要按它分发三层内容），理由写在它上面。
    //  搬出去的三份文件：`MapNowCard` / `MapSpineReadouts` / `MapQuickButtons`。

    /// 每一档 = 一个完整的功能界面。
    /// **入口只有一个 switch**：加页面就在 `HomeMode` 里加一档、在这里加一个 case。
    /// 这里是全 App 唯一列全功能界面的地方 —— 再没有第二处“入口清单”可以对不上。
    @ViewBuilder
    private func pageContent(_ mode: HomeMode) -> some View {
        switch mode {
        case .now: EmptyView()              // 「现在」不走这条路：它就是地图那张纸本身
        // 车辆档自带三段（档案 / 健康 / 保养）—— 它们回答的是同一个问题，
        // 所以是同一张纸里的三段，不是条子上的三格。
        // 注意：分段控件与那一叠卡就住在下面这个视图里，没有外壳 ——
        // 分段的**状态**（照片、OTA…）在它内部，卡表就必须在同一个视图里。
        case .vehicle: VehicleView()
        case .charge: ChargeView()
        case .control: ControlView()
        case .trips: TripsEventsView()
        // 「我的」同理：设置 / 应急 / 诊断。
        case .mine: MineView()
        }
    }
    // `wallpaperLayer()` 已搬进 `Map/MapWallpaperLayer.swift`（2026-09-25）：
    // 这个文件涨到 1211 行，越过了 `lintcfg.py` 的 1200 阈值 —— 按那个阈值的用法
    // 是把东西搬出去，不是把文件加进排除清单。搬的是**一件独立的事**（一张铺底的图），
    // 界面一字未改：调用点就是下面那个 `.background { MapWallpaperLayer(...) }`。

    //  这里原本有一条 `tyreRow`：四轮胎压逐轮排在卡里（标签 + kPa + 报警色）。
    //  它把下面四格里的「胎压」说了第二遍 —— 四格里那一格取的是**最低的那一条**
    //  （报警时同样是 error 色），所以挪走它并不丢掉「哪一轮危险」这件事。
    //  逐轮的完整一行在「车辆 → 体检」；首页只做一瞥（用户 2026-09-24：精简重复信息）。


    // =========================================================================
    // MARK: 此刻的光（可复算的那张表）
    // =========================================================================
    //
    //  它是首页那枚药丸搬进车牌菜单之后**唯一**的入口：药丸没了，但「这一屏的光
    //  是怎么算出来的」必须还能被调出来（每一行都是一个可复算的事实）。

    // `skySheet(_:)` 已于 2026-09-25 搬进 `MapSkySheet.swift`：本文件当时 1201 行，越过了
    // `lintcfg.py` 的 1200 阈值 —— 按那个阈值的用法，是把东西拆出去，不是把文件加进排除清单。
    // 界面一字未改（拆的是文件，不是设计）。

    // `cardBackground` 已于 2026-09-25 删除：它是「卡的面」的第三套实现
    // （`DSCard` / `GlassCard` / 它自己）。天空面板现在走 `dsSurface(padding: 0)`，
    // 于是艺术方向下的发丝线不会在这里被漏掉。


    // =========================================================================
    // MARK: 交互与数据
    // =========================================================================

    /// 不是 `private`：同上（三个图层内容都用它写「取不到」那一句）。
    /// 实体已搬到 `MapSkySheet.swift`（`MapNotice`）—— 拆「光」表时它跟着走，
    /// 因为那一支也要用同一句话。这里留一行**转发**：四个图层与评分段那几处调用点
    /// 因此一字不改（拆文件不该顺带改调用点）。
    func emptyNotice(_ text: String) -> some View { MapNotice(text: text) }

    private func color(for cls: String) -> Color {
        switch cls {
        case "ok": return TokensPalette.success
        case "warn": return TokensPalette.warning
        case "bad": return TokensPalette.error
        case "charge": return TokensPalette.info
        default: return TokensPalette.tertiary
        }
    }

    /// 跨面交接的镜头：出行面点一条事件上的「在图上看看」→ 地图移到这里。
    /// 消费后立刻清空 `mapFocus`，否则下一次回到地图会又跳一次。
    @MainActor
    private func focusOn(_ f: AppStore.MapFocus) {
        withAnimation(TokensMotion.value) {
            camera = .camera(MapCamera(centerCoordinate: CLLocationCoordinate2D(latitude: f.lat,
                                                                              longitude: f.lng),
                                       distance: cameraDistance * 1.6,
                                       pitch: 0))
        }
        didCenterOnce = true   // 别让随后的车位置刷新把镜头拉回车上
        ToastManager.shared.show(f.label.isEmpty ? "已移到事件位置" : f.label,
                                 icon: "mappin.and.ellipse")
        store.mapFocus = nil
    }

    /// 把相机移到车上（正北朝上、无俯仰：这是看自己的车，不是飞行视角）。
    @MainActor
    /// **不是 `private`**：右侧那枚「回到车」在 `MapQuickButtons.swift` 里。
    func centerOnCar(force: Bool) {
        guard let c = store.currentLocation?.coordinate else { return }
        if didCenterOnce && !force { return }
        didCenterOnce = true
        withAnimation(TokensMotion.value) {
            camera = .camera(MapCamera(centerCoordinate: c,
                                       distance: cameraDistance,
                                       pitch: 0))
        }
    }

    @MainActor
    private func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        await store.fetchCore()
        isRefreshing = false
    }

    // 这里曾有 `replayEntry()`：地图「充电」层上那个「看功率曲线」的入口，
    // 点开是 `ChargeReplaySheet`。两者都随充电账本删除（2026-09-23）——
    // 它读的「最近一次充电会话」本来就是账本派生出来的东西。
    // 功率曲线本身还在：充电页的「趋势」段画的就是同一份采样。

    /// 按**车的位置**搜附近充电站（搜索中心不再是写死的北京坐标）
    @MainActor
    private func searchChargersIfNeeded(force: Bool = false) async {
        guard let car = store.currentLocation else {
            // 「没有车的位置」不是「搜到 0 个」：两者在界面上都是空的，只有轨迹分得开。
            StartupJournal.shared.mark("充电站搜索：还没有车的位置")
            return
        }
        let key = String(format: "%.4f,%.4f", car.coordinate.latitude, car.coordinate.longitude)
        if !force, key == chargerCenterKey, !chargers.isEmpty { return }
        chargerCenterKey = key
        StartupJournal.shared.mark("充电站搜索开始")

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "充电站"
        request.region = MKCoordinateRegion(center: car.coordinate,
                                            latitudinalMeters: 8000,
                                            longitudinalMeters: 8000)
        let search = MKLocalSearch(request: request)
        // 用 async 重载（SDK 26 起有，返回类型与回调版一致）——
        // 我们本来就在 async 上下文里，少一层完成回调，也少一次绕回主线程的往返。
        guard let response = try? await search.start() else {
            StartupJournal.shared.mark("充电站搜索失败")
            return
        }
        let found: [MapCharger] = response.mapItems.enumerated().map { idx, item in
            MapCharger(
                id: "c\(idx)-\(item.name ?? "")",
                coordinate: item.location.coordinate,
                name: item.name ?? "充电站",
                distanceMeters: item.location.distance(from: car),
                isEVCharger: item.pointOfInterestCategory == .evCharger
            )
        }
        let sorted = found.sorted { $0.distanceMeters < $1.distanceMeters }
        // 不再只取最近 12 个：那是权宜之计（画不全、也说不清为什么是 12）。
        // 取回全部（上限 60 = 一次搜索的实际返回量），由聚合决定画成一个圈还是几个圈。
        chargers = Array(sorted.prefix(60))
        StartupJournal.shared.mark("充电站搜索结束 \(chargers.count) 个")
    }
}

//  这里原本有一个 `private extension Double { func clamped(to:) }`（文件层的小工具）。
//  2026-09-25 删：它唯一的使用点是宿主自己算档位的那段代码（已删，见 `bottomBarDrag`），
//  留下的就是「声明在、没有读者」。它当年留下的那条教训不在这里 —— 它写在
//  `scan/extguard.py` 的文件头与 HANDOFF §8 第 29 条里（extension 必须文件层、
//  不许带实例存储属性、不许碰别处的 private）：注释留在原处而值已经没人用，
//  正是这个仓库反复吃亏的那种「文档在替不存在的代码担保」。
