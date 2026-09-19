// =============================================================================
// ParkingMapView - 停车位置地图（坐标 + 反地理编码 + 导航）
// =============================================================================

import SwiftUI
import MapKit

struct ParkingMapView: View {
    private let store = AppStore.shared
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 39.9042, longitude: 116.4074),
        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
    )
    @State private var addressText = "获取中..."
    @State private var searchQuery = ""
    @State private var showSearch = false
    
    var hasLocation: Bool {
        store.parkingLocation != nil
    }
    
    var body: some View {
        ZStack {
            if hasLocation, let loc = store.parkingLocation {
                MapView(coordinate: loc.coordinate, span: region.span)
                    .ignoresSafeArea()
                
                // 地址覆盖层
                VStack {
                    Spacer()
                    parkingInfoCard(loc)
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "mappin")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary.opacity(0.4))
                    Text("未记录停车位置")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("停车后 App 会自动记录位置")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .pageBackground(Theme.pageBlue)
        .navigationTitle("停车位置")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showSearch.toggle() }) {
                    Image(systemName: "magnifyingglass")
                }
            }
        }
        .sheet(isPresented: $showSearch) {
            searchSheet
        }
        .accessibilityLabel(Text("停车位置地图"))
    }
    
    private func parkingInfoCard(_ loc: CLLocation) -> some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "mappin.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.red)
                VStack(alignment: .leading) {
                    Text(addressText)
                        .font(Theme.font(.subheadline as Font).bold())
                        .foregroundStyle(.primary)
                    Text(loc.formattedDistance(to: store.currentLocation))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: openMaps) {
                    Image(systemName: "car.fill")
                        .font(.caption)
                        .padding(8)
                        .background(Theme.Colors.accent.opacity(0.15))
                        .cornerRadius(8)
                }
            }
            
            Divider().opacity(0.3)
            
            HStack(spacing: 12) {
                infoChip(icon: "clock.fill", text: store.lastParkingTimeText)
                infoChip(icon: "figure.walk", text: "\(Int(loc.horizontalAccuracy))m 精度")
            }
        }
        .padding()
        .background(Color(UIColor.systemBackground).opacity(0.9))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
        .padding()
    }
    
    private func infoChip(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
    }
    
    private var searchSheet: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let loc = store.parkingLocation {
                    // 历史停车点
                    VStack(alignment: .leading, spacing: 8) {
                        Text("最近停车点").font(.headline)
                        ForEach(0..<min(3, store.parkingHistory.count), id: \.self) { i in
                            let p = store.parkingHistory[i]
                            HStack {
                                Image(systemName: "mappin").foregroundStyle(Theme.Colors.accent)
                                VStack(alignment: .leading) {
                                    Text(p.address ?? "未知位置").font(.subheadline)
                                    Text(p.date, style: .date).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 4)
                            if i < min(2, store.parkingHistory.count - 1) {
                                Divider().opacity(0.3)
                            }
                        }
                    }
                    .padding()
                    .glassCard(corner: Theme.Radius.medium)
                }
                
                Button(action: navToParking) {
                    HStack {
                        Image(systemName: "car.fill")
                        Text("导航到停车点")
                            .font(Theme.font(.subheadline as Font).bold())
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Theme.Colors.accent)
                    .foregroundStyle(.white)
                    .cornerRadius(12)
                }
            }
            .padding()
            .navigationTitle("停车历史")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private func openMaps() {
        guard let loc = store.parkingLocation else { return }
        let lt = loc.coordinate.latitude
        let ln = loc.coordinate.longitude
        if let url = URL(string: "maps://?daddr=\(lt),\(ln)&directionsmode=driving") {
            UIApplication.shared.open(url)
        }
    }
    
    private func navToParking() {
        guard let loc = store.parkingLocation else { return }
        showSearch = false
        openMaps()
    }
}

// MARK: - Preview
struct ParkingMapView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            ParkingMapView()
        }
    }
}
