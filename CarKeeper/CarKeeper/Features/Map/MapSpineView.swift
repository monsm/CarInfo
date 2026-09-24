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
//   ③ 地图样式来自 `ArtTheme.mapSpec` —— 换艺术主题 = 换真实 MapKit 配置，
//      阈值与理由都写在 MapStyleSpec.swift 里。
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

    @AppStorage(ArtThemeStore.key) private var themeRaw: String = ArtTheme.native.rawValue
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
    @State private var modePosition: Double = -1
    /// 底条是否正在展开（手指按在条子上）。
    /// 它只服务一件事：展开时把两侧的两枚圆钮**让出宽度并淡出** ——
    /// 原型 `.bottom.open .arm{opacity:0;transform:scale(.86)}`，
    /// 而“让出宽度”比单单淡出更要紧：条子展开后要 374pt（屏宽 390），
    /// 留给两枚圆钮就只能把间距压扁，而压间距正是原型明确否掉的那一件事。
    @State private var barOpen = false

    @State private var camera: MapCameraPosition = .automatic
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

    /// 算光用的时刻（实时就是现在）
    private var skyDate: Date {
        SkyLight.date(hour: skyLive ? nil : Int(skyHour.rounded()), from: Date())
    }

    private var theme: ArtTheme { ArtTheme(rawValue: themeRaw) ?? .native }
    private var spec: MapStyleSpec { theme.mapSpec }
    private var layer: MapSpineLayer { MapSpineLayer(rawValue: layerRaw) ?? .now }
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

    /// 底条占掉的纵向空间：26（离底）+ 46（条高）+ 14（呼吸位）= 86。
    /// **同一个数在原型里是 `.stack{bottom:86px}`** —— 页面内容的窗口正好停在条子上沿。
    /// 真机上它从**安全区底**算起（安全区之上再留 26），所以刘海屏与旧机型都是同一个观感。
    private static let barTotal: CGFloat = 86
    /// 底条离底多远（原型 `.bottom{bottom:26px}`）
    private static let barGap: CGFloat = 26
    /// 两侧圆钮的直径（原型 `.arm{width:calc(var(--H) + 4px)}`，H = 46）
    private static let armSize: CGFloat = 50
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
        let d = data
        ZStack(alignment: .bottom) {
            // ⓪ 六层页面同屏（原型 `.pages > .page{inset:0}` × 6）。
            pageDeck()

            // ① 顶：底条 = 左臂（车牌）｜模式条｜右臂（搜索），贴底 26。
            //    原型 `.bottom{position:absolute;left:0;right:0;bottom:26;gap:9;
            //    height:calc(var(--H) + 14px)}`：模式条就长在**最底**，
            //    内容从它上面长上去 —— 相机就是这么摆的。
            bottomBar
        }
        // 底条离底 26、页面窗到「屏底 − 86」：原型的这两个数都是从**屏幕**量的
        // （`.bottom{bottom:26}` / `.stack{bottom:86}`）。安全区底那 34pt 若不排除，
        // 条子会凭空抬高一截 —— 与原型差出一个手指的宽度。
        .ignoresSafeArea(edges: .bottom)
        .background(TokensPalette.canvas)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        // 原型里**六页都没有顶栏**：地图画到屏幕最上沿，其余五页的第一张卡是巨字头，
        // 状态栏之下没有任何栏。留一条空标题的栏不只是多一条 chrome ——
        // 它把卡片窗整体压低 44pt，于是「第一张卡落在哪」与原型差出一个卡头。
        // 原来靠它挂着的两件事搬进了页面自己：车控的语音播报在那一叠里（另一张卡），
        // 保养的「添加记录」在那一张卡里（一个动作），见各自文件。
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showSky) { skySheet(d).dsSheetCanvas() }
        // 右臂那几条会改车状态的快捷指令走**唯一那道门**：温度 → 生物识别 → 控车码。
        // 它挂在“现在”这一档（右臂就在这里），sheet 盖在地图上 ——
        // 不把用户推到车控页（一条锁车指令不该让人离开地图）。
        .controlCommandFlow($quickRequest)
        .task {
            await refresh()
            centerOnCar(force: true)
            if layer == .charge { await searchChargersIfNeeded() }
            await refreshWeatherIfNeeded()
        }
        .onChange(of: layer) { _, new in
            TokensHaptic.select()
            if new == .charge { Task { await searchChargersIfNeeded() } }
        }
        .onChange(of: d.carCoordinate?.latitude) { _, _ in centerOnCar(force: false) }
        .onChange(of: store.mapFocus) { _, f in if let f { focusOn(f) } }
        .onReceive(NotificationCenter.default.publisher(for: .locationUpdated)) { _ in
            centerOnCar(force: false)
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
        Map(position: $camera) {
            mapContent(d)
        }
        .mapStyle(spec.style)
        // 比例尺：地图上唯一能让「这一段有多长」变得可核对的东西。
        // 它是系统控件（MapKit 的 MapScaleView），不占位、不在原生主题下改变现有观感。
        .mapControls {
            // 罗盘与比例尺都在原型里（`.compass` / `.scale`）—— 它们是地图自己的仪器，
            // 不是我们摆上去的控件：一个回答「哪边是北」，一个回答「这一段有多长」。
            MapCompass()
                .mapControlVisibility(.visible)
            MapScaleView()
                .mapControlVisibility(.visible)
        }
        .overlay {
            // 系统瓦片的颜色改不了，只能盖一层。原生主题的不透明度是 0（不盖）。
            spec.scrim
                .opacity(spec.scrimOpacity)
                .allowsHitTesting(false)
        }
        // 光层：光池的位置由**太阳方位角**决定，暗角与颗粒由环境光决定。
        // 它是「车所在的那一刻」直接画在图上 —— 不吃点击，原生主题下一个像素都不加。
        .overlay {
            if let sky = d.sky(at: skyDate) {
                SkyOverlay(light: sky)
            }
        }
        .overlay(alignment: .topLeading) { mapPlaceLabel(d) }
        .ignoresSafeArea(edges: .top)
        .accessibilityLabel(Text("地图，车在这张图上"))
    }

    /// 图上的大字地名。**斜排的角度来自当前艺术方向**（夜光的相机本来就转了 7°）——
    /// 所以它和路网是同一个角度，不是装饰性倾斜。衬线 + 疏排是「印刷物」的做法。
    @ViewBuilder
    private func mapPlaceLabel(_ d: MapSpineData) -> some View {
        if !d.placeLabel.isEmpty {
            Text(d.placeLabel)
                .font(TokensSerif.place(29))
                .tracking(TokensTracking.place)
                .lineLimit(1)
                .foregroundStyle(TokensPalette.primary.opacity(0.9))
                .shadow(color: TokensPalette.canvas.opacity(0.55), radius: 6)
                .rotationEffect(.degrees(-spec.cameraHeading))
                .padding(.leading, TokensSpacing.page)
                .padding(.top, 108)
                .allowsHitTesting(false)
        }
    }

    @MapContentBuilder
    private func mapContent(_ d: MapSpineData) -> some MapContent {
        if let c = d.carCoordinate {
            Annotation(d.carName, coordinate: c) {
                MapCarPin(
                    socPct: d.socPct,
                    heading: d.headingDeg,
                    style: spec.pinStyle,
                    allowsGlow: spec.allowsGlow,
                    isActive: false,
                    lamp: d.sky(at: skyDate)?.lamp ?? 0
                )
                .frame(width: 44, height: 44)   // HIG 最小触控目标就落在钉中心
            }
        }
        rangeCircle(d)
        tripLines(d)
        hotspotCircles(d)
        holdPins(d)
        chargerPins
        issuePins(d)
    }

    /// 行程：**一条一条的起终点连线**（不是轨迹 —— TripRecord 里没有轨迹点）
    ///
    /// 每条线画两遍：先一条更宽更淡的（光晕），再一条细的（主线）。
    /// 只加这一点，路线就从「贴在瓦片上的线」变成「发着光的路径」——
    /// 原型里那个观感差主要就差在这一层，而不是差在底图上。
    /// 颜色仍是**同一个 accent**，没有新增颜色。
    @MapContentBuilder
    private func tripLines(_ d: MapSpineData) -> some MapContent {
        if layer == .trips {
            ForEach(d.trips) { t in
                MapPolyline(MKPolyline(coordinates: [t.from, t.to], count: 2))
                    .stroke(TokensPalette.accent.opacity(0.16),
                            style: StrokeStyle(lineWidth: 10, lineCap: .round))
                MapPolyline(MKPolyline(coordinates: [t.from, t.to], count: 2))
                    .stroke(TokensPalette.accent.opacity(0.9),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
        }
    }

    /// 续航圈：半径就是车报的 RemainedPowerMile（米）。车没报就不画 —— 不猜。
    @MapContentBuilder
    private func rangeCircle(_ d: MapSpineData) -> some MapContent {
        if layer == .now, let c = d.carCoordinate, let meters = d.rangeMeters, meters > 0 {
            MapCircle(center: c, radius: meters)
                .stroke(TokensPalette.accent,
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [4, 5]))
                .foregroundStyle(TokensPalette.accent.opacity(0.05))
        }
    }

    /// 常停热区：停车史聚出来的圈。描边示形状，填充透明度随次数加深。
    @MapContentBuilder
    private func hotspotCircles(_ d: MapSpineData) -> some MapContent {
        if layer == .holds {
            ForEach(d.hotspots) { h in
                MapCircle(center: h.center, radius: h.radiusMeters)
                    .stroke(TokensPalette.accent.opacity(0.55),
                            style: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                    .foregroundStyle(TokensPalette.accent.opacity(h.visits >= 3 ? 0.14 : 0.07))
            }
        }
    }

    @MapContentBuilder
    private func holdPins(_ d: MapSpineData) -> some MapContent {
        if layer == .holds {
            ForEach(d.holds) { h in
                Annotation("停车点", coordinate: h.coordinate) {
                    MapSpotPin(kind: .hold(isLatest: h.isLatest),
                               style: spec.pinStyle,
                               allowsGlow: spec.allowsGlow)
                }
            }
        }
    }

    /// 显示用的聚合结果（地图与面板共用同一份）
    private var chargerClusters: [MapChargerCluster] {
        MapSpineData.clusterChargers(chargers)
    }

    @MapContentBuilder
    private var chargerPins: some MapContent {
        if layer == .charge {
            // 一个位置只放一个标记：孤立的是钉子，挨在一起的是一个带**真实站数**的圈。
            // 点圈 = 放大到那一组 —— 聚合不能变成「点不开的东西」。
            ForEach(chargerClusters) { cluster in
                Annotation("充电站", coordinate: cluster.coordinate) {
                    if cluster.count == 1 {
                        MapSpotPin(kind: .charger(distanceText: cluster.nearest.distanceText),
                                   style: spec.pinStyle,
                                   allowsGlow: spec.allowsGlow)
                    } else {
                        Button {
                            withAnimation(TokensMotion.value) {
                                camera = .camera(MapCamera(centerCoordinate: cluster.coordinate,
                                                           distance: 1200))
                            }
                        } label: {
                            MapClusterPin(count: cluster.count)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @MapContentBuilder
    private func issuePins(_ d: MapSpineData) -> some MapContent {
        if layer == .now {
            ForEach(d.issues) { i in
                Annotation("异常", coordinate: i.coordinate) {
                    // 异常必须在图上自己说出来 —— 要点一下才知道是哪一条，不算「看见」
                    MapSpotPin(kind: .issue, style: spec.pinStyle,
                               allowsGlow: spec.allowsGlow, label: i.title)
                }
            }
        }
    }

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
        HStack(spacing: barOpen ? 0 : 9) {
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
                         })

            quickArm
        }
        .padding(.horizontal, Self.barPad)
        .padding(.bottom, Self.barGap)
        .frame(maxWidth: .infinity)
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
            Circle()
                .fill(TokensPalette.glassHighlight)
                .glassEffect(.regular, in: Circle())
                .overlay {
                    Circle().strokeBorder(TokensPalette.glassBorder, lineWidth: TokensHair.border)
                }
            if let text {
                Text(text)
                    .font(TokensTypo.fixed(11, weight: .bold))
                    .foregroundStyle(TokensPalette.secondary)
            } else if let icon {
                Image(safeSymbol: icon, fallback: icon)
                    .font(TokensTypo.fixed(17, weight: .medium))
                    .foregroundStyle(TokensPalette.primary)
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
        EnhancedToastManager.shared.show(ok ? "\(c.name)指令已发送" : "\(c.name)发送失败",
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
            // 换档的交叉过渡底下必须有**一层不透明的画布**。
            //
            // 出去与进来的两页各自淡一会儿（原型 `opacity = 1 − 1.6a` 同时作用在两者上），
            // 合成的透明度加起来不到 1；底下若是地图，过渡期间就会从卡片之间透出一层
            // 灰黑（用户 2026-09-24：「其他页面的暗层也删除」—— 非地图页上最容易看到的就是这一层）。
            // 铺上它之后，过渡的底是画布色，而不是「上一页 / 地图的鬼影」。
            // 它在最底层，地图那一页（`.now`）盖在它上面，所以地图页一点不变。
            TokensPalette.canvas.ignoresSafeArea()
            ForEach(HomeMode.allCases.indices, id: \.self) { i in
                let a = fade(i)
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

    /// 一层页面。两个形态与原型的两个 `.page` 形态一一对应：
    ///   · 「现在」＝ `.map{inset:0}` + 浮动两卡，**铺满全屏**（地图画到屏幕最上沿）
    ///   · 其余五档＝ `.stack{top:54;bottom:86}`：不透明的一页，卡片窗停在条子上沿
    @ViewBuilder
    private func pageBody(_ mode: HomeMode) -> some View {
        if mode == .now {
            nowLayer()
        } else {
            // 窗口 = 安全区顶（原型的 54 就是状态栏高，真机上安全区给出同一个数）
            //      → 屏底 − 86（条子上沿）。
            pageContent(mode)
                .padding(.bottom, Self.barTotal)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                // 不透明：六层同屏时它必须盖住底下的地图（原型那五页各有自己的底）。
                .background(TokensPalette.canvas.ignoresSafeArea())
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
        ZStack(alignment: .bottom) {
            // 地图是这一页**本身**（原型 `#page-now` 里的 `.map{inset:0}`），
            // 不是衬在六页底下的背景：换走时它跟着淡出、缩小，
            // 而不是「别的页浮在一张活地图上」（那样两页交界处会露出地图）。
            mapCanvas(d)

            // 底图之上**没有任何压暗层**（原型这里有 `.maptop` + `.mapvig` 两层，都已删）。
            //
            // 用户 2026-09-24：「全局不要加暗层」+「地图页顶部的信息挪到下面的玻璃卡片」——
            // 这两条是同一件事的两面：`.maptop` 存在的唯一理由是「车牌徽标压在瓦片上要读得出」，
            // 而徽标已经搬进下面那张玻璃卡（见 `nowHead`）。理由消失，层就跟着走。
            // 删干净之后地图上只剩两样不是瓦片的东西：地名（自带 textShadow，不吃整屏亮度）
            // 与地图自己的仪表（罗盘 / 比例尺）。

            // `.float{left:16;right:16;bottom:98;gap:12}`：底边离屏底 98
            //（条子占 86 + 12 的呼吸位），两卡之间 12。
            VStack(alignment: .leading, spacing: 12) {
                nowCard(d)
                readoutChips(d)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, Self.barTotal + 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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
    //  地图自己的仪表（罗盘 / 比例尺）是**系统控件**，它们自带底、不靠这层压暗。
    /// 卡头上的**图层胶囊**：写着当前在看哪一层，点开是这张地图的那几件事。
    ///
    /// 它原来是屏幕左上角的车牌徽标（车牌 + 状态 + 上报时间的那个控件），
    /// 徽标的信息已拆进卡头（车牌一行、状态与上报时间一行），菜单留在这里。
    /// 菜单里那几件事都是**不常按但必须能到**的：看哪一层（图上四个图层）、
    /// 重取数据、此刻的光、回到车（iPad 上再加一个新车况窗口）。
    /// 收进一个菜单是**结构决定**：它们原来各占一枚 —— 图层一张卡、光一枚药丸、
    /// 回到车一枚浮钮、顶栏三枚（刷新 / 搜索 / 回到车，而且长在**六页每一页**上）。
    private func layerMenu(_ d: MapSpineData) -> some View {
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
            Button {
                TokensHaptic.tap()
                Task { await refresh() }
            } label: {
                Label("重取数据", systemImage: "arrow.clockwise")
            }
            Button {
                TokensHaptic.tap()
                showSky = true
            } label: {
                Label(lightTitle(d), systemImage: "sun.max")
            }
            Button {
                TokensHaptic.tap()
                centerOnCar(force: true)
            } label: {
                Label("回到车", systemImage: "location.fill")
            }
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
            HStack(spacing: 4) {
                Text(layer.title)
                    .font(TokensTypo.caption)
                    .tracking(TokensTracking.label)
                Image(safeSymbol: "chevron.up.chevron.down", fallback: "chevron.down")
                    .font(TokensTypo.micro)
            }
            .foregroundStyle(TokensPalette.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background { Capsule().fill(TokensPalette.fillSubtle) }
            .overlay {
                Capsule().strokeBorder(TokensPalette.glassBorder, lineWidth: TokensHair.border)
            }
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

    /// 「现在」这一档的浮动首卡。形态与内容都照原型 `.float > .card`：
    ///   头  `.hd`   = 车牌 + 状态 · 上报时间（原图左上那枚徽标，2026-09-24 搬进卡）
    ///   地址 `.ch`  = 车端上报的那句地址（大字）
    ///   巨字 `.big` = **续航**（原型大字就是 412 km 续航，不是电量百分比）
    ///   副行 `.sub` = 表显里程 · 充不充电
    ///   光带 `.gain`= 电量（全 App 唯一的形状）
    ///
    /// 一页之内一个事实只有一个出处（用户 2026-09-24：「地图页的信息有很多是重复的」）：
    /// 电量与胎压都归下面那排四格读数 ── 卡里再说一遍「电量 68%」、
    /// 再排一行四轮胎压，就是同一句话说两遍。
    /// 四轮胎压的**逐轮细节**在「车辆 → 体检」里；首页只留一格「最低的那一条」。
    /// 换了图层（行程 / 停车 / 充电站）时换成那一层的内容 ——
    /// 于是「图上在看哪个问题」与「读它的数」是同一张卡，不必再多一张选择卡。
    @ViewBuilder
    private func nowCard(_ d: MapSpineData) -> some View {
        GlassCard(accent: HomeMode.now.accent) {
            VStack(alignment: .leading, spacing: TokensSpacing.sm) {
                nowHead(d)
                switch layer {
                case .now:
                    if d.hasLocation == false {
                        // 没有位置时不摆一堆「--」：说清为什么
                        emptyNotice(MapSpineLayer.now.emptyNote)
                    } else {
                        nowMetrics(d)
                    }
                case .trips: tripsContent(d)
                case .holds: holdsContent(d)
                case .charge: chargeContent(d)
                }
            }
        }
    }

    /// 卡头两行：**身份**（车牌）与**新鲜度**（状态 + 上报时间）。
    ///
    /// 这两行原来长在地图左上角的车牌徽标上（用户 2026-09-24：顶部信息挪进卡）。
    /// 搬进来之后它比在图上更准：徽标浮在瓦片上，只能用重阴影把字从底图里抬出来；
    /// 卡里它就是正文，遮罩与对比度全部由玻璃负责。
    /// 右侧那枚胶囊是图层菜单（原徽标菜单，见 `layerMenu`）。
    private func nowHead(_ d: MapSpineData) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: TokensSpacing.sm) {
                Text(plateText(d))
                    .font(TokensTypo.digits(15))
                    .tracking(1.2)
                    .foregroundStyle(TokensPalette.primary)
                Spacer(minLength: 0)
                layerMenu(d)
            }
            HStack(spacing: 6) {
                statusDot(d.online)
                Text("\(d.online.text) · 上报 \(d.updatedText)")
                    .font(TokensTypo.caption)
                    .foregroundStyle(TokensPalette.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("\(d.online.text)，上报 \(d.updatedText)"))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("车牌 \(plateText(d))") +
                            Text("，\(d.online.text)，上报 \(d.updatedText)"))
    }

    /// 现状卡的读数：地址 → 巨字续航 → 副行 → 光带。
    @ViewBuilder
    private func nowMetrics(_ d: MapSpineData) -> some View {
        if !d.address.isEmpty {
            Text(d.address)
                .font(TokensSerif.title(22))
                .tracking(TokensTracking.title)
                .foregroundStyle(TokensPalette.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        if d.rangeText == "--" {
            // 车没报续航就**不摆「-- km」** —— 那是一个假的读数
            GlassCardEmpty(text: "还没收到剩余续航", icon: "bolt.slash")
        } else {
            DSBigNumber(value: d.rangeText, unit: "km", caption: "续航", size: 56,
                        tint: TokensPalette.primary)
        }
        nowSub(d)
        // 光带 = 电量（全 App 唯一的形状，在地图上它是「车钉外面那圈弧」的展开）
        DSLightBar(progress: Double(d.socPct) / 100,
                   height: 5,
                   showsGlow: spec.allowsGlow,
                   tint: TokensPalette.lightBar)
    }

    /// 副行。空段直接丢掉（不摆占位）—— 「表显 53,766 km · 未充电」里任何一个字
    /// 取不到，那一句就不出现，而不是留一个 `--`。
    ///
    /// 它曾经从「电量 68%」开头 —— 那个数已经是下面四格里的「电量」那一格，
    /// 而电量在这张卡里还有第三种说法（光带）。一个 68% 说三遍不是信息多，是没精简。
    @ViewBuilder
    private func nowSub(_ d: MapSpineData) -> some View {
        let mileage = VM.vehicleSummary(store.car, store.controlCache)?.mileage
        let line = Self.join([mileage.map { "表显 \($0) km" },
                              d.chargeText])
        if !line.isEmpty {
            Text(line)
                .font(TokensTypo.caption)
                .foregroundStyle(TokensPalette.tertiary)
        }
    }

    /// 把若干片段拼成一行：空段与 `--` 直接丢掉（全站统一的做法）。
    private static func join(_ parts: [String?]) -> String {
        parts.compactMap { $0 }
            .filter { !$0.isEmpty && $0 != "--" }
            .joined(separator: " · ")
    }

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

    /// 「此刻的光」：样品版里那张表的真机版。
    /// 它不是「关于」页 —— 它让这一屏的光**可以被争论**：每一行都是一个可复算的事实，
    /// 而把天文事实翻译成界面数值的那几条规则，都写在值的旁边。
    private func skySheet(_ d: MapSpineData) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TokensSpacing.lg) {
                    if let sky = d.sky(at: skyDate) {
                        DSSectionHeader(title: "此刻的光")
                        VStack(alignment: .leading, spacing: 0) {
                            SkyFactTable(facts: sky.facts)
                        }
                        .padding(.horizontal, TokensSpacing.md)
                        .background(cardBackground)

                        // 时刻滑块 —— 样品里最标志性的那件东西：
                        // 把「此刻」变成「可以拖的时刻」，一拖就能看完一天的光（深夜→日出→正午→黄昏）。
                        // 它同时是这一整套光的**证明**：不是配的色，拖一下就自己看见。
                        DSSectionHeader(title: "看哪一刻的光")
                        VStack(alignment: .leading, spacing: TokensSpacing.sm) {
                            HStack(alignment: .firstTextBaseline, spacing: TokensSpacing.sm) {
                                Text(skyLive ? "此刻（实时）"
                                             : String(format: "%02d:00", Int(skyHour.rounded())))
                                    .font(TokensTypo.digits(20))
                                    .foregroundStyle(TokensPalette.primary)
                                Spacer(minLength: 0)
                                if !skyLive {
                                    Button("回到此刻") {
                                        TokensHaptic.tap()
                                        skyLive = true
                                    }
                                    .font(TokensTypo.footnote)
                                    .foregroundStyle(TokensPalette.accent)
                                    .buttonStyle(.plain)
                                }
                            }
                            Slider(value: $skyHour, in: 0...23)
                                .tint(TokensPalette.accent)
                                .onChange(of: skyHour) { _, _ in skyLive = false }
                            Text("按你所在时区。")
                                .font(TokensTypo.caption)
                                .foregroundStyle(TokensPalette.tertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(TokensSpacing.md)
                        .background(cardBackground)

                        if case .failed(let msg) = weather.status {
                            DSNotice(kind: .warning,
                                     text: "天气没取到（\(msg)），上面是晴空模型的算法值。")
                        }

                        Text("太阳高度角与方位角由车的位置算出（NOAA，不联网）。"
                             + "云量、降水来自 Open-Meteo 实况。"
                             + "没有实况就退回晴空模型。")
                            .font(TokensTypo.footnote)
                            .foregroundStyle(TokensPalette.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        emptyNotice("不知道车在哪儿")
                    }
                }
                .padding(.top, TokensSpacing.sm)
                .padding(.bottom, TokensSpacing.xxl)
            }
            .pageBackground()
            .navigationTitle("光")
            .navigationBarTitleDisplayMode(.inline)
            .presentationDetents([.medium, .large])
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        Task { await refreshWeatherIfNeeded(force: true) }
                    } label: {
                        if weather.status == .loading {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("重取天气")
                        }
                    }
                    .font(TokensTypo.footnote)
                    .disabled(weather.status == .loading)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { showSky = false }
                }
            }
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: TokensRadius.medium, style: .continuous)
            .fill(TokensPalette.surface)
    }


    // =========================================================================
    // MARK: 交互与数据
    // =========================================================================

    /// 不是 `private`：同上（三个图层内容都用它写「取不到」那一句）。
    func emptyNotice(_ text: String) -> some View {
        HStack(alignment: .top, spacing: TokensSpacing.sm) {
            Image(safeSymbol: "info.circle", fallback: "info.circle")
                .font(TokensTypo.fixed(13))
                .foregroundStyle(TokensPalette.tertiary)
            Text(text)
                .font(TokensTypo.footnote)
                .foregroundStyle(TokensPalette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, TokensSpacing.sm)
    }

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
                                       distance: spec.cameraDistance * 1.6,
                                       heading: spec.cameraHeading,
                                       pitch: 0))
        }
        didCenterOnce = true   // 别让随后的车位置刷新把镜头拉回车上
        ToastManager.shared.show(f.label.isEmpty ? "已移到事件位置" : f.label,
                                 icon: "mappin.and.ellipse")
        store.mapFocus = nil
    }

    /// 把相机移到车上。heading 来自**当前艺术方向**（夜光转 7°，让路网斜走）。
    @MainActor
    private func centerOnCar(force: Bool) {
        guard let c = store.currentLocation?.coordinate else { return }
        if didCenterOnce && !force { return }
        didCenterOnce = true
        withAnimation(TokensMotion.value) {
            camera = .camera(MapCamera(centerCoordinate: c,
                                       distance: spec.cameraDistance,
                                       heading: spec.cameraHeading,
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
        guard let car = store.currentLocation else { return }
        let key = String(format: "%.4f,%.4f", car.coordinate.latitude, car.coordinate.longitude)
        if !force, key == chargerCenterKey, !chargers.isEmpty { return }
        chargerCenterKey = key

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "充电站"
        request.region = MKCoordinateRegion(center: car.coordinate,
                                            latitudinalMeters: 8000,
                                            longitudinalMeters: 8000)
        let search = MKLocalSearch(request: request)
        // 用完成回调版（项目里已有同样写法，编译过）；回调里再回主线程写状态。
        search.start { response, _ in
            guard let response else { return }
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
            Task { @MainActor in chargers = Array(sorted.prefix(60)) }
        }
    }
}
