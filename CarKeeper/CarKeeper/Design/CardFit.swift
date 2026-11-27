import SwiftUI
import UIKit


enum CardFit {

    static func contentWidth(_ viewport: CGSize) -> CGFloat {
        max(0, viewport.width - 2 * StackSpec.Card.padH)
    }

    enum Typo {
        case title3, headline, body, callout, subheadline, footnote, caption, caption2
        case fixed(CGFloat)
        case monoCaption

        var uiFont: UIFont {
            switch self {
            case .title3:      return UIFont.preferredFont(forTextStyle: .title3)
            case .headline:    return UIFont.preferredFont(forTextStyle: .headline)
            case .body:        return UIFont.preferredFont(forTextStyle: .body)
            case .callout:     return UIFont.preferredFont(forTextStyle: .callout)
            case .subheadline: return UIFont.preferredFont(forTextStyle: .subheadline)
            case .footnote:    return UIFont.preferredFont(forTextStyle: .footnote)
            case .caption:     return UIFont.preferredFont(forTextStyle: .caption1)
            case .caption2:    return UIFont.preferredFont(forTextStyle: .caption2)
            case .fixed(let size): return UIFont.systemFont(ofSize: size)
            case .monoCaption:
                return UIFont.monospacedSystemFont(
                    ofSize: UIFont.preferredFont(forTextStyle: .caption1).pointSize,
                    weight: .regular)
            }
        }

        var lineHeight: CGFloat { uiFont.lineHeight }
    }


    enum Block {
        case text(String, Typo, cap: Int?)
        case pair(String, Typo, String, Typo, cap: Int?)
        case gap(CGFloat)
        case fixed(CGFloat)
    }

    struct Row {
        var blocks: [Block]
        var padTop: CGFloat
        var padBottom: CGFloat
        var floor: CGFloat

        init(_ blocks: [Block] = [],
             padTop: CGFloat = 0, padBottom: CGFloat = 0, floor: CGFloat = 0) {
            self.blocks = blocks
            self.padTop = padTop
            self.padBottom = padBottom
            self.floor = floor
        }

        static func text(_ text: String, _ style: Typo, cap: Int? = nil,
                         padTop: CGFloat = 0, padBottom: CGFloat = 0) -> Row {
            Row([.text(text, style, cap: cap)], padTop: padTop, padBottom: padBottom)
        }

        static func keyValue(_ key: String, _ value: String,
                             pad: CGFloat = TokensSpacing.sm) -> Row {
            Row([.pair(key, .footnote, value, .footnote, cap: nil)],
                padTop: pad, padBottom: pad)
        }

        static func item(title: String, titleStyle: Typo = .body, cap: Int? = nil,
                         extras: [Block] = [],
                         padTop: CGFloat = TokensSpacing.sm,
                         padBottom: CGFloat = TokensSpacing.sm) -> Row {
            Row([.text(title, titleStyle, cap: cap)] + extras,
                padTop: padTop, padBottom: padBottom, floor: TokensSpacing.row)
        }
    }


    private static let measuringHeight: CGFloat = 100_000
    private static let measuringWidth: CGFloat = 100_000

    static func textWidth(_ text: String, style: Typo) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        return (text as NSString).boundingRect(
            with: CGSize(width: measuringWidth, height: measuringHeight),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: style.uiFont],
            context: nil).width
    }

    static func lineCount(_ text: String, style: Typo, width: CGFloat, cap: Int? = nil) -> Int {
        if text.isEmpty { return 0 }
        if let cap, cap <= 1 { return 1 }
        guard width > 0 else { return 1 }
        let font = style.uiFont
        let rect = (text as NSString).boundingRect(
            with: CGSize(width: width, height: measuringHeight),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil)
        let h = max(font.lineHeight, rect.height)
        var n = Int((h / font.lineHeight).rounded(.up))
        if let cap { n = min(n, cap) }
        return max(1, n)
    }

    static func height(of row: Row, width: CGFloat) -> CGFloat {
        var sum: CGFloat = 0
        for b in row.blocks {
            switch b {
            case .text(let s, let style, let cap):
                sum += textHeight(s, style: style, width: width, cap: cap)
            case .pair(let left, let ls, let right, let rs, let cap):
                sum += max(textHeight(left, style: ls, width: width, cap: cap),
                           textHeight(right, style: rs, width: width, cap: cap))
            case .gap(let x), .fixed(let x):
                sum += x
            }
        }
        return max(row.floor, row.padTop + sum + row.padBottom)
    }

    static func textHeight(_ text: String, style: Typo,
                           width: CGFloat, cap: Int? = nil) -> CGFloat {
        CGFloat(lineCount(text, style: style, width: width, cap: cap)) * style.lineHeight
    }

    static func fittingPrefix(_ text: String, style: Typo, width: CGFloat,
                              lines: Int) -> (prefix: String, rest: String)? {
        guard lines > 0, width > 0 else { return nil }
        let chars = Array(text)
        guard chars.count > 1 else { return nil }
        if lineCount(text, style: style, width: width) <= lines { return nil }
        var lo = 1
        var hi = chars.count - 1
        var best = 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if lineCount(String(chars[0..<mid]), style: style, width: width) <= lines {
                best = mid
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        return (String(chars[0..<best]), String(chars[best...]))
    }

    static func height(of rows: [Row], width: CGFloat) -> CGFloat {
        rows.reduce(CGFloat(0)) { $0 + height(of: $1, width: width) }
    }


    struct Verdict {
        var height: CGFloat
        var limit: CGFloat
        var isKnown: Bool

        var screens: Double {
            guard isKnown, limit > 0 else { return 0 }
            return Double(height / limit)
        }

    }

    static func verdict(_ rows: [Row], width: CGFloat,
                        viewport: CGSize, reserved: CGFloat = 0) -> Verdict {
        let h = height(of: rows, width: width)
        return Verdict(height: h,
                       limit: max(0, viewport.height - reserved),
                       isKnown: viewport.height > 0 && width > 0)
    }


    struct TextPlan {
        var text: String
        var restLines: Int
        var screens: Double
        var truncatable: Bool

        static func all(_ text: String) -> TextPlan {
            TextPlan(text: text, restLines: 0, screens: 0, truncatable: false)
        }
    }

    static func plan(text: String, style: Typo, width: CGFloat,
                     viewport: CGSize, reserved: CGFloat = 0) -> TextPlan {
        guard viewport.height > 0, width > 0, !text.isEmpty else { return .all(text) }
        let total = lineCount(text, style: style, width: width)
        let budget = max(0, viewport.height - reserved)
        let allowed = Int((budget / style.lineHeight).rounded(.down))
        let screens = Double((textHeight(text, style: style, width: width) + reserved)
                             / viewport.height)
        guard allowed > 0, total > allowed else {
            return TextPlan(text: text, restLines: 0, screens: screens, truncatable: false)
        }
        guard let split = fittingPrefix(text, style: style, width: width, lines: allowed) else {
            return TextPlan(text: text, restLines: 0, screens: screens, truncatable: false)
        }
        return TextPlan(text: split.prefix, restLines: total - allowed,
                        screens: screens, truncatable: true)
    }


    enum Plan {
        case unknown
        case all
        case chunk(keep: Int, rest: Int)

        var keep: Int? {
            if case .chunk(let keep, _) = self { return keep }
            return nil
        }

        var hidden: Int {
            if case .chunk(_, let rest) = self { return rest }
            return 0
        }
    }

    static func plan(_ rows: [Row], width: CGFloat,
                     viewport: CGSize, reserved: CGFloat = 0) -> Plan {
        guard viewport.height > 0, width > 0 else { return .unknown }
        guard !rows.isEmpty else { return .all }
        let limit = max(0, viewport.height - reserved)
        var used: CGFloat = 0
        var keep = 0
        for row in rows {
            let h = height(of: row, width: width)
            if keep > 0, used + h > limit { break }
            used += h
            keep += 1
        }
        if keep >= rows.count { return .all }
        return .chunk(keep: max(1, keep), rest: rows.count - max(1, keep))
    }
}


private struct CardViewportKey: EnvironmentKey {
    static let defaultValue = CGSize.zero
}

extension EnvironmentValues {
    var cardViewport: CGSize {
        get { self[CardViewportKey.self] }
        set { self[CardViewportKey.self] = newValue }
    }
}


private struct StackTopInsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

private struct StackBottomInsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}


extension EnvironmentValues {
    var stackTopInset: CGFloat {
        get { self[StackTopInsetKey.self] }
        set { self[StackTopInsetKey.self] = newValue }
    }
}

extension EnvironmentValues {
    var stackBottomInset: CGFloat {
        get { self[StackBottomInsetKey.self] }
        set { self[StackBottomInsetKey.self] = newValue }
    }
}


struct DSCardMoreRow: View {
    var rest: Int
    var unit: String = "条"
    var screens: Double
    var open: Bool
    var action: () -> Void

    static func collapse(action: @escaping () -> Void) -> DSCardMoreRow {
        DSCardMoreRow(rest: 0, screens: 0, open: true, action: action)
    }

    var body: some View {
        Button {
            TokensHaptic.tap()
            action()
        } label: {
            HStack(spacing: TokensSpacing.sm) {
                Text(label)
                    .font(TokensTypo.footnote)
                    .foregroundStyle(TokensPalette.ambient)
                Spacer(minLength: TokensSpacing.sm)
                Image(safeSymbol: open ? "chevron.up" : "chevron.down",
                      fallback: open ? "chevron.up" : "chevron.down")
                    .font(TokensTypo.fixed(11, weight: .semibold))
                    .foregroundStyle(TokensPalette.tertiary)
            }
            .frame(minHeight: TokensSpacing.row)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(open ? "收起" : "还有 \(rest) \(unit)"))
        .accessibilityHint(Text(open ? "收回到能放下的量" : "摊开全部"))
    }

    private var label: String {
        if open { return "收起" }
        guard screens > 0 else { return "还有 \(rest) \(unit)" }
        let m = String(format: "%.1f", screens)
        return "还有 \(rest) \(unit) · 展开后约 \(m) 屏"
    }
}
