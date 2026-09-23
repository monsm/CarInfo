import SwiftUI

// =============================================================================
//  MapSpineView · 「现在」这一档里，四个图层各自要写的那一列内容
// =============================================================================
//
//  单独一个文件是**关切不同**：`MapSpineView` 管这一屏的骨架（六页同屏、底条、
//  车牌徽标、底部浮动两卡），这里管的是「图上在看哪个问题时，首卡里写什么」。
//  骨架改动是结构性的（原型对齐），内容只随数据变 —— 两者混在一个 1200 行的文件里，
//  改任何一个都要在另一个的地盘里找位置。
//
//  另一条理由更实际：`scan/lintcfg.py` 的 `file_length` 盯着最大那个文件。
//  拆过之后骨架那一份约 1089 行，离 1200 的阈值有余量，而不是贴着它 ——
//  贴着阈值的代价是下一次**任何**小改动都要先做一遍取舍。
//
//  注：下面三个函数用到骨架里的三个成员，所以那三个在骨架里**不是 `private`**：
//  `private` 的作用域是文件，跨文件看不见。它们是 `nav`（换档/进深潜页）、
//  `chargers`（按车的位置搜到的充电站）、`emptyNotice`（取不到时那一句真话）。
// =============================================================================

extension MapSpineView {
    // ---- 行程 ----
    @ViewBuilder
    func tripsContent(_ d: MapSpineData) -> some View {
        DSSectionHeader(title: "行程", trailing: d.trips.isEmpty ? nil : "\(d.trips.count) 段")
        if d.trips.isEmpty {
            emptyNotice(MapSpineLayer.trips.emptyNote)
        } else {
            // 把话说在前面：线是起终点，不是轨迹
            Text("起点到终点（没有逐点轨迹）")
                .font(TokensTypo.caption)
                .foregroundStyle(TokensPalette.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(d.trips.prefix(3)) { t in
                HStack(alignment: .firstTextBaseline, spacing: TokensSpacing.sm) {
                    // 注意：`TokensTypo.data` 是**属性**，带尺寸的那支叫 digits(_:)
                    Text(t.timeText)
                        .font(TokensTypo.digits(13))
                        .foregroundStyle(TokensPalette.primary)
                    Text(String(format: "%.1f km", t.distanceKm))
                        .font(TokensTypo.digits(13))
                        .foregroundStyle(TokensPalette.primary)
                    Text("\(t.startSoc)% → \(t.endSoc)%")
                        .font(TokensTypo.caption)
                        .foregroundStyle(TokensPalette.secondary)
                    Spacer(minLength: 0)
                    if let eff = t.efficiency {
                        Text(String(format: "%.1f kWh/100km", eff))
                            .font(TokensTypo.caption)
                            .foregroundStyle(TokensPalette.tertiary)
                    }
                }
            }
            Button("全部行程") { nav.openMode(.trips) }
                .font(TokensTypo.footnote)
                .foregroundStyle(TokensPalette.accent)
                .buttonStyle(.plain)
        }
    }

    // ---- 停车 ----
    @ViewBuilder
    func holdsContent(_ d: MapSpineData) -> some View {
        DSSectionHeader(title: "停车", trailing: d.holds.isEmpty ? nil : "\(d.holds.count) 个点")
        if d.holds.isEmpty {
            emptyNotice(MapSpineLayer.holds.emptyNote)
        } else {
            ForEach(d.holds.prefix(3)) { h in
                HStack(alignment: .firstTextBaseline, spacing: TokensSpacing.sm) {
                    Text(h.isLatest ? "上次" : h.agoText)
                        .font(TokensTypo.caption)
                        .foregroundStyle(h.isLatest ? TokensPalette.accent : TokensPalette.tertiary)
                    Text(h.address)
                        .font(TokensTypo.footnote)
                        .foregroundStyle(TokensPalette.primary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(MapSpineData.agoText(h.time))
                        .font(TokensTypo.caption)
                        .foregroundStyle(TokensPalette.tertiary)
                }
            }
            Button("全部停车与旅程") { nav.openMode(.trips) }
                .font(TokensTypo.footnote)
                .foregroundStyle(TokensPalette.accent)
                .buttonStyle(.plain)
        }
    }

    // ---- 充电 ----
    @ViewBuilder
    func chargeContent(_ d: MapSpineData) -> some View {
        DSSectionHeader(title: "充电", trailing: chargers.isEmpty ? nil : "附近 \(chargers.count) 个")
        if let s = d.charging {
            HStack(alignment: .firstTextBaseline, spacing: TokensSpacing.sm) {
                Text(s.power)
                    .font(TokensTypo.digits(17))
                    .foregroundStyle(TokensPalette.info)
                Text(s.start + " → " + s.end)
                    .font(TokensTypo.caption)
                    .foregroundStyle(TokensPalette.secondary)
                Spacer(minLength: 0)
                if let full = d.timeToFull {
                    Text("充满还要 \(full)")
                        .font(TokensTypo.caption)
                        .foregroundStyle(TokensPalette.tertiary)
                }
            }
        }

        if chargers.isEmpty {
            emptyNotice(MapSpineLayer.charge.emptyNote)
        } else {
            ForEach(chargers.prefix(3)) { c in
                HStack(alignment: .firstTextBaseline, spacing: TokensSpacing.sm) {
                    Text(c.name)
                        .font(TokensTypo.footnote)
                        .foregroundStyle(TokensPalette.primary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(c.distanceText)
                        .font(TokensTypo.digits(13))
                        .foregroundStyle(TokensPalette.secondary)
                    Text(c.isEVCharger ? "快充" : "—")
                        .font(TokensTypo.caption)
                        .foregroundStyle(TokensPalette.tertiary)
                }
            }
            Text("按车的位置实时搜索")
                .font(TokensTypo.caption)
                .foregroundStyle(TokensPalette.tertiary)
        }
        Button("充电与账单") { nav.openMode(.charge) }
            .font(TokensTypo.footnote)
            .foregroundStyle(TokensPalette.accent)
            .buttonStyle(.plain)
    }
}
