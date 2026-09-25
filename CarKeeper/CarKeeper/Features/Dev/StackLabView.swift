import SwiftUI

// =============================================================================
//  StackLabView —— 卡片叠 + 底条 的真机预览页
// =============================================================================
//
//  它原来叫「叠法对照页」：原型 `design-preview/stack.html` 里那七种叠法在这里
//  各占一格，用来在真机上挑一种。2026-09-24 用户定下「只用吸附堆叠，其他全删」，
//  2026-09-25 滚动本身也交回系统 —— 对照的一半就没了对象（只有一种东西可看）。
//
//  页子留着，因为剩下的那一半仍然只有真机能判：**同一批卡、同一个窗口**，
//  「卡片高度参差时叠起来的观感」「底条展开时两侧圆钮的分缝」这类事，
//  在浏览器里和在手上是两件事。
//
//  哪些东西**故意**还留在这里当对照：
//    · 示例卡高矮不一 —— 一律等高会把「下一张在哪儿」这件事藏起来，
//      而它恰恰是「一叠卡」最容易被做错的地方。
//    · 底条的两种跟手形态（`DSSwipeStrip.Follow`）：那是条子自己的决定，仍在挑。
struct StackLabView: View {
    @Environment(\.dismiss) private var dismiss

    /// 演示用的档位（条子上那一格）
    @State private var demo: String = HomeMode.now.rawValue
    /// 条子的跟手方式（两种形态）
    @State private var follow: DSSwipeStrip.Follow = .row

    var body: some View {
        VStack(spacing: 0) {
            header
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
    // MARK: 顶部的说明
    // =========================================================================

    private var header: some View {
        VStack(alignment: .leading, spacing: TokensSpacing.xxs) {
            Text("卡片叠预览")
                .font(TokensTypo.headline)
                .foregroundStyle(TokensPalette.primary)
            Text("滚动手感归系统；这一页只看卡片本身")
                .font(TokensTypo.caption)
                .foregroundStyle(TokensPalette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, TokensSpacing.md)
        .padding(.top, TokensSpacing.xl)
        .padding(.bottom, TokensSpacing.sm)
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
    // MARK: 预览窗口
    // =========================================================================

    private var window: some View {
        StackPageView(accent: HomeMode.now.accent, label: "卡片叠预览", cards: demoCards)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(TokensPalette.canvas)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(TokensPalette.hairline)
                    .frame(height: TokensHair.line)
            }
    }

    /// 预览用的卡。**故意高矮不一**：卡片高度是内容撑出来的，
    /// 一律等高的示例会把「下一张在哪儿」这件事藏起来 ——
    /// 而它恰恰是这一叠最容易被做错的地方。
    private var demoCards: [StackCard] {
        var out: [StackCard] = []
        out.append(StackCard(id: "lead", content: AnyView(
            VStack(alignment: .leading, spacing: TokensSpacing.xs) {
                Text("一叠卡")
                    .font(TokensTypo.title)
                    .foregroundStyle(TokensPalette.primary)
                Text("按真实高度排队，滚到哪停哪、松手交给系统的惯性")
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
