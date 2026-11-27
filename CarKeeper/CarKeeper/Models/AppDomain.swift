import Foundation
import SwiftUI
import CoreLocation

struct HistoryEntry: Identifiable {
    let id = UUID()
    let cmd: String
    let name: String
    let startedAt: Date
    let finishedAt: Date?
    let success: Bool
    let confirmed: Bool
    let duration: TimeInterval

    var statusColor: Color {
        if !confirmed { return TokensPalette.warning }
        return success ? TokensPalette.success : TokensPalette.error
    }
    var iconName: String {
        if !confirmed { return "questionmark.circle.fill" }
        return success ? "checkmark.circle.fill" : "xmark.circle.fill"
    }
    var resultText: String {
        if !confirmed { return "未确认" }
        return success ? "成功" : "失败"
    }
    var statusCls: String {
        if !confirmed { return "na" }
        return success ? "ok" : "bad"
    }
    var durationText: String {
        guard duration > 0 else { return "--" }
        if duration < 60 { return String(format: "%.1fs", duration) }
        return "\(Int(duration / 60))min"
    }
}

struct EnergyRecord: Identifiable {
    let id = UUID()
    let timestamp: Date
    let soc: Int
    let range: Int
}

struct TripRecord: Identifiable {
    let id = UUID()
    let startTime: Date
    let endTime: Date?
    let startLocation: CLLocation?
    let endLocation: CLLocation?
    let distanceKm: Double
    var durationText: String {
        let dur = (endTime?.timeIntervalSince(startTime) ?? 0) / 60
        return dur > 0 ? "\(Int(dur))min" : "--"
    }
    let startSoc: Int
    let endSoc: Int
    let avgEfficiency: Double?
    let kmPerPercent: Double?

    var startAddr: String = ""
    var endAddr: String = ""
}

struct ParkingPoint: Codable {
    let lat: Double
    let lng: Double
    let time: Date
    let address: String
}

struct ParkingRecord: Identifiable {
    let id = UUID()
    let location: CLLocation
    let time: Date
    let address: String
}

struct MapFocus: Equatable, Identifiable {
    let lat: Double
    let lng: Double
    let label: String
    var id: String { "\(lat),\(lng)" }
}

enum NetworkStatus: String {
    case online = "在线"
    case weak = "弱网"
    case offline = "离线"
}

enum TripTracker {
    struct Open: Equatable {
        var startTime: Date
        var startSoc: Int
        var startLocation: CLLocation?
        var startMileage: Int?
        var startAddr: String
    }

    static func makeRecord(_ open: Open, distanceKm: Double, endSoc: Int,
                           endLocation: CLLocation?, at time: Date,
                           endAddr: String) -> TripRecord {
        let socUsed = open.startSoc - endSoc
        let kmPerPercent: Double? = (socUsed > 0 && distanceKm > 0)
            ? distanceKm / Double(socUsed) : nil
        return TripRecord(
            startTime: open.startTime,
            endTime: time,
            startLocation: open.startLocation,
            endLocation: endLocation,
            distanceKm: distanceKm,
            startSoc: open.startSoc,
            endSoc: endSoc,
            avgEfficiency: nil,
            kmPerPercent: kmPerPercent,
            startAddr: open.startAddr,
            endAddr: endAddr
        )
    }

    static func tripKm(open: Open?, endMileage: Int?) -> Double {
        guard let open, let end = endMileage,
              let start = open.startMileage, end >= start else { return 0 }
        return Double(end - start)
    }
}

enum ParkingTracker {
    static let minSeparation = 120.0

    static func shouldSkip(last: ParkingPoint?, new: CLLocationCoordinate2D) -> Bool {
        guard let last else { return false }
        let d = CLLocation(latitude: last.lat, longitude: last.lng)
            .distance(from: CLLocation(latitude: new.latitude, longitude: new.longitude))
        return d < minSeparation
    }
}

enum CommandHistoryTracker {
    static let cap = 50

    static func insert(_ entry: HistoryEntry, into list: [HistoryEntry]) -> [HistoryEntry] {
        var out = list
        out.insert(entry, at: 0)
        if out.count > cap { out = Array(out.prefix(cap)) }
        return out
    }
}
