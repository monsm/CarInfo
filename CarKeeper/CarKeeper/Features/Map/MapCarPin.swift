// =============================================================================
// MapCarPin.swift — 地图上的"一件物件"
// =============================================================================
//
// 这一屏只有一件实体：车。所以车钉不是图标，是**做出来的一件东西**。
//
// 2026-09-25（用户第 1 条：「车牌名删除 电量 删除 车放正，车用玻璃胶囊 不要黑乎乎」）
// 之后，它只剩两笔：
//   • 一枚**玻璃胶囊**里的一辆车（底是真玻璃 —— 见 `capsule`）
//   • 脚下那圈**接地阴影**（"它站在这块地上"的唯一提示：平面化的钉像是贴上去的）
// 外加一笔非实体：车灯的光晕（`lampBloom`，亮度 = SkyLight.lamp，日照下几乎不亮）。
//
// 删掉的是**刻度盘 / 电量弧 / 盘下那枚数字 / 按航向旋转 / 黑底盘** —— 五件东西，
// 每一件的账写在 `body` 上面那段（与抽屉里那一格的关系、正面视角的车转过 90° 会怎样）。
// 这里原本还有三种画法（夜光 / 纸上 / 巨字）由**艺术方向**挑一套；它们随艺术方向
// 一起删了（留着只会让人以为「换一套」这件事还存在着）。
//
// 尺寸约定：胶囊本体约 34×28，钉本体 68×44 —— 44 正是 HIG 的最小触控目标
//（光晕与阴影可以画到框外，但命中区就是这一块）。
// =============================================================================
import SwiftUI

struct MapCarPin: View {
    /// 车灯亮度 0…1，来自 SkyLight（真实太阳位置算出来的），默认不亮
    var lamp: Double = 0

    //  2026-09-25（用户第 1 条：「车牌名删除 电量 删除 车放正，车用玻璃胶囊 不要黑乎乎」）
    //  —— 这一枚钉从此只回答一件事：**车在哪儿**。
    //
    //  删掉的三件东西各有理由（不是“顺手精简”）：
    //    · **电量**（刻度盘 + 电量弧 + 盘下那枚数字徽标）：同一个数在抽屉里已经有一格
    //      （那一横上的「电量」），而钉上那一个还要靠一圈弧再重复一次。
    //      这也是上一轮我自己报过的那条：同一个电量在卡里是绿、在钉上是蓝 ——
    //      同一份数据同屏两种说法。
    //    · **按航向旋转**（`heading`）：`car.fill` 是**正面视角**的车，按航向转过 90°
    //      就越看越像“车歪了/翻了”。地图上表达朝向的通行画法是俯视车或箭头，
    //      那需要另一个符号，不是这一枚钉能承担的事。用户说「车放正」，
    //      那就让车正着站：它现在的含义是“这里有一辆车”，不是“车头朝东”。
    //      代价写在这里：`MapSpineData.headingDeg` 因此没有读者了 ——
    //      而它**保留**在数据层里（它是车端接口的原始字段，跟 `API-FIELD-MAP` 一起
    //      记着“车头朝哪儿”这件事；将来给俯视车钉或地图上的箭头用得到）。
    //      真正删掉的是“它必须画出来”这个假设。
    //    · **黑底盘**（`TokensPalette.surface` 画的实心圆）：深色模式下那正是一块黑。
    //      用户要「玻璃胶囊」—— 现在是一枚真的玻璃胶囊（`dsGlassCapsule`），
    //      浮在瓦片上、边缘有折射，而不是一片压在地图上的黑圆。
    //
    //  留着的是**车灯光晕**与**接地阴影**：前者是「此刻的光」在这一屏唯一的体现
    //  （由太阳的位置算出来），后者是让钉站在地上而不是浮着的那一笔。两者都与电量无关。
    //
    //  ⚠️ 这枚钉**没有点击动作**（旧参数 `isActive` 从来没有读者，本轮一并删了）。
    //  所以玻璃不传 `interactive` —— 一个不会自己动的玻璃不该装成会动（
    //  见 `DSGlass` 那条：按下去的压缩交给系统演，前提是真的有事发生）。
    var body: some View {
        ZStack {
            lampBloom
            groundShadow(opacity: 0.34)
            capsule
        }
        .frame(width: 68, height: 44)   // HIG 的最小触控目标就落在这上面
        .accessibilityElement()
        .accessibilityLabel(Text("车的位置"))
    }

    /// 车 —— 一枚玻璃胶囊里的一辆车。**不转**（理由见上）。
    private var capsule: some View {
        Image(safeSymbol: "car.fill", fallback: "car.fill")
            .font(TokensTypo.fixed(19, weight: .semibold))
            // 底是真玻璃、底下是**连续的画面**（地图瓦片）→ `TokensInk`（系统按材质调它），
            // 再叠一圈反色外发光（用户第 8 条那一件）：浅色瓦片上那辆车也看得见。
            .foregroundStyle(TokensInk.primary)
            .dsInkGlow()
            .padding(.horizontal, TokensSpacing.snug)
            .padding(.vertical, TokensSpacing.xs)
            // 胶囊：`.overMedia`（`.clear`，画面保持可见）—— 这一枚钉的底就是瓦片。
            .dsGlassCapsule(variant: .overMedia)
            .accessibilityHidden(true)
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

    // MARK: 接地阴影
    /// 一枚扁的椭圆、模糊、偏下 —— 它只做一件事：让钉**站在**地上。
    /// 平面化的钉会像贴纸浮在地图上，这一笔是廉价与不廉价的差别之一。
    private func groundShadow(opacity: Double) -> some View {
        Ellipse()
            // 车钉的落地阴影 = 光照不到的那一块，所以它和暗角同源（`TokensPalette.scrim`）
            .fill(TokensPalette.scrim.opacity(opacity))
            .frame(width: 34, height: 8)
            .blur(radius: 5)
            // 偏移量跟着胶囊：它的半高约 14pt，阴影落在它下沿之下一点点。
            .offset(y: 17)
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