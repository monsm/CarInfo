// =============================================================================
// MapStyleSpec.swift — 艺术方向 → 真实 MapKit 配置
// =============================================================================
//
// 为什么需要这一层：三种艺术方向在**设计稿**上是三种画法，在**真机**上是三种
// 配置组合。这份文件就是那张对应表 —— 让"选方向"这件事落到真实 API 上。
//
// 先说清 MapKit 的边界（详见 CarKeeper/MAPKIT-FEASIBILITY.md，逐项核过官方文档）：
//   MapKit 的全部旋钮只有五个 —— 地图族（standard/imagery/hybrid）、海拔、
//   **强调度（.muted）**、POI 过滤、路况。**没有任何公开 API 能改道路/街区/水面的颜色。**
//   所以：
//     • 夜光  能落地：`.muted` + 暗色让系统地图自己退到背景，我们叠光层
//     • 纸上  **MapKit 做不到**：系统瓦片长不出纸与墨，只能压暗 + 纸色蒙版（打折方案）
//     • 巨字  最省：地图退成极淡的一层，几乎不依赖地理层
//
// 一条必须守住的架构规则（写错会出现"缩小时钉变小米、放大时钉变墙"）：
//   • 钉（车 / 停车点 / 充电站 / 异常）→ **屏幕空间**（`Annotation`），不随缩放变形
//   • 轨迹 / 热区（面积类）→ **地理空间**（`MapPolyline` / `MapCircle` / `MapPolygon`），随缩放
//
// 命名约定：顶层类型 + 顶层枚举，不嵌套泛用名（历史事故见 ArtTheme.swift 的说明）。
// =============================================================================
import SwiftUI
import MapKit

// MARK: - 车钉的画法
/// 三套方向各自的"一件物件"。车钉不是图标，是**这一屏唯一的实体**。
enum MapPinStyle: String {
    /// 夜光：发光环。光只出现在车上。
    case ring
    /// 纸上：墨线圈 + 手绘感的断口。纸上没有发光。
    case ink
    /// 巨字：发丝细环 + 十字准线。靠线与字距，不靠颜色。
    case rule
}

// MARK: - 一套地图取值
struct MapStyleSpec {
    /// 交给 SwiftUI `Map` 的样式（**这是 MapKit 真正的旋钮**）
    var style: MapStyle
    /// 叠在系统瓦片上的蒙版色。系统瓦片改不了色，只能在上面盖一层。
    var scrim: Color
    /// 蒙版不透明度。0 = 完全不盖（原生主题）。
    var scrimOpacity: Double
    /// 相机朝向（度）。夜光转 7°，让路网斜走 —— 正交网格是"理工男"的主要来源。
    var cameraHeading: Double
    /// 车钉画法
    var pinStyle: MapPinStyle
    /// 允许发光（纸上不允许：纸不会发光）
    var allowsGlow: Bool
    /// 文案：这套配置**为什么**长这样（真机页上会显示，可争论）
    var note: String

    /// 相机距离（米）。三套方向共用：都在街区尺度上看自己的车。
    var cameraDistance: Double { 1_400 }
}

extension ArtTheme {
    /// 这个艺术方向在真 MapKit 上的取值。
    var mapSpec: MapStyleSpec {
        switch self {
        // ---------------------------------------------------------------------
        case .nocturne:
            return MapStyleSpec(
                style: .standard(elevation: .flat,
                                 emphasis: .muted,
                                 pointsOfInterest: .excludingAll,
                                 showsTraffic: false),
                scrim: artMapHex(0x0A0910),
                scrimOpacity: 0.55,
                cameraHeading: 7,
                pinStyle: .ring,
                allowsGlow: true,
                note: "系统瓦片压到 .muted 再盖 55% 暗色"
            )
        // ---------------------------------------------------------------------
        case .paper:
            // 诚实标注：这一套在 MapKit 上**只是打折方案**。
            // 纸与墨需要整层自建地图（MapLibre + 自己的样式），代价详见文档第 3.2 节。
            return MapStyleSpec(
                style: .standard(elevation: .flat,
                                 emphasis: .muted,
                                 pointsOfInterest: .excludingAll,
                                 showsTraffic: false),
                scrim: artMapHex(0xF2E9D8),
                scrimOpacity: 0.30,
                cameraHeading: 0,
                pinStyle: .ink,
                allowsGlow: false,
                note: "压暗 + 纸色蒙版；真机上仍是现代地图"
            )
        // ---------------------------------------------------------------------
        case .typographic:
            return MapStyleSpec(
                style: .standard(elevation: .flat,
                                 emphasis: .muted,
                                 pointsOfInterest: .excludingAll,
                                 showsTraffic: false),
                scrim: artMapHex(0x0A0A0C),
                scrimOpacity: 0.78,
                cameraHeading: 0,
                pinStyle: .rule,
                allowsGlow: false,
                note: "地图退成 78% 蒙版"
            )
        // ---------------------------------------------------------------------
        case .native:
            // 原生 = 切换前的现状：**一个旋钮都不动**。
            // 用 `MapStyle.standard` 这个静态值（不传参数），所以它等于系统默认，
            // 也等于引入艺术主题之前的地图。
            return MapStyleSpec(
                style: .standard,
                scrim: .clear,
                scrimOpacity: 0,
                cameraHeading: 0,
                pinStyle: .ring,
                allowsGlow: true,
                note: "系统地图原样"
            )
        // -----------------------------------------------------------------
        // 2026-09-24 第八轮新增 16 套。全部是「`muted` + 色温蒙版」的同一机制，
        // 只差蒙版色与不透明度（MapKit 没有改瓦片颜色的公开 API，见文件头注）。
        case .frost:
            return MapStyleSpec(style: mutedSpec, scrim: artMapHex(0xE8F1F2),
                                scrimOpacity: 0.20, cameraHeading: 0, pinStyle: .ring,
                                allowsGlow: true, note: "瓦片盖 20% 冷白雾")
        case .celadon:
            return MapStyleSpec(style: mutedSpec, scrim: artMapHex(0xC8D4CC),
                                scrimOpacity: 0.30, cameraHeading: 0, pinStyle: .ink,
                                allowsGlow: false, note: "瓦片盖 30% 青灰（釉色）")
        case .darkroom:
            return MapStyleSpec(style: mutedSpec, scrim: artMapHex(0x2A0E06),
                                scrimOpacity: 0.75, cameraHeading: 0, pinStyle: .ring,
                                allowsGlow: true, note: "瓦片压 75% 暗 + 暖红罩")
        case .phosphor:
            return MapStyleSpec(style: mutedSpec, scrim: artMapHex(0x061A0C),
                                scrimOpacity: 0.80, cameraHeading: 0, pinStyle: .ring,
                                allowsGlow: true, note: "瓦片压 80% 暗 + 深绿罩")
        case .dune:
            return MapStyleSpec(style: mutedSpec, scrim: artMapHex(0xC89A5A),
                                scrimOpacity: 0.25, cameraHeading: 0, pinStyle: .ink,
                                allowsGlow: false, note: "瓦片盖 25% 暖沙")
        case .snowfield:
            return MapStyleSpec(style: mutedSpec, scrim: artMapHex(0x0B1830),
                                scrimOpacity: 0.70, cameraHeading: 0, pinStyle: .ring,
                                allowsGlow: true, note: "瓦片压 70% 冷蓝黑")
        case .blueprint:
            return MapStyleSpec(style: mutedSpec, scrim: artMapHex(0x10284A),
                                scrimOpacity: 0.45, cameraHeading: 0, pinStyle: .rule,
                                allowsGlow: false, note: "瓦片盖 45% 深蓝")
        case .amber:
            return MapStyleSpec(style: mutedSpec, scrim: artMapHex(0x3A2608),
                                scrimOpacity: 0.35, cameraHeading: 0, pinStyle: .ring,
                                allowsGlow: true, note: "瓦片盖 35% 暖橙")
        case .brushed:
            return MapStyleSpec(style: mutedSpec, scrim: artMapHex(0x8A8A90),
                                scrimOpacity: 0.30, cameraHeading: 0, pinStyle: .rule,
                                allowsGlow: false, note: "瓦片盖 30% 中性灰")
        case .cellar:
            return MapStyleSpec(style: mutedSpec, scrim: artMapHex(0x1E0E20),
                                scrimOpacity: 0.75, cameraHeading: 0, pinStyle: .ring,
                                allowsGlow: true, note: "瓦片压 75% 暗 + 深绛紫罩")
        case .cinnabar:
            return MapStyleSpec(style: mutedSpec, scrim: artMapHex(0xF6F1E6),
                                scrimOpacity: 0.20, cameraHeading: 0, pinStyle: .ink,
                                allowsGlow: false, note: "瓦片盖 20% 暖白")
        case .tundra:
            return MapStyleSpec(style: mutedSpec, scrim: artMapHex(0x6E8A82),
                                scrimOpacity: 0.40, cameraHeading: 0, pinStyle: .rule,
                                allowsGlow: false, note: "瓦片盖 40% 青灰绿")
        case .inkwash:
            return MapStyleSpec(style: mutedSpec, scrim: artMapHex(0xF4F4F0),
                                scrimOpacity: 0.30, cameraHeading: 0, pinStyle: .ink,
                                allowsGlow: false, note: "瓦片盖 30% 近白（留白）")
        case .forge:
            return MapStyleSpec(style: mutedSpec, scrim: artMapHex(0x0C0808),
                                scrimOpacity: 0.85, cameraHeading: 0, pinStyle: .ring,
                                allowsGlow: true, note: "瓦片压 85% 暗（铸铁）")
        case .mist:
            return MapStyleSpec(style: mutedSpec, scrim: artMapHex(0x9AAAB4),
                                scrimOpacity: 0.45, cameraHeading: 0, pinStyle: .rule,
                                allowsGlow: false, note: "瓦片盖 45% 灰蓝")
        case .neon:
            return MapStyleSpec(style: mutedSpec, scrim: artMapHex(0x140A24),
                                scrimOpacity: 0.80, cameraHeading: 0, pinStyle: .ring,
                                allowsGlow: true, note: "瓦片压 80% 暗 + 深紫黑罩")
        }
    }

    /// 「`muted` + 关 POI + 关路况 + 平海拔」：新增 16 套共用的那个地图族
    ///（它们要的都是「瓦片退到背景、我们罩色温」，与夜光同一机制）。
    private static let mutedSpec: MapStyle = MapStyle.standard(
        elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false)
}


// MARK: - 颜色构造
/// 顶层私有工具：0xRRGGBB → Color。与 ArtTheme 的 artHex 同一套做法。
/// （两个文件各自持有一个私有构造函数，是为了让本文件能独立读懂 ——
///   不跨文件依赖一个 private 符号。）
private func artMapHex(_ hex: UInt32, alpha: Double = 1) -> Color {
    Color(
        .sRGB,
        red: Double((hex >> 16) & 0xFF) / 255,
        green: Double((hex >> 8) & 0xFF) / 255,
        blue: Double(hex & 0xFF) / 255,
        opacity: alpha
    )
}
