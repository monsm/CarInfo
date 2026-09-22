// =============================================================================
// MapSkyOverlay.swift — 地图上面那层"光"
// =============================================================================
//
// 样品版好看的地方，一半在**地图被光笼罩**：光池有方向、画面有暗角、表面有颗粒。
// 系统瓦片的颜色改不了（MapKit 没有这个 API，见 MAPKIT-FEASIBILITY.md），
// 但**盖在瓦片上的这一层可以完全受控** —— 这一层就是它。
//
// 每一层都对应 `SkyLight` 里的一个物理量，不是随手调的：
//   • 光池   —— 位置由**太阳方位角**决定，强度由高度角/环境光决定
//   • 雾霭   —— 光来的方向上一片暖雾 + 顶部压暗（后者顺便让顶栏在图上可读）
//   • 暗角   —— 日光下退场（白天没有暗角），夜里最强
//   • 颗粒   —— 胶片感；**确定性伪随机**，所以它不闪（闪的是噪点动画，不是胶片）
//
// 守住的规则：
//   ① 不吃点击（`allowsHitTesting(false)`）—— 它只是光，不是控件。
//   ② 按主题档位开关：原生主题 = 完全不画（原生必须逐像素等于切换前的现状）；
//      「纸上」不画光池（纸不会发光）；「巨字」只留发丝网格。
// =============================================================================
import SwiftUI

struct MapSkyOverlay: View {
    let light: SkyLight

    private var decor: CanvasDecor { TokensPalette.decor }

    @ViewBuilder
    var body: some View {
        switch decor {
        case .none:
            // 原生主题：一个像素都不加。原生 = 现状，这条不许打折。
            EmptyView()
        case .lightPool:
            ZStack {
                lightPools
                haze
                vignette
                grain
            }
        case .paperGrain:
            ZStack {
                haze
                vignette
                grain
            }
        case .hairlineGrid:
            ZStack {
                hairlineGrid
                vignette
            }
        }
    }

    // -------------------------------------------------------------------------
    // MARK: 光池
    // -------------------------------------------------------------------------
    /// 三团光，围着"光源落点"铺开。落点 = 屏幕中心 + 太阳方向的偏移量
    /// （半径由高度角决定：太阳越低，光越斜、铺得越远）。
    /// 三团的重心不在正中，是为了让画面**不对称** —— 对称是"理工男"的主要来源。
    private var lightPools: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let casterX = w * 0.5 + light.dirX
            let casterY = h * 0.45 + light.dirY
            ZStack(alignment: .topLeading) {
                pool(x: casterX - w * 0.55, y: casterY - w * 0.55,
                     radius: w * 1.00, strength: light.pool)
                pool(x: casterX + w * 0.25, y: casterY - w * 0.70,
                     radius: w * 0.72, strength: light.pool * 0.78)
                pool(x: casterX - w * 0.62, y: casterY + w * 0.10,
                     radius: w * 0.62, strength: light.pool * 0.62)
            }
        }
        .allowsHitTesting(false)
    }

    /// 一团光。颜色用主题的 `lightSource`（夜光=暖白，纸上=墨）——
    /// 写死的琥珀色会在纸面上戳出一个洞。
    private func pool(x: CGFloat, y: CGFloat, radius: CGFloat, strength: Double) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [TokensPalette.lightSource.opacity(strength),
                             TokensPalette.lightSource.opacity(0)],
                    center: .center,
                    startRadius: 0,
                    endRadius: radius
                )
            )
            .frame(width: radius * 2, height: radius * 2)
            .offset(x: x, y: y)
    }

    // -------------------------------------------------------------------------
    // MARK: 雾霭
    // -------------------------------------------------------------------------
    private var haze: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let cx = w * 0.5 + light.dirX * 0.35
            let cy = geo.size.height * 0.42 + light.dirY * 0.35
            ZStack(alignment: .topLeading) {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [hazeColor.opacity(light.pool * 0.75), hazeColor.opacity(0)],
                            center: .center,
                            startRadius: 0,
                            endRadius: w * 1.15
                        )
                    )
                    .frame(width: w * 2.3, height: w * 2.3)
                    .offset(x: cx - w * 1.15, y: cy - w * 1.15)

                // 顶部压暗：让顶栏的药丸在图上读得清（样品版也这么做）
                LinearGradient(
                    colors: [TokensPalette.canvas.opacity(0.46), TokensPalette.canvas.opacity(0)],
                    startPoint: .top,
                    endPoint: .center
                )
            }
        }
        .allowsHitTesting(false)
    }

    /// 雾的颜色：夜光是暖的（跟着光走），纸上是墨（像纸被压深了一点）。
    private var hazeColor: Color {
        switch decor {
        case .lightPool: return TokensPalette.accent
        case .paperGrain: return TokensPalette.primary
        default: return TokensPalette.canvas
        }
    }

    // -------------------------------------------------------------------------
    // MARK: 暗角
    // -------------------------------------------------------------------------
    /// 强度来自真实环境光：白天几乎看不见，夜里 0.62。
    private var vignette: some View {
        GeometryReader { geo in
            let maxDim = max(geo.size.width, geo.size.height)
            RadialGradient(
                colors: [Color.black.opacity(0), Color.black.opacity(light.vignette * vignetteScale)],
                center: UnitPoint(x: 0.5 + light.dirX / (geo.size.width * 2),
                                  y: 0.42 + light.dirY / (geo.size.height * 2)),
                startRadius: maxDim * 0.34,
                endRadius: maxDim * 0.78
            )
        }
        .allowsHitTesting(false)
    }

    /// 「纸上」不压得那么狠 —— 纸是亮的，压重了就像脏了。
    private var vignetteScale: Double {
        switch decor {
        case .lightPool: return 1.0
        case .paperGrain: return 0.42
        case .hairlineGrid: return 0.55
        default: return 0
        }
    }

    // -------------------------------------------------------------------------
    // MARK: 颗粒
    // -------------------------------------------------------------------------
    private var grain: some View {
        MapGrainLayer(strength: light.grain * grainScale)
            .allowsHitTesting(false)
    }

    private var grainScale: Double {
        switch decor {
        case .lightPool: return 1.0
        case .paperGrain: return 0.8
        default: return 0
        }
    }

    // -------------------------------------------------------------------------
    // MARK: 发丝网格（巨字方向：版面即内容）
    // -------------------------------------------------------------------------
    private var hairlineGrid: some View {
        GeometryReader { geo in
            Path { p in
                let step: CGFloat = 44
                var x: CGFloat = 0
                while x <= geo.size.width {
                    p.move(to: CGPoint(x: x, y: 0))
                    p.addLine(to: CGPoint(x: x, y: geo.size.height))
                    x += step
                }
                var y: CGFloat = 0
                while y <= geo.size.height {
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: geo.size.width, y: y))
                    y += step
                }
            }
            .stroke(TokensPalette.primary.opacity(0.07), lineWidth: 0.5)
        }
        .allowsHitTesting(false)
    }
}

// =============================================================================
// SkyFactTable —— 「光」表
// =============================================================================
//
// 一行一个事实：左边是这一栏叫什么 + **它是怎么来的**，右边是值。
// 为什么值得占一页：光好不好看是主观的，但「这一屏的光从哪来」不该是主观的。
// 把规则印在值的旁边，这一屏就变得可以被争论 —— 而可以被争论，才谈得上被设计。
struct SkyFactTable: View {
    let facts: [SkyFact]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(facts) { f in
                HStack(alignment: .firstTextBaseline, spacing: TokensSpacing.md) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(f.label)
                            .font(TokensTypo.caption)
                            .foregroundStyle(TokensPalette.secondary)
                        Text(f.note)
                            .font(TokensTypo.caption2)
                            .foregroundStyle(TokensPalette.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Text(f.value)
                        .font(TokensTypo.digits(13))
                        .foregroundStyle(TokensPalette.primary)
                        .fixedSize()
                }
                .padding(.vertical, TokensSpacing.sm)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(TokensPalette.hairline)
                        .frame(height: TokensHair.line)
                }
            }
        }
    }
}

// =============================================================================
// MapGrainLayer —— 胶片颗粒
// =============================================================================
//
// 为什么不用系统随机数：`Double.random` 每次重绘都是新的噪声，画面会**闪** ——
// 那是"噪点动画"，不是颗粒。这里用固定种子的线性同余发生器：
// 同一块屏幕每次画的点完全一样，所以它安静。
//
// 为什么粒度按面积算：屏幕越大颗粒越多，密度才一致。
struct MapGrainLayer: View {
    var strength: Double

    var body: some View {
        Canvas { ctx, size in
            // 确定性伪随机：种子固定 → 每一帧的颗粒位置完全一致
            var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
            func next() -> Double {
                seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                return Double((seed >> 11) & 0xFF_FFFF) / Double(0xFF_FFFF)
            }
            let count = Int(size.width * size.height / 240)
            for _ in 0..<count {
                let x = next() * size.width
                let y = next() * size.height
                let side = next() > 0.5 ? 1.2 : 0.7
                // 一个小方块：move + 三条线 + 闭合。不用带 transform 的那两个重载 ——
                // 这一点粒度不值得为一个装饰去赌一个没核过的默认参数。
                var dot = Path()
                dot.move(to: CGPoint(x: x, y: y))
                dot.addLine(to: CGPoint(x: x + side, y: y))
                dot.addLine(to: CGPoint(x: x + side, y: y + side))
                dot.addLine(to: CGPoint(x: x, y: y + side))
                dot.closeSubpath()
                ctx.fill(dot, with: .color(TokensPalette.primary.opacity(0.15 + next() * 0.5)))
            }
        }
        .opacity(strength)
    }
}
