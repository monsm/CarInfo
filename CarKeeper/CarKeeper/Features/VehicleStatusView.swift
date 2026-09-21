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
        HStack(spacing: TokensSpacing.sm) {
            Image(safeSymbol: severity.icon, fallback: "exclamationmark.triangle.fill")
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
        HStack(spacing: TokensSpacing.md) {
            ForEach(availableModes, id: \.self) { mode in
                Button {
                    onModeChange(mode)
                } label: {
                    VStack(spacing: 4) {
                        Image(safeSymbol: mode.icon, fallback: "car.fill")
                            .font(.title3)
                        Text(mode.rawValue)
                            .font(.caption2)
                    }
                    .frame(width: 56, height: 56)
                    .background(mode == currentMode ? mode.color : Color.clear)
                    .foregroundColor(mode == currentMode ? .white : mode.color)
                    .cornerRadius(TokensRadius.medium)
                    .overlay(
                        RoundedRectangle(cornerRadius: TokensRadius.medium)
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

    // ⚠️ 字段名与取值语义必须对齐官方报文（对照小程序 utils/vm.js 的 bodyDetailModel / bodyStatus）：
    // 门 / 后备箱 / 前舱盖 / 天窗 / 车窗开度 / 灯光：0 = 关闭或已锁，非 0 = 开启或未锁。
    // 之前这里读的是 doorLocked / trunkOpen / hoodOpen / windowFrontLeft …… 这些键在长安接口里
    // 根本不存在（小程序 0 处命中），而且用的是 `as? Bool`（报文里是 0/1）→ 整张 2D 车图恒定「全关」。
    private func flag(_ names: [String]) -> Bool {
        let x = ciNumber(control, names)
        return x != nil && x != 0
    }

    /// 车窗：优先看开度（> 0 表示开启），没有开度再看状态位
    private func windowOpen(_ degreeKeys: [String], _ stateKeys: [String]) -> Bool {
        if let deg = ciNumber(control, degreeKeys) { return deg > 0 }
        return flag(stateKeys)
    }

    private var isDoorLocked: Bool {
        // 锁止：DriverDoorLock == 0 表示已锁
        ciNumber(control, ["DriverDoorLock"]).map { $0 == 0 } ?? false
    }
    private var isTrunkOpen: Bool { flag(["Trunk"]) }
    private var isHoodOpen: Bool { flag(["Hood"]) }
    private var isSunroofOpen: Bool { flag(["Sunroof"]) }
    private var isWindowFrontLeftOpen: Bool {
        windowOpen(["LeftAnteriorWindowDegree"], ["LeftFrontDoorrWindow"])
    }
    private var isWindowFrontRightOpen: Bool {
        windowOpen(["RightAnteriorWindowDegree"], ["RightFrontDoorrWindow"])
    }
    private var isWindowRearLeftOpen: Bool {
        windowOpen(["LeftRearWindowDegree"], ["LeftRearDoorrWindow"])
    }
    private var isWindowRearRightOpen: Bool {
        windowOpen(["RightRearWindowDegree"], ["RightRearWindow"])
    }
    private var isHeadlightOn: Bool {
        flag(["LowBeam"]) || flag(["HighBeam"])
    }
    /// 双闪：左右转向灯同时点亮（官方报文没有独立的 hazard 字段，故由转向灯推导）
    private var isHazardOn: Bool {
        flag(["LeftTurnSignal", "TurnLndicatorLeft"]) && flag(["RightTurnSignal", "TurnLndicatorRight"])
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

            // 天窗开启指示（Sunroof != 0）
            if isSunroofOpen {
                Image(safeSymbol: "rectangle.inset.filled", fallback: "rectangle")
                    .font(.system(size: 26))
                    .foregroundStyle(.orange)
                    .offset(y: -30)
                    .accessibilityLabel(Text("天窗已打开"))
            }

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

            // 车灯状态（原来是无含义的纯色圆点，现在用灯光 / 危险警示图标）
            if isHeadlightOn {
                Image(safeSymbol: "lightbulb.fill", fallback: "lightbulb")
                    .font(.system(size: 13))
                    .foregroundStyle(.yellow)
                    .offset(x: -35, y: -85)
                Image(safeSymbol: "lightbulb.fill", fallback: "lightbulb")
                    .font(.system(size: 13))
                    .foregroundStyle(.yellow)
                    .offset(x: 35, y: -85)
            }
            if isHazardOn {
                Image(safeSymbol: "exclamationmark.triangle.fill", fallback: "exclamationmark.triangle")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
                    .offset(x: -35, y: -85)
                Image(safeSymbol: "exclamationmark.triangle.fill", fallback: "exclamationmark.triangle")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
                    .offset(x: 35, y: -85)
            }

            // 锁止状态中心图标
            Image(safeSymbol: isDoorLocked ? "lock.fill" : "lock.open.fill", fallback: "lock.fill")
                .font(.title2)
                .foregroundColor(isDoorLocked ? .green : .orange)
                .offset(y: 50)

            // 后备箱指示（原来是 🔓 emoji，改成真正的图标）
            if isTrunkOpen {
                Image(safeSymbol: "archivebox.fill", fallback: "shippingbox.fill")
                    .font(.title3)
                    .foregroundStyle(.orange)
                    .offset(x: 0, y: 85)
                    .accessibilityLabel(Text("后备箱已打开"))
            }
            // 前机盖指示
            if isHoodOpen {
                Image(safeSymbol: "exclamationmark.triangle.fill", fallback: "exclamationmark.triangle")
                    .font(.title3)
                    .foregroundStyle(.orange)
                    .offset(x: 0, y: -65)
                    .accessibilityLabel(Text("前机盖已打开"))
            }
        }
        .frame(width: 140, height: 220)
    }
}
