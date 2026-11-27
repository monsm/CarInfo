import SwiftUI
import MapKit


extension MapSpineView {
    @MapContentBuilder
    func mapContent(_ d: MapSpineData) -> some MapContent {
        if let c = d.carCoordinate {
            Annotation("", coordinate: c) {
                MapCarPin(lamp: d.sky(at: skyDate)?.lamp ?? 0)
            }
        }
        phonePin()
        driveTraceLine(trace)
        rangeCircle(d)
        tripLines(d)
        hotspotCircles(d)
        holdPins(d)
        chargerPins
        issuePins(d)
    }

    @MapContentBuilder
    func driveTraceLine(_ t: DriveTrace) -> some MapContent {
        if t.points.count >= 2 {
            MapPolyline(MKPolyline(coordinates: t.points, count: t.points.count))
                .stroke(TokensPalette.info.opacity(0.18),
                        style: StrokeStyle(lineWidth: 11, lineCap: .round))
            MapPolyline(MKPolyline(coordinates: t.points, count: t.points.count))
                .stroke(TokensPalette.info,
                        style: StrokeStyle(lineWidth: 4, lineCap: .round))
        }
    }

    @MapContentBuilder
    func tripLines(_ d: MapSpineData) -> some MapContent {
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

    @MapContentBuilder
    func rangeCircle(_ d: MapSpineData) -> some MapContent {
        if layer == .now, let c = d.carCoordinate, let meters = d.rangeMeters, meters > 0 {
            MapCircle(center: c, radius: meters)
                .stroke(TokensPalette.accent,
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [4, 5]))
                .foregroundStyle(TokensPalette.accent.opacity(0.05))
        }
    }

    @MapContentBuilder
    func hotspotCircles(_ d: MapSpineData) -> some MapContent {
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
    func holdPins(_ d: MapSpineData) -> some MapContent {
        if layer == .holds {
            ForEach(d.holds) { h in
                Annotation("停车点", coordinate: h.coordinate) {
                    MapSpotPin(kind: .hold(isLatest: h.isLatest))
                }
            }
        }
    }

    var chargerClusters: [MapChargerCluster] {
        MapSpineData.clusterChargers(chargers)
    }

    @MapContentBuilder
    var chargerPins: some MapContent {
        if layer == .charge {
            ForEach(chargerClusters) { cluster in
                Annotation("充电站", coordinate: cluster.coordinate) {
                    if cluster.count == 1 {
                        MapSpotPin(kind: .charger(distanceText: cluster.nearest.distanceText))
                    } else {
                        Button {
                            withAnimation(TokensMotion.value) {
                                camera = .camera(MapCamera(centerCoordinate: cluster.coordinate,
                                                           distance: 1200,
                                                           pitch: cameraPitch))
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
    func issuePins(_ d: MapSpineData) -> some MapContent {
        if layer == .now {
            ForEach(d.issues) { i in
                Annotation("异常", coordinate: i.coordinate) {
                    MapSpotPin(kind: .issue, label: i.title)
                }
            }
        }
    }
}
