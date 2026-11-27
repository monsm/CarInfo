
import Foundation
import Network
import Combine

class NetworkQualityMonitor: ObservableObject {
    static let shared = NetworkQualityMonitor()

    @Published var latency: Double = 0
    @Published var isReachable: Bool = false
    @Published var connectionType: String = "unknown"

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "network.quality.monitor")

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            let reachable = path.status == .satisfied
            let type: String
            if path.usesInterfaceType(.wifi) {
                type = "WiFi"
            } else if path.usesInterfaceType(.cellular) {
                type = "蜂窝"
            } else if path.usesInterfaceType(.wiredEthernet) {
                type = "有线"
            } else {
                type = "未知"
            }
            DispatchQueue.main.async {
                self.isReachable = reachable
                self.connectionType = type
            }
        }
        monitor.start(queue: queue)
    }

    func stop() {
        monitor.cancel()
    }

    deinit {
        monitor.cancel()
    }


    func measureLatency() {
        guard let url = URL(string: "https://m.iov.changan.com.cn") else { return }
        let start = CFAbsoluteTimeGetCurrent()
        URLSession.shared.dataTask(with: url) { [weak self] _, _, _ in
            let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
            DispatchQueue.main.async { self?.latency = elapsed }
        }.resume()
    }
}
