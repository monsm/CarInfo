// =============================================================================
// N36 API 自动重试 + N37 网络质量监控
// =============================================================================

import Foundation
import Network
import Combine

// MARK: - N36 指数退避重试
struct RetryConfig {
    let maxRetries: Int
    let baseDelay: TimeInterval
    let maxDelay: TimeInterval
    let jitter: Double
}

extension URLSession {
    /// 带自动重试的 GET 请求
    func dataTaskRetryable(
        url: URL,
        config: RetryConfig = RetryConfig(maxRetries: 3, baseDelay: 1.0, maxDelay: 10.0, jitter: 0.3)
    ) async throws -> (Data, URLResponse) {
        var lastError: Error?
        for attempt in 0..<config.maxRetries {
            do {
                let (data, response) = try await self.data(from: url)
                guard let httpResponse = response as? HTTPURLResponse else { continue }
                if httpResponse.statusCode >= 500 && attempt < config.maxRetries - 1 {
                    let delay = min(config.baseDelay * pow(2, Double(attempt)), config.maxDelay)
                        * (1 + Double.random(in: -config.jitter...config.jitter))
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    lastError = NSError(domain: "RetryableError", code: httpResponse.statusCode, userInfo: nil)
                    continue
                }
                return (data, response)
            } catch {
                lastError = error
                if attempt < config.maxRetries - 1 {
                    let delay = min(config.baseDelay * pow(2, Double(attempt)), config.maxDelay)
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }
        throw lastError ?? NSError(domain: "Network", code: -1, userInfo: nil)
    }
}

// MARK: - N37 网络质量实时监控
class NetworkQualityMonitor: ObservableObject {
    static let shared = NetworkQualityMonitor()
    
    @Published var latency: Double = 0          // ms
    @Published var isReachable: Bool = false
    @Published var connectionType: String = "unknown"
    
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "network.quality.monitor")
    private var lastCheck: Date?
    
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
        
        // 每 30s 测一次延迟
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.measureLatency()
        }
    }
    
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
                self.offlineMessage = reachable ? "" : "网络连接已断开，显示缓存数据"
                // 更新 AppStore 离线状态
                AppStore.shared.isOfflineMode = !reachable
                AppStore.shared.offlineMessage = self.offlineMessage
            }
            .store(in: &cancellables)
    }
    
    private var cancellables = Set<AnyCancellable>()
}
