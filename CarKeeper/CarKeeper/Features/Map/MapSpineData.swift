import SwiftUI
import CoreLocation
import MapKit

enum MapSpineLayer: String, CaseIterable, Identifiable {
    case now
    case trips
    case holds
    case charge

    var id: String { rawValue }

    var title: String {
        switch self {
        case .now: return "现在"
        case .trips: return "行程"
        case .holds: return "停车"
        case .charge: return "充电"
        }
    }


    var emptyNote: String {
        switch self {
        case .now: return "还没收到位置上报"
        case .trips: return "还没有行程记录"
        case .holds: return "还没有停车记录"
        case .charge: return "正在搜索附近充电站"
        }
    }
}

extension MapSpineLayer {
    static let storageKey = "carkeeper_map_layer"

}

struct MapTripLine: Identifiable {
    let id: String
    let from: CLLocationCoordinate2D
    let to: CLLocationCoordinate2D
    let startedAt: Date
    let endedAt: Date?
    let distanceKm: Double
    let startSoc: Int
    let endSoc: Int
    let efficiency: Double?
    let kmPerPercent: Double?

    var socUsed: Int { max(0, startSoc - endSoc) }

    var timeText: String {
        DateText.shared.string(startedAt, "HH:mm")
    }
}

struct MapHoldPoint: Identifiable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let address: String
    let time: Date
    let isLatest: Bool

    var agoText: String { MapSpineData.agoText(time) }
}

struct MapIssue: Identifiable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let title: String
    let detail: String
    let cls: String
}

struct MapTyre: Identifiable {
    let label: String
    let kpa: String
    let warn: Bool
    var id: String { label }
}

struct MapHotspot: Identifiable {
    let id: String
    let center: CLLocationCoordinate2D
    let radiusMeters: Double
    let visits: Int
    let lastVisit: Date
}

struct MapCharger: Identifiable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let name: String
    let distanceMeters: Double
    let isEVCharger: Bool

    var distanceText: String {
        distanceMeters < 1000
            ? "\(Int(distanceMeters.rounded())) m"
            : String(format: "%.1f km", distanceMeters / 1000)
    }
}

struct MapSpineData {
    var carCoordinate: CLLocationCoordinate2D?
    var headingDeg: Double
    var headingText: String
    var address: String
    var gpsText: String
    var gpsCls: String
    var satAlt: String

    var socPct: Int
    var socCls: String
    var rangeText: String
    var chargeText: String
    var chargeCls: String
    var charging: ChargingSession?
    var timeToFull: String?

    var carName: String
    var online: OnlineState
    var updated: String

    var trips: [MapTripLine]
    var holds: [MapHoldPoint]
    var issues: [MapIssue]
    var tyres: [MapTyre]
    var hotspots: [MapHotspot]

    var hasLocation: Bool { carCoordinate != nil }


    @MainActor
    var rangeMeters: Double? {
        let cache = AppStore.shared.caches
        for key in ["charge", "control"] {
            if let n = ciNumber(ciVal(cache, key), ["RemainedPowerMile"]), n > 0 {
                return n * 1_000
            }
        }
        return nil
    }

    @MainActor
    var sky: SkyLight? { sky(at: Date()) }

    @MainActor
    func sky(at date: Date) -> SkyLight? {
        guard let c = carCoordinate else { return nil }
        let isNow = abs(date.timeIntervalSinceNow) < 60
        return SkyLight.now(at: date,
                            coordinate: c,
                            weather: isNow ? WeatherService.shared.current : nil)
    }


    @MainActor
    static func build() -> MapSpineData {
        let store = AppStore.shared
        let cache = store.caches
        let e = VM.energy(cache, store.car)
        let loc = VM.locStatus(cache)
        let chips = VM.bodyStatus(cache)
        let car = store.currentLocation

        let trips = spineTrips(from: store.tripHistory)

        let holds = spineHolds(latest: store.parkingLocation,
                              history: store.parkingHistory,
                              lastParkingTime: store.lastParkingTime)

        let issues = spineIssues(car: car, chips: chips)

        let tyreList = tyres(cache)

        let hotspots = clusterHotspots(from: store.parkingHistory,
                                       excluding: store.parkingLocation)

        return MapSpineData(
            carCoordinate: car?.coordinate,
            headingDeg: Double(loc.degNum),
            headingText: loc.dir,
            address: loc.addr.isEmpty ? "--" : loc.addr,
            gpsText: loc.gpsText,
            gpsCls: loc.gpsCls,
            satAlt: loc.satAlt,
            socPct: e.socPct,
            socCls: e.socCls,
            rangeText: e.range,
            chargeText: e.chargeText,
            chargeCls: e.chargeCls,
            charging: e.charging,
            timeToFull: e.timeToFull,
            carName: e.carName.isEmpty ? "我的车" : e.carName,
            online: e.online,
            updated: e.updated,
            trips: trips,
            holds: holds,
            issues: issues,
            tyres: tyreList,
            hotspots: hotspots
        )
    }

    static func clusterHotspots(
        from records: [AppStore.ParkingRecord],
        excluding latest: CLLocation?
    ) -> [MapHotspot] {
        var used = Array(repeating: false, count: records.count)
        var out: [MapHotspot] = []

        for i in records.indices where !used[i] {
            used[i] = true
            var group: [Int] = [i]
            for j in records.indices where j != i && !used[j] {
                if let p = latest, p.distance(from: records[j].location) < 25 { continue }
                if records[j].location.distance(from: records[i].location) <= 80 {
                    used[j] = true
                    group.append(j)
                }
            }
            guard group.count >= 2 else { continue }

            var lat = 0.0, lng = 0.0
            for j in group {
                lat += records[j].location.coordinate.latitude
                lng += records[j].location.coordinate.longitude
            }
            let center = CLLocationCoordinate2D(latitude: lat / Double(group.count),
                                                longitude: lng / Double(group.count))
            let centerLoc = CLLocation(latitude: center.latitude, longitude: center.longitude)
            var maxMeters = 0.0
            for j in group {
                maxMeters = max(maxMeters, records[j].location.distance(from: centerLoc))
            }
            let newest = group.map { records[$0].time }.max() ?? records[i].time
            out.append(MapHotspot(
                id: "hot-\(Int(center.latitude * 10000))-\(Int(center.longitude * 10000))",
                center: center,
                radiusMeters: maxMeters + 60,
                visits: group.count,
                lastVisit: newest
            ))
        }
        return out.sorted { $0.visits > $1.visits }
    }

    private static func tyres(_ cache: [String: Any?]) -> [MapTyre] {
        let model = VM.tyreStatus(cache)
        return model.items.compactMap { item in
            let kpa = item.kpa.trimmingCharacters(in: .whitespaces)
            guard !kpa.isEmpty, kpa != "--" else { return nil }
            return MapTyre(label: item.label, kpa: kpa, warn: item.warn)
        }
    }

    @MainActor
    static func spineTrips(from trips: [AppStore.TripRecord]) -> [MapTripLine] {
        trips.compactMap { t in
            guard let a = t.startLocation?.coordinate, let b = t.endLocation?.coordinate else {
                return nil
            }
            return MapTripLine(
                id: t.id.uuidString,
                from: a, to: b,
                startedAt: t.startTime,
                endedAt: t.endTime,
                distanceKm: t.distanceKm,
                startSoc: t.startSoc,
                endSoc: t.endSoc,
                efficiency: t.avgEfficiency,
                kmPerPercent: t.kmPerPercent
            )
        }
    }

    @MainActor
    static func spineHolds(latest: CLLocation?, history: [AppStore.ParkingRecord],
                          lastParkingTime: Date?) -> [MapHoldPoint] {
        var holds: [MapHoldPoint] = []
        if let p = latest {
            holds.append(MapHoldPoint(
                id: "latest",
                coordinate: p.coordinate,
                address: history.first?.address ?? "上次停车位置",
                time: lastParkingTime ?? Date(),
                isLatest: true
            ))
        }
        holds += history.enumerated().compactMap { idx, rec in
            if let p = latest, p.distance(from: rec.location) < 25 { return nil }
            return MapHoldPoint(
                id: "h\(idx)",
                coordinate: rec.location.coordinate,
                address: rec.address,
                time: rec.time,
                isLatest: false
            )
        }
        return holds
    }

    static func spineIssues(car: CLLocation?, chips: [StatusChip]) -> [MapIssue] {
        guard let c = car else { return [] }
        return chips.filter { $0.ok == false }.map { chip in
            MapIssue(
                id: chip.id,
                coordinate: c.coordinate,
                title: "\(chip.label)\(chip.text.isEmpty ? "" : " · \(chip.text)")",
                detail: "最后一次上报时车在这儿",
                cls: chip.cls
            )
        }
    }

    static func agoText(_ date: Date) -> String {

        let s = Date().timeIntervalSince(date)
        if s < 60 { return "刚刚" }
        if s < 3600 { return "\(Int(s / 60)) 分钟前" }
        if s < 86400 { return "\(Int(s / 3600)) 小时前" }
        return "\(Int(s / 86400)) 天前"
    }
}

struct MapChargerCluster: Identifiable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let count: Int
    let nearest: MapCharger
}

extension MapSpineData {
    static func clusterChargers(_ chargers: [MapCharger],
                                radiusMeters: Double = 400) -> [MapChargerCluster] {
        var out: [MapChargerCluster] = []
        var outLoc: [CLLocation] = []
        for c in chargers.sorted(by: { $0.distanceMeters < $1.distanceMeters }) {
            let here = CLLocation(latitude: c.coordinate.latitude, longitude: c.coordinate.longitude)
            if let i = outLoc.firstIndex(where: { $0.distance(from: here) <= radiusMeters }) {
                let old = out[i]
                let n = Double(old.count)
                let center = CLLocationCoordinate2D(
                    latitude: (old.coordinate.latitude * n + c.coordinate.latitude) / (n + 1),
                    longitude: (old.coordinate.longitude * n + c.coordinate.longitude) / (n + 1)
                )
                out[i] = MapChargerCluster(
                    id: old.id,
                    coordinate: center,
                    count: old.count + 1,
                    nearest: old.nearest
                )
                outLoc[i] = CLLocation(latitude: center.latitude, longitude: center.longitude)
            } else {
                out.append(MapChargerCluster(id: c.id, coordinate: c.coordinate, count: 1, nearest: c))
                outLoc.append(here)
            }
        }
        return out
    }
}
