import SwiftUI

struct ArcStack: View {

    var cards: [StackCard]
    var accent: Color = TokensPalette.accent
    var label: String = ""
    var onReachBottom: (() -> Void)? = nil

    @State private var current = 0

    @Environment(\.stackTopInset) private var topInset

    @Environment(\.stackBottomInset) private var bottomInset

    var body: some View {
        GeometryReader { geo in
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    VStack(spacing: StackSpec.Card.gap) {
                        ForEach(cards) { card in
                            card.render(accent: accent)
                                .frame(width: max(0, geo.size.width - 2 * StackSpec.Card.inset),
                                       alignment: .top)
                                .padding(.horizontal, StackSpec.Card.inset)
                                .id(card.id)
                        }
                    }
                    .frame(width: geo.size.width, alignment: .top)
                    .environment(\.cardViewport,
                                 CGSize(width: max(0, geo.size.width - 2 * StackSpec.Card.inset),
                                        height: max(1, geo.size.height)))
                }
                .accessibilityAdjustableAction { direction in
                    step(direction == .increment ? 1 : -1, proxy: proxy)
                }
                .ignoresSafeArea(edges: .top)
                .contentMargins(.top, topInset)
                .contentMargins(.bottom, bottomInset)
                .scrollEdgeEffectStyle(.soft, for: .top)
                .onScrollGeometryChange(for: Bool.self) { g in
                    g.contentSize.height > g.containerSize.height
                        && g.contentOffset.y + g.containerSize.height
                            >= g.contentSize.height - g.containerSize.height
                } action: { _, near in
                    if near { onReachBottom?() }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text(label.isEmpty ? "卡片列表" : label))
        }
    }


    private func step(_ delta: Int, proxy: ScrollViewProxy) {
        let last = max(0, cards.count - 1)
        let next = min(max(current + delta, 0), last)
        guard next != current, cards.indices.contains(next) else { return }
        current = next
        TokensHaptic.select()
        withAnimation(StackSpec.settle) {
            proxy.scrollTo(cards[next].id, anchor: next == last ? .bottom : .top)
        }
    }
}

struct StackPageView: View {
    var accent: Color = TokensPalette.accent
    var label: String = ""
    var cards: [StackCard]
    var onReachBottom: (() -> Void)? = nil

    var body: some View {
        ArcStack(cards: cards, accent: accent, label: label, onReachBottom: onReachBottom)
    }
}

struct StackCard: Identifiable {
    let id: String
    var title: String = ""
    var value: String? = nil
    var cls: String = "na"
    var at: Date? = nil
    var content: AnyView

    func render(accent: Color) -> AnyView {
        AnyView(
            GlassCard(accent: accent) {
                VStack(alignment: .leading, spacing: TokensSpacing.md) {
                    if !title.isEmpty {
                        GlassCardHead(title: title, value: value, cls: cls, at: at)
                    }
                    content
                }
            }
        )
    }
}
