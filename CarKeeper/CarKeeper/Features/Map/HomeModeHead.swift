import SwiftUI

struct HomeModeHead: View {
    let mode: HomeMode

    private let store = AppStore.shared

    private struct Hero {
        let value: String
        var unit: String? = nil
        var caption: String? = nil
        var size: CGFloat = 54
        var tint: Color = TokensPalette.primary
    }

    var body: some View {
        if mode == .now {
            EmptyView()
        } else {
            let h = hero
            DSBigNumber(value: h.value, unit: h.unit,
                        caption: h.caption, size: h.size, tint: h.tint)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
        }
    }


    @MainActor
    private var hero: Hero {
        switch mode {
        case .now:
            return Hero(value: "--")
        case .vehicle:
            let s = VM.vehicleSummary(store.car, store.controlCache)
            if let km = s?.mileage {
                return Hero(value: "\(km)", unit: "km",
                            caption: Self.line([s?.plate, s?.model]))
            }
            return Hero(value: s?.plate ?? "--", caption: "里程还没上报",
                        size: 44, tint: TokensPalette.secondary)
        case .charge:
            let e = VM.energy(store.caches, store.car)
            return Hero(value: "\(e.socPct)", unit: "%",
                        caption: Self.line([e.range.isEmpty ? nil : "续航 \(e.range)", e.carName]))
        case .control:
            let c = VM.comfortStatus(store.caches)
            return Hero(value: c.cabinTemp, unit: "°C",
                        caption: Self.line(["空调 \(c.acText)"]))
        case .trips:
            let today = store.tripHistory.filter { Calendar.current.isDateInToday($0.startTime) }
            let km = today.reduce(0.0) { $0 + $1.distanceKm }
            return Hero(value: String(format: "%.1f", km), unit: "km",
                        caption: today.isEmpty ? "今天还没有行程" : "今天 · \(today.count) 段")
        case .mine:
            let plate = VM.vehicleSummary(store.car, store.controlCache)?.plate
            if let u = VM.userModel(store.user) {
                let name = u.nickname.isEmpty ? u.name : u.nickname
                return Hero(value: name.isEmpty ? "--" : name,
                            caption: Self.line([plate, u.mobile]), size: 44)
            }
            return Hero(value: "--", caption: "还没取到账号信息", size: 44, tint: TokensPalette.secondary)
        }
    }

    private static func line(_ parts: [String?]) -> String {
        parts.compactMap { $0 }
            .filter { !$0.isEmpty && $0 != "--" }
            .joined(separator: " · ")
    }
}
