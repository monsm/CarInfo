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
//   相机 App   —— 换模式**不离开取景框**：模式条紧贴在内容的上沿，
//                 每一档只有文字、选中只靠颜色，且条子自身可横向滚动。
//                 （细节与「为什么没照搬左右滑换模式」见 modeStrip）
//
// 四个模式 = 四个真实问题（不是一个分类菜单）：现在 / 行程 / 停车 / 充电。
// 换模式 = 同一张图换一个提问，图、车钉、手势全程不变。
//
// 三条架构规则（写错就出问题，不是风格问题）：
//   ① 钉 = 屏幕空间（`Annotation`），面积/轨迹 = 地理空间（`MapPolyline`）。
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

struct MapSpineView: View {
    private let store = AppStore.shared
    @EnvironmentObject private var nav: NavState
    /// iPad 分栏用（SceneID.detail 的场景声明在 CarKeeperApp.swift）
    @Environment(\.openWindow) private var openWindow
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// 天气实况（光需要云量）：**订阅**它 —— 快照是异步到达的，不订阅这一屏就不会重画。
    @ObservedObject private var weather = WeatherService.shared

    @AppStorage(ArtThemeStore.key) private var themeRaw: String = ArtTheme.native.rawValue
    /// 记住上次看的图层（地图主屏的"当前位置"应该被记住，不该每次回到默认）
    // 键名定义在 MapSpineLayer.storageKey（别处把地图开到某一层也用同一个键）
    @AppStorage(MapSpineLayer.storageKey) private var layerRaw: String = MapSpineLayer.now.rawValue

    @State private var camera: MapCameraPosition = .automatic
    @State private var didCenterOnce = false
    @State private var chargers: [MapCharger] = []
    @State private var chargerCenterKey = ""
    @State private var showIndex = false
    @State private var isRefreshing = false
    @State private var showReplay = false
    @State private var replaySession: ChargeSession?
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

    /// 数据在 main actor 上组装（AppStore 是 @MainActor @Observable）。
    @MainActor private var data: MapSpineData { MapSpineData.build() }

    var body: some View {
        let d = data
        ZStack(alignment: .bottom) {
            mapCanvas(d)

            VStack(spacing: 0) {
                topBar(d)
                Spacer(minLength: 0)
                // 常驻操作条：高频动作不离开这张图就能发出去。
                // 它与底部面板是**两件事**：面板是「车现在什么样」，条子是「现在能做什么」——
                // 面板只服务「现在」这一层，而锁车在「行程/停车/充电」层里同样会发生。
                MapQuickBar()
                bottomPanel(d)
            }
        }
        .background(TokensPalette.canvas)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarItems(d) }
        .sheet(isPresented: $showIndex) { indexSheet(d).dsSheetCanvas() }
        .sheet(isPresented: $showReplay) {
            if let s = replaySession { ChargeReplaySheet(session: s).dsSheetCanvas() }
        }
        .sheet(isPresented: $showSky) { skySheet(d).dsSheetCanvas() }
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
    @MapContentBuilder
    private func tripLines(_ d: MapSpineData) -> some MapContent {
        if layer == .trips {
            ForEach(d.trips) { t in
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
    // MARK: 顶部：图层 + 同步状态
    // =========================================================================

    @ViewBuilder
    private func topBar(_ d: MapSpineData) -> some View {
        VStack(spacing: TokensSpacing.sm) {
            // 顶部的图层胶囊条已**整个移到底部纸的上沿**，并改成相机 App 的模式条语法（见 modeStrip）。
            // 顶部现在只剩一件事：这台车此刻的数据是不是新的。
            HStack(spacing: TokensSpacing.sm) {
                HStack(spacing: TokensSpacing.sm) {
                    statusDot(d.online)
                    Text(d.online.text)
                        .font(TokensTypo.caption)
                        .foregroundStyle(TokensPalette.secondary)
                    Text("·")
                        .font(TokensTypo.caption)
                        .foregroundStyle(TokensPalette.tertiary)
                    Text("上报 \(d.updatedText)")
                        .font(TokensTypo.caption)
                        .foregroundStyle(TokensPalette.tertiary)
                }
                .padding(.horizontal, TokensSpacing.sm + 2)
                .padding(.vertical, 6)
                .background { Capsule().fill(TokensPalette.surface.opacity(0.94)) }

                Spacer(minLength: 0)

                if d.hasLocation == false {
                    Text("没有位置")
                        .font(TokensTypo.caption)
                        .foregroundStyle(TokensPalette.warning)
                } else if let sky = d.sky(at: skyDate) {
                    Button {
                        TokensHaptic.tap()
                        showSky = true
                    } label: {
                        lightPill(sky)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("此刻的光：\(sky.phase.title)，"
                                             + "太阳高度 \(Int(sky.altitude.rounded())) 度。"
                                             + "点开看它是怎么算出来的"))
                }
            }
        }
        .padding(.horizontal, TokensSpacing.page)
        .padding(.top, TokensSpacing.sm)
    }

    private func statusDot(_ online: OnlineState) -> some View {
        Circle()
            .fill(color(for: online.cls))
            .frame(width: 6, height: 6)
    }

    /// 光名药丸：这一刻的光叫什么、太阳多高、**从哪个方向来**。
    /// 那个箭头的角度就是真实方位角（正北为 0，顺时针）—— 不是装饰罗盘。
    private func lightPill(_ sky: SkyLight) -> some View {
        HStack(spacing: 6) {
            Image(safeSymbol: "arrow.up", fallback: "arrow.up")
                .font(TokensTypo.fixed(10, weight: .semibold))
                .rotationEffect(.degrees(sky.azimuth))
            Text(sky.phase.title)
                .font(TokensSerif.label(11))
                .tracking(TokensTracking.label)
            Text(String(format: "%.0f°", sky.altitude))
                .font(TokensTypo.digits(11))
                .foregroundStyle(TokensPalette.tertiary)
            // 云量只在「看此刻」时挂上来：它是**此刻**的实况，滑块拖出的时刻没有对应值
            if skyLive, let w = sky.weather {
                Text("云 \(w.cloudText)")
                    .font(TokensTypo.digits(11))
                    .foregroundStyle(TokensPalette.tertiary)
            }
            // 回放时必须看得见自己不在实时上 —— 不然这就是一屏假象
            if !skyLive {
                Text("回放")
                    .font(TokensTypo.caption2)
                    .foregroundStyle(TokensPalette.warning)
            }
        }
        .foregroundStyle(TokensPalette.secondary)
        .padding(.horizontal, TokensSpacing.sm + 2)
        .padding(.vertical, 6)
        .background { Capsule().fill(TokensPalette.surface.opacity(0.94)) }
    }

    // =========================================================================
    // MARK: 底部面板
    // =========================================================================

    @ViewBuilder
    private func bottomPanel(_ d: MapSpineData) -> some View {
        VStack(alignment: .leading, spacing: TokensSpacing.md) {
            panelGrab
            modeStrip
            panelTitle(d)
            if d.hasLocation == false {
                // 没有位置时，**不摆一堆 -- 占位**，只说清为什么
                emptyNotice("还没收到车的位置上报。连上车之后这张图才会有东西可看。")
            } else {
                switch layer {
                case .now: nowContent(d)
                case .trips: tripsContent(d)
                case .holds: holdsContent(d)
                case .charge: chargeContent(d)
                }
            }
        }
        .padding(.horizontal, TokensSpacing.md)
        .padding(.top, TokensSpacing.md)
        .padding(.bottom, TokensSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: TokensRadius.large,
                                   topTrailingRadius: TokensRadius.large,
                                   style: .continuous)
                .fill(TokensPalette.surface)
                .ignoresSafeArea(edges: .bottom)
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(TokensPalette.hairline)
                .frame(height: TokensHair.line)
        }
    }

    // =========================================================================
    // MARK: 模式条（相机 App 的语法，替代了顶部的胶囊条）
    // =========================================================================
    // 主框架 = **Apple Maps 的一张全屏地图 + 一张贴着底边的纸**，
    // 而「换这张纸在回答哪个问题」用的是**相机 App 的模式条**：
    //
    //   ① 换模式**不离开这张图**：没有页面推入、没有 Tab、没有遮罩 —— 取景框不变，
    //      变的只是它此刻在回答哪个问题（现在在哪 / 去过哪儿 / 停在哪 / 去哪充电）；
    //   ② 每一项**只有文字**：没有图标、没有底、没有描边。选中只靠颜色与字重说话
    //      （相机靠黄色，我们靠主题的 accent —— 全 App 唯一的强调色）；
    //   ③ 它**横向可滚动**，所以再加第五、第六个模式不会撑坏版式。
    //
    // 有一件**刻意没有照搬**：相机 App 里左右滑取景框就换模式，可地图的横向拖拽是**平移**。
    // 抢掉它会让「拖地图」变成「换模式」—— 那比少一个手势糟得多。所以第 ③ 条只落实到
    // 「条子自己可滚」。
    //
    // 为什么它不在顶部（原来的胶囊条在顶部）：那既不像地图（Maps 把模式选择放在纸的上沿，
    // 紧挨它控制的内容），也不像相机（相机的模式条在内容下沿），还和顶部的同步状态抢同一条视线。
    private var modeStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: TokensSpacing.xl) {
                ForEach(MapSpineLayer.allCases) { l in
                    let selected = l == layer
                    Button {
                        guard !selected else { return }
                        layerRaw = l.rawValue
                    } label: {
                        VStack(spacing: 3) {
                            Text(l.title)
                                .font(TokensTypo.subheadline.weight(selected ? .semibold : .regular))
                                .foregroundStyle(selected ? TokensPalette.accent : TokensPalette.secondary)
                            // 车机/户外都读得出来的「当前模式」：相机靠颜色，我们再给一个 3pt 的点。
                            Circle()
                                .fill(selected ? TokensPalette.accent : Color.clear)
                                .frame(width: 3, height: 3)
                        }
                        .padding(.vertical, TokensSpacing.xs)
                        .frame(minWidth: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("看\(l.title)"))
                    .accessibilityAddTraits(selected ? [.isSelected] : [])
                }
            }
            .padding(.horizontal, TokensSpacing.xxs)
        }
        .scrollBounceBehavior(.basedOnSize)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(TokensPalette.hairline)
                .frame(height: TokensHair.line)
        }
    }

    /// 抓手：面板是「一张可以拉起来的纸」，这一点必须看得见（样品版就是靠它读的）。
    private var panelGrab: some View {
        Capsule()
            .fill(TokensPalette.hairline)
            .frame(width: 40, height: 4)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }

    /// 面板标题：衬线大字 + 一台**描边画出来的**小车（不是 SF Symbol）。
    /// 负字距是大字才需要的 -
    /// 字号一大，字距不收紧就散。
    private func panelTitle(_ d: MapSpineData) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: TokensSpacing.sm) {
            Text(d.carName.isEmpty ? "车" : d.carName)
                .font(TokensSerif.title(26))
                .tracking(TokensTracking.title)
                .foregroundStyle(TokensPalette.primary)
                .lineLimit(1)
            CarGlyph(width: 30, height: 16, color: TokensPalette.secondary)
                .offset(y: -3)
            Spacer(minLength: 0)
            Text(d.address)
                .font(TokensTypo.caption)
                .foregroundStyle(TokensPalette.tertiary)
                .lineLimit(1)
                .layoutPriority(-1)
        }
    }

    // ---- 现在 ----
    @ViewBuilder
    private func nowContent(_ d: MapSpineData) -> some View {
        // 车名与地址已经搬到了面板标题行（衬线大字），这里只留三句读数
        HStack(alignment: .firstTextBaseline, spacing: TokensSpacing.sm) {
            Text("车头朝\(d.headingText)")
                .font(TokensTypo.digits(12))
                .foregroundStyle(TokensPalette.tertiary)
            if !d.gpsText.isEmpty {
                Text("·")
                    .font(TokensTypo.caption)
                    .foregroundStyle(TokensPalette.tertiary)
                Text("GPS \(d.gpsText)")
                    .font(TokensTypo.digits(12))
                    .foregroundStyle(TokensPalette.tertiary)
            }
            Spacer(minLength: 0)
        }

        HStack(alignment: .bottom, spacing: TokensSpacing.lg) {
            DSBigNumber(value: "\(d.socPct)", unit: "%", size: 54, tint: TokensPalette.primary)
            VStack(alignment: .leading, spacing: 4) {
                Text("续航 \(d.rangeText)")
                    .font(TokensTypo.subheadline)
                    .foregroundStyle(TokensPalette.primary)
                Text(d.chargeText)
                    .font(TokensTypo.caption)
                    .foregroundStyle(color(for: d.chargeCls))
                if let avg = d.avgConsumption {
                    Text("百公里 \(avg) kWh")
                        .font(TokensTypo.caption)
                        .foregroundStyle(TokensPalette.tertiary)
                }
            }
            Spacer(minLength: 0)
        }

        // 光带 = 电量（全 App 唯一的形状，在地图上它是"车钉外面那圈弧"的展开）
        DSLightBar(progress: Double(d.socPct) / 100,
                   height: 5,
                   showsGlow: spec.allowsGlow,
                   tint: TokensPalette.lightBar)

        tyreRow(d)

        if !d.reasons.isEmpty {
            DSSectionHeader(title: "为什么")
            VStack(alignment: .leading, spacing: TokensSpacing.sm) {
                ForEach(d.reasons.prefix(4)) { r in
                    HStack(alignment: .top, spacing: TokensSpacing.sm) {
                        Circle()
                            .fill(color(for: r.cls))
                            .frame(width: 5, height: 5)
                            .padding(.top, 6)
                        Text(r.text)
                            .font(TokensTypo.footnote)
                            .foregroundStyle(TokensPalette.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }

        actionRow(d)
    }

    /// 四轮胎压：一条安静的事实行。**任何一轮没真读到，整行就不出现** —— 不摆占位符。
    /// 报警位是车端自己置的（LfPressureWarning），颜色取自主题的 error，不是写死的红。
    @ViewBuilder
    private func tyreRow(_ d: MapSpineData) -> some View {
        if !d.tyres.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: TokensSpacing.md) {
                ForEach(d.tyres) { t in
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(t.label)
                            .font(TokensTypo.caption2)
                            .foregroundStyle(TokensPalette.tertiary)
                        Text(t.kpa)
                            .font(TokensTypo.caption.monospacedDigit())
                            .foregroundStyle(t.warn ? TokensPalette.error : TokensPalette.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(Text(t.warn
                        ? "\(t.label)胎压 \(t.kpa) 千帕，报警"
                        : "\(t.label)胎压 \(t.kpa) 千帕"))
                }
                Spacer(minLength: 0)
                Text("kPa")
                    .font(TokensTypo.caption2)
                    .foregroundStyle(TokensPalette.tertiary)
            }
        }
    }

    /// 控制长在对象上：不新写一套车控，直接进已有的车控 / 电池页
    private func actionRow(_ d: MapSpineData) -> some View {
        HStack(spacing: TokensSpacing.sm) {
            // 主操作只有一个，其余三个是并列的 —— 四个都一样重要 = 没有重要的
            action("车控", "slider.horizontal.3", hot: true) {
                nav.pushNavigation(.control)
            }
            // 叫「回到车」而不是「找车」：它做的是把镜头移回车所在位置。
            // 「找车」是另一件事（下发 RemoteSearchCar 让车鸣笛闪灯），
            // 那一个在地图下方的常驻操作条里。两个都叫「找车」= 用户分不清点哪个。
            action("回到车", "location.circle") { centerOnCar(force: true) }
            action("充电", "bolt.fill") { nav.pushNavigation(.battery) }
            // 「事件」而不是「异常」：这一列里多数是点火/熄火这类**正常事件**，
            // 叫「异常」等于把正常行驶也标成故障。它并进出行页了（`MessagesSection`）。
            action("事件", "exclamationmark.triangle") { nav.pushNavigation(.trips) }
        }
    }

    /// 四宫格动作块：图标在上、疏排小字在下（样品版的 q4 结构）。
    /// `hot` 只给**一个**动作 —— 强调一旦泛滥就等于没有强调。
    private func action(_ title: String, _ icon: String, hot: Bool = false,
                        _ run: @escaping () -> Void) -> some View {
        Button {
            TokensHaptic.tap()
            run()
        } label: {
            VStack(spacing: 6) {
                Image(safeSymbol: icon, fallback: icon)
                    .font(TokensTypo.fixed(17, weight: .medium))
                Text(title)
                    .font(TokensTypo.caption)
                    .tracking(TokensTracking.label)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(hot ? TokensPalette.accent : TokensPalette.raised)
            }
            .foregroundStyle(hot ? TokensPalette.labelOnTint : TokensPalette.primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
    }

    // ---- 行程 ----
    @ViewBuilder
    private func tripsContent(_ d: MapSpineData) -> some View {
        DSSectionHeader(title: "行程", trailing: d.trips.isEmpty ? nil : "\(d.trips.count) 段")
        if d.trips.isEmpty {
            emptyNotice(MapSpineLayer.trips.emptyNote)
        } else {
            // 把话说在前面：线是起终点，不是轨迹
            Text("图上的线是**起点到终点**的连接 —— 这次行程没有记录逐点轨迹。")
                .font(TokensTypo.caption)
                .foregroundStyle(TokensPalette.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(d.trips.prefix(3)) { t in
                HStack(alignment: .firstTextBaseline, spacing: TokensSpacing.sm) {
                    // 注意：`TokensTypo.data` 是**属性**，带尺寸的那支叫 digits(_:)
                    Text(t.timeText)
                        .font(TokensTypo.digits(13))
                        .foregroundStyle(TokensPalette.primary)
                    Text(String(format: "%.1f km", t.distanceKm))
                        .font(TokensTypo.digits(13))
                        .foregroundStyle(TokensPalette.primary)
                    Text("\(t.startSoc)% → \(t.endSoc)%")
                        .font(TokensTypo.caption)
                        .foregroundStyle(TokensPalette.secondary)
                    Spacer(minLength: 0)
                    if let eff = t.efficiency {
                        Text(String(format: "%.1f kWh/100km", eff))
                            .font(TokensTypo.caption)
                            .foregroundStyle(TokensPalette.tertiary)
                    }
                }
            }
            Button("全部行程") { nav.pushNavigation(.trips) }
                .font(TokensTypo.footnote)
                .foregroundStyle(TokensPalette.accent)
                .buttonStyle(.plain)
        }
    }

    // ---- 停车 ----
    @ViewBuilder
    private func holdsContent(_ d: MapSpineData) -> some View {
        DSSectionHeader(title: "停车", trailing: d.holds.isEmpty ? nil : "\(d.holds.count) 个点")
        if d.holds.isEmpty {
            emptyNotice(MapSpineLayer.holds.emptyNote)
        } else {
            ForEach(d.holds.prefix(3)) { h in
                HStack(alignment: .firstTextBaseline, spacing: TokensSpacing.sm) {
                    Text(h.isLatest ? "上次" : h.agoText)
                        .font(TokensTypo.caption)
                        .foregroundStyle(h.isLatest ? TokensPalette.accent : TokensPalette.tertiary)
                    Text(h.address)
                        .font(TokensTypo.footnote)
                        .foregroundStyle(TokensPalette.primary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(MapSpineData.agoText(h.time))
                        .font(TokensTypo.caption)
                        .foregroundStyle(TokensPalette.tertiary)
                }
            }
            Button("去行程时间轴看全部停车与旅程") { nav.pushNavigation(.trips) }
                .font(TokensTypo.footnote)
                .foregroundStyle(TokensPalette.accent)
                .buttonStyle(.plain)
        }
    }

    // ---- 充电 ----
    @ViewBuilder
    private func chargeContent(_ d: MapSpineData) -> some View {
        DSSectionHeader(title: "充电", trailing: chargers.isEmpty ? nil : "附近 \(chargers.count) 个")
        if let s = d.charging {
            HStack(alignment: .firstTextBaseline, spacing: TokensSpacing.sm) {
                Text(s.power)
                    .font(TokensTypo.digits(17))
                    .foregroundStyle(TokensPalette.info)
                Text(s.start + " → " + s.end)
                    .font(TokensTypo.caption)
                    .foregroundStyle(TokensPalette.secondary)
                Spacer(minLength: 0)
                if let full = d.timeToFull {
                    Text("充满还要 \(full)")
                        .font(TokensTypo.caption)
                        .foregroundStyle(TokensPalette.tertiary)
                }
            }
        }

        // 充电回放：只有功率采样真的攒出了一条会话才出现；正在充的那次不回放（还没结果）
        replayEntry()

        // 钱和电在同一层：这一充花了多少，是车端功率采样积分出来的真值
        ChargeMoneyBlock()

        if chargers.isEmpty {
            emptyNotice(MapSpineLayer.charge.emptyNote)
        } else {
            ForEach(chargers.prefix(3)) { c in
                HStack(alignment: .firstTextBaseline, spacing: TokensSpacing.sm) {
                    Text(c.name)
                        .font(TokensTypo.footnote)
                        .foregroundStyle(TokensPalette.primary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(c.distanceText)
                        .font(TokensTypo.digits(13))
                        .foregroundStyle(TokensPalette.secondary)
                    Text(c.isEVCharger ? "快充" : "—")
                        .font(TokensTypo.caption)
                        .foregroundStyle(TokensPalette.tertiary)
                }
            }
            Text("来自按车的位置做的实时搜索（MKLocalSearch），不是写死的列表。")
                .font(TokensTypo.caption)
                .foregroundStyle(TokensPalette.tertiary)
            Text("行程的“回放”做不了：TripRecord 只存起终点，没有逐点轨迹 —— 这是现状，不是缺陷。")
                .font(TokensTypo.caption)
                .foregroundStyle(TokensPalette.tertiary)
        }
        Button("充电与账单") { nav.pushNavigation(.battery) }
            .font(TokensTypo.footnote)
            .foregroundStyle(TokensPalette.accent)
            .buttonStyle(.plain)
    }

    // =========================================================================
    // MARK: 工具栏 + 索引
    // =========================================================================

    @ToolbarContentBuilder
    private func toolbarItems(_ d: MapSpineData) -> some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                TokensHaptic.tap()
                Task {
                    await refresh()
                    await searchChargersIfNeeded(force: true)
                }
            } label: {
                Image(safeSymbol: "arrow.clockwise", fallback: "arrow.clockwise")
            }
            .disabled(isRefreshing)
            .accessibilityLabel(Text("刷新车的数据"))
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                TokensHaptic.tap()
                showIndex = true
            } label: {
                Image(safeSymbol: "square.grid.2x2", fallback: "square.grid.2x2")
            }
            .accessibilityLabel(Text("全部功能"))
        }
        // 全局搜索：此前那个 HUD 搜的是写死的字符串、点下去什么都不发生，
        // 而且没有任何入口 —— 现在从地图顶部就能到。
        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                TokensHaptic.tap()
                nav.showSearch = true
            } label: {
                Image(safeSymbol: "magnifyingglass", fallback: "magnifyingglass")
            }
            .accessibilityLabel(Text("搜索页面、车、行程、指令"))
        }
        ToolbarItem(placement: .navigationBarLeading) {
            Button {
                TokensHaptic.tap()
                centerOnCar(force: true)
            } label: {
                Image(safeSymbol: "location.fill", fallback: "location.fill")
            }
            .disabled(d.hasLocation == false)
            .accessibilityLabel(Text("回到车的位置"))
        }
        // iPad：把车况另开一个窗口。场景声明在 CarKeeperApp（WindowGroup(id: SceneID.detail)），
        // 能不能真开由平台 + Info.plist 的 UIApplicationSupportsMultipleScenes 决定 ——
        // 所以这里只在常规宽度（iPad）出现，iPhone 上不摆一个必然失败的按钮。
        if sizeClass == .regular {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    TokensHaptic.tap()
                    openWindow(id: SceneID.detail)
                } label: {
                    Image(safeSymbol: "rectangle.on.rectangle", fallback: "rectangle.on.rectangle")
                }
                .accessibilityLabel(Text("在新窗口打开车况"))
            }
        }
    }

    /// 索引页：**App 唯一的功能目录**。
    ///
    /// 它曾经是「去掉 Tab 栏的代价补在这里」，而 Tab 栏并没去掉 —— 于是两套目录并存，
    /// 同一页在 Tab、地图图层、索引页、「我的」磁贴里最多出现 4 次。现在 Tab 栏没了，
    /// 这一页是真目录，所以它**按意图分组**（我现在要做什么），不再平铺 16 项让人找。
    private func indexSheet(_ d: MapSpineData) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TokensSpacing.lg) {
                    // 「地图上的地方」这一组（四个图层入口）已删：
                    // 模式条就长在纸的上沿、永远可见，再在目录里摆同一份四个入口，
                    // 就是「同一件事两个入口」——缝合怪的第一来源。
                    // 索引页从此只做一件事：列**离开地图**的深潜页。

                    // 「用车提示」不再单列：它已并入车辆档案（`VehicleTipsSection`）。
                    // 「全量数据」不再单列：它并进了体检与数据（`RawDataSection`）。
                    indexGroup("这辆车", [.vehicle, .battery, .health, .control])
                    indexGroup("出行", [.trips, .emergency])
                    // 「导出数据」并进了保养与钱，「驾驶评分」并进了出行页 ——
                    // 这一组现在只剩一个入口，分组也就不必存在了。
                    indexGroup("保养与钱", [.service])
                    // 「消息」不再单列：它并进了出行页（`MessagesSection`）。
                    indexGroup("系统", [.dev, .mine])

                    Text("三种艺术主题（夜光 / 纸上 / 巨字）住在开发者工具里，按一下换一套。"
                         + "这一页是 App 唯一的功能目录：地图是主屏，其余全在这里。")
                        .font(TokensTypo.caption)
                        .foregroundStyle(TokensPalette.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, TokensSpacing.sm)
                .padding(.bottom, TokensSpacing.xxl)
            }
            .pageBackground()
            .navigationTitle("全部功能")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { showIndex = false }
                }
            }
        }
    }

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
                            Text("按你所在时区的钟点；光由**车的经纬度**与这个时刻算出，所以拖到哪一格，光就真的算到哪一格。")
                                .font(TokensTypo.caption)
                                .foregroundStyle(TokensPalette.tertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(TokensSpacing.md)
                        .background(cardBackground)

                        if case .failed(let msg) = weather.status {
                            DSNotice(kind: .warning,
                                     text: "天气没取到（\(msg)）—— 上面那几行是晴空模型的算法值，不是实测。")
                        }

                        Text("太阳的高度角与方位角，由车所在的经纬度与此刻算出（NOAA 简化算法，纯数学，不联网），可以复算。"
                             + "云量 / 降水 / 天气码来自 Open-Meteo 实况，辐照度 = 晴空模型 × 云量衰减（式子印在上面那行的说明里）。"
                             + "没有取到实况时（离线、取数失败、或还没取到）退回晴空模型，并在那一行写明「没有天气数据」。")
                            .font(TokensTypo.footnote)
                            .foregroundStyle(TokensPalette.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        emptyNotice("不知道车在哪儿，就没有这一刻的光 —— 光是从车的位置算出来的。")
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

    private func indexRow(_ title: String, _ icon: String, _ hint: String,
                          _ run: @escaping () -> Void) -> some View {
        Button {
            TokensHaptic.tap()
            run()
        } label: {
            HStack(spacing: TokensSpacing.md) {
                Text(title)
                    .font(TokensTypo.body)
                    .foregroundStyle(TokensPalette.primary)
                Spacer(minLength: TokensSpacing.sm)
                Image(safeSymbol: icon, fallback: icon)
                    .font(TokensTypo.fixed(12, weight: .semibold))
                    .foregroundStyle(TokensPalette.tertiary)
            }
            .padding(.vertical, TokensSpacing.md)
            .padding(.horizontal, TokensSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(hint.isEmpty ? title : hint))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(TokensPalette.hairline)
                .frame(height: TokensHair.line)
                .padding(.leading, TokensSpacing.md)
        }
    }

    /// 深潜页的显示名。穷举（无 default）：新增深链时编译器会强制在这里表态。
    /// 索引页的一组：小标题 + 一组行。
    ///
    /// 刻意不列 `.dashboard` 与 `.parking`：它们指向的页面与 `.score` / `.trips` 是同一个，
    /// 同一页摆两个入口就是「缝合怪」最直接的来源（深链 `carkeeper://dashboard`
    /// 与 `carkeeper://parking` 仍然可用，只是不出现在目录里）。
    @ViewBuilder
    private func indexGroup(_ title: String, _ links: [Deeplink]) -> some View {
        DSSectionHeader(title: title)
        VStack(spacing: 0) {
            ForEach(links, id: \.self) { link in
                indexRow(deeplinkTitle(link), "chevron.right", "") {
                    showIndex = false
                    nav.pushNavigation(link)
                }
            }
        }
        .background(cardBackground)
    }

    private func deeplinkTitle(_ link: Deeplink) -> String {
        switch link {
        case .mine: return "车与账号"
        case .vehicle: return "车辆档案"
        case .health: return "体检与数据"
        case .battery: return "电池与充电"
        case .dev: return "开发者工具"
        case .control: return "车控"
        case .dashboard: return "仪表"
        case .trips: return "出行"
        case .service: return "保养与钱"
        case .parking: return "停车位置"
        case .emergency: return "应急面板"
        case .score: return "驾驶评分"
        }
    }

    // =========================================================================
    // MARK: 交互与数据
    // =========================================================================

    private func emptyNotice(_ text: String) -> some View {
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

    /// 回放入口。有已完成的会话才出现；点击打开采样曲线。
    @ViewBuilder
    private func replayEntry() -> some View {
        if let latest = ChargeLedger.shared.sessions.first {
            Button {
                TokensHaptic.tap()
                replaySession = latest
                showReplay = true
            } label: {
                HStack(spacing: TokensSpacing.sm) {
                    Image(safeSymbol: "chart.xyaxis.line", fallback: "chart.xyaxis.line")
                        .font(TokensTypo.fixed(13, weight: .medium))
                    Text("看这次充电的功率曲线")
                        .font(TokensTypo.footnote)
                    Spacer(minLength: 0)
                    Text(ChargeLedger.kwhText(latest.kWh) + " kWh")
                        .font(TokensTypo.digits(13))
                        .foregroundStyle(TokensPalette.secondary)
                    Image(safeSymbol: "chevron.right", fallback: "chevron.right")
                        .font(TokensTypo.fixed(11, weight: .semibold))
                        .foregroundStyle(TokensPalette.tertiary)
                }
                .padding(.vertical, TokensSpacing.sm)
                .padding(.horizontal, TokensSpacing.md)
                .background {
                    RoundedRectangle(cornerRadius: TokensRadius.medium, style: .continuous)
                        .fill(TokensPalette.raised)
                }
                .foregroundStyle(TokensPalette.primary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("查看最近一次充电的功率曲线"))
        }
    }

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
