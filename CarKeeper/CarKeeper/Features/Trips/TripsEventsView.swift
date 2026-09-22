// =============================================================================
// TripsEventsView — 出行：一条时间轴，每一段都长在地图上，下面是常停之地与车的事件
// =============================================================================
//
// 取代旧 TripAnalyticsView（分段柱状图 + 汇总卡）之后，这一屏回答的问题变了：
//   旧：「这段时间开了多少」→ 一个大数字加一张柱状图
//   新：「我的时间花在哪些路上」→ 时间轴上每段行程配一张真地图，
//       常停的地方聚成圈（与地图主屏同一套聚类，同一个答案）
//
// 数据事实（不美化）：
//   • TripRecord 只有起终点两个坐标 —— 线是连线，不是轨迹；地图窗口框住两地
//   • 没有行程时整屏只有一句真话，不摆 0 km 冒充统计
// =============================================================================

import SwiftUI
import MapKit

/// 出行 —— 每一次出行的时间轴 + 常停的地方 + 车发来的事件。
///
/// 原为「行程」页（`TripsTimelineView`）。批 7 把「消息」吸收进来：
/// 消息流里的 IGNITION / FLAMEOUT 事件本来就是行程的骨架，两页读的是同一件事。
struct TripsEventsView: View {
    private let store = AppStore.shared

    private var trips: [AppStore.TripRecord] {
        store.tripHistory.sorted { $0.startTime > $1.startTime }
    }

    private var hotspots: [MapHotspot] {
        MapSpineData.clusterHotspots(from: store.parkingHistory, excluding: store.parkingLocation)
    }

    /// 从消息缓存里的 IGNITION / FLAMEOUT 事件直接配成行程（不等 ingestEvents）。
    /// 数据源与 `store.tripHistory` 是**同一件事**，但这里多一个好处：
    /// 消息一拉到手就能渲染，不依赖 `fetchVehicleData()` 的触发时机。
    private var tripsFromMessages: [AppStore.TripRecord] {
        let raw = store.caches["messages"] as? [[String: Any]] ?? []
        guard !raw.isEmpty else { return [] }
        // 复用 AppStore 里已有的现成方法：跳去、配对、写进 tripHistory
        // —— 不行，那会改全局状态。这里只做「展示用」的临时配对，不写。
        let events: [(ignition: Bool, at: Date, loc: CLLocationCoordinate2D?, addr: String)] = raw
            .compactMap { m -> (Bool, Date, CLLocationCoordinate2D?, String)? in
                guard let kind = ciString(m, ["InfoTypeId", "infoTypeId"])?.uppercased(),
                      kind == "IGNITION" || kind == "FLAMEOUT" else { return nil }
                let p = AppStore.jumpParams(m)
                guard let at = VM.serverDate(p["gpsTime"]) ?? VM.serverDate(ciPick(m, ["CreatedAt", "createdAt"])) else { return nil }
                var loc: CLLocationCoordinate2D?
                if let lat = VM.vnum(p["lat"]), let lng = VM.vnum(p["lng"]) {
                    loc = CLLocationCoordinate2D(latitude: lat, longitude: lng)
                }
                let addr = (p["addrName"] as? String) ?? ""
                return (kind == "IGNITION", at, loc, addr)
            }
            .sorted { $0.at < $1.at }

        // 点火 → 下一个熄火 = 一段行程（里程差 = 两点直线距离，只有 GPS 时才真）
        var out: [AppStore.TripRecord] = []
        var open: (ignitionAt: Date, ignitionLoc: CLLocationCoordinate2D?, ignitionAddr: String)?
        for e in events {
            if e.ignition {
                open = (e.at, e.loc, e.addr)
            } else if let o = open {
                let dist: Double = {
                    guard let a = o.ignitionLoc, let b = e.loc else { return 0 }
                    let m1 = CLLocation(latitude: a.latitude, longitude: a.longitude)
                    let m2 = CLLocation(latitude: b.latitude, longitude: b.longitude)
                    return m1.distance(from: m2) / 1000
                }()
                out.append(AppStore.TripRecord(
                    startTime: o.ignitionAt, endTime: e.at,
                    startLocation: o.ignitionLoc.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) },
                    endLocation: e.loc.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) },
                    distanceKm: dist,
                    startSoc: 0, endSoc: 0,
                    avgEfficiency: nil, kmPerPercent: nil))
                open = nil
            }
        }
        // 只有点着火还没熄火的：也展示（进行中的一段）
        if let o = open {
            out.append(AppStore.TripRecord(
                startTime: o.ignitionAt, endTime: nil,
                startLocation: o.ignitionLoc.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) },
                endLocation: nil,
                distanceKm: 0,
                startSoc: 0, endSoc: 0,
                avgEfficiency: nil, kmPerPercent: nil))
        }
        return out
    }

    /// 展示用的行程：本机记录的优先；如果本机还是空，从消息直接配出。
    private var displayTrips: [AppStore.TripRecord] {
        !trips.isEmpty ? trips : tripsFromMessages
    }

    var body: some View {
        // 出行只有一张画布：行程在上、常停之地在中间、车的事件在下。
        DSPaperPage {
            DSPageTitle(title: "出行", subtitle: "每一次出行、常停的地方，以及车发来的事件")

            if displayTrips.isEmpty {
                emptyState
            } else {
                summaryHeader(displayTrips)
                ForEach(Array(displayTrips.enumerated()), id: \.element.id) { idx, trip in
                    timelineRow(trip, isLast: idx == displayTrips.count - 1)
                }
                if !hotspots.isEmpty {
                    hotspotsBand(hotspots)
                }
            }

            // 分数：完全由上面那些行程的电耗算出来（原「驾驶评分」页）
            ScoreSection()
                .padding(.top, TokensSpacing.xl)

            // 车的事件：点火/熄火/控制记录（原「消息」页）
            MessagesSection()
                .padding(.top, TokensSpacing.xl)
        }
        .pageBackground()
        .dsPageTitle("出行")
        .accessibilityLabel(Text("出行"))
    }

    // ---- 空态：一句真话，不放假统计 ----
    private var emptyState: some View {
        VStack(spacing: TokensSpacing.md) {
            Image(safeSymbol: "point.topleft.down.to.point.bottomright.curvepath", fallback: "point.topleft.down.to.point.bottomright.curvepath")
                .font(TokensTypo.fixed(34, weight: .light))
                .foregroundStyle(TokensPalette.tertiary)
            Text("还没有行程记录")
                .font(TokensTypo.headline)
                .foregroundStyle(TokensPalette.primary)
            Text("开始行驶后，每一次出行都会落在这条时间轴上。")
                .font(TokensTypo.footnote)
                .foregroundStyle(TokensPalette.secondary)
                .multilineTextAlignment(.center)
        }
        // 不再吃掉整屏高度：它下面还有「车的事件」这一节
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
            // 时间轴轴线：圆点 + 向下延伸的发丝线
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

            VStack(alignment: .leading, spacing: TokensSpacing.sm) {
                headerText(trip)
                MiniTripMap(from: trip.startLocation?.coordinate, to: trip.endLocation?.coordinate)
                    .frame(height: 132)
                    .clipShape(RoundedRectangle(cornerRadius: TokensRadius.medium, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: TokensRadius.medium, style: .continuous)
                            .strokeBorder(TokensPalette.hairline, lineWidth: 0.5)
                    )
                statsRow(trip)
            }
        }
        .padding(.bottom, TokensSpacing.xl)
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
            Text("\(max(0, trip.startSoc - trip.endSoc))% 电量")
                .font(TokensTypo.caption)
                .foregroundStyle(TokensPalette.secondary)
            Spacer(minLength: 0)
            // 能效只显示**算得出来**的那个：kWh/100km 需要电池容量（报文里 capacity 是 null），
            // 所以实际先用「每 1% SOC 跑多少 km」——它不需要容量，是行程里真实读到的事实。
            if let eff = trip.avgEfficiency {
                Text(String(format: "%.1f kWh/100km", eff))
                    .font(TokensTypo.caption)
                    .foregroundStyle(TokensPalette.tertiary)
            } else if let kmPerPct = trip.kmPerPercent {
                Text(String(format: "每 1%% 电量 %.1f km", kmPerPct))
                    .font(TokensTypo.caption)
                    .foregroundStyle(TokensPalette.tertiary)
            }
        }
    }

    /// 常停热区与地图主屏是**同一套聚类** —— 两处必须是同一个答案
    private func hotspotsBand(_ spots: [MapHotspot]) -> some View {
        VStack(alignment: .leading, spacing: TokensSpacing.sm) {
            DSSectionHeader(title: "常来之地")
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
            Text("从停车记录聚类得出（±80 米算同一处）；地图「停车」层上画着它们的圈。")
                .font(TokensTypo.caption)
                .foregroundStyle(TokensPalette.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, TokensSpacing.lg)
    }
}

// =============================================================================
//  每段行程的真地图：起点 → 终点两点一线
// =============================================================================

/// 一次行程的迷你地图。**线是起终点连线，不是轨迹** —— TripRecord 没有逐点坐标。
/// 相机取「恰好框住两点」：中点为心，距离按纬度/经度跨度换算成米取大者；
/// 任何一端缺失就整个不画（不假装知道车开过哪）。
struct MiniTripMap: View {
    let from: CLLocationCoordinate2D?
    let to: CLLocationCoordinate2D?

    var body: some View {
        if let a = from, let b = to {
            Map(position: .constant(.camera(MapCamera(
                centerCoordinate: CLLocationCoordinate2D(
                    latitude: (a.latitude + b.latitude) / 2,
                    longitude: (a.longitude + b.longitude) / 2),
                distance: fitDistance(a, b),
                heading: 0,
                pitch: 0)))) {
                MapPolyline(MKPolyline(coordinates: [a, b], count: 2))
                    .stroke(TokensPalette.accent.opacity(0.9),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round))
                Annotation("起点", coordinate: a) { dot(TokensPalette.tertiary) }
                Annotation("终点", coordinate: b) { dot(TokensPalette.accent) }
            }
            .mapStyle(.standard(elevation: .flat, emphasis: .muted,
                                pointsOfInterest: .excludingAll, showsTraffic: false))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: TokensRadius.medium, style: .continuous)
                    .fill(TokensPalette.raised)
                Text("这一段没有记录坐标")
                    .font(TokensTypo.caption)
                    .foregroundStyle(TokensPalette.tertiary)
            }
        }
    }

    /// 把两点框进画面所需的视距（米）。纬度差按 111 km/度换算；经度差乘 cos(纬度)。
    private func fitDistance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let latMeters = abs(b.latitude - a.latitude) * 111_000
        let lngMeters = abs(b.longitude - a.longitude) * 111_000
            * max(0.2, cos(a.latitude * .pi / 180))
        let span = max(latMeters, lngMeters)
        // 两点重合或几乎没动：退到能看清两个钉的默认视距
        return max(span * 2.4, 900)
    }

    private func dot(_ color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: 10, height: 10)
            .overlay(Circle().strokeBorder(TokensPalette.surface, lineWidth: 2))
    }
}
