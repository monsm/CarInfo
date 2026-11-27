import UIKit


@MainActor
final class KeepAwake {

    static let shared = KeepAwake()

    private init() {}

    private var applied: Bool? = nil

    func start() {
        arm()
    }

    private func arm() {
        withObservationTracking {
            _ = AppStore.shared.isCarMoving
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.apply()
                self?.arm()
            }
        }
    }

    private func apply() {
        let moving = AppStore.shared.isCarMoving
        guard applied != moving else { return }
        applied = moving
        UIApplication.shared.isIdleTimerDisabled = moving
    }
}
