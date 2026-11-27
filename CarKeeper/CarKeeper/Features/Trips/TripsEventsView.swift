
import SwiftUI
import MapKit

private let tripCardStep: Int = 5

private let tripCardCap: Int = 30

struct TripsEventsView: View {
    private let store = AppStore.shared
    @ObservedObject private var routes = RouteService.shared

    @State private var shownTrips = tripCardStep

    @State private var eventDays = 3

    @State private var flippedTrip: Double? = nil

    @State private var tab: HomeSub = .journeys

    private var trips: [AppStore.TripRecord] {
        store.tripHistory.sorted { $0.startTime > $1.startTime }
    }

    private var hotspots: [MapHotspot] {
        MapSpineData.clusterHotspots(from: store.parkingHistory, excluding: store.parkingLocation)
    }

    private var tripsFromMessages: [AppStore.TripRecord] {
        let raw = store.caches["messages"] as? [[String: Any]] ?? []
        return TripBuilder.displayTrips(from: TripBuilder.events(from: raw))
    }

    private var displayTrips: [AppStore.TripRecord] {
        TripBuilder.merge(fromMessages: tripsFromMessages, stored: trips)
    }

    private func loadMoreTrips() {
        guard shownTrips < tripCardCap else { return }
        shownTrips = min(shownTrips + tripCardStep, tripCardCap)
    }

    private func moreTripsNote(_ rest: Int) -> some View {
        HStack(spacing: TokensSpacing.sm) {
            Image(safeSymbol: "arrow.down.circle", fallback: "arrow.down.circle")
                .font(TokensTypo.footnote)
                .foregroundStyle(TokensPalette.tertiary)
            Text("往下滑，剩下的 \(rest) 段接着出来")
                .font(TokensTypo.footnote)
                .foregroundStyle(TokensPalette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func restAsMessagesRow(_ rest: Int) -> some View {
        VStack(alignment: .leading, spacing: TokensSpacing.xs) {
            Text("再往前的 \(rest) 段在「事件」那一段里，按时间列着。")
                .font(TokensTypo.footnote)
                .foregroundStyle(TokensPalette.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("每一段在这里都会占一张地图，所以封顶 30 段。")
                .font(TokensTypo.caption)
                .foregroundStyle(TokensPalette.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @MainActor
    private var cards: [StackCard] {
        var out = HomeMode.trips.headCards
        out.append(StackCard(id: "tabs", content: AnyView(
            DSSegmentPicker(options: HomeSub.tripsTabs.map { (value: $0, title: $0.title) },
                            selection: $tab,
                            label: "段落"))))
        switch tab {
        case .events:
            out.append(StackCard(id: "events", title: "车的事件",
                                 content: AnyView(MessagesSection(shownDays: $eventDays))))
        default:
            out.append(contentsOf: journeyCards)
        }
        return out
    }

    @MainActor
    private var journeyCards: [StackCard] {
        var out: [StackCard] = []
        let list = displayTrips
        let visible = Array(list.prefix(min(shownTrips, tripCardCap)))
        if list.isEmpty {
            out.append(StackCard(id: "empty", content: AnyView(emptyState)))
        } else {
            out.append(StackCard(id: "summary", title: "总览",
                                 at: store.cacheTime("messages"),
                                 content: AnyView(summaryHeader(list))))
            for (idx, trip) in visible.enumerated() {
                let isLast = idx == visible.count - 1 && visible.count == list.count
                out.append(StackCard(id: "trip-\(idx)", title: "行程",
                                     value: String(format: "%.1f km", trip.distanceKm), cls: "ok",
                                     content: AnyView(timelineRow(trip, isLast: isLast))))
            }
            if visible.count < min(list.count, tripCardCap) {
                let rest = min(list.count, tripCardCap) - visible.count
                out.append(StackCard(id: "more-trips", title: "还有 \(rest) 段",
                                     content: AnyView(moreTripsNote(rest))))
            } else if list.count > tripCardCap {
                out.append(StackCard(id: "rest-as-messages", title: "更早的 \(list.count - tripCardCap) 段",
                                     content: AnyView(restAsMessagesRow(list.count - tripCardCap))))
            }
            if !hotspots.isEmpty {
                out.append(StackCard(id: "hotspots", title: "常停之地",
                                     content: AnyView(hotspotsBand(hotspots))))
            }
        }
        out.append(StackCard(id: "score", title: "评分", content: AnyView(ScoreSection())))
        return out
    }

    private var reachBottom: (() -> Void)? {
        tab == .journeys ? { loadMoreTrips() } : { loadMoreEventDays() }
    }

    private func loadMoreEventDays() {
        eventDays += 3
    }

    var body: some View {
        StackPageView(accent: HomeMode.trips.accent, label: "出行", cards: cards,
                      onReachBottom: reachBottom)
        .dsPageTitle("出行")
        .accessibilityLabel(Text("出行"))
    }

    private var emptyState: some View {
        VStack(spacing: TokensSpacing.md) {
            Image(safeSymbol: "point.topleft.down.to.point.bottomright.curvepath",
                            fallback: "point.topleft.down.to.point.bottomright.curvepath")
                .font(TokensTypo.fixed(34, weight: .light))
                .foregroundStyle(TokensPalette.tertiary)
            Text("还没有行程记录")
                .font(TokensTypo.headline)
                .foregroundStyle(TokensPalette.primary)
            Text("点火与熄火各记一次，配成一段行程。")
                .font(TokensTypo.footnote)
                .foregroundStyle(TokensPalette.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, TokensSpacing.xxl)
    }

    private func summaryHeader(_ trips: [AppStore.TripRecord]) -> some View {
        let totalKm = trips.reduce(0) { $0 + $1.distanceKm }
        let effs = trips.compactMap(\.avgEfficiency)
        let avgEff = effs.isEmpty ? nil : effs.reduce(0, +) / Double(effs.count)
        return VStack(alignment: .leading, spacing: TokensSpacing.xs) {
            Text("全部 \(trips.count) 段行程")
                .font(TokensTypo.footnote)
                .foregroundStyle(TokensPalette.secondary)
            HStack(alignment: .firstTextBaseline, spacing: TokensSpacing.sm) {
                Text(String(format: "%.0f", totalKm))
                    .font(TokensTypo.digits(56))
                    .foregroundStyle(TokensPalette.primary)
                Text("km 合计")
                    .font(TokensTypo.footnote)
                    .foregroundStyle(TokensPalette.tertiary)
                Spacer(minLength: 0)
                if let eff = avgEff {
                    Text(String(format: "均耗 %.1f", eff))
                        .font(TokensTypo.digits(15))
                        .foregroundStyle(TokensPalette.secondary)
                }
            }
        }
        .padding(.bottom, TokensSpacing.lg)
    }

    private func timelineRow(_ trip: AppStore.TripRecord, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: TokensSpacing.md) {
            VStack(spacing: 0) {
                Circle()
                    .fill(TokensPalette.accent)
                    .frame(width: 9, height: 9)
                if !isLast {
                    Rectangle()
                        .fill(TokensPalette.hairline)
                        .frame(width: 1.5)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 9)

            tripFlip(trip)
        }
        .padding(.bottom, TokensSpacing.xl)
    }

    @ViewBuilder
    private func tripFlip(_ trip: AppStore.TripRecord) -> some View {
        let key = trip.startTime.timeIntervalSince1970
        let flipped = flippedTrip == key
        tripBack(trip)
            .opacity(flipped ? 1 : 0)
            .rotation3DEffect(.degrees(flipped ? 0 : -180), axis: (x: 0, y: 1, z: 0))
            .overlay {
                tripFront(trip)
                    .opacity(flipped ? 0 : 1)
                    .rotation3DEffect(.degrees(flipped ? 180 : 0), axis: (x: 0, y: 1, z: 0))
            }
        .contentShape(Rectangle())
        .onTapGesture {
            TokensHaptic.tap()
            withAnimation(TokensMotion.value) { flippedTrip = flipped ? nil : key }
        }
        .accessibilityElement(children: .contain)
        .accessibilityHint(Text("点一下翻到背面看详情"))
        .accessibilityAction { flippedTrip = flipped ? nil : key }
    }

    private func tripFront(_ trip: AppStore.TripRecord) -> some View {
        VStack(alignment: .leading, spacing: TokensSpacing.sm) {
            headerText(trip)
            MiniTripMap(from: trip.startLocation?.coordinate, to: trip.endLocation?.coordinate)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 132, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: TokensRadius.medium, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: TokensRadius.medium, style: .continuous)
                        .strokeBorder(TokensPalette.hairline, lineWidth: 0.5)
                )
            placeNamesRow(trip)
            statsRow(trip)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func placeNamesRow(_ trip: AppStore.TripRecord) -> some View {
        if !trip.startAddr.isEmpty || !trip.endAddr.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: TokensSpacing.xs) {
                Text(trip.startAddr.isEmpty ? "起点未知" : trip.startAddr)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(safeSymbol: "arrow.right", fallback: "arrow.right")
                    .font(TokensTypo.caption2)
                    .foregroundStyle(TokensPalette.tertiary)
                Text(trip.endAddr.isEmpty ? "终点未知" : trip.endAddr)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .font(TokensTypo.caption)
            .foregroundStyle(TokensPalette.secondary)
        }
    }

    private func tripBack(_ trip: AppStore.TripRecord) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            headerText(trip)
            DSDivider()
            DSKeyValueRow(key: "出发", value: trip.startTime.formatted(date: .omitted, time: .shortened))
            DSDivider()
            DSKeyValueRow(key: "到达",
                          value: trip.endTime.map { $0.formatted(date: .omitted, time: .shortened) }
                                 ?? "还没熄火")
            DSDivider()
            DSKeyValueRow(key: "时长", value: trip.durationText)
            DSDivider()
            DSKeyValueRow(key: "两点直线", value: String(format: "%.1f km", trip.distanceKm))
            if let road = roadRoute(trip) {
                DSDivider()
                DSKeyValueRow(key: "路线长度",
                              value: String(format: "%.1f km", road.distanceMeters / 1000))
            }
            if !trip.startAddr.isEmpty {
                DSDivider()
                DSKeyValueRow(key: "起点", value: trip.startAddr)
            }
            if !trip.endAddr.isEmpty {
                DSDivider()
                DSKeyValueRow(key: "终点", value: trip.endAddr)
            }
            if let kmPerPct = trip.kmPerPercent {
                DSDivider()
                DSKeyValueRow(key: "每 1% 电量", value: String(format: "%.2f km", kmPerPct))
            }
            if let eff = trip.avgEfficiency {
                DSDivider()
                DSKeyValueRow(key: "平均能耗", value: String(format: "%.1f kWh/100km", eff))
            }
        }
    }

    private func headerText(_ trip: AppStore.TripRecord) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(dayText(trip.startTime))
                .font(TokensTypo.subheadline)
                .foregroundStyle(TokensPalette.primary)
            Spacer(minLength: 0)
            Text(trip.durationText)
                .font(TokensTypo.caption)
                .foregroundStyle(TokensPalette.tertiary)
        }
    }

    private func dayText(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "今天 " + date.formatted(date: .omitted, time: .shortened) }
        if cal.isDateInYesterday(date) { return "昨天 " + date.formatted(date: .omitted, time: .shortened) }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private func statsRow(_ trip: AppStore.TripRecord) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: TokensSpacing.md) {
            Text(String(format: "%.1f km", trip.distanceKm))
                .font(TokensTypo.digits(17))
                .foregroundStyle(TokensPalette.primary)
            Text("直线")
                .font(TokensTypo.caption2)
                .foregroundStyle(TokensPalette.tertiary)
            Spacer(minLength: 0)
            if let eff = trip.avgEfficiency {
                Text(String(format: "%.1f kWh/100km", eff))
                    .font(TokensTypo.caption)
                    .foregroundStyle(TokensPalette.tertiary)
            } else if let kmPerPct = trip.kmPerPercent {
                Text(String(format: "%.1f km / 1%% 电量", kmPerPct))
                    .font(TokensTypo.caption)
                    .foregroundStyle(TokensPalette.tertiary)
            }
            Image(safeSymbol: "arrow.triangle.2.circlepath", fallback: "arrow.triangle.2.circlepath")
                .font(TokensTypo.caption2)
                .foregroundStyle(TokensPalette.tertiary)
                .accessibilityHidden(true)
        }
    }

    private func roadRoute(_ trip: AppStore.TripRecord) -> RouteService.Route? {
        guard let a = trip.startLocation?.coordinate, let b = trip.endLocation?.coordinate else {
            return nil
        }
        return routes.cached(from: a, to: b)
    }

    private func hotspotsBand(_ spots: [MapHotspot]) -> some View {
        VStack(alignment: .leading, spacing: TokensSpacing.sm) {
            ForEach(spots.prefix(3)) { s in
                HStack(alignment: .firstTextBaseline) {
                    Image(safeSymbol: "mappin.circle.fill", fallback: "mappin.circle.fill")
                        .font(TokensTypo.fixed(13))
                        .foregroundStyle(TokensPalette.accent)
                    Text("\(s.visits) 次")
                        .font(TokensTypo.footnote)
                        .foregroundStyle(TokensPalette.primary)
                    Spacer(minLength: 0)
                    Text(MapSpineData.agoText(s.lastVisit))
                        .font(TokensTypo.caption)
                        .foregroundStyle(TokensPalette.tertiary)
                }
            }
            Text("停车史聚类（±80 米算同一处）")
                .font(TokensTypo.caption)
                .foregroundStyle(TokensPalette.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, TokensSpacing.lg)
    }
}


struct MiniTripMap: View {
    let from: CLLocationCoordinate2D?
    let to: CLLocationCoordinate2D?

    @State private var road: [CLLocationCoordinate2D] = []
    @State private var tried = false

    @State private var camera: MapCameraPosition = .automatic

    var body: some View {
        if let a = from, let b = to {
            Map(position: $camera) {
                let pts = line(a, b)
                MapPolyline(MKPolyline(coordinates: pts, count: pts.count))
                    .stroke(TokensPalette.accent.opacity(0.9),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round))
                Annotation("", coordinate: a) { endpoint("起", TokensPalette.success) }
                Annotation("", coordinate: b) { endpoint("终", TokensPalette.accent) }
            }
            .mapStyle(.standard(elevation: .flat, emphasis: .muted,
                                pointsOfInterest: .excludingAll, showsTraffic: false))
            .allowsHitTesting(false)
            .task(id: routeKey(a, b)) {
                tried = false
                camera = fit(a, b)
                road = await RouteService.shared.route(from: a, to: b)?.points ?? []
                tried = true
                camera = fit(a, b)
            }
            .overlay(alignment: .bottomLeading) { fallbackNote }
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: TokensRadius.medium, style: .continuous)
                    .fill(TokensPalette.panel)
                Text("这一段没有记录坐标")
                    .font(TokensTypo.caption)
                    .foregroundStyle(TokensPalette.tertiary)
            }
        }
    }

    private func line(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> [CLLocationCoordinate2D] {
        road.count > 1 ? road : [a, b]
    }

    private func fit(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> MapCameraPosition {
        let pts = line(a, b)
        let lats = pts.map(\.latitude)
        let lngs = pts.map(\.longitude)
        let minLat = lats.min() ?? a.latitude, maxLat = lats.max() ?? a.latitude
        let minLng = lngs.min() ?? a.longitude, maxLng = lngs.max() ?? a.longitude
        let midLat = (minLat + maxLat) / 2
        let midLng = (minLng + maxLng) / 2
        let spanLat = (maxLat - minLat) * 111_000
        let spanLng = (maxLng - minLng) * 111_000 * max(0.2, cos(midLat * .pi / 180))
        return .camera(MapCamera(
            centerCoordinate: CLLocationCoordinate2D(latitude: midLat, longitude: midLng),
            distance: max(max(spanLat, spanLng) * 2.4, 900),
            heading: 0,
            pitch: 0))
    }

    @ViewBuilder
    private var fallbackNote: some View {
        if tried && road.isEmpty {
            Text("线是两点连线")
                .font(TokensTypo.caption2)
                .foregroundStyle(TokensPalette.secondary)
                .padding(.horizontal, TokensSpacing.xs)
                .padding(.vertical, TokensSpacing.xxs)
                .background(TokensPalette.panel, in: Capsule())
                .padding(TokensSpacing.xs)
        }
    }

    private func endpoint(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(TokensTypo.fixed(11, weight: .bold))
            .foregroundStyle(TokensPalette.labelOnTint)
            .frame(width: 20, height: 20)
            .background(Circle().fill(color))
            .overlay(Circle().strokeBorder(TokensPalette.surface, lineWidth: 2))
    }

    private func routeKey(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> String {
        String(format: "%.5f,%.5f>%.5f,%.5f", a.latitude, a.longitude, b.latitude, b.longitude)
    }
}
