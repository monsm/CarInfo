import Foundation
import SwiftUI
import CoreLocation


struct CommandRecord: Identifiable {
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

struct EnergySample: Identifiable {
    let id = UUID()
    let timestamp: Date
    let soc: Int
    let range: Int
}

struct TripLog: Identifiable {
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

struct ParkingMark: Codable {
    let lat: Double
    let lng: Double
    let time: Date
    let address: String
}

struct ParkingVisit: Identifiable {
    let id = UUID()
    let location: CLLocation
    let time: Date
    let address: String
}

struct MapTarget: Equatable, Identifiable {
    let lat: Double
    let lng: Double
    let label: String
    var id: String { "\(lat),\(lng)" }
}

enum LinkStatus: String {
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
                           endAddr: String) -> TripLog {
        let socUsed = open.startSoc - endSoc
        let kmPerPercent: Double? = (socUsed > 0 && distanceKm > 0)
            ? distanceKm / Double(socUsed) : nil
        return TripLog(
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

    static func shouldSkip(last: ParkingMark?, new: CLLocationCoordinate2D) -> Bool {
        guard let last else { return false }
        let d = CLLocation(latitude: last.lat, longitude: last.lng)
            .distance(from: CLLocation(latitude: new.latitude, longitude: new.longitude))
        return d < minSeparation
    }
}

enum CommandHistoryTracker {
    static let cap = 50

    static func insert(_ entry: CommandRecord, into list: [CommandRecord]) -> [CommandRecord] {
        var out = list
        out.insert(entry, at: 0)
        if out.count > cap { out = Array(out.prefix(cap)) }
        return out
    }
}

enum TripBuilder {
    struct Event: Identifiable {
        let id: String
        let ignition: Bool
        let at: Date
        let coordinate: CLLocationCoordinate2D?
        let addr: String

        var location: CLLocation? {
            coordinate.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) }
        }
    }

    static func events(from messages: [[String: Any]]) -> [Event] {
        messages.compactMap { m -> Event? in
            guard let kind = ciString(m, ["InfoTypeId", "infoTypeId"])?.uppercased(),
                  kind == "IGNITION" || kind == "FLAMEOUT" else { return nil }
            let id = ciString(m, ["StubId", "stubId"]) ?? ciString(m, ["Id", "id"]) ?? ""
            guard !id.isEmpty else { return nil }
            let p = AppStore.jumpParams(m)
            guard let at = VM.serverDate(p["gpsTime"])
                    ?? VM.serverDate(ciPick(m, ["CreatedAt", "createdAt"])) else { return nil }
            var coord: CLLocationCoordinate2D?
            if let lat = VM.vnum(p["lat"]), let lng = VM.vnum(p["lng"]) {
                coord = CLLocationCoordinate2D(latitude: lat, longitude: lng)
            }
            return Event(id: id, ignition: kind == "IGNITION", at: at,
                         coordinate: coord, addr: (p["addrName"] as? String) ?? "")
        }.sorted { $0.at < $1.at }
    }

    static func displayTrips(from events: [Event]) -> [TripLog] {
        var out: [TripLog] = []
        var open: Event?
        for e in events {
            if e.ignition {
                open = e
            } else if let o = open {
                out.append(TripLog(
                    startTime: o.at, endTime: e.at,
                    startLocation: o.location, endLocation: e.location,
                    distanceKm: straightLineKm(o.coordinate, e.coordinate),
                    startSoc: 0, endSoc: 0,
                    avgEfficiency: nil, kmPerPercent: nil,
                    startAddr: o.addr, endAddr: e.addr))
                open = nil
            }
        }
        if let o = open {
            out.append(TripLog(
                startTime: o.at, endTime: nil,
                startLocation: o.location, endLocation: nil,
                distanceKm: 0, startSoc: 0, endSoc: 0,
                avgEfficiency: nil, kmPerPercent: nil))
        }
        return out
    }

    static func merge(fromMessages: [TripLog], stored: [TripLog]) -> [TripLog] {
        guard !fromMessages.isEmpty else { return stored }
        var byStart: [Date: TripLog] = [:]
        for t in fromMessages { byStart[t.startTime] = t }
        for t in stored {
            guard let cand = byStart[t.startTime] else {
                byStart[t.startTime] = t
                continue
            }
            var winner: TripLog
            var loser: TripLog
            if t.distanceKm > 0 && cand.distanceKm <= 0 { winner = t; loser = cand }
            else { winner = cand; loser = t }
            if winner.startAddr.isEmpty { winner.startAddr = loser.startAddr }
            if winner.endAddr.isEmpty { winner.endAddr = loser.endAddr }
            byStart[t.startTime] = winner
        }
        let all = Array(byStart.values)
        return all.filter { $0.distanceKm > 0 }.sorted { $0.startTime > $1.startTime }
            + all.filter { $0.distanceKm == 0 }.sorted { $0.startTime > $1.startTime }
    }

    private static func straightLineKm(_ a: CLLocationCoordinate2D?, _ b: CLLocationCoordinate2D?) -> Double {
        guard let a, let b else { return 0 }
        return CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude)) / 1000
    }
}
