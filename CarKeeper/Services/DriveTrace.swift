import SwiftUI
import CoreLocation

@MainActor
final class DriveTrace: ObservableObject {
    static let shared = DriveTrace()

    @Published private(set) var points: [CLLocationCoordinate2D] = []
    @Published private(set) var active = false

    private let minStep: Double = 8
    private let maxPoints = 2_000

    private init() {}


    func begin() {
        points = []
        active = true
    }

    func end() {
        active = false
    }

    func ingest(_ coordinate: CLLocationCoordinate2D, moving: Bool) {
        if !active {
            guard moving else { return }
            points = []
            active = true
        }
        append(coordinate)
    }

    private func append(_ coordinate: CLLocationCoordinate2D) {
        if let last = points.last {
            let a = CLLocation(latitude: last.latitude, longitude: last.longitude)
            let b = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            guard a.distance(from: b) >= minStep else { return }
        }
        points.append(coordinate)
        if points.count > maxPoints {
            points.removeFirst(points.count - maxPoints)
        }
    }

}
