// =============================================================================
// TripDetailView —— 行程详情页（坐标轨迹 + 能耗分析 + 驾驶评分）
// =============================================================================

import SwiftUI
import MapKit

extension Date {
    var durationText: String {
        let hours = Int(timeIntervalSince1970 / 3600)
        let minutes = Int(timeIntervalSince1970.truncatingRemainder(dividingBy: 3600) / 60)
        return hours > 0 ? "\(\(hours)h\(minutes)m" : "\(\(minutes)m"
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
    
    private let speedFormatter: MassFormatter = {
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
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.md)
        }
        .pageBackground(Theme.pageGreen)
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
                        .font(Theme.caption)
                        .foregroundStyle(.secondary)
                    Text(trip.startTime, style: .time)
                        .font(Theme.subheadline)
                        .foregroundStyle(.primary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(DurationFormatter.string(from: max((trip.endTime ?? Date()).timeIntervalSince(trip.startTime), 1)))
                        .font(Theme.caption)
                        .foregroundStyle(.secondary)
                    Text(trip.startTime, style: .date)
                        .font(Theme.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Divider().opacity(0.3)
            
            HStack(spacing: 20) {
                statItem(icon: "distance.walk", value: "\(trip.distanceKm, format: .number.precision(.significantDigits(3)))", unit: "km", label: "里程")
                statItem(icon: "bolt.fill", value: "\(trip.socChange)%", unit: "", label: "SOC变化")
                statItem(icon: "gauge.high", value: efficiencyText, unit: "", label: "能耗")
            }
        }
        .padding()
        .glassCard(corner: Theme.Radius.medium)
    }
    
    private func statItem(icon: String, value: String, unit: String, label: String) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(.accent)
                Text(value)
                    .font(Theme.heroNum)
                    .foregroundStyle(.primary)
                if !unit.isEmpty {
                    Text(unit)
                        .font(Theme.caption)
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
                    .foregroundStyle(.accent)
                Text("行驶路线")
                    .font(Theme.subheadline.bold())
                Spacer()
                Button(action: { showMap.toggle() }) {
                    Text(showMap ? "收起" : "展开")
                        .font(.caption)
                        .foregroundStyle(.accent)
                }
            }
            
            if showMap, let start = trip.startLocation, let end = trip.endLocation {
                MapView(coordinate: mapCenter, span: span, points: [start.coordinate, end.coordinate])
                    .frame(height: 200)
                    .cornerRadius(Theme.Radius.small)
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
                .glassCard(corner: Theme.Radius.small)
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
        .glassCard(corner: Theme.Radius.medium)
    }
    
    private func locationChip(icon: String, text: String, coord: CLLocation) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.accent)
            VStack(alignment: .leading) {
                Text(text).font(.caption2).foregroundStyle(.secondary)
                Text(String(format: "%.4f, %.4f", coord.latitude, coord.longitude))
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
                Image(systemName: "battery.100.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                Text("能耗分析")
                    .font(Theme.subheadline.bold())
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
        .glassCard(corner: Theme.Radius.medium)
    }
    
    private func energyRow(label: String, value: String, color: Color) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(Theme.subheadline).foregroundStyle(color)
        }
    }
    
    // MARK: - 驾驶行为
    private var drivingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: " steeringwheel")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Text("驾驶行为")
                    .font(Theme.subheadline.bold())
                Spacer()
                Text(DurationFormatter.string(from: max((trip.endTime ?? Date()).timeIntervalSince(trip.startTime), 1)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            // 驾驶评分条
            VStack(spacing: 8) {
                HStack {
                    Text("平稳驾驶").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("良好").font(.caption).foregroundStyle(.green)
                }
                ProgressBar(value: 0.8, color: .green)
                
                HStack {
                    Text("急加速/刹车").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("偶尔").font(.caption).foregroundStyle(.orange)
                }
                ProgressBar(value: 0.6, color: .orange)
                
                HStack {
                    Text("超速次数").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("0次").font(.caption).foregroundStyle(.green)
                }
                ProgressBar(value: 1.0, color: .green)
            }
            .padding(.horizontal, 4)
        }
        .padding()
        .glassCard(corner: Theme.Radius.medium)
    }
    
    // MARK: - 时间线
    private var timelineCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "clock.fill")
                    .font(.caption)
                    .foregroundStyle(.blue)
                Text("时间线")
                    .font(Theme.subheadline.bold())
                Spacer()
            }
            
            VStack(spacing: 0) {
                timelineItem(icon: "play.fill", text: "行程开始", time: trip.startTime, color: .green)
                timelineItem(icon: "location.fill", text: "途经点（GPS记录中）", time: trip.startTime.addingTimeInterval((trip.endTime ?? Date()).timeIntervalSince(trip.startTime) / 3600 * 3600 / 2), color: .blue)
                timelineItem(icon: "flag.fill", text: "行程结束", time: trip.endTime ?? Date(), color: .orange)
            }
            .glassCard(corner: Theme.Radius.small)
        }
        .padding()
    }
    
    private func timelineItem(icon: String, text: String, time: Date, color: Color) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(color.opacity(0.2))
                .frame(width: 32, height: 32)
                .overlay(Image(systemName: icon).font(.caption).foregroundStyle(color))
            
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
    private func shareTrip {
        let text = """
🚗 我的行程
━━━━━━━━━━━━━
📏 里程：\(String(format: "%.1f km", trip.distanceKm))
🔋 SOC变化：\(trip.socChange)%
⚡ 能耗：\(efficiencyText)
⏱️ 时长：\(DurationFormatter.string(from: max((trip.endTime ?? Date()).timeIntervalSince(trip.startTime), 1)))
📍 \(trip.startTime, style: .date)
"""
        NotificationCenter.default.post(name: .showToast, object: nil, userInfo: ["text": "行程已复制", "icon": "checkmark.circle.fill"])
        UIPasteboard.general.string = text
    }
}

// MARK: - MapKit Wrapper
struct MapView: UIViewRepresentable {
    var coordinate: CLLocationCoordinate2D
    var span: MKCoordinateSpan
    var points: [CLLocationCoordinate2D]
    
    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map region = MKCoordinateRegion(center: coordinate, span: span)
        // Add polyline
        if points.count >= 2 {
            let polyline = MKPolyline(coordinates: points, count: points.count)
            map.addOverlay(polyline)
        }
        return map
    }
    
    func updateUIView(_ mapView: MKMapView, context: Context) {}
    
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    
    class Coordinator: NSObject, MKMapViewDelegate {
        let parent: MapView
        init(_ parent: MapView) { self.parent = parent }
        
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = .accentColor
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
                startSoc: 85, endSoc: 78,
                distanceKm: 42.5,
                avgEfficiency: 14.2
            ))
        }
    }
}
