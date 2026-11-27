import UIKit


@MainActor
final class KeepAwake {

    static let shared = KeepAwake()

    private init() {}

    private var applied: Bool? = nil
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        apply()
        arm()
    }

    func stop() {
        started = false
        applied = nil
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private func arm() {
        guard started else { return }
        withObservationTracking {
            _ = AppStore.shared.isCarMoving
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.started else { return }
                self.apply()
                self.arm()
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
