import SwiftUI

// =============================================================================
//  StackLabView —— 叠法对照页（在真机上挑，而不是在原型里挑）
// =============================================================================
//
//  原型 `design-preview/stack.html` 里那七种叠法在这里各占一格：**同一个窗口、
//  同一批卡、同一套手势**，只换 `StackVariant`。所以「哪一种好看」在这里是可比的 ——
//  如果每种各写一套示例内容，比的就不是叠法而是内容。
//
//  选中哪一种会写进 UserDefaults（`StackSpec.variantKey`），
//  六页下次进来就是那一种（`StackPageView` 的默认值读它）。**默认弧出**。
//
//  为什么它必须存在（而不是我选一种就完事）：手感与观感在真机上和在浏览器里
//  是两件事 —— 弧度的角度、消失带的宽度、透镜的跟手，数字对得上不代表看着对。
//  这一步是把纸面判断变成事实的唯一环节。
struct StackLabView: View {
    @Environment(\.dismiss) private var dismiss

    /// 演示用的档位（条子上那一格）
    @State private var demo: String = HomeMode.now.rawValue
    /// 条子的跟手方式（两种形态）
    @State private var follow: DSSwipeStrip.Follow = .row
    /// 当前叠法。**不持久化**：它只决定这一屏显示哪一种
    @State private var variant: StackVariant = StackSpec.chosen
    /// 已经写进偏好的那一种（用来显示「六页已跟随」）
    @State private var saved: StackVariant = StackSpec.chosen

    var body: some View {
        VStack(spacing: 0) {
            header
            variants
            followRow
            window
            DSSwipeStrip(items: HomeMode.stripItems, selectedID: $demo, follow: follow)
                .padding(.horizontal, TokensSpacing.md)
                .padding(.bottom, TokensSpacing.sm)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(TokensPalette.canvas)
        .overlay(alignment: .topTrailing) {
            Button("关闭") { dismiss() }
                .font(TokensTypo.footnote)
                .foregroundStyle(TokensPalette.accent)
                .padding(TokensSpacing.md)
        }
    }

    // =========================================================================
    // MARK: 顶部的选择器
    // =========================================================================

    private var header: some View {
        VStack(alignment: .leading, spacing: TokensSpacing.xxs) {
            Text("叠法对照")
                .font(TokensTypo.headline)
                .foregroundStyle(TokensPalette.primary)
            Text("同一个窗口、同一批卡，只换上下滑动的方式。挑中即全站生效")
                .font(TokensTypo.caption)
                .foregroundStyle(TokensPalette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, TokensSpacing.md)
        .padding(.top, TokensSpacing.xl)
        .padding(.bottom, TokensSpacing.sm)
    }

    /// 叠法现在是唯一的（用户 2026-09-24：只用吸附堆叠，其他全删），
    /// 所以对照页不再有「七选一」—— 这里显示一句固定说明。
    private var variants: some View {
        VStack(alignment: .leading, spacing: TokensSpacing.xxs) {
            Text("叠法：吸附堆叠（唯一）")
                .font(TokensTypo.footnote)
                .foregroundStyle(TokensPalette.primary)
            Text("松手停在哪儿就算哪儿 —— 不回弹、不自动吸到档位")
                .font(TokensTypo.micro)
                .foregroundStyle(TokensPalette.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, TokensSpacing.md)
    }

    private var followRow: some View {
        HStack(spacing: TokensSpacing.sm) {
            Text("条子")
                .font(TokensTypo.caption)
                .foregroundStyle(TokensPalette.tertiary)
            DSSegmented(options: DSSwipeStrip.Follow.allCases.map { (value: $0, title: $0.title) },
                        selection: $follow)
        }
        .padding(.horizontal, TokensSpacing.md)
        .padding(.vertical, TokensSpacing.sm)
    }

    // =========================================================================
    // MARK: 对照窗口
    // =========================================================================

    private var window: some View {
        StackPageView(variant: variant, accent: HomeMode.now.accent,
                      label: "叠法对照", cards: demoCards)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(TokensPalette.canvas)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(TokensPalette.hairline)
                    .frame(height: TokensHair.line)
            }
    }

    /// 对照用的卡。**故意高矮不一**：卡片高度是内容撑出来的，
    /// 一律等高的示例会把「下一页在哪儿」这件事藏起来 ——
    /// 而它恰恰是七种叠法差别最大的地方。
    private var demoCards: [StackCard] {
        var out: [StackCard] = []
        out.append(StackCard(id: "lead", content: AnyView(
            VStack(alignment: .leading, spacing: TokensSpacing.xs) {
                Text("弧出")
                    .font(TokensTypo.title)
                    .foregroundStyle(TokensPalette.primary)
                Text("卡片等距排开，贴边淡出并转出画面")
                    .font(TokensTypo.footnote)
                    .foregroundStyle(TokensPalette.secondary)
            })))
        let rows: [(String, String, Int)] = [
            ("电池", "68%", 1),
            ("胎压", "2.4 / 2.4 / 2.5 / 2.5", 4),
            ("续航", "412 km", 1),
            ("行程", "今天 3 段 · 42.6 km", 3),
            ("车门", "已锁", 1),
            ("空调", "24°C", 2)
        ]
        for (i, r) in rows.enumerated() {
            out.append(StackCard(id: "r\(i)", title: r.0, value: r.1, cls: "ok",
                                 content: AnyView(
                VStack(alignment: .leading, spacing: TokensSpacing.xs) {
                    ForEach(0..<r.2, id: \.self) { k in
                        GlassCardEmpty(text: "示例第 \(k + 1) 行", icon: "minus")
                    }
                })))
        }
        return out
    }
}
