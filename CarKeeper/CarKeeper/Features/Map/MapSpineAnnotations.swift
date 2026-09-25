import SwiftUI
import MapKit

// =============================================================================
//  MapSpineView · 「地图上画什么」—— 车钉、行程线、续航圈、热区、停车点、
//  充电桩（带聚合）、异常点
// =============================================================================
//
//  单独一个文件是**关切不同**：`MapSpineView` 管这一屏的骨架（六页同屏、底条、
//  镜头、图层、手势），这里只回答一件事：底图上那几个东西长什么样、什么时候出现。
//  骨架改动是结构性的（原型对齐），图上的画法只随数据与图层变。
//
//  另一条理由更实际：`scan/lintcfg.py` 的 `file_length` 盯着最大那个文件。
//  这一轮骨架又到 1207 行（阈值 1200），按那个阈值的用法是把东西**搬出去**。
//  拆过之后骨架那一份约 1085 行，离阈值有余量 —— 贴着阈值的代价是下一次
//  **任何**小改动都要先做一遍取舍，这个账在 `MapSpineLayers.swift` 的头注里
//  已经写过两次了。
//
//  注：下面用到的 `layer` / `chargers` / `camera` / `skyDate` / `phonePin()` 因此
//  **不是 `private`** —— `private` 的作用域是文件，跨文件看不见（`scan/extguard.py`
//  判据 ③）。它们各自的说明写在骨架里。
// =============================================================================

extension MapSpineView {
    @MapContentBuilder
    func mapContent(_ d: MapSpineData) -> some MapContent {
        if let c = d.carCoordinate {
            Annotation(d.carName, coordinate: c) {
                MapCarPin(
                    socPct: d.socPct,
                    heading: d.headingDeg,
                    isActive: false,
                    lamp: d.sky(at: skyDate)?.lamp ?? 0
                )
                .frame(width: 44, height: 44)   // HIG 最小触控目标就落在钉中心
            }
        }
        // 手机自己那一点（只在真的拿到位置时出现）—— 与车钝是**两个**点：
        // 「车在哪」与「我在哪」是两个问题（见 `MapQuickButtons.phonePin`）。
        phonePin()
        rangeCircle(d)
        tripLines(d)
        hotspotCircles(d)
        holdPins(d)
        chargerPins
        issuePins(d)
    }

    /// 行程：**一条一条的起终点连线**（不是轨迹 —— TripRecord 里没有轨迹点）
    ///
    /// 每条线画两遍：先一条更宽更淡的（光晕），再一条细的（主线）。
    /// 只加这一点，路线就从「贴在瓦片上的线」变成「发着光的路径」——
    /// 原型里那个观感差主要就差在这一层，而不是差在底图上。
    /// 颜色仍是**同一个 accent**，没有新增颜色。
    @MapContentBuilder
    func tripLines(_ d: MapSpineData) -> some MapContent {
        if layer == .trips {
            ForEach(d.trips) { t in
                MapPolyline(MKPolyline(coordinates: [t.from, t.to], count: 2))
                    .stroke(TokensPalette.accent.opacity(0.16),
                            style: StrokeStyle(lineWidth: 10, lineCap: .round))
                MapPolyline(MKPolyline(coordinates: [t.from, t.to], count: 2))
                    .stroke(TokensPalette.accent.opacity(0.9),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
        }
    }

    /// 续航圈：半径就是车报的 RemainedPowerMile（米）。车没报就不画 —— 不猜。
    @MapContentBuilder
    func rangeCircle(_ d: MapSpineData) -> some MapContent {
        if layer == .now, let c = d.carCoordinate, let meters = d.rangeMeters, meters > 0 {
            MapCircle(center: c, radius: meters)
                .stroke(TokensPalette.accent,
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [4, 5]))
                .foregroundStyle(TokensPalette.accent.opacity(0.05))
        }
    }

    /// 常停热区：停车史聚出来的圈。描边示形状，填充透明度随次数加深。
    @MapContentBuilder
    func hotspotCircles(_ d: MapSpineData) -> some MapContent {
        if layer == .holds {
            ForEach(d.hotspots) { h in
                MapCircle(center: h.center, radius: h.radiusMeters)
                    .stroke(TokensPalette.accent.opacity(0.55),
                            style: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                    .foregroundStyle(TokensPalette.accent.opacity(h.visits >= 3 ? 0.14 : 0.07))
            }
        }
    }

    @MapContentBuilder
    func holdPins(_ d: MapSpineData) -> some MapContent {
        if layer == .holds {
            ForEach(d.holds) { h in
                Annotation("停车点", coordinate: h.coordinate) {
                    MapSpotPin(kind: .hold(isLatest: h.isLatest))
                }
            }
        }
    }

    /// 显示用的聚合结果（地图与面板共用同一份）
    var chargerClusters: [MapChargerCluster] {
        MapSpineData.clusterChargers(chargers)
    }

    @MapContentBuilder
    var chargerPins: some MapContent {
        if layer == .charge {
            // 一个位置只放一个标记：孤立的是钉子，挨在一起的是一个带**真实站数**的圈。
            // 点圈 = 放大到那一组 —— 聚合不能变成「点不开的东西」。
            ForEach(chargerClusters) { cluster in
                Annotation("充电站", coordinate: cluster.coordinate) {
                    if cluster.count == 1 {
                        MapSpotPin(kind: .charger(distanceText: cluster.nearest.distanceText))
                    } else {
                        Button {
                            withAnimation(TokensMotion.value) {
                                camera = .camera(MapCamera(centerCoordinate: cluster.coordinate,
                                                           distance: 1200))
                            }
                        } label: {
                            MapClusterPin(count: cluster.count)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @MapContentBuilder
    func issuePins(_ d: MapSpineData) -> some MapContent {
        if layer == .now {
            ForEach(d.issues) { i in
                Annotation("异常", coordinate: i.coordinate) {
                    // 异常必须在图上自己说出来 —— 要点一下才知道是哪一条，不算「看见」
                    MapSpotPin(kind: .issue, label: i.title)
                }
            }
        }
    }
}
