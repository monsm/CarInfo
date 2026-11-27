import Foundation
import CoreLocation
import Combine


enum WMOWeather {
    static func text(_ code: Int) -> String? {
        switch code {
        case 0: return "晴"
        case 1: return "大致晴朗"
        case 2: return "局部多云"
        case 3: return "阴"
        case 45, 48: return "雾"
        case 51, 53, 55: return "毛毛雨"
        case 56, 57: return "冻毛毛雨"
        case 61, 63, 65: return "雨"
        case 66, 67: return "冻雨"
        case 71, 73, 75: return "雪"
        case 77: return "雪粒"
        case 80, 81, 82: return "阵雨"
        case 85, 86: return "阵雪"
        case 95: return "雷暴"
        case 96, 99: return "雷暴伴冰雹"
        default: return nil
        }
    }
}

struct SkyWeather: Equatable {
    var cloudCover: Double
    var precipitation: Double
    var temperatureC: Double
    var code: Int
    var fetchedAt: Date
    var latitude: Double
    var longitude: Double

    func ageMinutes(at now: Date) -> Double { now.timeIntervalSince(fetchedAt) / 60 }

    var cloudText: String { "\(Int(cloudCover.rounded()))%" }

    var precipitationText: String { String(format: "%.1f mm/h", precipitation) }

    var temperatureText: String { String(format: "%.1f ℃", temperatureC) }

    var codeText: String { WMOWeather.text(code) ?? "天气码 \(code)" }

    func sourceText(at now: Date) -> String {
        "Open-Meteo 实况 · \(Int(ageMinutes(at: now).rounded())) 分钟前"
    }
}

@MainActor
final class WeatherService: ObservableObject {

    static let shared = WeatherService()

    enum Status: Equatable {
        case idle
        case loading
        case ok
        case failed(String)
    }

    @Published private(set) var current: SkyWeather?
    @Published private(set) var status: Status = .idle


    nonisolated static let refreshMinutes: Double = 15
    nonisolated static let moveThresholdMeters: Double = 5_000
    nonisolated static let host = "api.open-meteo.com"

    private var inFlight = false
    private var lastAttempt: Date?

    private init() {}


    nonisolated static func requestURL(latitude: Double, longitude: Double) -> URL? {
        let lat = (latitude * 100).rounded() / 100
        let lon = (longitude * 100).rounded() / 100
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = host
        comps.path = "/v1/forecast"
        comps.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.2f", lat)),
            URLQueryItem(name: "longitude", value: String(format: "%.2f", lon)),
            URLQueryItem(name: "current", value: "cloud_cover,precipitation,temperature_2m,weather_code"),
            URLQueryItem(name: "timezone", value: "UTC")
        ]
        return comps.url
    }

    nonisolated static func parse(_ data: Data,
                                  latitude: Double,
                                  longitude: Double,
                                  at now: Date) -> SkyWeather? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cur = obj["current"] as? [String: Any] else { return nil }
        guard let cloud = (cur["cloud_cover"] as? NSNumber)?.doubleValue,
              let temp = (cur["temperature_2m"] as? NSNumber)?.doubleValue else { return nil }
        let precip = (cur["precipitation"] as? NSNumber)?.doubleValue ?? 0
        let code = (cur["weather_code"] as? NSNumber)?.intValue ?? -1
        return SkyWeather(cloudCover: min(max(cloud, 0), 100),
                          precipitation: max(0, precip),
                          temperatureC: temp,
                          code: code,
                          fetchedAt: now,
                          latitude: latitude,
                          longitude: longitude)
    }


    func refreshIfNeeded(coordinate: CLLocationCoordinate2D, force: Bool = false) async {
        guard !inFlight else { return }
        let now = Date()
        if !force, let snapshot = current, let last = lastAttempt,
           now.timeIntervalSince(last) < Self.refreshMinutes * 60,
           Self.distanceMeters(from: snapshot, to: coordinate) < Self.moveThresholdMeters {
            return
        }
        await fetch(coordinate: coordinate, at: now)
    }

    func refresh(coordinate: CLLocationCoordinate2D) async {
        guard !inFlight else { return }
        await fetch(coordinate: coordinate, at: Date())
    }

    private func fetch(coordinate: CLLocationCoordinate2D, at now: Date) async {
        inFlight = true
        status = .loading
        defer {
            inFlight = false
            lastAttempt = Date()
        }
        guard let url = Self.requestURL(latitude: coordinate.latitude,
                                        longitude: coordinate.longitude) else {
            status = .failed("坐标无效")
            return
        }
        do {
            var req = URLRequest(url: url)
            req.httpMethod = "GET"
            req.timeoutInterval = 20
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            guard http.statusCode == 200 else { throw URLError(.badServerResponse) }
            guard let parsed = Self.parse(data,
                                          latitude: coordinate.latitude,
                                          longitude: coordinate.longitude,
                                          at: Date()) else {
                status = .failed("取不到天气")
                return
            }
            current = parsed
            status = .ok
        } catch {
            status = .failed(error.localizedDescription)
        }
    }


    nonisolated static func distanceMeters(from snapshot: SkyWeather,
                                           to coordinate: CLLocationCoordinate2D) -> Double {
        let a = CLLocation(latitude: snapshot.latitude, longitude: snapshot.longitude)
        let b = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return a.distance(from: b)
    }
}
