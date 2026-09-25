// =============================================================================
// MapCarPin.swift — 地图上的"一件物件"
// =============================================================================
//
// 这一屏只有一件实体：车。所以车钉不是图标，是**做出来的一件东西**：
//   • 外面的**弧就是电量**（不是装饰性圆环）—— 弧的长度 = SOC，起点在正上方
//   • 弧外面那一圈**刻度**是仪表盘的语言（转轴上的尺），不是花纹
//   • 里面那个小字是同一个数字（换数值时字宽不跳，monospacedDigit）
//   • 顶部那个缺口是**车头朝向**（来自 location 接口的 Heading，不是猜的）
//   • 脚下那圈**接地阴影**是"它站在这块地上"的唯一提示（平面化的钉像是贴上去的）
//   • 车灯是**算出来的**：亮度 = SkyLight.lamp（1 − 晴空辐照度/220，日照下几乎不亮）
//
// 三种艺术方向在这里的差别不是配色，是**画法**：
//   ring  夜光 —— 刻度盘 + 弧形 + 外发光 + 接地阴影（光只出现在车上）
//   ink   纸上 —— 墨线圈 + 虚线刻度 + 无发光（纸不会发光）
//   rule  巨字 —— 两层发丝细环 + 十字准线，没有实心填充（版面即内容）
//
// 尺寸约定：钉本体 76pt（外圈光晕可溢出），命中区由 MapSpineView 给（HIG 要 44pt）。
// =============================================================================
import SwiftUI

struct MapCarPin: View {
    /// 0…100
    var socPct: Int
    /// 车头朝向（度，0 = 正北）
    var heading: Double
    /// 选中态（点了钉 → 车控环展开）
    var isActive: Bool
    /// 车灯亮度 0…1，来自 SkyLight（真实太阳位置算出来的），默认不亮
    var lamp: Double = 0

    private var progress: Double { max(0, min(1, Double(socPct) / 100)) }

    /// 低电量的语义色由**数值**决定，不由主题决定（状态色是状态）
    private var ringColor: Color {
        if socPct < 15 { return TokensPalette.error }
        if socPct < 30 { return TokensPalette.warning }
        return TokensPalette.accent
    }

    var body: some View {
        ZStack {
            lampBloom

            Circle()
                .fill(ringColor.opacity(0.22))
                .frame(width: 62, height: 62)
                .blur(radius: 12)

            headingMark
        }
        .frame(width: 76, height: 76)
        .accessibilityElement()
        .accessibilityLabel(Text("车的位置"))
        .accessibilityValue(Text("电量 \(socPct)%，车头朝 \(Int(heading.rounded())) 度"))
    }

    // MARK: 车灯 —— 唯一一处"由光算出来"的发光
    /// 它亮不亮不取决于是不是夜里，而取决于**太阳给不给光**。
    /// 所以正午的钉是干净的，黄昏的钉脚下开始有暖光。
    @ViewBuilder
    private var lampBloom: some View {
        if lamp > 0.05 {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [TokensPalette.lightSource.opacity(0.34 * lamp),
                                 TokensPalette.lightSource.opacity(0)],
                        center: .center,
                        startRadius: 0,
                        endRadius: 78
                    )
                )
                .frame(width: 156, height: 156)
        }
    }

    // MARK: 车钉本体 —— 刻度盘 + 电量弧 + 车灯 + 接地阴影
    /// 它以前有三套（刻度盘 / 墨线圈 / 发丝准线），由**艺术方向**挑一套：
    /// 纸上的方向用墨线、巨字的方向用准线。2026-09-25 主题删到只剩原生，
    /// 于是另外两套也删了 —— 留着它们只会让人以为 "换一套" 这件事还存在着。
    private var ringStyle: some View {
        ZStack {
            groundShadow(opacity: 0.34)

            // 刻度盘：仪表盘的语言。一圈短尺，不是花纹 ——
            // 它让"弧"读起来像指针在表盘上走，而不是一条装饰圆弧。
            Circle()
                .stroke(TokensPalette.track,
                        style: StrokeStyle(lineWidth: 9, dash: [0.9, 14.3]))
                .frame(width: 58, height: 58)

            Circle()
                .fill(TokensPalette.surface)
                .frame(width: 48, height: 48)
                .shadow(color: TokensPalette.scrim.opacity(0.45), radius: 14, y: 6)

            Circle()
                .strokeBorder(TokensPalette.hairline, lineWidth: 0.5)
                .frame(width: 48, height: 48)

            // 未充电部分的轨道
            Circle()
                .stroke(TokensPalette.track, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                .frame(width: 58, height: 58)

            // 电量弧（从正上方开始，顺时针）
            Circle()
                .trim(from: 0, to: progress)
                .stroke(ringColor,
                        style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 58, height: 58)
                .shadow(color: ringColor.opacity(0.7), radius: 6)

            socText(color: TokensPalette.primary)
        }
    }

    // MARK: 接地阴影
    /// 一枚扁的椭圆、模糊、偏下 —— 它只做一件事：让钉**站在**地上。
    /// 平面化的钉会像贴纸浮在地图上，这一笔是廉价与不廉价的差别之一。
    private func groundShadow(opacity: Double) -> some View {
        Ellipse()
            // 车钉的落地阴影 = 光照不到的那一块，所以它和暗角同源（`TokensPalette.scrim`）
            .fill(TokensPalette.scrim.opacity(opacity))
            .frame(width: 36, height: 8)
            .blur(radius: 5)
            .offset(y: 25)
    }

    // MARK: 车头朝向
    /// 一个小缺口环，绕中心转 —— 它表达的是**从接口读到的 Heading**，不是装饰动画。
    private var headingMark: some View {
        ZStack {
            Circle()
                .trim(from: 0.0, to: 0.055)
                .stroke(TokensPalette.primary.opacity(0.65), lineWidth: 3)
                .frame(width: 46, height: 46)
                .rotationEffect(.degrees(heading - 90 - 5))
        }
    }

    private func socText(color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text("\(socPct)")
                .font(TokensTypo.digits(16).weight(.semibold))
                .foregroundStyle(color)
            Text("%")
                .font(TokensTypo.digits(9).weight(.medium))
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
/// 聚合后的标记：一个圆 + 组内**真实的站数**。
///
/// 它不是一个站，所以不能画得和一个站一样 —— 形状是这里唯一能传达「这不是一个点」的东西
/// （数字会变、位置会变，但「圈 vs 钉」一眼就能分开）。
struct MapClusterPin: View {
    let count: Int

    var body: some View {
        Text("\(count)")
            .font(TokensTypo.dataSmall)
            .foregroundStyle(TokensPalette.labelOnTint)
            .frame(width: 30, height: 30)
            .background(Circle().fill(TokensPalette.ambient))
            .overlay(Circle().strokeBorder(TokensPalette.canvas, lineWidth: 1.5))
            .accessibilityLabel(Text("\(count) 个充电站"))
    }
}

struct MapSpotPin: View {
    enum Kind {
        case hold(isLatest: Bool)
        case charger(distanceText: String)
        case issue
    }

    var kind: Kind
    /// 钉旁边的文字注记。异常才需要（"后备箱未关"这类必须一眼看见）——
    /// 它带文字阴影，因为地图底色不可控，注记必须在任何底上读得清。
    var label: String? = nil

    var body: some View {
        VStack(spacing: TokensSpacing.xs) {
            switch kind {
            case .hold(let isLatest):
                holdPin(isLatest: isLatest)
            case .charger(let distanceText):
                chargerPin(distanceText: distanceText)
            case .issue:
                issuePin
            }
            if let label, !label.isEmpty {
                Text(label)
                    .font(TokensTypo.digits(11))
                    .tracking(TokensTracking.label)
                    .foregroundStyle(TokensPalette.error)
                    .shadow(color: TokensPalette.scrim.opacity(0.55), radius: 3, y: 1)
                    .fixedSize()
            }
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
                .shadow(color: TokensPalette.scrim.opacity(0.35), radius: 8, y: 4)
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
        VStack(spacing: TokensSpacing.xs) {
            ZStack {
                Circle()
                    .fill(TokensPalette.surface)
                    .frame(width: 22, height: 22)
                    .overlay { Circle().strokeBorder(inkSoft.opacity(0.6), lineWidth: 1) }
                Image(safeSymbol: "bolt.fill", fallback: "bolt.fill")
                    .font(TokensTypo.fixed(10, weight: .semibold))
                    .foregroundStyle(TokensPalette.info)
            }
            // 价签式标注：**写在钉上的距离**，不随地图缩放变大
            Text(distanceText)
                .font(TokensTypo.digits(10).weight(.medium))
                .foregroundStyle(ink)
                .padding(.horizontal, TokensSpacing.xs)
                .padding(.vertical, TokensSpacing.xxs)
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
                .font(TokensTypo.fixed(11, weight: .bold))
                .foregroundStyle(TokensPalette.labelOnTint)
                .offset(y: 1)
        }
        .frame(width: 44, height: 44)
        .shadow(color: TokensPalette.error.opacity(0.6), radius: 8)
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

// =============================================================================
// CarGlyphShape —— 一台用线画出来的车
// =============================================================================
//
// 样品版里的车是**描边**画出来的（不是 SF Symbol）：一条腰线、一条底盘线、两个轮。
// 差别在于：符号是"图标语言"，描边是"制图语言"—— 后者放在地图与版面上都不违和。
// 坐标取自样品版（150×150 画布里的 44×23 那一段），这里按 rect 归一化。
// 只画车身与底盘 —— 两个轮由 `CarGlyph` 用两个圆补上（同一个图形，两种画法拆开）。
struct CarGlyphShape: Shape {
    func path(in rect: CGRect) -> Path {
        // 原始坐标空间：x 53…97、y 69…92
        func px(_ x: Double) -> CGFloat { rect.minX + CGFloat((x - 53) / 44) * rect.width }
        func py(_ y: Double) -> CGFloat { rect.minY + CGFloat((y - 69) / 23) * rect.height }

        var p = Path()
        // 车顶与腰线
        p.move(to: CGPoint(x: px(56), y: py(86)))
        p.addLine(to: CGPoint(x: px(60.5), y: py(73)))
        p.addQuadCurve(to: CGPoint(x: px(66.4), y: py(69)),
                       control: CGPoint(x: px(61.8), y: py(69)))
        p.addLine(to: CGPoint(x: px(83.6), y: py(69)))
        p.addQuadCurve(to: CGPoint(x: px(89.5), y: py(73)),
                       control: CGPoint(x: px(88.2), y: py(69)))
        p.addLine(to: CGPoint(x: px(94), y: py(86)))
        // 底盘线
        p.move(to: CGPoint(x: px(53), y: py(86)))
        p.addLine(to: CGPoint(x: px(97), y: py(86)))
        return p
    }
}

/// 完整的"一台车"：车身（描边路径）+ 两个轮（描边圆）。
/// 为什么拆开：椭圆子路径要带一个 CGAffineTransform 重载，而"两个圆"用视图表达更直白、
/// 也不用为一个装饰图形承担一个未核实签名的风险。
struct CarGlyph: View {
    var width: CGFloat = 30
    var height: CGFloat = 16
    var color: Color = TokensPalette.secondary

    /// 轮径 = 车宽的 10.8/44（样品版的原始坐标）
    private var wheel: CGFloat { width * 10.8 / 44 }

    var body: some View {
        ZStack(alignment: .topLeading) {
            CarGlyphShape()
                .stroke(color, lineWidth: 1.4)
            wheelView(centerX: 66)
            wheelView(centerX: 84)
        }
        .frame(width: width, height: height)
        .accessibilityHidden(true)
    }

    /// 轮心按样品版的坐标系定位（x 66 / 84、y 87）
    private func wheelView(centerX: Double) -> some View {
        Circle()
            .stroke(color, lineWidth: 1.4)
            .frame(width: wheel, height: wheel)
            .offset(x: width * CGFloat((centerX - 53) / 44) - wheel / 2,
                    y: height * CGFloat((87 - 69) / 23) - wheel / 2)
    }
}
