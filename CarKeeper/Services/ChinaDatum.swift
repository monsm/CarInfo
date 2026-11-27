import Foundation
import CoreLocation

enum ChinaDatum {

    static func gcj02(fromWGS84 c: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        guard !outOfChina(c) else { return c }
        let d = delta(lat: c.latitude, lon: c.longitude)
        return CLLocationCoordinate2D(latitude: c.latitude + d.dLat,
                                      longitude: c.longitude + d.dLon)
    }

    static func wgs84(fromGCJ02 c: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        guard !outOfChina(c) else { return c }
        var guess = CLLocationCoordinate2D(
            latitude: c.latitude - delta(lat: c.latitude, lon: c.longitude).dLat,
            longitude: c.longitude - delta(lat: c.latitude, lon: c.longitude).dLon)
        for _ in 0..<3 {
            let d = delta(lat: guess.latitude, lon: guess.longitude)
            let next = CLLocationCoordinate2D(latitude: c.latitude - d.dLat,
                                              longitude: c.longitude - d.dLon)
            if next.latitude == guess.latitude && next.longitude == guess.longitude { break }
            guess = next
        }
        return guess
    }


    private static let axis = 6_378_245.0
    private static let eccentricity = 0.006_693_421_622_965_943

    private static func outOfChina(_ c: CLLocationCoordinate2D) -> Bool {
        if c.longitude < 72.004 || c.longitude > 137.8347 { return true }
        if c.latitude < 0.8293 || c.latitude > 55.8271 { return true }
        return false
    }

    private static func delta(lat: Double, lon: Double) -> (dLat: Double, dLon: Double) {
        var dLat = transformLat(lon - 105.0, lat - 35.0)
        var dLon = transformLon(lon - 105.0, lat - 35.0)
        let radLat = lat / 180.0 * Double.pi
        var magic = sin(radLat)
        magic = 1 - eccentricity * magic * magic
        let sqrtMagic = sqrt(magic)
        dLat = (dLat * 180.0) / ((axis * (1 - eccentricity)) / (magic * sqrtMagic) * Double.pi)
        dLon = (dLon * 180.0) / (axis / sqrtMagic * cos(radLat) * Double.pi)
        return (dLat, dLon)
    }

    private static func transformLat(_ x: Double, _ y: Double) -> Double {
        var ret = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * sqrt(abs(x))
        ret += (20.0 * sin(6.0 * x * Double.pi) + 20.0 * sin(2.0 * x * Double.pi)) * 2.0 / 3.0
        ret += (20.0 * sin(y * Double.pi) + 40.0 * sin(y / 3.0 * Double.pi)) * 2.0 / 3.0
        ret += (160.0 * sin(y / 12.0 * Double.pi) + 320.0 * sin(y * Double.pi / 30.0)) * 2.0 / 3.0
        return ret
    }

    private static func transformLon(_ x: Double, _ y: Double) -> Double {
        var ret = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * sqrt(abs(x))
        ret += (20.0 * sin(6.0 * x * Double.pi) + 20.0 * sin(2.0 * x * Double.pi)) * 2.0 / 3.0
        ret += (20.0 * sin(x * Double.pi) + 40.0 * sin(x / 3.0 * Double.pi)) * 2.0 / 3.0
        ret += (150.0 * sin(x / 12.0 * Double.pi) + 300.0 * sin(x / 30.0 * Double.pi)) * 2.0 / 3.0
        return ret
    }
}
