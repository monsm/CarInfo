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
            //  标题传**空串**，不是 `d.carName`。
            //
            //  `Annotation` 的第一个参数是**图上会画的字**（MapKit 会把它画在钉下面）——
            //  它与我们自己的电量徽标叠在一起，而那个标题是服务端给的车名
            //（用户看到的「电车」，不是我们写的字）。用户 2026-09-25 第 1 条：
            //  「**车牌名删除** 电量 删除」—— 钉上现在只剩一辆车，下面什么字都没有。
            //  钉自己的尺寸（68×44，HIG 的最小触控目标）在 `MapCarPin` 里给：
            //  同一个几何只有一个出处，调用点不再重复一次。
            Annotation("", coordinate: c) {
                MapCarPin(lamp: d.sky(at: skyDate)?.lamp ?? 0)
            }
        }
        // 手机自己那一点（只在真的拿到位置时出现）—— 与车钉是**两个**点：
        // 「车在哪」与「我在哪」是两个问题（见 `MapQuickButtons.phonePin`）。
        phonePin()
        driveTraceLine(trace)
        rangeCircle(d)
        tripLines(d)
        hotspotCircles(d)
        holdPins(d)
        chargerPins
        issuePins(d)
    }

    /// 这一趟**开过的路**（用户 2026-09-26：「车动起来后在地图页画出行驶轨迹……
    /// 直至车辆熄火」）。
    ///
    ///  点从哪来：车端每报一次定位（`AppStore.saveCache`）就往 `DriveTrace` 里落一个，
    ///  点火清空成新的一段、熄火封口（不再长）。它**不是** `TripRecord` 那条
    ///  「起终点连线」（那条线是两点之间拼出来的，没有过程）—— 两者共存：
    ///  这一段是“正在开的这一趟”，而行程卡里那张图是“以前那一趟”。
    ///
    ///  画法与行程线同一套（先一道更宽更淡的亮晕，再一条主线）：同一件东西
    ///  （一条路径）在地图上只该有一种画法。
    @MapContentBuilder
    func driveTraceLine(_ t: DriveTrace) -> some MapContent {
        // 一个点画不出线（`MKPolyline` 要两点起）。它仍然是“真的在记”的证据 ——
        // 车钉旁边那一点就是刚走这一步。
        if t.points.count >= 2 {
            MapPolyline(MKPolyline(coordinates: t.points, count: t.points.count))
                .stroke(TokensPalette.info.opacity(0.18),
                        style: StrokeStyle(lineWidth: 11, lineCap: .round))
            MapPolyline(MKPolyline(coordinates: t.points, count: t.points.count))
                .stroke(TokensPalette.info,
                        style: StrokeStyle(lineWidth: 4, lineCap: .round))
        }
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
                                // 朝向与俯仰跟另两处镜头同一套（`cameraPitch` = 0，2D）——
                                // 点开一个聚合点不该把镜头打回 `.automatic` 的取景。
                                camera = .camera(MapCamera(centerCoordinate: cluster.coordinate,
                                                           distance: 1200,
                                                           pitch: cameraPitch))
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
