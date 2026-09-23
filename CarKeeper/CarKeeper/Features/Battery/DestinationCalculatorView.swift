import SwiftUI

// =============================================================================
//  目的地续航 —— 充电页里的一段（不是一屏）
// =============================================================================
//  它原来是一个独立 sheet（`DestinationCalculatorView`），由充电页右上角
//  一个图标点开。2026-09-23 改成一节：**算一次续航不值得离开当前页** ——
//  它只是一次算术（当前续航 × 0.85），而 sheet 会盖住它要读的那些数字。
//
//  为什么留 15% 余量：表显续航是在标准工况下测的，空调、坡度、低温都会让它更短。
//  这个系数是**刻意保守**的：宁可说「到不了」让人中途补一次，也不要让人在高速上
//  发现数字算多了。它不是车端报的值，所以页面上明写「估算」。
// =============================================================================

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

    /// 页脚只在算完之后说结论 —— 没算之前它只是解释「这个数是怎么来的」。
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
