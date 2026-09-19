// =============================================================================
// Live Activity — #28 Dynamic Island 支持（充电状态）
// 充电中时显示实时进度条和剩余时间
// 注：实际 Live Activity 需要创建 Live Activities Target
// =============================================================================

import SwiftUI
import WidgetKit

// MARK: - Live Activity Attributes
struct ChargingLiveActivityAttributes: LiveActivityAttributes {
    struct ContentState: Codable, Hashable {
        var progress: Double        // 0.0 - 1.0
        var soc: Int                // 当前电量百分比
        var timeRemaining: String   // 剩余时间字符串
        var isCharging: Bool
        var power: String           // 充电功率
    }
    
    // 动态岛锁屏状态
    var lockScreenLeading: LeadingContent
    var lockScreenTrailing: TrailingContent
    var banner: String
    var bannerLeadingImage: String
}

// MARK: - Leading Content（左侧）
struct LeadingContent {
    let systemImageName: String
    let label: String?
    let subLabel: String?
}

// MARK: - Trailing Content（右侧）
struct TrailingContent {
    let state: String?
    let label: String?
    let valueLabel: String?
}

// MARK: - Live Activity View
struct ChargingLiveActivityView: View {
    let attributes: ChargingLiveActivityAttributes
    let state: ChargingLiveActivityAttributes.ContentState
    
    var body: some View {
        HStack {
            // 左侧：充电图标 + 电量
            VStack(alignment: .leading, spacing: 2) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.green)
                Text("\(state.soc)%")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.primary)
            }
            
            Spacer()
            
            // 右侧：剩余时间
            VStack(alignment: .trailing, spacing: 2) {
                Text(state.timeRemaining)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.primary)
                if let power = state.power, !power.isEmpty {
                    Text(power)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - Compact Live Activity（横向紧凑模式）
struct ChargingLiveActivityCompact: View {
    let attributes: ChargingLiveActivityAttributes
    let state: ChargingLiveActivityAttributes.ContentState
    
    var body: some View {
        HStack {
            Image(systemName: "bolt.fill")
                .foregroundStyle(.green)
            Text("\(state.soc)%")
                .fontWeight(.bold)
            Spacer()
            Text(state.timeRemaining)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
    }
}

// MARK: - Live Activity Manager
class LiveActivityManager {
    static let shared = LiveActivityManager()
    
    private init() {}
    
    /// 开始充电 Live Activity
    func startChargingActivity(soc: Int, timeRemaining: String, power: String) {
        let contentState = ChargingLiveActivityAttributes.ContentState(
            progress: Double(soc) / 100,
            soc: soc,
            timeRemaining: timeRemaining,
            isCharging: true,
            power: power
        )
        
        let attributes = ChargingLiveActivityAttributes(
            lockScreenLeading: LeadingContent(
                systemImageName: "bolt.fill",
                label: "充电中",
                subLabel: "\(soc)% 电量"
            ),
            lockScreenTrailing: TrailingContent(
                state: "\(timeRemaining)",
                label: "预计充满",
                valueLabel: power
            ),
            banner: "正在充电：\(soc)%",
            bannerLeadingImage: "bolt.fill"
        )
        
        // 实际启动 Live Activity
        // Activity<ChargingLiveActivityAttributes>.request(...)
    }
    
    /// 更新充电进度
    func updateChargingProgress(soc: Int, timeRemaining: String) {
        // 实际更新 Live Activity
        // Task { await currentActivity?.update(...) }
    }
    
    /// 结束充电 Live Activity
    func endChargingActivity() {
        // 实际结束 Live Activity
        // Activity<ChargingLiveActivityAttributes>.end(...)
    }
}
