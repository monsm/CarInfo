// =============================================================================
// E7 充电功率实时曲线
// E9 停车位置反地理编码
// E10 到家/到公司地理围栏
// E11 车辆位置热力图
// E12 行程轨迹回放
// E16 导航到停车点
// =============================================================================

import SwiftUI
import Charts
import MapKit
import CoreLocation

// MARK: - E7 充电功率实时曲线
struct ChargingPowerChart: View {
    let powerHistory: [ChargingPowerRecord]
    
    var body: some View {
        if powerHistory.count < 2 {
            Text("充电中...")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity)
                .glassCard()
        } else {
            Chart {
                ForEach(powerHistory.indices.dropLast(), id: \.self) { i in
                    LineMark(
                        x: .value("时间", powerHistory[i].time),
                        y: .value("功率 kW", powerHistory[i].power)
                    )
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .foregroundStyle(.green)
                    
                    PointMark(
                        x: .value("时间", powerHistory[i].time),
                        y: .value("功率 kW", powerHistory[i].power)
                    )
                    .foregroundStyle(.green)
                    .symbolSize(6)
                }
            }
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 4))
            }
            .frame(height: 100)
            .glassCard()
        }
    }
}

struct ChargingPowerRecord: Identifiable {
    let id = UUID()
    let time: Date
    let power: Double // kW
}

// MARK: - E9 反地理编码
class ReverseGeocoder: ObservableObject {
    static let shared = ReverseGeocoder()
    
    @Published var cachedAddresses: [String: String] = [:]
    
    func getAddress(for location: CLLocation) async -> String {
        let key = "\(location.coordinate.latitude),\(location.coordinate.longitude)"
        if let cached = cachedAddresses[key] {
            return cached
        }
        
        let geocoder = CLGeocoder()
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            if let placemark = placemarks.first {
                let address = [
                    placemark.locality,
                    placemark.administrativeArea,
                    placemark.country
                ].compactMap { $0 }.joined(separator: " ")
                cachedAddresses[key] = address
                return address
            }
        } catch {
            print("Geocode error: \(error)")
        }
        return "位置未知"
    }
}

// MARK: - E10 地理围栏管理器
class GeofenceManager: ObservableObject {
    static let shared = GeofenceManager()
    
    @Published var homeLocation: CLLocation?
    @Published var workLocation: CLLocation?
    @Published var homeRadius: Double = 150 // meters
    @Published var workRadius: Double = 150
    
    private let manager = CLLocationManager()
    private var homeRegion: CLCircularRegion?
    private var workRegion: CLCircularRegion?
    
    private init() {
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 500
    }
    
    func setupGeofences() {
        guard let home = homeLocation, let work = workLocation else { return }
        
        homeRegion = CLCircularRegion(center: home.coordinate, radius: homeRadius, identifier: "home")
        homeRegion?.notifyOnEntry = true
        homeRegion?.notifyOnExit = true
        
        workRegion = CLCircularRegion(center: work.coordinate, radius: workRadius, identifier: "work")
        workRegion?.notifyOnEntry = true
        workRegion?.notifyOnExit = true
        
        manager.startMonitoring(for: homeRegion!)
        manager.startMonitoring(for: workRegion!)
    }
}

extension GeofenceManager: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        if region.identifier == "home" {
            print("进入家区域")
            // 触发到家提醒
        }
        if region.identifier == "work" {
            print("进入工作区域")
            // 触发到公司提醒
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        if region.identifier == "home" {
            print("离开家区域")
        }
        if region.identifier == "work" {
            print("离开工作区域")
        }
    }
}

// MARK: - E11 位置热力图
struct LocationHeatmapView: View {
    let locations: [CLLocation]
    
    var body: some View {
        Map {
            ForEach(Array(locations.enumerated()), id: \.offset) { idx, location in
                Marker("", coordinate: location.coordinate)
                    .tint(Color.red.opacity(Double(idx) / Double(locations.count)))
            }
        }
        .mapStyle(.standard)
        .frame(height: 200)
        .glassCard()
    }
}

// MARK: - E12 行程轨迹回放
struct TripTrajectoryView: View {
    let startLocation: CLLocation?
    let endLocation: CLLocation?
    
    var body: some View {
        guard let start = startLocation, let end = endLocation else {
            return Text("无轨迹数据").frame(maxWidth: .infinity).glassCard()
        }
        
        return Map {
            Marker("起点", coordinate: start.coordinate)
                .tint(.green)
            Marker("终点", coordinate: end.coordinate)
                .tint(.red)
            
            Polyline(colors: [start.coordinate, end.coordinate])
                .stroke(style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                .foregroundStyle(.accentColor.opacity(0.6))
        }
        .mapStyle(.standard)
        .frame(height: 150)
        .glassCard()
    }
}

struct Polyline: Shape {
    var path: Path {
        Path { p in
            // 简化的两点连线，实际应使用真实轨迹点
            p.move(to: CGPoint(x: 50, y: 100))
            p.addLine(to: CGPoint(x: 150, y: 50))
        }
    }
}

// MARK: - E16 导航到停车点
struct NavigateToParkingButton: View {
    let location: CLLocation?
    let label: String
    
    var body: some View {
        Button {
            guard let loc = location else { return }
            let coordinate = loc.coordinate
            let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
            mapItem.name = label
            mapItem.openInMaps(launchOptions: [
                MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
            ])
        } label: {
            HStack {
                Image(systemName: "navigation")
                Text("导航到停车点")
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.accentColor)
            .foregroundColor(.white)
            .cornerRadius(Theme.Radius.md)
        }
        .disabled(location == nil)
    }
}
