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
// 这里原本有三种画法（夜光 / 纸上 / 巨字），由**艺术方向**挑一套 ——
// 2026-09-25 主题只剩原生，另外两套随艺术方向一起删了（留着它们只会让人
// 以为「换一套」这件事还存在着）。现在只有一种：刻度盘 + 电量弧 + 车 + 接地阴影。
//
// 尺寸约定：钉本体 76×96（外圈光晕可溢出；多出来的 20pt 是圆盘下那枚电量徽标），
// 命中区由 MapSpineView 给（HIG 要 44pt）。
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

    //  ⚠️ 2026-09-25 第 9 条（用户：「车的位置没有车的图标了，像是被删了很多」）：
    //  这不是感觉，是真事 —— **`body` 从来没有调用过 `ringStyle`**。
    //
    //  那一刻（艺术主题删到只剩原生那一轮）`body` 里写的是 `headingMark` 一个，
    //  而刻度盘、电量弧、底盘、接地阴影、那个数字全在 `ringStyle` 里 ——
    //  于是车钉被画出来的只有两样：一团模糊的色光、一个小缺口环。
    //  一串「看起来该存在的东西」全变成了**到不了的代码**：不报错、不崩、编译全过，
    //  只是屏幕上少了一辆车（`scan/orphans.py` 只盖系统类型的扩展成员，看不见项目
    //  自己的计算属性 —— 这是它明说的盲区，所以这类错只能靠人在真机上看）。
    //
    //  现在把三样东西一起画出来，并且各说各的一件事：
    //    · `ringStyle`  = 刻度盘 + 电量弧 + 底盘（**电量的形状**）
    //    · `carGlyph`   = 车本身（**车头朝向**，它按 Heading 转 —— 缺口环因此删了，
    //                     同一件事不再用两种画法说）
    //    · `socBadge`   = 那个数字（从圆盘里搬到圆盘下：盘心让给了车）
    var body: some View {
        ZStack {
            lampBloom

            Circle()
                .fill(ringColor.opacity(0.22))
                .frame(width: 62, height: 62)
                .blur(radius: 12)

            ringStyle

            // 电量徽标：挂在圆盘**下面**（`offset` 让开接地阴影）。
            // 它带一枚与底盘同厚的底 —— 地图底色不可控，数字必须在任何底上读得清。
            socBadge
                .offset(y: 34)
        }
        .frame(width: 76, height: 96)
        // 钉心仍在圆盘中心（数字往上挪了 34，所以整框高 96、中心对在圆盘上）。
        .accessibilityElement()
        .accessibilityLabel(Text("车的位置"))
        .accessibilityValue(Text("电量 \(socPct)%，车头朝 \(Int(heading.rounded())) 度"))
    }

    /// 车本身 —— 钉的中心是**车**，不是数字。
    /// 它按 `heading` 转：车头指向哪边，这张小图就朝哪边。
    /// `car.fill` 在符号里是**正面视角**的车，转起来仍然是「车」；
    /// 而记「朝向」本来就不需要俯视图 —— 用户要的是「看得见一辆车」。
    private var carGlyph: some View {
        Image(safeSymbol: "car.fill", fallback: "car.fill")
            .font(TokensTypo.fixed(19, weight: .medium))
            .foregroundStyle(TokensPalette.primary)
            .rotationEffect(.degrees(heading))
            .accessibilityHidden(true)
    }

    /// 圆盘下方那枚小胶囊：电量数字。
    private var socBadge: some View {
        socText(color: ringColor)
            .padding(.horizontal, TokensSpacing.sm)
            .padding(.vertical, TokensSpacing.xxs)
            .background {
                Capsule().fill(TokensPalette.surface.opacity(0.92))
            }
            .overlay {
                Capsule().strokeBorder(TokensPalette.hairline, lineWidth: TokensHair.border)
            }
            .shadow(color: TokensPalette.scrim.opacity(0.35), radius: 6, y: 3)
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

            // 盘心：车（数字见 `socBadge`，它挂在圆盘下）
            carGlyph
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

    //  MARK: 已删除：车头朝向的缺口环 `headingMark`（2026-09-25）
    //
    //  它是一圈小缺口，绕中心转，表达从接口读到的 Heading。
    //  现在这件事由 `carGlyph` 的车**自己**说（车头朝哪儿，那辆车就朝哪儿）——
    //  同一个事实不再有两个画法：一个缺口环 + 一辆朝前的车，读起来是两种朝向。

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
//  已删除：`CarGlyphShape` / `CarGlyph`（线描的车，2026-09-25）
// =============================================================================
//
//  那是一台**描边画出来**的车（一条腰线、一条底盘线、两个轮），当时是地图与
//  版面上的「制图语言」。而且它**早就没有读者了** —— 车钉（`MapCarPin`）在
//  主题删到只剩原生那一轮之后就没有再引用它，留着只是「看起来还有一辆车」。
//
//  现在车钉里那辆车是 SF Symbol 的 `car.fill`（见 `MapCarPin.carGlyph`）：
//  它按 Heading 转，而且在任何底色上都读得出来 —— 手写路径做不到这一条。
//