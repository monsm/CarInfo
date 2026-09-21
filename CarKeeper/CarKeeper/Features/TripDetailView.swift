// =============================================================================
// TripDetailView —— 行程详情页（坐标轨迹 + 能耗分析 + 驾驶评分）
// =============================================================================

import SwiftUI
import MapKit

extension Date {
    var durationText: String {
        let hours = Int(timeIntervalSince1970 / 3600)
        let minutes = Int(timeIntervalSince1970.truncatingRemainder(dividingBy: 3600) / 60)
        return hours > 0 ? "\(hours)h\(minutes)m" : "\(minutes)m"
    }
}

/// 时长格式化（行程详情用）
enum DurationFormatter {
    static func string(from interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        return hours > 0 ? "\(hours) 小时 \(minutes) 分" : "\(minutes) 分钟"
    }
}

struct TripDetailView: View {
    let store = AppStore.shared
    let trip: TripRecord
    @State private var mapCenter = CLLocationCoordinate2D(latitude: 39.9, longitude: 107.0)
    @State private var span = MKCoordinateSpan(latitudeDelta: 2, longitudeDelta: 2)
    @State private var showMap = false

    private let distanceFormatter: LengthFormatter = {
        let f = LengthFormatter()
        f.unitStyle = .short
        f.numberFormatter.minimumFractionDigits = 1
        return f
    }()

    private let speedFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f
    }()

    var avgSpeed: Double {
        let hours = max((trip.endTime ?? Date()).timeIntervalSince(trip.startTime) / 3600, 0.1)
        return trip.distanceKm / hours
    }

    var efficiencyText: String {
        if let eff = trip.avgEfficiency {
            return String(format: "%.1f kWh/100km", eff)
        }
        return "—"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 概览卡片
                overviewCard

                // 地图
                if trip.startLocation != nil || trip.endLocation != nil {
                    mapCard
                }

                // 能耗详情
                energyCard

                // 驾驶行为
                drivingCard

                // 时间线
                timelineCard
            }
            .padding(.horizontal, TokensSpacing.lg)
            .padding(.vertical, TokensSpacing.md)
        }
        .background(TokensPalette.background)
        .navigationTitle("行程详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: shareTrip) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .accessibilityLabel(Text("行程详情"))
        .accessibilityHint(Text("查看行程距离、能耗和驾驶评分"))
    }

    // MARK: - 概览
    private var overviewCard: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(trip.startTime, style: .date)
                        .font(TokensTypo.caption)
                        .foregroundStyle(.secondary)
                    Text(trip.startTime, style: .time)
                        .font(TokensTypo.subheadline)
                        .foregroundStyle(.primary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(DurationFormatter.string(
                        from: max((trip.endTime ?? Date()).timeIntervalSince(trip.startTime), 1)))
                        .font(TokensTypo.caption)
                        .foregroundStyle(.secondary)
                    Text(trip.startTime, style: .date)
                        .font(TokensTypo.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider().opacity(0.3)

            HStack(spacing: 20) {
                statItem(icon: "figure.walk", value: String(format: "%.1f", trip.distanceKm), unit: "km", label: "里程")
                statItem(icon: "bolt.fill", value: "\(trip.socChange)%", unit: "", label: "SOC变化")
                statItem(icon: "bolt.fill", value: efficiencyText, unit: "", label: "能耗")
            }
        }
        .padding()
        .glassCard(corner: TokensRadius.medium)
    }

    private func statItem(icon: String, value: String, unit: String, label: String) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(safeSymbol: icon, fallback: "gauge")
                    .font(.caption)
                    .foregroundStyle(TokensPalette.ambient)
                Text(value)
                    .font(TokensTypo.metric(22))
                    .foregroundStyle(.primary)
                if !unit.isEmpty {
                    Text(unit)
                        .font(TokensTypo.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - 地图
    private var mapCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "map.fill")
                    .font(.caption)
                    .foregroundStyle(TokensPalette.ambient)
                Text("行驶路线")
                    .font(Theme.font(.subheadline as Font).bold())
                Spacer()
                Button(action: { showMap.toggle() }) {
                    Text(showMap ? "收起" : "展开")
                        .font(.caption)
                        .foregroundStyle(TokensPalette.ambient)
                }
            }

            if showMap, let start = trip.startLocation, let end = trip.endLocation {
                MapView(coordinate: mapCenter, span: span, points: [start.coordinate, end.coordinate])
                    .frame(height: 200)
                    .cornerRadius(TokensRadius.small)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "map.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary.opacity(0.5))
                    Text("无GPS轨迹数据")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(height: 120)
                .glassCard(corner: TokensRadius.small)
            }

            // 起点/终点信息
            HStack {
                if let loc = trip.startLocation {
                    locationChip(icon: "house.fill", text: "起点", coord: loc)
                }
                Spacer()
                if let loc = trip.endLocation {
                    locationChip(icon: "mappin.fill", text: "终点", coord: loc)
                }
            }
        }
        .padding()
        .glassCard(corner: TokensRadius.medium)
    }

    private func locationChip(icon: String, text: String, coord: CLLocation) -> some View {
        HStack(spacing: 6) {
            Image(safeSymbol: icon, fallback: "gauge")
                .font(.caption)
                    .foregroundStyle(TokensPalette.ambient)
            VStack(alignment: .leading) {
                Text(text).font(.caption2).foregroundStyle(.secondary)
                Text(String(format: "%.4f, %.4f", coord.coordinate.latitude, coord.coordinate.longitude))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.primary.opacity(0.05))
        .cornerRadius(8)
    }

    // MARK: - 能耗详情
    private var energyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(safeSymbol: "battery.100", fallback: "bolt.fill")
                    .font(.caption)
                    .foregroundStyle(TokensPalette.success)
                Text("能耗分析")
                    .font(Theme.font(.subheadline as Font).bold())
                Spacer()
            }

            VStack(spacing: 8) {
                energyRow(label: "起始电量", value: "\(trip.startSoc)%", color: .green)
                energyRow(label: "结束电量", value: "\(trip.endSoc)%", color: .orange)
                energyRow(label: "消耗电量", value: "\(trip.socChange)%", color: .red)
                energyRow(label: "平均能耗", value: efficiencyText, color: .blue)
                energyRow(label: "平均速度", value: String(format: "%.0f km/h", avgSpeed), color: .purple)
            }
        }
        .padding()
        .glassCard(corner: TokensRadius.medium)
    }

    private func energyRow(label: String, value: String, color: Color) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(TokensTypo.subheadline).foregroundStyle(color)
        }
    }

    // MARK: - 驾驶行为
    private var drivingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                // 原来这里是 " steeringwheel"（多了一个前导空格）—— 名字非法会渲染成空白图标
                Image(safeSymbol: "steeringwheel", fallback: "car.fill")
                    .font(.caption)
                    .foregroundStyle(TokensPalette.warning)
                Text("驾驶行为")
                    .font(Theme.font(.subheadline as Font).bold())
                Spacer()
                Text(
                    DurationFormatter.string(
                        from: max(
                            (trip.endTime ?? Date()).timeIntervalSince(trip.startTime),
                            1
                        )
                    )
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // 驾驶评分条
            VStack(spacing: 8) {
                HStack {
                    Text("平稳驾驶").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("良好").font(.caption).foregroundStyle(TokensPalette.success)
                }
                ProgressBar(value: 0.8, color: .green)

                HStack {
                    Text("急加速/刹车").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("偶尔").font(.caption).foregroundStyle(TokensPalette.warning)
                }
                ProgressBar(value: 0.6, color: .orange)

                HStack {
                    Text("超速次数").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("0次").font(.caption).foregroundStyle(TokensPalette.success)
                }
                ProgressBar(value: 1.0, color: .green)
            }
            .padding(.horizontal, 4)
        }
        .padding()
        .glassCard(corner: TokensRadius.medium)
    }

    // MARK: - 时间线
    private var timelineCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "clock.fill")
                    .font(.caption)
                    .foregroundStyle(TokensPalette.info)
                Text("时间线")
                    .font(Theme.font(.subheadline as Font).bold())
                Spacer()
            }

            VStack(spacing: 0) {
                timelineItem(icon: "play.fill", text: "行程开始", time: trip.startTime, color: .green)
                timelineItem(
                    icon: "location.fill",
                    text: "途经点（GPS记录中）",
                    time: trip.startTime.addingTimeInterval(
                        (trip.endTime ?? Date()).timeIntervalSince(trip.startTime)
                        / 3600 * 3600 / 2
                    ),
                    color: .blue
                )
                timelineItem(icon: "flag.fill", text: "行程结束", time: trip.endTime ?? Date(), color: .orange)
            }
            .glassCard(corner: TokensRadius.small)
        }
        .padding()
    }

    private func timelineItem(icon: String, text: String, time: Date, color: Color) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(color.opacity(0.2))
                .frame(width: 32, height: 32)
                .overlay(Image(safeSymbol: icon, fallback: "location.fill").font(.caption).foregroundStyle(color))

            VStack(alignment: .leading, spacing: 2) {
                Text(text).font(.caption).foregroundStyle(.primary)
                Text(time, style: .time).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - 分享
    private func shareTrip() {
        let text = """
🚗 我的行程
━━━━━━━━━━━━━
📏 里程：\(String(format: "%.1f km", trip.distanceKm))
🔋 SOC变化：\(trip.socChange)%
⚡ 能耗：\(efficiencyText)
⏱️ 时长：\(DurationFormatter.string(from: max((trip.endTime ?? Date()).timeIntervalSince(trip.startTime), 1)))
📍 出发：\(trip.startTime.formatted(date: .numeric, time: .omitted))
"""
        UIPasteboard.general.string = text
        ToastManager.shared.show("行程已复制", icon: "checkmark.circle.fill")
    }
}

// MARK: - MapKit Wrapper
/// 通用地图包装：坐标在哪里，图上就有标注 —— 不允许再出现“有图无点”。
/// 此前的问题：makeUIView 里算了 region 却从没赋给地图，也从不加任何标注，
/// updateUIView 为空 —— 位置变化后图也不动，永远是一张空白世界地图。
/// 行为：`coordinate` 变化 → 移动标注并把地图居中；`points` ≥ 2 → 画行程折线。
struct MapView: UIViewRepresentable {
    var coordinate: CLLocationCoordinate2D
    var span: MKCoordinateSpan
    var points: [CLLocationCoordinate2D]
    /// 标注名称（可选）：首页传地址；不传则只显示车形大头针
    var title: String = ""

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsCompass = false
        map.showsScale = false
        map.isRotateEnabled = false
        map.isPitchEnabled = false
        context.coordinator.lastCoordinate = coordinate
        context.coordinator.apply(map: map, coordinate: coordinate, span: span,
                                  points: points, title: title, animate: false)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let c = context.coordinator
        let moved = abs(c.lastCoordinate.latitude - coordinate.latitude) > 1e-9
            || abs(c.lastCoordinate.longitude - coordinate.longitude) > 1e-9
        guard moved else { return }
        c.lastCoordinate = coordinate
        c.apply(map: map, coordinate: coordinate, span: span,
                points: points, title: title, animate: true)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator: NSObject, MKMapViewDelegate {
        var lastCoordinate = CLLocationCoordinate2D(latitude: 39.9, longitude: 116.4)
        private var annotation: MKPointAnnotation?

        /// 统一入口（幂等）：移动标注 → 居中 → 重画折线，重复调用不会叠加标注/折线
        func apply(map: MKMapView, coordinate: CLLocationCoordinate2D, span: MKCoordinateSpan,
                   points: [CLLocationCoordinate2D], title: String, animate: Bool) {
            if let a = annotation {
                a.coordinate = coordinate
                a.title = title.isEmpty ? nil : title
            } else {
                let a = MKPointAnnotation()
                a.coordinate = coordinate
                a.title = title.isEmpty ? nil : title
                annotation = a
                map.addAnnotation(a)
            }
            map.setRegion(MKCoordinateRegion(center: coordinate, span: span), animated: animate)

            let existing = map.overlays.compactMap { $0 as? MKPolyline }
            if let old = existing.first {
                guard old.pointCount != points.count else { return }
                map.removeOverlay(old)
            }
            if points.count >= 2 {
                map.addOverlay(MKPolyline(coordinates: points, count: points.count))
            }
        }

        // 车形大头针：一跟就能认出“这是车”，不是收藏点
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard annotation is MKPointAnnotation else { return nil }
            let id = "car-pin"
            let view = (mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView)
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
            view.annotation = annotation
            view.glyphImage = UIImage(systemName: "car.fill")
            view.displayPriority = .required
            view.canShowCallout = false
            return view
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = UIColor(TokensPalette.ambient)
                renderer.lineWidth = 3
                renderer.lineDashPattern = [6, 4]
                return renderer
            }
            return MKOverlayRenderer()
        }
    }
}

// MARK: - Progress Bar
struct ProgressBar: View {
    let value: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(height: 6)
                RoundedRectangle(cornerRadius: 4)
                    .fill(color)
                    .frame(width: geo.size.width * min(value, 1.0), height: 6)
                    .animation(.spring(response: 0.5), value: value)
            }
        }
        .frame(height: 6)
    }
}

// MARK: - Preview
struct TripDetailView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            TripDetailView(trip: TripRecord(
                startTime: Date().addingTimeInterval(-7200),
                endTime: Date(),
                distanceKm: 42.5,
                startSoc: 85,
                endSoc: 78,
                avgEfficiency: 14.2
            ))
        }
    }
}
