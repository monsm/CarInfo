import SwiftUI
import CoreLocation
import MapKit



enum MapFollowTarget: String, CaseIterable, Identifiable {
    case car
    case phone

    var id: String { rawValue }

    var title: String {
        switch self {
        case .car: return "车"
        case .phone: return "手机"
        }
    }
}

enum MapCameraFollow {

    static let bandCenter: Double = 0.38

    static let spanFactor: Double = 0.90

    private static let metresPerDegree: Double = 111_320

    static func camera(on coordinate: CLLocationCoordinate2D?,
                       heading: Double,
                       distance: Double,
                       pitch: Double) -> MapCameraPosition? {
        guard let c = coordinate else { return nil }
        let back = (heading + 180) * .pi / 180
        let shift = (0.5 - bandCenter) * distance * spanFactor
        let dLat = shift * cos(back) / metresPerDegree
        let shrink = max(0.2, cos(c.latitude * .pi / 180))
        let dLng = shift * sin(back) / (metresPerDegree * shrink)
        let center = CLLocationCoordinate2D(latitude: c.latitude + dLat,
                                           longitude: c.longitude + dLng)
        return .camera(MapCamera(centerCoordinate: center,
                                 distance: distance,
                                 heading: heading,
                                 pitch: pitch))
    }
}

extension MapSpineView {

    @MainActor
    func centerOnCar(force: Bool) {
        guard let c = store.currentLocation?.coordinate else { return }
        if didCenterOnce && !force && !store.isCarMoving { return }
        didCenterOnce = true
        let heading = store.carHeadingDeg
        guard let pos = MapCameraFollow.camera(on: c, heading: heading,
                                               distance: cameraDistance,
                                               pitch: cameraPitch) else { return }
        withAnimation(TokensMotion.value) { camera = pos }
    }
}
