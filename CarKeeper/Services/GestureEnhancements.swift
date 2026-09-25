// =============================================================================
// N46 摇一摇锁车 + N47 SOC 长按详情 + N48 左右滑动换车
// =============================================================================

import SwiftUI
import CoreMotion

// MARK: - N46 摇一摇锁车
///
/// 两处实修：
///
/// ① **阈值**。旧值是合加速度 > 1.5 g，而静止时合加速度就是重力 1.0 g ——
///    手机揣兜里走路、拿起来看时间都会越过 1.5，于是「摇一摇锁车」会被频繁误触。
///    改成 2.6 g（要真的挥手幅度），并加 8 秒冷却：一次挥手会连着上报很多帧。
/// ② **它真的锁车了吗**。旧实现在 `CarKeeperApp` 里只有一行
///    `EnhancedToastManager.shared.show("摇一摇已触发")` —— 弹个提示，不发任何指令。
///    现在走和车控/语音同一条路：验 PIN → 发 `CentralLock` → 记进指令历史。
///
/// 关于隔离：类本身**不是** `@MainActor` —— 重力回调（`CMAccelerometer`）不在
/// 主 actor 上，把整个类的属性标成主 actor 会让那个回调编译不过
/// （“main actor-isolated property can not be mutated from a nonisolated context”）。
/// 所以只有真正碰 UI/网络的 `lockCarIfNeeded()` 标 `@MainActor`。
final class ShakeDetector: ObservableObject {
    static let shared = ShakeDetector()
    /// 用户开关。默认关（这个功能会真的锁车，不该默认开）
    static let enabledKey = "carkeeper_shake_to_lock"

    private let motionManager = CMMotionManager()
    private let threshold = 2.6
    private let cooldown: TimeInterval = 8
    private var lastFire = Date.distantPast
    private var isBusy = false

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Self.enabledKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.enabledKey)
            if newValue { startMonitoring() } else { stopMonitoring() }
        }
    }

    private init() {}

    func startMonitoring() {
        guard motionManager.isAccelerometerAvailable, isEnabled else { return }
        motionManager.accelerometerUpdateInterval = 0.1
        motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
            guard let data = data, let self = self else { return }
            let g = sqrt(data.acceleration.x * data.acceleration.x +
                         data.acceleration.y * data.acceleration.y +
                         data.acceleration.z * data.acceleration.z)
            guard g > self.threshold else { return }
            guard Date().timeIntervalSince(self.lastFire) > self.cooldown else { return }
            self.lastFire = Date()
            Task { await self.lockCarIfNeeded() }
        }
    }

    func stopMonitoring() {
        motionManager.stopAccelerometerUpdates()
    }

    // MARK: 真正做的事

    // （旧的 `var onShake` 回调已删：全仓只有一个设置点，而那个设置点
    //  只弹一句「摇一摇已触发」。留着它只会让下一个人以为这里有挂点可用。）

    @MainActor
    func lockCarIfNeeded() async {
        guard !isBusy else { return }
        let store = AppStore.shared
        guard store.isLoggedIn, !store.carId.isEmpty else {
            ToastManager.shared.show("摇一摇锁车需要先登录", icon: "exclamationmark.triangle.fill")
            return
        }
        // 车已经锁着：不发指令（再锁一次也是真请求，会白跑一趟），照实说
        if let v = ciNumber(ciVal(store.caches, "control"), ["DriverDoorLock"]), v == 0 {
            ToastManager.shared.show("车已锁好", icon: "lock.fill")
            return
        }
        guard let pin = store.readPin(), !pin.isEmpty else {
            ToastManager.shared.show("摇一摇锁车需要先设置 PIN", icon: "key.fill")
            return
        }

        isBusy = true
        defer { isBusy = false }
        let start = Date()
        do {
            _ = try await APIClient.shared.sendControlCommand(cmd: "CentralLock", carId: store.carId, pin: pin)
            let dur = Date().timeIntervalSince(start)
            store.addCommandHistory(cmd: "CentralLock", name: "锁车（摇一摇）", success: true, duration: dur)
            ToastManager.shared.show("已摇一摇锁车", icon: "lock.fill")
            TokensHaptic.result(true)
        } catch {
            let dur = Date().timeIntervalSince(start)
            store.addCommandHistory(cmd: "CentralLock", name: "锁车（摇一摇）", success: false, duration: dur)
            ToastManager.shared.show("锁车失败：\(error.localizedDescription)", icon: "xmark.circle.fill")
            TokensHaptic.result(false)
        }
    }
}
