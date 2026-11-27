import SwiftUI



struct DrawerTopKey: PreferenceKey {
    static let defaultValue: [Anchor<CGRect>] = []
    static func reduce(value: inout [Anchor<CGRect>], nextValue: () -> [Anchor<CGRect>]) {
        value.append(contentsOf: nextValue())
    }
}

struct DrawerHandle {
    let reveal: Binding<CGFloat>
    let height: CGFloat
    let open: Bool
    let toggle: () -> Void
    let land: (_ open: Bool) -> Void
}

struct MapNowDrawer<Head: View, Content: View>: View {
    @Binding var open: Bool
    private let head: (DrawerHandle) -> Head
    private let content: () -> Content

    @State private var reveal: CGFloat = 0
    @State private var bodyHeight: CGFloat = 0

    init(open: Binding<Bool>,
         @ViewBuilder head: @escaping (DrawerHandle) -> Head,
         @ViewBuilder content: @escaping () -> Content) {
        _open = open
        self.head = head
        self.content = content
    }

    var body: some View {
        GlassCard(accent: HomeMode.now.accent) {
            VStack(alignment: .leading, spacing: 0) {
                head(handle)
                content()
                    .fixedSize(horizontal: false, vertical: true)
                    .background(alignment: .top) { measure }
                    .frame(height: max(0, bodyHeight * reveal), alignment: .top)
                    .clipped()
            }
        }
        .anchorPreference(key: DrawerTopKey.self, value: .bounds) { [$0] }
        .onAppear { reveal = open ? 1 : 0 }
        .onChange(of: open) { _, want in
            guard (want ? 1 : 0) != reveal else { return }
            withAnimation(TokensMotion.settle) { reveal = want ? 1 : 0 }
        }
    }

    private var handle: DrawerHandle {
        DrawerHandle(reveal: $reveal,
                     height: bodyHeight,
                     open: open,
                     toggle: { land(!open) },
                     land: { land($0) })
    }

    private func land(_ next: Bool) {
        withAnimation(TokensMotion.settle) {
            open = next
            reveal = next ? 1 : 0
        }
    }

    private var measure: some View {
        GeometryReader { g in
            Color.clear
                .onAppear { bodyHeight = g.size.height }
                .onChange(of: g.size.height) { _, h in
                    if abs(h - bodyHeight) > 0.5 { bodyHeight = h }
                }
        }
    }
}

extension MapSpineView {


    @ViewBuilder
    func nowCard(_ d: MapSpineData) -> some View {
        MapNowDrawer(open: $drawerOpen) { handle in
            drawerHead(d, handle: handle)
        } content: {
            drawerContent(d)
        }
    }

    @ViewBuilder
    func drawerContent(_ d: MapSpineData) -> some View {
        VStack(alignment: .leading, spacing: TokensSpacing.lg) {
            HStack(alignment: .center, spacing: TokensSpacing.sm) {
                drawerSub(d)
                Spacer(minLength: TokensSpacing.sm)
                layerMenu(d)
            }
            switch layer {
            case .now:
                if d.hasLocation == false {
                    emptyNotice(MapSpineLayer.now.emptyNote)
                } else {
                    nowMetrics(d)
                }
                readoutsDrawer(d)
            case .trips: tripsContent(d)
            case .holds: holdsContent(d)
            case .charge: chargeContent(d)
            }
        }
        .padding(.top, TokensSpacing.lg)
    }

    @ViewBuilder
    func nowMetrics(_ d: MapSpineData) -> some View {
        if !d.address.isEmpty {
            Text(d.address)
                .font(TokensTypo.fixed(22))
                .tracking(TokensTracking.title)
                .foregroundStyle(TokensPalette.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        DSLightBar(progress: Double(d.socPct) / 100,
                   height: 5,
                   tint: TokensPalette.lightBar)
    }

    @ViewBuilder
    func drawerSub(_ d: MapSpineData) -> some View {
        let mileage = VM.vehicleSummary(store.car, store.controlCache)?.mileage
        let line = Self.join([mileage.map { "表显 \($0) km" },
                              d.chargeText])
        if !line.isEmpty {
            Text(line)
                .font(TokensTypo.caption)
                .foregroundStyle(TokensPalette.tertiary)
        }
    }

    private static func join(_ parts: [String?]) -> String {
        parts.compactMap { $0 }
            .filter { !$0.isEmpty && $0 != "--" }
            .joined(separator: " · ")
    }
}
