// =============================================================================
// N38 崩溃日志上报 + N39 内存监控
// =============================================================================

import Foundation

// MARK: - N38 崩溃日志捕获与上报
class CrashReporter : ObservableObject {
    static let shared = CrashReporter()
    
    private let logFileKey = "carkeeper_crash_log"
    
    private init() {}
    
    func setup() {
        // 捕获 Swift 未处理异常
        let handler: (NSException) -> Void = { exception in
            self.logCrash(exception)
        }
        NSSetUncaughtExceptionHandler(handler)
        
        // 捕获信号异常（SIGSEGV 等）
        signal(SIGABRT) { sig in
            CrashReporter.shared.logSignalCrash(signal: sig)
            _exit(sig)
        }
        signal(SIGSEGV) { sig in
            CrashReporter.shared.logSignalCrash(signal: sig)
            _exit(sig)
        }
    }
    
    private func logCrash(_ exception: NSException) {
        let log = """
        === Crash Report \(Date().iso8601) ===
        Exception: \(exception.name.rawValue)
        Reason: \(exception.reason ?? "nil")
        Backtrace: \(exception.callStackReturnAddresses.map { String(format: "0x%016lx", $0) }.joined(separator: "\n"))
        =======================================
        """
        appendCrashLog(log)
    }
    
    private func logSignalCrash(signal: Int32) {
        let log = """
        === Signal Crash \(Date().iso8601) ===
        Signal: SIG\(signal)
        Backtrace: \(Thread.callStackSymbols.joined(separator: "\n"))
        =======================================
        """
        appendCrashLog(log)
    }
    
    private func appendCrashLog(_ log: String) {
        var history = readCrashHistory()
        history.append(log)
        if history.count > 5 { history = Array(history.suffix(5)) }
        UserDefaults.standard.set(history, forKey: logFileKey)
    }
    
    func readCrashHistory() -> [String] {
        UserDefaults.standard.stringArray(forKey: logFileKey) ?? []
    }
    
    func clearCrashHistory() {
        UserDefaults.standard.removeObject(forKey: logFileKey)
    }
}

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
                task_info(mach_task_self_, task_flavor_t(mach_task_basic_info_class), $0, &count)
            }
        }
        
        guard kerr == KERN_SUCCESS else { return }
        
        let bytes = Double(taskInfo.resident_size)
        let mb = bytes / 1024.0 / 1024.0
        let oldWarning = warningLevel
        warningLevel = mb > 500 ? 2 : mb > 300 ? 1 : 0
        
        DispatchQueue.main.async {
            self.usedMemoryMB = mb
            // 内存警告时自动清理缓存
            if oldWarning < self.warningLevel && self.warningLevel >= 2 {
                AppStore.shared.clearCache()
            }
        }
    }
}

// MARK: - Date 辅助
extension Date {
    var iso8601: String {
        ISO8601DateFormatter().string(from: self)
    }
}
