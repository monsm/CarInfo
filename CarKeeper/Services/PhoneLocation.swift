import Foundation
import CoreLocation
import Combine

final class PhoneLocation: NSObject, ObservableObject, CLLocationManagerDelegate {

    static let shared = PhoneLocation()

    enum Status: Equatable {
        case idle
        case asking
        case denied
        case locating
        case found
        case coarse
        case failed
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var coordinate: CLLocationCoordinate2D?
    @Published private(set) var accuracy: CLLocationAccuracy?

    var mapCoordinate: CLLocationCoordinate2D? {
        coordinate.map { ChinaDatum.gcj02(fromWGS84: $0) }
    }

    private static let goodAccuracy: CLLocationAccuracy = 35
    private static let coarseLimit: CLLocationAccuracy = 100
    private static let settleDeadline: TimeInterval = 6

    private let manager = CLLocationManager()
    private var fallback: CLLocation?
    private var settleToken = 0

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
    }

    func request() {
        switch manager.authorizationStatus {
        case .notDetermined:
            status = .asking
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            status = .locating
            fallback = nil
            armSettleTimer()
            manager.startUpdatingLocation()
        case .denied, .restricted:
            status = .denied
        @unknown default:
            status = .denied
        }
    }


    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            if status == .asking { request() }
        case .denied, .restricted:
            status = .denied
        case .notDetermined:
            break
        @unknown default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let valid = locations.filter { $0.horizontalAccuracy >= 0 }
        guard let best = valid.min(by: { $0.horizontalAccuracy < $1.horizontalAccuracy }) else { return }

        if best.horizontalAccuracy <= Self.goodAccuracy {
            accept(best)
            return
        }
        if fallback == nil || best.horizontalAccuracy < (fallback?.horizontalAccuracy ?? .greatestFiniteMagnitude) {
            fallback = best
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        status = coordinate == nil ? .failed : status
    }


    private func accept(_ location: CLLocation) {
        coordinate = location.coordinate
        accuracy = location.horizontalAccuracy
        status = location.horizontalAccuracy <= Self.coarseLimit ? .found : .coarse
        settleToken += 1
        manager.stopUpdatingLocation()
        fallback = nil
    }

    private func armSettleTimer() {
        settleToken += 1
        let token = settleToken
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleDeadline) {
            guard token == self.settleToken, self.status == .locating else { return }
            if let f = self.fallback {
                self.accept(f)
            } else {
                self.status = .failed
                self.manager.stopUpdatingLocation()
            }
        }
    }
}
