
import Foundation
import CoreLocation

@MainActor
final class RouteService: ObservableObject {
    static let shared = RouteService()

    struct Route {
        let points: [CLLocationCoordinate2D]
        let distanceMeters: Double
    }

    private static let base = "https://router.project-osrm.org/route/v1/driving/"

    private var cache: [String: Route] = [:]
    private var cacheOrder: [String] = []
    private let cacheCap = 64
    private var inflight: [String: Task<Route?, Never>] = [:]
    @Published private(set) var revision: Int = 0

    private init() {}

    func route(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) async -> Route? {
        let key = Self.key(a, b)
        if let hit = cache[key] {
            touch(key)
            return hit
        }
        if let flying = inflight[key] { return await flying.value }
        let task = Task<Route?, Never> { await Self.fetch(a, b) }
        inflight[key] = task
        let out = await task.value
        inflight[key] = nil
        if let out {
            cache[key] = out
            touch(key)
            revision += 1
        }
        return out
    }

    private func touch(_ key: String) {
        if let i = cacheOrder.firstIndex(of: key) { cacheOrder.remove(at: i) }
        cacheOrder.append(key)
        while cacheOrder.count > cacheCap {
            let oldest = cacheOrder.removeFirst()
            cache.removeValue(forKey: oldest)
        }
    }

    func cached(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Route? {
        cache[Self.key(a, b)]
    }


    private static func fetch(_ a: CLLocationCoordinate2D,
                              _ b: CLLocationCoordinate2D) async -> Route? {
        let wa = ChinaDatum.wgs84(fromGCJ02: a)
        let wb = ChinaDatum.wgs84(fromGCJ02: b)
        let path = String(format: "%.6f,%.6f;%.6f,%.6f",
                          wa.longitude, wa.latitude, wb.longitude, wb.latitude)
        guard let url = URL(string: base + path
                            + "?overview=simplified&geometries=geojson&steps=false") else {
            return nil
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 20
        req.setValue("CarKeeper/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            return nil
        }
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let routes = obj["routes"] as? [[String: Any]],
              let first = routes.first,
              let geometry = first["geometry"] as? [String: Any],
              let coords = geometry["coordinates"] as? [[Double]] else {
            return nil
        }
        var points: [CLLocationCoordinate2D] = []
        points.reserveCapacity(coords.count)
        for pair in coords {
            guard pair.count >= 2 else { continue }
            let wgs = CLLocationCoordinate2D(latitude: pair[1], longitude: pair[0])
            points.append(ChinaDatum.gcj02(fromWGS84: wgs))
        }
        guard points.count > 1 else { return nil }
        return Route(points: points,
                     distanceMeters: (first["distance"] as? Double) ?? 0)
    }

    private static func key(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> String {
        String(format: "%.5f,%.5f>%.5f,%.5f", a.latitude, a.longitude, b.latitude, b.longitude)
    }
}
