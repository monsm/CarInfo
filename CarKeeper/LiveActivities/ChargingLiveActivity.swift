// =============================================================================
// ChargingLiveActivity — #28 Dynamic Island 支持（充电状态完整实现）
// 创建 Live Activities Target 后，实现 ActivityManager 来启动/停止活动
// =============================================================================

import SwiftUI
import WidgetKit
import Foundation

// MARK: - Live Activity Attributes

struct ChargingLiveAttributes: LiveActivityAttributes {
    // 静态属性（不随时间变化）
    struct ContentState: Codable, Hashable {
        var soc: Int
        var range: Int
        var timeToFull: String?
        var chargingPower: String
        var isActive: Bool
    }
    
    // 动态内容（随时间变化）
    var soc: Int
    var range: Int
    var isCharging: Bool
}

// MARK: - Activity Manager

/// 负责启动/更新/停止 Live Activity
enum ChargingLiveActivityManager {
    private static var activity: Activity<ChargingLiveAttributes, ChargingLiveAttributes.ContentState>?
    
    /// 开始充电 Live Activity
    static func start(soc: Int, range: Int, power: String) async {
        let initialState = ChargingLiveAttributes.ContentState(
            soc: soc, range: range,
            timeToFull: calculateTimeToFull(soc: soc, power: power),
            chargingPower: power,
            isActive: true
        )
        let attributes = ChargingLiveAttributes(soc: soc, range: range, isCharging: true)
        
        do {
            activity = try await Activity<ChargingLiveAttributes, ChargingLiveAttributes.ContentState>.begin(attributes) {
                ChargingLiveAttributes.ContentState(soc: soc, range: range, timeToFull: initialState.timeToFull, chargingPower: power, isActive: true)
            }
        } catch {
            print("Failed to start Live Activity: \(error)")
        }
    }
    
    /// 更新充电状态
    static func update(soc: Int, range: Int, power: String) {
        guard let activity = activity else { return }
        let newState = ChargingLiveAttributes.ContentState(
            soc: soc, range: range,
            timeToFull: calculateTimeToFull(soc: soc, power: power),
            chargingPower: power,
            isActive: true
        )
        activity.update(newState, staleDate: Calendar.current.date(byAdding: .minute, value: 30, to: Date()))
    }
    
    /// 停止充电 Live Activity
    static func end() {
        guard let activity = activity else { return }
        activity.end(.default, dismissalPolicy: .after(Date().addingTimeInterval(60)))
        self.activity = nil
    }
    
    /// 计算充满时间
    private static func calculateTimeToFull(soc: Int, power: String) -> String? {
        guard let p = Double(power.replacingOccurrences(of: " kW", with: "")), p > 0, soc < 100 else { return nil }
        let minutes = Int(Double(100 - soc) / p * 60)
        if minutes > 60 {
            return "约\(minutes / 60)小时\(minutes % 60)分钟"
        } else if minutes > 0 {
            return "约\(minutes)分钟"
        }
        return nil
    }
}

// MARK: - Live Activity View

struct ChargingLiveActivityView: View {
    var attributes: ChargingLiveAttributes
    var state: ChargingLiveAttributes.ContentState
    
    var body: some View {
        VStack(spacing: 8) {
            // SOC 大数字
            Text("\(state.soc)%")
                .font(.system(size: 32, weight: .bold, design: .monospaced))
                .foregroundStyle(state.soc < 20 ? .red : .green)
            
            // 续航 + 功率
            HStack(spacing: 12) {
                Label("\(state.range)km", systemImage: "gauge.high")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                if !state.chargingPower.isEmpty {
                    Label(state.chargingPower, systemImage: "bolt.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                }
            }
            
            // 充满时间
            if let ttf = state.timeToFull {
                Text("预计 \(ttf) 充满")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            
            // 进度条
            ProgressView(value: CGFloat(state.soc) / 100)
                .progressViewStyle(LinearProgressViewStyle(tint: .green))
                .frame(maxWidth: .infinity)
        }
        .padding(12)
        .background(Color(.systemBackground).opacity(0.9), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - 后台刷新任务

class ChargingRefreshTask {
    private var timer: Timer?
    private let refreshInterval: TimeInterval = 60  // 每60秒刷新
    
    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }
    
    func stop() {
        timer?.invalidate()
        timer = nil
    }
    
    private func refresh() {
        // 从 UserDefaults 读取最新数据并更新 Live Activity
        let defaults = UserDefaults(suiteName: "group.com.carkeeper.data") ?? UserDefaults.standard
        let soc = defaults.integer(forKey: "widget_soc")
        let range = defaults.integer(forKey: "widget_range")
        let power = defaults.string(forKey: "widget_power") ?? ""
        ChargingLiveActivityManager.update(soc: max(0, min(100, soc)), range: max(0, range), power: power)
    }
}
