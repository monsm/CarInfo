import Foundation


@MainActor
final class RefreshLoop {

    static let shared = RefreshLoop()

    private init() {}

    enum Cadence {
        static let moving: Double = 1
        static let movingFullEvery: Int = 10
        static let parkedFloor: Double = 2
        static let parkedCeil: Double = 60
        static let parkedSteps: Int = 5
        static let page: Double = 60
        static let heavy: Double = 300
    }

    private var task: Task<Void, Never>? = nil


    private var zeroStreak = 0

    private var motionTicks = 0

    private var lastHeavyAt: Date? = nil

    private var lastModeRaw: String? = nil


    private var currentModeRaw: String {
        UserDefaults.standard.string(forKey: HomeMode.storageKey) ?? HomeMode.now.rawValue
    }

    private var isOnMap: Bool { currentModeRaw == HomeMode.now.rawValue }

    private var modeChanged: Bool { currentModeRaw != lastModeRaw }

    var interval: Double {
        guard isOnMap else { return Cadence.page }
        return AppStore.shared.isCarMoving ? Cadence.moving : parkedInterval
    }

    var parkedInterval: Double {
        let steps = min(zeroStreak, Cadence.parkedSteps)
        return min(Cadence.parkedCeil, Cadence.parkedFloor * pow(2, Double(steps)))
    }


    func start() {
        guard task == nil else { return }
        lastModeRaw = currentModeRaw
        task = Task { [weak self] in
            while let self, !Task.isCancelled {
                var waited: Double = 0
                let wait = self.interval
                while waited < wait {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    if Task.isCancelled { return }
                    waited += 1
                    if self.modeChanged { break }
                }
                if Task.isCancelled { return }
                await self.tick(pageArrived: self.modeChanged)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }


    private func tick(pageArrived: Bool) async {
        let store = AppStore.shared
        lastModeRaw = currentModeRaw
        guard store.isLoggedIn, !store.carId.isEmpty else { return }
        if isOnMap {
            if store.isCarMoving {
                zeroStreak = 0
                motionTicks += 1
                if motionTicks % Cadence.movingFullEvery == 0 {
                    await store.fetchCore()
                } else {
                    await store.fetchMotion()
                }
            } else {
                motionTicks = 0
                await store.fetchCore()
                zeroStreak += 1
            }
        } else {
            let due = lastHeavyAt.map { Date().timeIntervalSince($0) >= Cadence.heavy } ?? true
            if pageArrived || due {
                await store.fetchVehicleData()
                lastHeavyAt = Date()
            } else {
                await store.fetchCore()
            }
        }
    }

    func refreshAll() async {
        let store = AppStore.shared
        guard store.isLoggedIn, !store.carId.isEmpty else { return }
        await store.fetchVehicleData()
        lastHeavyAt = Date()
        let missed = store.lastMissedSources
        ToastManager.shared.show(
            missed.isEmpty ? "已取到最新数据" : "有 \(missed.count) 项没取到",
            icon: missed.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
    }
}
