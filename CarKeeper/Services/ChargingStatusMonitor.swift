
import Foundation
import UserNotifications

@MainActor
final class ChargingStatusMonitor: ObservableObject {
    static let shared = ChargingStatusMonitor()
    private init() {}


    @Published private(set) var isCharging = false
    @Published private(set) var soc = 0
    @Published private(set) var powerKW: Double = 0

    @Published private(set) var sessionStartSOC: Int?
    @Published private(set) var sessionStartAt: Date?

    @Published private(set) var lastEvent: String?
    @Published private(set) var lastEventAt: Date?

    private(set) var completedSessions = 0


    private var lastCharging: Bool?
    private var notifiedFullSOC = -1


    func startMonitoring() {
        lastCharging = nil
        notifiedFullSOC = -1
    }

    func stopMonitoring() {
        lastCharging = nil
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        guard status == .notDetermined else { return status == .authorized }
        return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }


    func observe(soc: Int, charging: Bool, powerKW: Double?) {
        self.isCharging = charging
        self.soc = soc
        self.powerKW = powerKW ?? 0

        guard let previous = lastCharging else {
            lastCharging = charging
            if charging {
                sessionStartSOC = nil
                sessionStartAt = Date()
                mark("已连接到充电桩（中途启动）")
            }
            return
        }

        guard previous != charging else {
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


    private func mark(_ text: String) {
        lastEvent = text
        lastEventAt = Date()
    }

    private func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: "charge_\(UUID().uuidString)",
                                           content: content,
                                           trigger: nil)
        Task {
            try? await UNUserNotificationCenter.current().add(request)
        }
    }

    var summary: String {
        if isCharging {
            let from = sessionStartSOC.map { "\($0)% → " } ?? ""
            return "充电中 · \(from)\(soc)%\(powerKW > 0 ? String(format: " · %.1f kW", powerKW) : "")"
        }
        return lastEvent ?? "未充电"
    }
}
