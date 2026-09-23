// =============================================================================
// E40 充电状态监控
// =============================================================================
//
// 上一版这个文件是一个 12 行的桩：`startMonitoring()` 是空的，
// 而且 App 只写了 `_ = ChargingStatusMonitor.shared` —— 连它都没调用过。
//
// 现在它由**真实的报文**驱动：`AppStore.recordHistory()` 在每次拿到车端数据后
// 调用 `observe(soc:charging:powerKW:)`，所以这里的每一个数字都来自车，
// 不是定时器猜出来的。它只做三件有实质意义的事：
//   ① 记录「本次充电」的起点（SOC 与时刻）—— 车端报文里没有这两个值
//   ② 状态跃迁时推送一条本地通知：开始充电 / 充电结束（附本次充进去多少）
//   ③ 把当前状态公开给「开发者工具」看，避免「启动了但没人看」
//
// 不做什么：它**不**生成充电记录。充电会话（度数、曲线）由
// `HistoryStore` 采样 + `ChargeLedger.derive` 积分得出 —— 那是另一条链路，
// 两边各算一遍会出现两个不一样的总度数。

import Foundation
import UserNotifications

@MainActor
final class ChargingStatusMonitor: ObservableObject {
    static let shared = ChargingStatusMonitor()
    private init() {}

    // MARK: 当前状态（都是最近一次报文的实况）

    @Published private(set) var isCharging = false
    @Published private(set) var soc = 0
    @Published private(set) var powerKW: Double = 0

    /// 本次充电的起点。车端报文里没有「这次充电从多少度开始」，只能由 App 在
    /// 跃迁的那一刻记下来 —— 所以冷启动时第一次看到「正在充电」时它是 nil。
    @Published private(set) var sessionStartSOC: Int?
    @Published private(set) var sessionStartAt: Date?

    /// 最近一次状态变化（开发者工具里显示，用来回答「它到底在干活吗」）
    @Published private(set) var lastEvent: String?
    @Published private(set) var lastEventAt: Date?

    /// 本机累计完成的充电次数（进程内计数，不落盘）
    private(set) var completedSessions = 0

    /// 通知开关：与全 App 的语音/通知偏好一致，默认开
    private var notificationsEnabled: Bool {
        UserDefaults.standard.object(forKey: "carkeeper_charge_notify") as? Bool ?? true
    }

    private var lastCharging: Bool?
    /// 已就「充满」提醒过一次的 SOC，避免每 30 秒重复推
    private var notifiedFullSOC = -1

    // MARK: 生命周期

    /// 目前没有需要常驻的资源：状态由报文驱动，没有定时器、没有后台任务。
    /// 保留这个方法是为了「启动顺序」在壳层里读起来一致（其余监控都有 start）。
    func startMonitoring() {
        lastCharging = nil
        notifiedFullSOC = -1
    }

    func stopMonitoring() {
        lastCharging = nil
    }

    // MARK: 由报文驱动的观察点

    /// - Parameters:
    ///   - soc: 当前 SOC（%）
    ///   - charging: 车端是否在充电（`AppStore.isCharging`）
    ///   - powerKW: 当前充电功率，取不到传 nil
    func observe(soc: Int, charging: Bool, powerKW: Double?) {
        self.isCharging = charging
        self.soc = soc
        self.powerKW = powerKW ?? 0

        guard let previous = lastCharging else {
            // 首次拿到报文：只记状态，不推通知（否则每次冷启动都会收到一条
            // 「开始充电」，而车可能已经充了两个小时）
            lastCharging = charging
            if charging {
                sessionStartSOC = nil
                sessionStartAt = Date()
                mark("已连接到充电桩（中途启动）")
            }
            return
        }

        guard previous != charging else {
            // 状态没变：只在「充满」这一刻提醒一次
            if charging && soc >= 100 && notifiedFullSOC != soc {
                notifiedFullSOC = soc
                mark("电量已满（\(soc)%）")
                notify(title: "充电完成",
                       body: "电量已达 \(soc)%，可以拔枪了。")
            }
            return
        }

        lastCharging = charging
        if charging {
            sessionStartSOC = soc
            sessionStartAt = Date()
            mark("开始充电 · 起始 \(soc)%")
            notify(title: "已开始充电",
                   body: "当前电量 \(soc)%\(powerKW.map { String(format: " · %.1f kW", $0) } ?? "")。")
        } else {
            let gained = sessionStartSOC.map { soc - $0 }
            completedSessions += 1
            var body = "当前电量 \(soc)%"
            if let g = gained, g > 0 { body += "，这次充进去 \(g)%" }
            mark("充电结束 · \(body)")
            notify(title: "充电结束", body: body + "。")
            sessionStartSOC = nil
            sessionStartAt = nil
            notifiedFullSOC = -1
        }
    }

    // MARK: 内部

    private func mark(_ text: String) {
        lastEvent = text
        lastEventAt = Date()
    }

    private func notify(title: String, body: String) {
        guard notificationsEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        // trigger 为 nil = 立刻送达。用日历触发器会把它变成「明天 9 点」，
        // 那就不是「充电结束提醒」了。
        let request = UNNotificationRequest(identifier: "charge_\(UUID().uuidString)",
                                           content: content,
                                           trigger: nil)
        Task {
            try? await UNUserNotificationCenter.current().add(request)
        }
    }

    /// 开发者工具用的一行摘要
    var summary: String {
        if isCharging {
            let from = sessionStartSOC.map { "\($0)% → " } ?? ""
            return "充电中 · \(from)\(soc)%\(powerKW > 0 ? String(format: " · %.1f kW", powerKW) : "")"
        }
        return lastEvent ?? "未充电"
    }
}
