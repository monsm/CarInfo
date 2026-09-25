// =============================================================================
// N37 网络质量实时监控
// =============================================================================
//
//  这里原本还有一段「N36 指数退避重试」：`RetryConfig` + `URLSession.dataTaskRetryable`。
//  2026-09-25 删 —— 它是**第二套重试实现**，而且一个读者都没有（全仓只有它自己的
//  声明与默认参数里那个 `RetryConfig`）。App 真正走的重试是 `Retrier.global`
//  （`API.request` 里那一步，HANDOFF 的服务表写着它的策略），而这段代码留着会让
//  读的人以为网络层有两套策略 —— 两套实现里先看到的那一套看起来就是真的。
//  发现它的是 `scan/orphans.py` 判据 ②（系统类型扩展里没人读的成员）：
//  那条判据是这一轮加的，加完当场报到它。

import Foundation
import Network
import Combine

// MARK: - N37 网络质量实时监控
class NetworkQualityMonitor: ObservableObject {
    static let shared = NetworkQualityMonitor()

    @Published var latency: Double = 0          // ms
    @Published var isReachable: Bool = false
    @Published var connectionType: String = "unknown"

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "network.quality.monitor")
    private var lastCheck: Date?
    /// 延迟采样的定时器（必须存下来才能停 —— 见 `start` 里那条注）
    private var latencyTimer: Timer?

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            self.isReachable = path.status == .satisfied
            if path.usesInterfaceType(.wifi) {
                self.connectionType = "WiFi"
            } else if path.usesInterfaceType(.cellular) {
                self.connectionType = "蜂窝"
            } else if path.usesInterfaceType(.wiredEthernet) {
                self.connectionType = "有线"
            } else {
                self.connectionType = "未知"
            }
        }
        monitor.start(queue: queue)

        // 每 30s 测一次延迟。
        // 2026-09-25 地毯式审核：原来这个定时器的返回值同样被丢掉（与 `MemoryMonitor`
        // 同一处错）：没人能停它，调两次就是两条 30 秒循环各自发包。现在存下来并判重。
        guard latencyTimer == nil else { return }
        latencyTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.measureLatency()
        }
    }

    /// 停掉延迟采样。
    func stop() {
        latencyTimer?.invalidate()
        latencyTimer = nil
        monitor.cancel()
    }

    deinit { latencyTimer?.invalidate() }

    private func measureLatency() {
        guard let url = URL(string: "https://m.iov.changan.com.cn") else { return }
        let start = CFAbsoluteTimeGetCurrent()
        URLSession.shared.dataTask(with: url) { [weak self] _, _, _ in
            let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
            DispatchQueue.main.async { self?.latency = elapsed }
        }.resume()
    }
}

// MARK: - N41 离线模式
class OfflineModeManager: ObservableObject {
    static let shared = OfflineModeManager()

    @Published var isOffline: Bool = false
    @Published var offlineMessage: String = ""

    private let monitor = NetworkQualityMonitor.shared

    private init() {
        monitor.$isReachable
            .sink { [weak self] reachable in
                guard let self = self else { return }
                self.isOffline = !reachable
                let message = reachable ? "" : "网络连接已断开"
                self.offlineMessage = message
                // 更新 AppStore 离线状态（AppStore 是 MainActor 隔离的）
                Task { @MainActor in
                    AppStore.shared.isOfflineMode = !reachable
                    AppStore.shared.offlineMessage = message
                }
            }
            .store(in: &cancellables)
    }

    private var cancellables = Set<AnyCancellable>()
}
