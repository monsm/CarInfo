import SwiftUI
import MapKit
import CoreLocation


extension MapSpineView {

    struct Readout: Identifiable {
        let id: String
        let key: String
        let value: String
        var unit: String? = nil
        var cls: String = "na"
    }

    func readoutRow(_ items: [Readout]) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(items) { c in
                readoutCell(c)
            }
        }
    }

    @MainActor
    func readoutsPrimary(_ d: MapSpineData) -> [Readout] {
        let speed = VM.driveStatus(store.caches).speed
        return [
            Readout(id: "range", key: "续航",
                    value: d.rangeText == "--" ? "无数据" : d.rangeText,
                    unit: d.rangeText == "--" ? nil : "km"),
            Readout(id: "soc", key: "电量", value: "\(d.socPct)", unit: "%", cls: d.socCls),
            Readout(id: "speed", key: "车速",
                    value: speed == "--" ? "无数据" : speed,
                    unit: speed == "--" ? nil : "km/h")
        ]
    }

    @MainActor
    func readoutsMore(_ d: MapSpineData) -> [Readout] {
        let lock = VM.bodyStatus(store.caches).first { $0.label == "车锁" }
        let lowest = d.tyres.min { (Int($0.kpa) ?? Int.max) < (Int($1.kpa) ?? Int.max) }
        var out: [Readout] = [
            Readout(id: "tyre", key: "胎压",
                    value: lowest?.kpa ?? "无数据",
                    unit: lowest == nil ? nil : "kPa",
                    cls: lowest?.warn == true ? "bad" : "na"),
            Readout(id: "lock", key: "车锁",
                    value: lock?.text ?? "无数据",
                    cls: lock?.cls ?? "na")
        ]
        if let ttf = d.timeToFull, !ttf.isEmpty {
            out.append(Readout(id: "ttf", key: "充满", value: ttf))
        }
        return out
    }

    @MainActor
    func readoutsRest(_ d: MapSpineData) -> [Readout] {
        var out: [Readout] = []
        if !d.headingText.isEmpty, d.headingText != "--" {
            out.append(Readout(id: "heading", key: "航向", value: d.headingText))
        }
        if !d.gpsText.isEmpty, d.gpsText != "--" {
            out.append(Readout(id: "gps", key: "GPS", value: d.gpsText, cls: d.gpsCls))
        }
        return out
    }

    func readoutCell(_ r: Readout) -> some View {
        VStack(spacing: TokensSpacing.xxs) {
            HStack(alignment: .firstTextBaseline, spacing: TokensSpacing.xxs) {
                Text(r.value)
                    .font(TokensTypo.digits(16))
                    .foregroundStyle(r.cls == "na" ? TokensPalette.primary
                                                   : TokensPalette.statusColor(r.cls))
                if let unit = r.unit {
                    Text(unit)
                        .font(TokensTypo.caption2)
                        .foregroundStyle(TokensPalette.tertiary)
                }
            }
            Text(r.key)
                .font(TokensTypo.caption2)
                .foregroundStyle(TokensPalette.tertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(r.unit.map { "\(r.key) \(r.value) \($0)" } ?? "\(r.key) \(r.value)"))
    }


    @MainActor
    func drawerHead(_ d: MapSpineData, handle: DrawerHandle) -> some View {
        VStack(alignment: .leading, spacing: TokensSpacing.sm) {
            drawerGrabber(handle)
            summaryBar(d)
        }
    }

    @MainActor
    func summaryBar(_ d: MapSpineData) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: TokensSpacing.sm) {
            ForEach(readoutsPrimary(d)) { r in
                DSBigNumber(value: r.value,
                            unit: r.unit,
                            caption: r.key,
                            size: 30,
                            tint: r.cls == "na" ? TokensPalette.primary
                                                : TokensPalette.statusColor(r.cls),
                            alignment: .center,
                            weight: .bold)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .accessibilityElement(children: .contain)
    }

    @MainActor
    func drawerGrabber(_ handle: DrawerHandle) -> some View {
        Capsule()
            .fill(TokensPalette.track)
            .frame(width: 36, height: 5)
            .frame(maxWidth: .infinity)
            .frame(height: TokensSpacing.lg)
            .contentShape(Rectangle())
            .onTapGesture {
                TokensHaptic.select()
                handle.toggle()
            }
            .highPriorityGesture(drawerDrag(handle))
            .accessibilityElement()
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(Text("更多读数"))
            .accessibilityValue(Text(handle.open ? "已展开" : "已收起"))
            .accessibilityAction { handle.toggle() }
    }

    func drawerDrag(_ handle: DrawerHandle) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .onChanged { v in
                let travel = max(80, handle.height)
                let base: CGFloat = handle.open ? 1 : 0
                let next = min(1, max(0, base - v.translation.height / travel))
                if next != handle.reveal.wrappedValue { handle.reveal.wrappedValue = next }
            }
            .onEnded { v in
                let dy = v.predictedEndTranslation.height
                let wantsOpen = handle.reveal.wrappedValue > 0.5 ? (dy <= 60) : (dy < -60)
                handle.land(wantsOpen)
            }
    }

    @MainActor
    func readoutsDrawer(_ d: MapSpineData) -> some View {
        let rest = readoutsRest(d)
        return VStack(alignment: .leading, spacing: TokensSpacing.md) {
            readoutRow(readoutsMore(d))
            if !rest.isEmpty {
                DSDivider()
                readoutRow(rest)
            }
        }
    }

}

