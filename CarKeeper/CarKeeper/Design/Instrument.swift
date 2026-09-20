// =============================================================================
// Instrument.swift — 仪表组件
// 112pt thin 数字 + 进度弧 + 状态指示
// =============================================================================
import SwiftUI

// MARK: - 巨型数字
// MARK: - 进度弧
struct DSArcProgress: View {
    let progress: Double
    let size: CGFloat
    let lineWidth: CGFloat
    let tint: Color
    let trackColor: Color
    let showValue: Bool

    init(
        progress: Double,
        size: CGFloat = 200,
        lineWidth: CGFloat = 8,
        tint: Color = Kansei.Color.ambient,
        trackColor: Color = Kansei.Color.glassBorder,
        showValue: Bool = true
    ) {
        self.progress = max(0, min(1, progress))
        self.size = size
        self.lineWidth = lineWidth
        self.tint = tint
        self.trackColor = trackColor
        self.showValue = showValue
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(trackColor, style: StrokeStyle(lineWidth: lineWidth))

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    tint,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.5, dampingFraction: 0.7), value: progress)

            if showValue {
                Circle()
                    .fill(Kansei.Color.nightSurface.opacity(0.8))
                    .frame(width: size * 0.7, height: size * 0.7)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - 三列状态条
// MARK: - 状态标签
// MARK: - 行项目
