import SwiftUI


struct DestinationCalculatorSection: View {
    private let store = AppStore.shared
    @State private var distance = ""
    @State private var canReach: Bool?

    var body: some View {
        DSSection(title: "目的地续航", footer: footer) {
            DSGroupRow {
                HStack(spacing: TokensSpacing.sm) {
                    TextField("目的地距离", text: $distance)
                        .keyboardType(.decimalPad)
                        .font(TokensTypo.body)
                    Text("km")
                        .font(TokensTypo.footnote)
                        .foregroundStyle(TokensPalette.secondary)
                    Button("算一算") { calculate() }
                        .font(TokensTypo.footnote.weight(.semibold))
                        .foregroundStyle(TokensPalette.ambient)
                        .disabled(Double(distance) == nil)
                }
            }
            if let reach = canReach {
                DSGroupRow(showsSeparator: false) {
                    DSKeyValueRow(key: "能否到达",
                                  value: reach ? "够用" : "可能不够",
                                  valueCls: reach ? "ok" : "warn")
                }
            }
        }
    }

    private var footer: String {
        guard let reach = canReach else {
            return "按当前续航留 15% 余量估算。"
        }
        return reach
            ? "按当前续航留 15% 余量算，够用。"
            : "按当前续航留 15% 余量算，可能不够。"
    }

    private func calculate() {
        guard let dist = Double(distance), dist > 0 else { canReach = nil; return }
        let e = VM.energy(store.caches, store.car)
        let range = Double(Int(e.range) ?? 0)
        let usable = e.socPct > 0 ? range * 0.85 : 0
        canReach = usable >= dist
    }
}
