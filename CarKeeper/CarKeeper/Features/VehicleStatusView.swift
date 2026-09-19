// =============================================================================
// E4 故障码严重度分级
// E5 驾驶模式显示
// E8 车辆2D状态俯视图
// =============================================================================

import SwiftUI

// MARK: - E4 故障码严重度分级
enum DTCSeverity: String, CaseIterable, Identifiable {
    case critical = "critical"      // 红色 - 立即检修
    case warning = "warning"         // 橙色 - 尽快检查
    case info = "info"               // 蓝色 - 提示信息
    case resolved = "resolved"       // 绿色 - 已解决
    
    var id: String { rawValue }
    var color: Color {
        switch self {
        case .critical: return .red
        case .warning: return .orange
        case .info: return .blue
        case .resolved: return .green
        }
    }
    var icon: String {
        switch self {
        case .critical: return "exclamationmark.triangle.fill"
        case .warning: return "exclamationmark.circle.fill"
        case .info: return "info.circle.fill"
        case .resolved: return "checkmark.circle.fill"
        }
    }
    var label: String {
        switch self {
        case .critical: return "紧急"
        case .warning: return "警告"
        case .info: return "提示"
        case .resolved: return "已解决"
        }
    }
}

struct DTCSeverityBadge: View {
    let severity: DTCSeverity
    let code: String
    let description: String
    
    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: severity.icon)
                .foregroundColor(severity.color)
                .font(.title3)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(code)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(severity.label)
                        .font(.caption2)
                        .foregroundColor(severity.color)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(severity.color.opacity(0.15))
                        .cornerRadius(4)
                }
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .glassCard()
    }
}

// MARK: - E5 驾驶模式显示
enum DriveMode: String, CaseIterable {
    case eco = "ECO"
    case comfort = "COMFORT"
    case sport = "SPORT"
    case snow = "SNOW"
    
    var icon: String {
        switch self {
        case .eco: return "leaf.fill"
        case .comfort: return "smiley.fill"
        case .sport: return "bolt.fill"
        case .snow: return "snowflake.fill"
        }
    }
    var color: Color {
        switch self {
        case .eco: return .green
        case .comfort: return .blue
        case .sport: return .orange
        case .snow: return .cyan
        }
    }
}

struct DriveModeDisplay: View {
    let currentMode: DriveMode
    let availableModes: [DriveMode]
    let onModeChange: (DriveMode) -> Void
    
    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            ForEach(availableModes, id: \.self) { mode in
                Button {
                    onModeChange(mode)
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: mode.icon)
                            .font(.title3)
                        Text(mode.rawValue)
                            .font(.caption2)
                    }
                    .frame(width: 56, height: 56)
                    .background(mode == currentMode ? mode.color : Color.clear)
                    .foregroundColor(mode == currentMode ? .white : mode.color)
                    .cornerRadius(Theme.Radius.md)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.md)
                            .stroke(mode == currentMode ? mode.color : Color.clear, lineWidth: 2)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .glassCard()
    }
}

// MARK: - E8 车辆2D状态俯视图
struct Vehicle2DStatusView: View {
    let control: [String: Any]?
    
    private var isDoorLocked: Bool {
        (control?["doorLocked"] as? Bool) ?? false
    }
    private var isTrunkOpen: Bool {
        (control?["trunkOpen"] as? Bool) ?? false
    }
    private var isHoodOpen: Bool {
        (control?["hoodOpen"] as? Bool) ?? false
    }
    private var isWindowFrontLeftOpen: Bool {
        (control?["windowFrontLeft"] as? Bool) ?? false
    }
    private var isWindowFrontRightOpen: Bool {
        (control?["windowFrontRight"] as? Bool) ?? false
    }
    private var isWindowRearLeftOpen: Bool {
        (control?["windowRearLeft"] as? Bool) ?? false
    }
    private var isWindowRearRightOpen: Bool {
        (control?["windowRearRight"] as? Bool) ?? false
    }
    private var isHeadlightOn: Bool {
        (control?["headlight"] as? Bool) ?? false
    }
    private var isHazardOn: Bool {
        (control?["hazardLight"] as? Bool) ?? false
    }
    
    var body: some View {
        ZStack {
            // 车身轮廓
            Rectangle()
                .fill(Color.secondary.opacity(0.1))
                .frame(width: 120, height: 200)
                .cornerRadius(20)
            
            // 车顶
            Rectangle()
                .fill(Color.secondary.opacity(0.15))
                .frame(width: 100, height: 100)
                .offset(y: -30)
                .cornerRadius(15)
            
            // 车门状态指示
            // 左前门
            if isWindowFrontLeftOpen {
                Rectangle()
                    .fill(.red.opacity(0.6))
                    .frame(width: 8, height: 40)
                    .offset(x: -62, y: -20)
            } else {
                Rectangle()
                    .fill(.green.opacity(0.6))
                    .frame(width: 8, height: 40)
                    .offset(x: -62, y: -20)
            }
            // 右前门
            if isWindowFrontRightOpen {
                Rectangle()
                    .fill(.red.opacity(0.6))
                    .frame(width: 8, height: 40)
                    .offset(x: 54, y: -20)
            } else {
                Rectangle()
                    .fill(.green.opacity(0.6))
                    .frame(width: 8, height: 40)
                    .offset(x: 54, y: -20)
            }
            // 左后门
            if isWindowRearLeftOpen {
                Rectangle()
                    .fill(.red.opacity(0.6))
                    .frame(width: 8, height: 35)
                    .offset(x: -62, y: 30)
            } else {
                Rectangle()
                    .fill(.green.opacity(0.6))
                    .frame(width: 8, height: 35)
                    .offset(x: -62, y: 30)
            }
            // 右后门
            if isWindowRearRightOpen {
                Rectangle()
                    .fill(.red.opacity(0.6))
                    .frame(width: 8, height: 35)
                    .offset(x: 54, y: 30)
                } else {
                Rectangle()
                    .fill(.green.opacity(0.6))
                    .frame(width: 8, height: 35)
                    .offset(x: 54, y: 30)
            }
            
            // 车灯状态
            if isHeadlightOn {
                Circle()
                    .fill(.yellow.opacity(0.8))
                    .frame(width: 12, height: 12)
                    .offset(x: -35, y: -85)
                Circle()
                    .fill(.yellow.opacity(0.8))
                    .frame(width: 12, height: 12)
                    .offset(x: 35, y: -85)
            }
            if isHazardOn {
                Circle()
                    .fill(.orange.opacity(0.8))
                    .frame(width: 10, height: 10)
                    .offset(x: -35, y: -85)
                Circle()
                    .fill(.orange.opacity(0.8))
                    .frame(width: 10, height: 10)
                    .offset(x: 35, y: -85)
            }
            
            // 锁止状态中心图标
            Image(systemName: isDoorLocked ? "lock.fill" : "lock.open.fill")
                .font(.title2)
                .foregroundColor(isDoorLocked ? .green : .orange)
                .offset(y: 50)
            
            // 后备箱指示
            if isTrunkOpen {
                Text("🔓")
                    .font(.title3)
                    .offset(x: 0, y: 85)
            }
            if isHoodOpen {
                Text("🔓")
                    .font(.title3)
                    .offset(x: 0, y: -65)
            }
        }
        .frame(width: 140, height: 220)
    }
}
