import SwiftUI


extension ControlView {

    var fitWidth: CGFloat { max(0, cardViewport.width - 2 * StackSpec.Card.padH) }

    func historyFitRow(_ item: AppStore.HistoryEntry) -> CardFit.Row {
        var blocks: [CardFit.Block] = [
            .text(item.name, .footnote, cap: nil),
            .gap(TokensSpacing.xxs),
            .text(item.startedAt.formatted(date: .omitted, time: .shortened), .caption2, cap: nil)
        ]
        if expandedRuns.contains(item.id) {
            let rows: [(String, String)] = [
                ("开始", item.startedAt.formatted(date: .omitted, time: .standard)),
                ("结束", item.finishedAt.map { $0.formatted(date: .omitted, time: .standard) } ?? "—"),
                ("耗时", item.durationText),
                ("结果", item.resultText)
            ]
            blocks.append(.gap(TokensSpacing.sm))
            for (i, row) in rows.enumerated() {
                if i > 0 { blocks.append(.gap(TokensSpacing.sm * 2)) }
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

    var historyChrome: CGFloat {
        var h = CardFit.textHeight("做过什么", style: .footnote, width: fitWidth)
        h += TokensSpacing.md + TokensSpacing.md
        h += CardFit.Typo.footnote.lineHeight + TokensSpacing.md * 2
        h += CardFit.Typo.fixed(28).lineHeight + TokensSpacing.xs
            + CardFit.Typo.caption2.lineHeight + TokensSpacing.xs * 2
        h += TokensSpacing.md
        h += TokensSpacing.row
        return h
    }

}
