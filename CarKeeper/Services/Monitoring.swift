
import Foundation

class MemoryMonitor: ObservableObject {
    static let shared = MemoryMonitor()

    @Published var usedMemoryMB: Double = 0
    @Published var warningLevel: Int = 0

    private var lastWarningLevel: Int = 0
    private var timer: Timer?

    private init() {}

    func startMonitoring(interval: TimeInterval = 5) {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.updateMemory()
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    deinit { timer?.invalidate() }

    private func updateMemory() {
        var taskInfo = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.stride) / 4

        let kerr: kern_return_t = withUnsafeMutablePointer(to: &taskInfo) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        guard kerr == KERN_SUCCESS else { return }

        let bytes = Double(taskInfo.resident_size)
        let mb = bytes / 1024.0 / 1024.0
        warningLevel = mb > 500 ? 2 : mb > 300 ? 1 : 0

        DispatchQueue.main.async {
            self.usedMemoryMB = mb
        }
    }
}

