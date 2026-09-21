// =============================================================================
// N46 摇一摇锁车 + N47 SOC 长按详情 + N48 左右滑动换车
// =============================================================================

import SwiftUI
import CoreMotion

// MARK: - N46 摇一摇锁车
class ShakeDetector: ObservableObject {
    static let shared = ShakeDetector()
    private let motionManager = CMMotionManager()
    private var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: "carkeeper_shake_to_lock")
    }

    private init() {}

    func startMonitoring() {
        guard motionManager.isAccelerometerAvailable, isEnabled else { return }
        motionManager.accelerometerUpdateInterval = 0.1
        motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, error in
            guard let data = data, let self = self else { return }
            let acceleration = sqrt(data.acceleration.x * data.acceleration.x +
                                    data.acceleration.y * data.acceleration.y +
                                    data.acceleration.z * data.acceleration.z)
            if acceleration > 1.5 { // 检测到明显摇动
                self.onShake?(data.acceleration)
            }
        }
    }

    func stopMonitoring() {
        motionManager.stopAccelerometerUpdates()
    }

    var onShake: ((CMAcceleration) -> Void)?
}
