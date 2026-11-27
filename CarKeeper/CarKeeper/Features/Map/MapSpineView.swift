import SwiftUI
import MapKit
import CoreLocation

struct MapSpineView: View {
    let store = AppStore.shared
    @EnvironmentObject var nav: NavState
    @Environment(\.openWindow) private var openWindow
    @Environment(\.horizontalSizeClass) private var sizeClass
    @ObservedObject private var weather = WeatherService.shared

    @AppStorage(MapSpineLayer.storageKey) private var layerRaw: String = MapSpineLayer.now.rawValue
    @AppStorage(HomeMode.storageKey) private var homeModeRaw: String = HomeMode.now.rawValue
    @State private var modePosition: Double = -1

    @State private var barRowDrag: DSSwipeStrip.RowDrag?

    @State var camera: MapCameraPosition = .automatic
    @State var didCenterOnce = false
    @State var chargers: [MapCharger] = []
    @State private var chargerCenterKey = ""
    @State private var isRefreshing = false
    @State private var showSky = false
    @State private var skyLive = true
    @State private var skyHour: Double = 12

    @AppStorage(MapSpineView.drawerKey) var drawerOpen = false


    @ObservedObject var trace = DriveTrace.shared

    @ObservedObject private var wallpaper = WallpaperService.shared

    @State var follow: MapFollowTarget = .car

    @ObservedObject private var phone = PhoneLocation.shared

    var skyDate: Date {
        SkyLight.date(hour: skyLive ? nil : Int(skyHour.rounded()), from: Date())
    }

    let cameraDistance: Double = 1_400

    let cameraPitch: Double = 0

    @Namespace var mapScope
    @State private var topSafeGap: CGFloat = 0
    var layer: MapSpineLayer { MapSpineLayer(rawValue: layerRaw) ?? .now }
    private var homeMode: HomeMode { HomeMode(rawValue: homeModeRaw) ?? .now }

    private var deckPos: Double {
        if homeMode == .vehicle {
            return barRowDrag != nil ? max(0, modePosition) : Double(modeIndex)
        }
        return modePosition >= 0 ? modePosition : Double(modeIndex)
    }

    private var modeIndex: Int {
        HomeMode.allCases.firstIndex(of: homeMode) ?? 0
    }

    private func fade(_ i: Int) -> Double {
        min(1, abs(Double(i) - deckPos))
    }

    @MainActor private var data: MapSpineData { MapSpineData.build() }

    static let drawerKey = "carkeeper_map_drawer"

    private static let barTotal: CGFloat = 94
    private static let barGap: CGFloat = 33
    private static let armSize: CGFloat = DSSwipeStrip.barHeight

    private static let barSeam: CGFloat = 9
    private static let barPad: CGFloat = 33
    @State private var quickRequest: ControlRequest?
    @State private var barDragging = false

    private func barRowWidth(_ pageWidth: CGFloat) -> CGFloat {
        max(160, pageWidth - 2 * Self.barPad)
    }
    private func stripLaneWidth(_ pageWidth: CGFloat) -> CGFloat {
        max(120, barRowWidth(pageWidth) - 2 * Self.armSize - 2 * Self.barSeam)
    }

    var body: some View {
        GeometryReader { screen in
            deck(screenWidth: screen.size.width)
        }
    }

    private func deck(screenWidth: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            pageDeck(pageWidth: screenWidth)

            bottomBar(pageWidth: screenWidth)

            if let t = nav.currentToast {
                ToastView(text: t.text, icon: t.icon)
                    .padding(.bottom, Self.barTotal + TokensSpacing.snug)
                    .id(t.text)
            }
        }
        .frame(width: screenWidth)
        .ignoresSafeArea(edges: .bottom)
        .background {
            GeometryReader { g in
                Color.clear
                    .onAppear { topSafeGap = g.frame(in: .global).minY }
                    .onChange(of: g.frame(in: .global).minY) { _, y in topSafeGap = y }
            }
        }
        .environment(\.stackTopInset, topSafeGap + TokensSpacing.md)
        .animation(.easeOut(duration: 0.2), value: nav.currentToast?.text)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showSky) {
            MapSkySheet(data: MapSpineData.build(),
                        skyHour: $skyHour,
                        skyLive: $skyLive,
                        isOpen: $showSky,
                        retryWeather: { await refreshWeatherIfNeeded(force: true) })
        }
        .controlCommandFlow($quickRequest)
        .task {
            if let last = store.parkingLocation {
                camera = .camera(MapCamera(centerCoordinate: last.coordinate,
                                           distance: cameraDistance,
                                           heading: 0,
                                           pitch: cameraPitch))
            }
            await refresh()
            centerOnCar(force: true)
            if layer == .charge { await searchChargersIfNeeded() }
            await refreshWeatherIfNeeded()
            await wallpaper.refreshIfStale()
        }
        .onChange(of: layer) { _, new in
            TokensHaptic.select()
            drawerOpen = true
            if new == .charge { Task { await searchChargersIfNeeded() } }
        }
        .onChange(of: store.currentLocation?.coordinate.latitude) { _, _ in centerOnCar(force: false) }
        .onChange(of: store.mapFocus) { _, f in if let f { focusOn(f) } }
        .onReceive(NotificationCenter.default.publisher(for: .locationUpdated)) { _ in
            centerOnCar(force: false)
        }
        .onChange(of: PhoneLocation.shared.mapCoordinate?.latitude) { _, _ in
            guard follow == .phone, !store.isCarMoving else { return }
            fly(to: PhoneLocation.shared.mapCoordinate)
        }
    }

    @MainActor
    private func refreshWeatherIfNeeded(force: Bool = false) async {
        guard let c = data.carCoordinate else { return }
        await WeatherService.shared.refreshIfNeeded(coordinate: c, force: force)
    }


    @ViewBuilder
    private func mapCanvas(_ d: MapSpineData) -> some View {
        Map(position: $camera, scope: mapScope) {
            mapContent(d)
        }
        .mapStyle(.standard(elevation: .flat))
    .mapControls { }
    .mapControlVisibility(.hidden)
        .ignoresSafeArea(edges: .top)
        .accessibilityLabel(Text("地图，车在这张图上"))
    }




    private func bottomBar(pageWidth: CGFloat) -> some View {
        HStack(spacing: Self.barSeam) {
            arm(icon: "car.fill", current: homeMode == .vehicle) { nav.openMode(.vehicle) }
                .accessibilityLabel(Text(homeMode == .vehicle ? "车辆（当前所在）" : "车辆"))
            Spacer(minLength: 0)
            DSSwipeStrip(items: HomeMode.stripItems,
                         selectedID: $homeModeRaw,
                         availableWidth: stripLaneWidth(pageWidth),
                         spillWidth: pageWidth,
                         onDragging: { now in barDragging = now },
                         onPosition: { pos in
                             modePosition = pos
                         },
                         rowDrag: barRowDrag)
            Spacer(minLength: 0)
            quickArm
        }
        .padding(.horizontal, Self.barPad)
        .padding(.bottom, Self.barGap)
        .frame(minWidth: pageWidth, maxWidth: pageWidth)
        .contentShape(Rectangle())
        .animation(TokensMotion.fade, value: barDragging)
        .simultaneousGesture(bottomBarDrag)
    }

    var bottomBarDrag: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { v in
                guard abs(v.translation.width) > abs(v.translation.height) else { return }
                barRowDrag = DSSwipeStrip.RowDrag(
                    translation: v.translation.width,
                    predicted: v.predictedEndTranslation.width,
                    moved: abs(v.translation.width) > 8)
            }
            .onEnded { _ in
                barRowDrag = nil
            }
    }

    @ViewBuilder
    private func arm(icon: String,
                     current: Bool = false,
                     _ run: @escaping () -> Void) -> some View {
        if barDragging {
            armPlaceholder
        } else {
            ZStack {
                Button {
                    TokensHaptic.tap()
                    run()
                } label: {
                    armDisc
                }
                .buttonStyle(.plain)
                armGlyph(icon: icon, current: current)
            }
            .transition(.opacity)
        }
    }

    private var armPlaceholder: some View {
        Color.clear
            .frame(width: Self.armSize, height: Self.armSize)
    }

    private var armDisc: some View {
        Color.clear
            .frame(width: Self.armSize, height: Self.armSize)
            .dsGlass(in: Circle(), interactive: true)
            .contentShape(Circle())
    }

    private func armGlyph(icon: String, current: Bool = false) -> some View {
        Image(safeSymbol: icon, fallback: icon)
            .font(TokensTypo.fixed(17, weight: .medium))
            .foregroundStyle(current ? TokensPalette.accent : TokensPalette.primary)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private var quickArm: some View {
        if barDragging {
            armPlaceholder
        } else {
            Menu {
                ForEach(Self.quickCommands, id: \.key) { c in
                    Button {
                        TokensHaptic.tap()
                        if c.changesState {
                            quickRequest = ControlRequest(key: c.key, name: c.name)
                        } else {
                            Task { await refreshCondition(c) }
                        }
                    } label: {
                        Label(c.name, systemImage: c.symbol)
                    }
                }
            } label: {
                armDisc.overlay { armGlyph(icon: "key.fill") }
            }
            .buttonStyle(.plain)
            .transition(.opacity)
            .accessibilityLabel(Text("快捷车控"))
            .accessibilityHint(Text("锁车、解锁、闪灯、鸣笛、远程寻车（需控车码）、刷新车况"))
        }
    }

    private struct QuickCommand {
        let key: String
        let name: String
        let symbol: String
        var changesState: Bool = true
    }

    private static let quickCommands: [QuickCommand] = [
        QuickCommand(key: "LockDoor", name: "锁车", symbol: "lock.fill"),
        QuickCommand(key: "UnLockDoor", name: "解锁", symbol: "lock.open.fill"),
        QuickCommand(key: "FlashLight", name: "闪灯", symbol: "lightbulb.fill"),
        QuickCommand(key: "Whistle", name: "鸣笛", symbol: "speaker.wave.2.fill"),
        QuickCommand(key: "RemoteSearchCar", name: "远程寻车", symbol: "location.fill"),
        QuickCommand(key: "UpCarCondition", name: "刷新车况", symbol: "arrow.clockwise",
                     changesState: false)
    ]

    private func refreshCondition(_ c: QuickCommand) async {
        let ok = await store.sendControlCommand(c.key)
        ToastManager.shared.show(ok ? "\(c.name)指令已发送" : "\(c.name)发送失败",
                                         icon: ok ? c.symbol : "exclamationmark.triangle.fill")
    }



    @ViewBuilder
    private func pageDeck(pageWidth: CGFloat) -> some View {
        ZStack {
            MapWallpaperLayer(image: wallpaper.image,
                              position: HomeMode.wallpaperPosition(deckPos))
            ForEach(HomeMode.allCases.indices, id: \.self) { i in
                let a = fade(i)
                pageBody(HomeMode.allCases[i], pageWidth: pageWidth)
                    .frame(minWidth: pageWidth, maxWidth: pageWidth, alignment: .top)
                    .opacity(a >= 0.62 ? 0 : 1 - a * 1.6)
                    .allowsHitTesting(i == modeIndex)
                    .accessibilityHidden(i != modeIndex)
            }
        }
    }

    @ViewBuilder
    private func pageBody(_ mode: HomeMode, pageWidth: CGFloat) -> some View {
        if mode == .now {
            nowLayer()
        } else {
            pageContent(mode)
                .frame(minWidth: pageWidth, maxWidth: pageWidth,
                       maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea(edges: .bottom)
                .environment(\.stackBottomInset, Self.barTotal)
        }
    }

    @ViewBuilder
    private func nowLayer() -> some View {
        let d = data
        ZStack(alignment: .bottom) {
            mapCanvas(d)

            MapScaleView(anchorEdge: .leading, scope: mapScope)
                .padding(.leading, TokensSpacing.md)
                .padding(.top, TokensSpacing.sm)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .allowsHitTesting(false)


            nowCard(d)
                .padding(.horizontal, TokensSpacing.md)
                .padding(.bottom, Self.barTotal + 12)
                .frame(maxWidth: .infinity, alignment: .leading)


        }
        .overlayPreferenceValue(DrawerTopKey.self) { anchors in
            followsDrawer(d, top: anchors.first)
        }
        .mapScope(mapScope)
    }

    func layerMenu(_ d: MapSpineData) -> some View {
        Menu {
            ForEach(MapSpineLayer.allCases) { l in
                Button {
                    TokensHaptic.select()
                    layerRaw = l.rawValue
                } label: {
                    Label(l.title, systemImage: l == layer ? "checkmark.circle.fill" : "circle")
                }
            }
            Divider()
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
            if sizeClass == .regular {
                Button {
                    TokensHaptic.tap()
                    openWindow(id: SceneID.detail)
                } label: {
                    Label("新车况窗口", systemImage: "rectangle.on.rectangle")
                }
            }
        } label: {
            HStack(spacing: TokensSpacing.xs) {
                Text(layer.title)
                    .font(TokensTypo.caption)
                    .tracking(TokensTracking.label)
                Image(safeSymbol: "chevron.up.chevron.down", fallback: "chevron.down")
                    .font(TokensTypo.micro)
            }
            .foregroundStyle(TokensPalette.accent)
            .padding(.horizontal, TokensSpacing.snug)
            .padding(.vertical, TokensSpacing.xs)
            .background(Capsule().fill(TokensPalette.fillSubtle))
            .overlay(Capsule().strokeBorder(TokensPalette.hairline,
                                            lineWidth: TokensHair.border))
            .contentShape(Capsule())
        }
        .accessibilityLabel(Text("图层：\(layer.title)"))
        .accessibilityHint(Text("点开：看哪一层、重取数据、此刻的光、回到车"))
    }


    private func lightTitle(_ d: MapSpineData) -> String {
        guard let sky = d.sky(at: skyDate) else { return "此刻的光" }
        return "此刻的光 · \(sky.phase.title)"
    }


    @ViewBuilder
    private func pageContent(_ mode: HomeMode) -> some View {
        switch mode {
        case .now: EmptyView()
        case .vehicle: VehicleView()
        case .charge: ChargeView()
        case .control: ControlView()
        case .trips: TripsEventsView()
        case .mine: MineView()
        }
    }








    func emptyNotice(_ text: String) -> some View { MapNotice(text: text) }

    @MainActor
    private func focusOn(_ f: AppStore.MapFocus) {
        withAnimation(TokensMotion.value) {
            camera = .camera(MapCamera(centerCoordinate: CLLocationCoordinate2D(latitude: f.lat,
                                                                              longitude: f.lng),
                                       distance: cameraDistance * 1.6,
                                       pitch: cameraPitch))
        }
        didCenterOnce = true
        ToastManager.shared.show(f.label.isEmpty ? "已移到事件位置" : f.label,
                                 icon: "mappin.and.ellipse")
        store.mapFocus = nil
    }


    @MainActor
    private func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        await store.fetchCore()
        isRefreshing = false
    }


    @MainActor
    private func searchChargersIfNeeded(force: Bool = false) async {
        guard let car = store.currentLocation else {
            return
        }
        let key = String(format: "%.4f,%.4f", car.coordinate.latitude, car.coordinate.longitude)
        if !force, key == chargerCenterKey, !chargers.isEmpty { return }
        chargerCenterKey = key

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "充电站"
        request.region = MKCoordinateRegion(center: car.coordinate,
                                            latitudinalMeters: 8000,
                                            longitudinalMeters: 8000)
        let search = MKLocalSearch(request: request)
        guard let response = try? await search.start() else {
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
        chargers = Array(sorted.prefix(60))
    }
}

