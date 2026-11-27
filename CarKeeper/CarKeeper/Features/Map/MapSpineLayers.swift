import SwiftUI


extension MapSpineView {
    @ViewBuilder
    func tripsContent(_ d: MapSpineData) -> some View {
        DSSectionHeader(title: "行程", trailing: d.trips.isEmpty ? nil : "\(d.trips.count) 段")
        if d.trips.isEmpty {
            emptyNotice(MapSpineLayer.trips.emptyNote)
        } else {
            Text("起点到终点（没有逐点轨迹）")
                .font(TokensTypo.caption)
                .foregroundStyle(TokensPalette.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(d.trips.prefix(3)) { t in
                HStack(alignment: .firstTextBaseline, spacing: TokensSpacing.sm) {
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
