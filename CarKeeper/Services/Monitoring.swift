// =============================================================================
// N39 内存监控
// =============================================================================
//
// ⚠️ 这里曾有 N38「崩溃日志捕获与上报」（`CrashReporter`）。2026-09-23 整块删除：
//    它把最近 5 条崩溃写进 UserDefaults（`carkeeper_crash_log`），**只给「诊断」页
//    看一个条数**。用户这一轮的要求是「全局删掉缓存机制，任何数据都是 api 数据」，
//    而这是最典型的「本机攒出来的数」—— 写它的只有 App 自己，读它的只有一个界面。
//    删掉它意味着再也拿不到自己 App 的崩溃堆栈（系统崩溃报告仍在
//    「设置 → 隐私与安全性 → 分析与改进」里，那份才是权威的那份）。
//    同时删掉的还有只为它存在的 `Date.iso8601` 扩展。

import Foundation

// MARK: - N39 内存监控
class MemoryMonitor: ObservableObject {
    static let shared = MemoryMonitor()

    @Published var usedMemoryMB: Double = 0
    @Published var warningLevel: Int = 0  // 0=normal, 1=warning, 2=critical

    private var lastWarningLevel: Int = 0

    private init() {}

    func startMonitoring(interval: TimeInterval = 5) {
        Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.updateMemory()
        }
    }

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
            // 这里原来写着「内存警告时自动清理缓存」：`AppStore.shared.clearCache()`。
            // 已删 —— `caches` 现在装的是**刚刚那一次响应**，不是可以随时丢掉的副本：
            // 清掉它等于把用户正在看的数字清空成空态，而内存并不会因此明显下降
            // （它只是几个 JSON 字典）。
        }
    }
}

