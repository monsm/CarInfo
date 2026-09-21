// =============================================================================
// Car.swift — LivingCar 渲染器
// 全屏车辆投影 + 呼吸光效 + 可点击交互区域
// =============================================================================
import SwiftUI

struct LivingCarView: View {
    let soc: Double           // 0-1
    let isCharging: Bool
    let isLocked: Bool
    let zones: [CarZone]
    let onZone: (CarZone) -> Void

    @State private var breatheProgress: CGFloat = 0
    @State private var selectedZone: CarZone?

    enum CarZone: String, CaseIterable {
        case doorFront, doorRear, trunk
        var id: String { rawValue }
        var tapArea: CGRect {
            switch self {
            case .doorFront: return CGRect(x: 0.15, y: 0.35, width: 0.25, height: 0.3)
            case .doorRear: return CGRect(x: 0.42, y: 0.35, width: 0.25, height: 0.3)
            case .trunk: return CGRect(x: 0.7, y: 0.4, width: 0.2, height: 0.2)
            }
        }
    }

    var body: some View {
        ZStack {
            carSilhouette
                .opacity(0.9)

            if isCharging {
                chargingBurst
            }

            interactiveZones
        }
        .frame(height: 200)
        .onAppear {
            withAnimation(KanseiMotion.breathe) {
                breatheProgress = 1.0
            }
        }
    }

    // MARK: - 车身剪影（简化版 Tesla 风格）
    private var carSilhouette: some View {
        ZStack {
            // 车身主体
            Path { path in
                path.move(to: CGPoint(x: 50, y: 140))
                path.addCurve(to: CGPoint(x: 80, y: 100),
                             control1: CGPoint(x: 60, y: 130),
                             control2: CGPoint(x: 70, y: 110))
                path.addLine(to: CGPoint(x: 120, y: 80))
                path.addCurve(to: CGPoint(x: 180, y: 80),
                             control1: CGPoint(x: 140, y: 70),
                             control2: CGPoint(x: 160, y: 70))
                path.addCurve(to: CGPoint(x: 220, y: 100),
                             control1: CGPoint(x: 200, y: 70),
                             control2: CGPoint(x: 210, y: 90))
                path.addLine(to: CGPoint(x: 250, y: 140))
                path.addArc(center: CGPoint(x: 90, y: 150), radius: 20,
                           startAngle: .degrees(180), endAngle: .degrees(0),
                           clockwise: false)
                path.addLine(to: CGPoint(x: 210, y: 150))
                path.addArc(center: CGPoint(x: 200, y: 150), radius: 20,
                           startAngle: .degrees(180), endAngle: .degrees(0),
                           clockwise: false)
                path.closeSubpath()
            }
            .fill(
                LinearGradient(
                    colors: [
                        KanseiPalette.primary.opacity(0.95),
                        KanseiPalette.primary.opacity(0.7)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            // 车窗
            Path { path in
                path.move(to: CGPoint(x: 125, y: 82))
                path.addLine(to: CGPoint(x: 175, y: 82))
                path.addLine(to: CGPoint(x: 195, y: 100))
                path.addLine(to: CGPoint(x: 115, y: 100))
                path.closeSubpath()
            }
            .fill(KanseiPalette.nightSurface.opacity(0.8))

            // 车轮
            Circle()
                .fill(KanseiPalette.nightSurface)
                .frame(width: 40, height: 40)
                .position(x: 90, y: 150)

            Circle()
                .fill(KanseiPalette.nightSurface)
                .frame(width: 40, height: 40)
                .position(x: 200, y: 150)

            // SOC 光带
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            KanseiPalette.ambient,
                            KanseiPalette.ambient.opacity(0.3)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 200 * soc, height: 2)
                .position(x: 100 + 100 * soc, y: 120)
                .blur(radius: 3)
                .opacity(breatheProgress * 0.8)
        }
    }

    // MARK: - 充电特效
    private var chargingBurst: some View {
        ZStack {
            Circle()
                .fill(KanseiPalette.info.opacity(0.3))
                .frame(width: 60, height: 60)
                .position(x: 250, y: 120)
                .blur(radius: 20)
                .kanseiBreathe(opacity: 0.5)

            Image(systemName: "bolt.fill")
                .font(.system(size: 24))
                .foregroundColor(KanseiPalette.info)
                .position(x: 250, y: 120)
        }
    }

    // MARK: - 可交互区域
    private var interactiveZones: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(Array(zones.enumerated()), id: \.offset) { _, zone in
                    let area = zone.tapArea
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            selectedZone == zone
                                ? KanseiPalette.ambient.opacity(0.3)
                                : Color.clear
                        )
                        .frame(width: geo.size.width * area.width)
                        .frame(height: geo.size.height * area.height)
                        .position(
                            x: geo.size.width * (area.origin.x + area.width / 2),
                            y: geo.size.height * (area.origin.y + area.height / 2)
                        )
                        .onTapGesture {
                            selectedZone = zone
                            withAnimation(KanseiMotion.tap) {
                                onZone(zone)
                            }
                        }
                }
            }
        }
    }
}
