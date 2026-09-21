// =============================================================================
// MapCarPin.swift — 地图上的"一件物件"
// =============================================================================
//
// 这一屏只有一件实体：车。所以车钉不是图标，是**做出来的一件东西**：
//   • 外面的**弧就是电量**（不是装饰性圆环）—— 弧的长度 = SOC，起点在正上方
//   • 里面那个小字是同一个数字（换数值时字宽不跳，monospacedDigit）
//   • 顶部那个缺口是**车头朝向**（来自 location 接口的 Heading，不是猜的）
//
// 三种艺术方向在这里的差别不是配色，是**画法**：
//   ring  夜光 —— 弧形 + 外发光 + 接地阴影（光只出现在车上）
//   ink   纸上 —— 墨线圈 + 实心墨点 + 无发光（纸不会发光）
//   rule  巨字 —— 两层发丝细环 + 十字准线，没有实心填充（版面即内容）
//
// 尺寸约定：钉本体 64pt，命中区由 MapSpineView 给（HIG 要 44pt）。
// =============================================================================
import SwiftUI

struct MapCarPin: View {
    /// 0…100
    var socPct: Int
    /// 车头朝向（度，0 = 正北）
    var heading: Double
    var style: MapPinStyle
    var allowsGlow: Bool
    /// 选中态（点了钉 → 车控环展开）
    var isActive: Bool

    private var progress: Double { max(0, min(1, Double(socPct) / 100)) }

    /// 低电量的语义色由**数值**决定，不由主题决定（状态色是状态）
    private var ringColor: Color {
        if socPct < 15 { return TokensPalette.error }
        if socPct < 30 { return TokensPalette.warning }
        return TokensPalette.accent
    }

    var body: some View {
        ZStack {
            if allowsGlow {
                Circle()
                    .fill(ringColor.opacity(0.22))
                    .frame(width: 62, height: 62)
                    .blur(radius: 12)
            }

            switch style {
            case .ring:  ringStyle
            case .ink:   inkStyle
            case .rule:  ruleStyle
            }

            headingMark
        }
        .frame(width: 76, height: 76)
        .accessibilityElement()
        .accessibilityLabel(Text("车的位置"))
        .accessibilityValue(Text("电量 \(socPct)%，车头朝 \(Int(heading.rounded())) 度"))
    }

    // MARK: 夜光 —— 弧形 + 发光 + 接地阴影
    private var ringStyle: some View {
        ZStack {
            Circle()
                .fill(TokensPalette.surface)
                .frame(width: 52, height: 52)
                .shadow(color: .black.opacity(0.45), radius: 14, y: 6)

            Circle()
                .strokeBorder(TokensPalette.hairline, lineWidth: 0.5)
                .frame(width: 52, height: 52)

            // 未充电部分的轨道
            Circle()
                .stroke(TokensPalette.track, style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
                .frame(width: 60, height: 60)

            // 电量弧（从正上方开始，顺时针）
            Circle()
                .trim(from: 0, to: progress)
                .stroke(ringColor,
                        style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 60, height: 60)
                .shadow(color: allowsGlow ? ringColor.opacity(0.7) : .clear, radius: 6)

            socText(color: TokensPalette.primary)
        }
    }

    // MARK: 纸上 —— 墨线圈（无发光、无阴影，纸是平的）
    private var inkStyle: some View {
        ZStack {
            Circle()
                .fill(TokensPalette.surface)
                .frame(width: 52, height: 52)

            Circle()
                .stroke(TokensPalette.primary, lineWidth: 1.6)
                .frame(width: 52, height: 52)

            // 电量：弧仍然是真的，但画成墨 —— 纸上只有墨与红
            Circle()
                .trim(from: 0, to: progress)
                .stroke(ringColor,
                        style: StrokeStyle(lineWidth: 3, lineCap: .butt))
                .rotationEffect(.degrees(-90))
                .frame(width: 62, height: 62)

            // 未充的部分用虚线，像手工标注的刻度
            Circle()
                .trim(from: progress, to: 1)
                .stroke(TokensPalette.primary.opacity(0.35),
                        style: StrokeStyle(lineWidth: 3, lineCap: .butt, dash: [1, 4]))
                .rotationEffect(.degrees(-90))
                .frame(width: 62, height: 62)

            socText(color: TokensPalette.primary)
        }
    }

    // MARK: 巨字 —— 发丝环 + 十字准线
    private var ruleStyle: some View {
        ZStack {
            Circle()
                .stroke(TokensPalette.primary.opacity(0.28), lineWidth: 0.5)
                .frame(width: 64, height: 64)
            Circle()
                .stroke(TokensPalette.primary.opacity(0.16), lineWidth: 0.5)
                .frame(width: 44, height: 44)

            // 准线：四条短线，把钉变成"瞄准标记"而不是"图标"
            ForEach(0..<4, id: \.self) { i in
                Rectangle()
                    .fill(TokensPalette.primary.opacity(0.30))
                    .frame(width: 8, height: 0.5)
                    .offset(y: -34)
                    .rotationEffect(.degrees(Double(i) * 90))
            }

            Circle()
                .trim(from: 0, to: progress)
                .stroke(ringColor, style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 64, height: 64)

            socText(color: TokensPalette.primary)
        }
    }

    // MARK: 车头朝向
    /// 一个小缺口环，绕中心转 —— 它表达的是**从接口读到的 Heading**，不是装饰动画。
    private var headingMark: some View {
        ZStack {
            Circle()
                .trim(from: 0.0, to: 0.055)
                .stroke(TokensPalette.primary.opacity(style == .ink ? 0.9 : 0.65), lineWidth: 3)
                .frame(width: style == .rule ? 52 : 46, height: style == .rule ? 52 : 46)
                .rotationEffect(.degrees(heading - 90 - 5))
        }
    }

    private func socText(color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text("\(socPct)")
                .font(.system(size: 17, weight: .semibold).monospacedDigit())
                .foregroundStyle(color)
            Text("%")
                .font(.system(size: 9, weight: .medium).monospacedDigit())
                .foregroundStyle(color.opacity(0.6))
        }
    }
}

// =============================================================================
// MapSpotPin —— 图上其他的点
// =============================================================================
//
// 三类小钉的**形状不同**（不是只有颜色不同）：
//   停车 = 方块（矩形是"位置标记"的通用形状，纸上方向尤其成立）
//   充电 = 圆 + 闪电
//   异常 = 三角（警示形状，与 ISO 2575 的警示几何同源）
//
// 全部是屏幕空间（放在 `Annotation` 里）—— **不随地图缩放变形**。
// 这是最容易被写错的一条：面积类的东西（热区）才该放进地图坐标空间。
struct MapSpotPin: View {
    enum Kind {
        case hold(isLatest: Bool)
        case charger(distanceText: String)
        case issue
    }

    var kind: Kind
    var style: MapPinStyle
    var allowsGlow: Bool

    var body: some View {
        switch kind {
        case .hold(let isLatest):
            holdPin(isLatest: isLatest)
        case .charger(let distanceText):
            chargerPin(distanceText: distanceText)
        case .issue:
            issuePin
        }
    }

    private var ink: Color { TokensPalette.primary }
    private var inkSoft: Color { TokensPalette.secondary }

    private func holdPin(isLatest: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(TokensPalette.surface)
                .frame(width: isLatest ? 20 : 16, height: isLatest ? 20 : 16)
                .overlay {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(ink.opacity(isLatest ? 0.85 : 0.45),
                                      lineWidth: isLatest ? 1.6 : 1)
                }
                .shadow(color: allowsGlow ? .black.opacity(0.35) : .clear, radius: 8, y: 4)
            if isLatest {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(ink)
                    .frame(width: 7, height: 7)
            }
        }
        .frame(width: 44, height: 44)
        .accessibilityLabel(Text(isLatest ? "上次停车位置" : "更早的停车位置"))
    }

    private func chargerPin(distanceText: String) -> some View {
        VStack(spacing: 3) {
            ZStack {
                Circle()
                    .fill(TokensPalette.surface)
                    .frame(width: 22, height: 22)
                    .overlay { Circle().strokeBorder(inkSoft.opacity(0.6), lineWidth: 1) }
                Image(systemName: "bolt.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(TokensPalette.info)
            }
            // 价签式标注：**写在钉上的距离**，不随地图缩放变大
            Text(distanceText)
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(ink)
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background {
                    Capsule().fill(TokensPalette.surface.opacity(0.92))
                }
                .overlay { Capsule().strokeBorder(TokensPalette.hairline, lineWidth: 0.5) }
        }
        .frame(width: 60, height: 40)
        .accessibilityLabel(Text("充电站，距离 \(distanceText)"))
    }

    private var issuePin: some View {
        ZStack {
            Triangle()
                .fill(TokensPalette.error)
                .frame(width: 20, height: 18)
            Text("!")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(TokensPalette.labelOnTint)
                .offset(y: 1)
        }
        .frame(width: 44, height: 44)
        .shadow(color: allowsGlow ? TokensPalette.error.opacity(0.6) : .clear, radius: 8)
        .accessibilityLabel(Text("有一条异常"))
    }
}

/// 等边三角形（警示形状）。放在顶层，不用 SwiftUI 的 Path 泛用名。
struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
