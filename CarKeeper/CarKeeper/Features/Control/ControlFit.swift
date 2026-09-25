import SwiftUI

// =============================================================================
//  ControlView · 「展开后有多挤」的度量
// =============================================================================
//
//  为什么单独一个文件：`ControlView.swift` 已经贴着 `scan/lintcfg.py` 的 1200 行
//  阈值（搬出这一块之前是 1168 行）—— 贴着阈值的代价是下一次**任何**小改动都要
//  先做一遍取舍。这一块与那一屏的其余部分关切也不同：那边管「车控这一屏长什么样」，
//  这里只回答一件事：「历史列表摊开之后会占几屏、放得下几条」。
//
//  因此下面用到的 `expandedRuns` / `historyFull` / `cardViewport` 都不是 `private`：
//  `private` 的作用域是文件，跨文件看不见。它们在 `ControlView` 里各自写明了为什么。
// =============================================================================

extension ControlView {
    // =========================================================================
    // MARK: 展开后有多挤（CardFit）
    // =========================================================================
    //
    //  用户 2026-09-25：「所有卡片内需要展开的都要严格计算展开后的拥挤程度，
    //  完全根据数据来，不能猜」。这一节的展开量是**历史条数 × 每条是否摊开**：
    //  一条收起约两行（名称 + 时间），摊开后多四行键值（开始/结束/耗时/结果）。
    //  历史桶埋在 UserDefaults 里，上限 50 条 —— 全部列出来、再摊开几条，
    //  卡片能长到三屏多，而这里没有内层滚动（叠叠乐自管手势）。
    //
    //  ★ 下面两行对应 `historyRow` 真画出来的东西：收起 = 名称 + 时间；
    //  摊开 = 再加四条 `DSKeyValueRow`（每条自带上下 8pt）。

    /// 卡片内容的真实宽度（视口已扣除叠叠乐左右各 18，这里是卡片自己的左右 18）
    var fitWidth: CGFloat { max(0, cardViewport.width - 2 * StackSpec.Card.padH) }

    func historyFitRow(_ item: AppStore.HistoryEntry) -> CardFit.Row {
        var blocks: [CardFit.Block] = [
            .text(item.name, .footnote, cap: nil),
            .gap(TokensSpacing.xxs),
            .text(item.startedAt.formatted(date: .omitted, time: .shortened), .caption2, cap: nil)
        ]
        if expandedRuns.contains(item.id) {
            // 四条键值行：开始 / 结束 / 耗时 / 结果（值与界面上写的是同一份）
            let rows: [(String, String)] = [
                ("开始", item.startedAt.formatted(date: .omitted, time: .standard)),
                ("结束", item.finishedAt.map { $0.formatted(date: .omitted, time: .standard) } ?? "—"),
                ("耗时", item.durationText),
                ("结果", item.resultText)
            ]
            blocks.append(.gap(TokensSpacing.sm))
            for (i, row) in rows.enumerated() {
                if i > 0 { blocks.append(.gap(TokensSpacing.sm * 2)) }   // 键值行自带上下 8
                blocks.append(.pair(row.0, .footnote, row.1, .footnote, cap: nil))
            }
        }
        return CardFit.Row(blocks, floor: TokensSpacing.row)
    }

    var historyPlan: CardFit.Plan {
        if historyFull { return .all }
        return CardFit.plan(filteredRuns.map(historyFitRow), width: fitWidth,
                            viewport: cardViewport, reserved: historyChrome)
    }

    var historyScreens: Double {
        CardFit.verdict(filteredRuns.map(historyFitRow), width: fitWidth,
                        viewport: cardViewport, reserved: historyChrome).screens
    }

    /// 这一组里除历史列表之外的东西：组标题 + 筛选分段 + 两个统计 + 展开手柄。
    /// 它们的高度也是算的（文字取真实行高，控件取自己声明的那个高度）。
    var historyChrome: CGFloat {
        // 组标题行
        var h = CardFit.textHeight("做过什么", style: .footnote, width: fitWidth)
        h += TokensSpacing.md + TokensSpacing.md
        // 筛选那一行（分段控件自己的高度就是它文字行的高）
        h += CardFit.Typo.footnote.lineHeight + TokensSpacing.md * 2
        // 两个统计那一行：大数字 + 小标签 + 上下内边距
        h += CardFit.Typo.fixed(28).lineHeight + TokensSpacing.xs
            + CardFit.Typo.caption2.lineHeight + TokensSpacing.xs * 2
        h += TokensSpacing.md
        // 展开手柄（它是分组里的一行）
        h += TokensSpacing.row
        return h
    }

}
