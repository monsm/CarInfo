import SwiftUI



struct DSSwipeStrip: View {

    struct Item: Identifiable, Hashable {
        let id: String
        let title: String

        init(id: String, title: String) {
            self.id = id
            self.title = title
        }
    }

    let items: [Item]
    @Binding var selectedID: String
    var availableWidth: CGFloat = 212
    var spillWidth: CGFloat = 212
    var onDragging: ((Bool) -> Void)?
    var onPosition: ((Double) -> Void)?

    struct RowDrag: Equatable {
        var translation: CGFloat
        var predicted: CGFloat
        var moved: Bool
    }

    var rowDrag: RowDrag? = nil

    static let barHeight: CGFloat = 47
    private let slot: CGFloat = 36
    private var pillPad: CGFloat { Self.barHeight * 0.37 }
    private var gapMax: CGFloat { Self.barHeight * 1.32 - slot }

    private func loupeWidth(_ pitch: CGFloat) -> CGFloat { pitch * (dragging ? 1.24 : 1.15) }
    private var loupeHeight: CGFloat { Self.barHeight * (dragging ? 1 : 0.86) }

    @State private var c: CGFloat = 0
    @State private var cBase: CGFloat?
    @State private var moved = false
    @State private var rowBase: CGFloat?
    @State private var rowPredicted: CGFloat = 0
    @State private var rowMoved = false

    private var index: Int? { items.firstIndex { $0.id == selectedID } }

    private var loupeVisible: Bool { index != nil || dragging }

    private var dragging: Bool {
        if cBase != nil { return moved }
        if rowBase != nil { return rowMoved }
        return false
    }


    private func ideal(_ i: Double, gap: CGFloat) -> CGFloat {
        CGFloat(i) * (slot + gap) + slot / 2
    }

    private func pitch(_ gap: CGFloat) -> CGFloat { slot + gap }

    private func fade(x: CGFloat, barW: CGFloat, pitch: CGFloat) -> Double {
        let visible = dragging ? max(barW, spillWidth) : barW
        let over = abs(x - barW / 2) - max(0, (visible - slot) / 2)
        guard over > 0 else { return 1 }
        return max(0.55, 1 - Double(over / max(1, pitch)) * 0.45)
    }

    private func gap(for width: CGFloat, shown: Int) -> CGFloat {
        let n = max(1, shown)
        if n == 1 { return gapMax }
        let fits = (width - 2 * pillPad - CGFloat(n) * slot) / CGFloat(n - 1)
        return min(gapMax, max(6, fits))
    }

    private func barWidth() -> CGFloat {
        max(120, availableWidth)
    }

    private func limits(width: CGFloat, gap: CGFloat) -> ClosedRange<CGFloat> {
        let lo = ideal(0, gap: gap)
        let hi = ideal(Double(max(0, items.count - 1)), gap: gap)
        return lo...hi
    }

    private func screenX(_ rowX: CGFloat, barW: CGFloat, c: CGFloat) -> CGFloat {
        barW / 2 + rowX - c
    }

    private func pvValue(c: CGFloat, gap: CGFloat) -> Double {
        Double((c - slot / 2) / pitch(gap))
    }

    private func clampC(_ raw: CGFloat, lim: ClosedRange<CGFloat>, gap: CGFloat) -> CGFloat {
        let slack = pitch(gap) * 0.5
        func soften(_ v: CGFloat, _ bound: CGFloat, _ direction: CGFloat) -> CGFloat {
            let over = (v - bound) * direction
            if over <= 0 { return v }
            let damped = 0.5 * (1 - pow(0.5, over / slack))
            return bound + damped * direction
        }
        if raw > lim.upperBound { return soften(raw, lim.upperBound, 1) }
        if raw < lim.lowerBound { return soften(raw, lim.lowerBound, -1) }
        return raw
    }


    var body: some View {
        let barW = barWidth()
        let gap = gap(for: max(barW, spillWidth), shown: items.count)
        let lim = limits(width: barW, gap: gap)
        let cShown = clampC(c, lim: lim, gap: gap)
        ZStack(alignment: .leading) {
            if !dragging {
                band(barW: barW)
                    .transition(.opacity)
            }
            capsule(barW: barW, gap: gap)
            labels(gap: gap, barW: barW, c: cShown)
        }
        .animation(TokensMotion.fade, value: dragging)
        .frame(width: barW, height: Self.barHeight)
        .contentShape(Rectangle())
        .highPriorityGesture(swipe(gap: gap, lim: lim, barW: barW))
        .onAppear { settle(animated: false, gap: gap, lim: lim) }
        .onChange(of: selectedID) { _, _ in settle(animated: true, gap: gap, lim: lim) }
        .onChange(of: rowDrag) { _, new in rowDragChanged(new, gap: gap, lim: lim) }
        .onChange(of: dragging) { _, now in onDragging?(now) }
        .onChange(of: availableWidth) { _, _ in settle(animated: false, gap: gap, lim: lim) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("功能"))
    }


    private func band(barW: CGFloat) -> some View {
        Capsule()
            .fill(TokensPalette.barFill)
            .overlay {
                Capsule().strokeBorder(TokensPalette.hairline, lineWidth: TokensHair.border)
            }
            .frame(width: barW, height: Self.barHeight)
            .allowsHitTesting(false)
    }

    private func capsule(barW: CGFloat, gap: CGFloat) -> some View {
        let shape = Capsule()
        let w = min(loupeWidth(pitch(gap)), max(slot, barW - 2 * TokensSpacing.xs))
        return Color.clear
            .frame(width: w, height: loupeHeight)
            .dsGlass(in: shape, interactive: false, dim: 0)
            .opacity(loupeVisible ? 1 : 0)
            .animation(TokensMotion.fade, value: loupeVisible)
            .animation(TokensMotion.settle, value: dragging)
            .position(x: barW / 2, y: Self.barHeight / 2)
            .allowsHitTesting(false)
    }

    private func labels(gap: CGFloat, barW: CGFloat, c: CGFloat) -> some View {
        ZStack {
            ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                let x = screenX(ideal(Double(i), gap: gap), barW: barW, c: c)
                Text(item.title)
                    .font(TokensTypo.fixed(13, weight: .semibold))
                    .tracking(TokensTracking.label)
                    .foregroundStyle(i == index ? TokensPalette.accent
                                                : TokensPalette.primary)
                    .opacity(fade(x: x, barW: barW, pitch: pitch(gap)))
                    .frame(width: slot)
                    .position(x: x, y: Self.barHeight / 2)
                    .accessibilityLabel(Text(item.title))
                    .accessibilityAddTraits(i == index ? [.isSelected, .isButton] : [.isButton])
                    .accessibilityAction { pick(i) }
            }
        }
        .frame(width: barW, height: Self.barHeight)
        .mask {
            Rectangle()
                .frame(width: dragging ? max(barW, spillWidth) : min(barW, pitch(gap) * 3),
                       height: Self.barHeight)
        }
        .allowsHitTesting(false)
    }


    private func swipe(gap: CGFloat, lim: ClosedRange<CGFloat>, barW: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                if cBase == nil {
                    cBase = c
                    moved = false
                    rowBase = nil
                    rowMoved = false
                }
                if abs(v.translation.width) > 8 { moved = true }
                let raw = (cBase ?? c) - v.translation.width
                c = clampC(raw, lim: lim, gap: gap)
                onPosition?(pvValue(c: c, gap: gap))
            }
            .onEnded { v in
                if !moved {
                    pick(nearest(to: v.location.x, gap: gap, barW: barW))
                } else {
                    snap(gap: gap, lim: lim, projected: projectedPV(v, gap: gap))
                }
                cBase = nil
            }
    }

    private func nearest(to x: CGFloat, gap: CGFloat, barW: CGFloat) -> Int {
        let rowX = x - barW / 2 + c
        let raw = (rowX - slot / 2) / pitch(gap)
        return min(max(Int(raw.rounded()), 0), max(0, items.count - 1))
    }

    private func rowDragChanged(_ e: RowDrag?, gap: CGFloat, lim: ClosedRange<CGFloat>) {
        guard cBase == nil else {
            rowBase = nil
            rowMoved = false
            return
        }
        guard let e else {
            if let base = rowBase {
                rowBase = nil
                if rowMoved {
                    snap(gap: gap, lim: lim,
                         projected: pvValue(c: base - rowPredicted, gap: gap))
                }
            }
            rowMoved = false
            return
        }
        if rowBase == nil { rowBase = c }
        guard let base = rowBase else { return }
        if e.moved { rowMoved = true }
        rowPredicted = e.predicted
        c = clampC(base - e.translation, lim: lim, gap: gap)
        onPosition?(pvValue(c: c, gap: gap))
    }

    private func landingPV(_ projected: Double?, gap: CGFloat) -> Double {
        let pos = pvValue(c: c, gap: gap)
        guard let projected else { return pos }
        let extra = projected - pos
        guard abs(extra) > 0.5 else { return pos }
        return pos + min(max(extra, -1), 1)
    }

    private func projectedPV(_ v: DragGesture.Value, gap: CGFloat) -> Double {
        pvValue(c: (cBase ?? c) - v.predictedEndTranslation.width, gap: gap)
    }

    private func snap(gap: CGFloat, lim: ClosedRange<CGFloat>, projected: Double? = nil) {
        let last = Double(max(0, items.count - 1))
        let pv = min(max(landingPV(projected, gap: gap), 0), last)
        let i = min(max(Int(pv.rounded()), 0), max(0, items.count - 1))
        guard items.indices.contains(i) else { return }
        if items[i].id == selectedID {
            withAnimation(TokensMotion.settle) {
                c = clampC(ideal(Double(i), gap: gap), lim: lim, gap: gap)
            }
            onPosition?(Double(i))
        } else {
            selectedID = items[i].id
            TokensHaptic.select()
        }
    }

    private func settle(animated: Bool, gap: CGFloat, lim: ClosedRange<CGFloat>) {
        let nearest = min(max(Int(pvValue(c: c, gap: gap).rounded()), 0),
                          max(0, items.count - 1))
        let i = index ?? nearest
        let target = clampC(ideal(Double(i), gap: gap), lim: lim, gap: gap)
        if animated {
            withAnimation(TokensMotion.settle) { c = target }
        } else {
            c = target
        }
        onPosition?(Double(i))
    }

    private func pick(_ i: Int) {
        guard items.indices.contains(i), items[i].id != selectedID else { return }
        selectedID = items[i].id
        TokensHaptic.select()
    }
}
