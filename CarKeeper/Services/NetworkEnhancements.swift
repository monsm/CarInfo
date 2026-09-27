// =============================================================================
// N37 网络质量监控 —— **系统的那一台**（NWPathMonitor）
// =============================================================================
//
//  这里原本还有一段「N36 指数退避重试」：`RetryConfig` + `URLSession.dataTaskRetryable`。
//  2026-09-25 删 —— 它是**第二套重试实现**，而且一个读者都没有（全仓只有它自己的
//  声明与默认参数里那个 `RetryConfig`）。App 真正走的重试是 `Retrier.global`
//  （`API.request` 里那一步，HANDOFF 的服务表写着它的策略），而这段代码留着会让
//  读的人以为网络层有两套策略 —— 两套实现里先看到的那一套看起来就是真的。
//  发现它的是 `scan/orphans.py` 判据 ②（系统类型扩展里没人读的成员）：
//  那条判据是这一轮加的，加完当场报到它。
//
//  2026-09-26（第三十一轮地毯式审核）又删掉两件，判据是同一个：
//  **「App 的网络好不好」这件事全仓有四个判据，而其中两个是多余的、且会互相打脸。**
//
//    · `OfflineModeManager` 整份删除。它做的事只有一件：把
//      `NetworkQualityMonitor.isReachable` 取反、改名叫 `isOffline`、再写回
//      `AppStore.isOfflineMode` —— 于是同一个布尔有两个写者，一个看网络路径
//      （NWPathMonitor），一个看**真实取数有没有拿到东西**（`AppStore.saveCache`：
//      本次一个源都没取到才算离线）。两个写者就有两个答案：WiFi 连着、服务端在维护时，
//      路径说「在线」而取数说「离线」，屏幕上那条提示就在两者之间闪。
//      留下的那一个是取数那个 —— 它回答的才是用户真正在问的问题
//      （「数据为什么没出来」）；路径那一份仍然读得到，但它只是**诊断页的一行读数**，
//      不再参与判断。它的 `offlineMessage` 一并删除：一个写者、**零个读者**
//      （`AppStore.offlineMessage` 同样删掉 —— 那个是四个写者、零个读者）。
//    · 30 秒一次的延迟采样删除，改成 `measureLatency()`（**谁读谁调**：目前只有
//      「诊断」页，它打开时测一次）。原来那是一个永远在跑的 30 秒 HTTP 请求
//      （120 次/小时），而它的唯一下游是诊断页里的一行读数 ——
//      这正是用户自己定的那条规矩（「api 压力大的可采取用户查看时再加载」）
//      最该用上的地方：没有人看着这一行的时候，那个数没有意义。
//
//  留在这里的是 NWPathMonitor 本身：它事件驱动、不花流量，也只有它答得出
//  「走的是 WiFi 还是蜂窝」。

import Foundation
import Network
import Combine

// MARK: - N37 网络质量监控
class NetworkQualityMonitor: ObservableObject {
    static let shared = NetworkQualityMonitor()

    @Published var latency: Double = 0          // ms（`measureLatency()` 测出来的那一次）
    @Published var isReachable: Bool = false
    @Published var connectionType: String = "unknown"

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "network.quality.monitor")

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
    }

    //  `stop()` 与那个存下来的 `latencyTimer` 随定时器一起删（2026-09-26）：
    //  没有定时器要停，而 `stop()` 本身全仓一个调用点都没有 ——
    //  它就是「一个只写了、没有人读」的同一类东西。

    /// 测一次到车联网网关的往返耗时（毫秒）。**谁读谁调**，没有定时器（见文件头）。
    func measureLatency() {
        guard let url = URL(string: "https://m.iov.changan.com.cn") else { return }
        let start = CFAbsoluteTimeGetCurrent()
        URLSession.shared.dataTask(with: url) { [weak self] _, _, _ in
            let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
            DispatchQueue.main.async { self?.latency = elapsed }
        }.resume()
    }
}
