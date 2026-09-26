import SwiftUI
import UIKit

// =============================================================================
//  CardFit —— 「这张卡展开之后有多挤」的唯一算法
// =============================================================================
//
//  用户原话（2026-09-25）：「所有卡片内需要展开的都要严格计算展开后的拥挤程度，
//  完全根据数据来，不能猜」。
//
//  为什么需要它：展开类的东西（体检的分系统、消息的详情与正文、指令历史、
//  导出预览…）从前各自决定「展开后放多少」，多数答案是「全都放」。可全部放多少
//  **由数据决定**：一台车 6 个系统各 8 个子项，展开就是 48 行 ≈ 三屏多。
//  那不是排版选错了，是把「有多长」交给了运气。
//
//  这个算法只用三种真实来源，**一个手写的长度常量都没有**：
//
//    ① 行的真实高度 —— 字体取自同名的系统档（`UIFont.preferredFont(forTextStyle:)`），
//       它的 `lineHeight` 就是**当前动态字号下**那一行的高度。用户把系统字号调大，
//       这个数跟着变大；任何写下来的常量都跟不了。
//    ② 文字的真实折行数 —— `NSString.boundingRect(with:options:attributes:)`，
//       用同一个 UIFont、在同一个宽度里量。不是「字数 ÷ 每行字数」那种算。
//    ③ 容器真实可用高度 —— `ArcStack` 量到的视口（`EnvironmentValues.cardViewport`）。
//       读不到时它是 `.zero`：这时一切裁决返回 `.unknown`，界面**不做任何分块**。
//       「不知道」与「放得下」必须是两种答案 —— 本仓库的老毛病正是这两者长得一样。
//
//  由此得到两样东西：
//    · `Verdict`：展开后会占几屏（`screens`）。这是可以摆在界面上的事实。
//    · `Plan`：放得下就 `.all`，放不下就 `.chunk(keep:rest:)` —— `keep` 是
//      **按每一行的真实高度逐行累加**得出的，不是「条数 × 平均行高」。
//
//  与 DS 的分工：这里只算，不画。唯一例外是 `DSCardMoreRow`（「还有 N 条」那一行）——
//  它是这个算法的**出口**，每一处用到分块的地方都必须是同一行、同一句话，
//  所以它跟着算法住在这里，而不是让每个页面各写一遍。
// =============================================================================

enum CardFit {
    // MARK: - 文字档
    //
    //  ★ 档位名与 `TokensTypo` 里的同名档位**一一对应**（`body`→`TokensTypo.body`…）：
    //    那里加一档，这里要一起加，否则「界面用 15pt、算法按 13pt 量」，
    //    算出来的屏数会系统性地偏小 —— 而那种偏差在界面上看不出来。

    enum Typo {
        case title3, headline, body, callout, subheadline, footnote, caption, caption2
        /// 定尺文字（画布里的图形与读数）：尺寸由调用点给，且必须来自令牌。
        case fixed(CGFloat)
        /// `Font.system(.caption, design: .monospaced)` —— 导出预览那块等宽正文（
        /// 字号取 `caption` 的**真实**点数，所以它跟着动态字号走）
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

        /// 当前动态字号下这一档一行有多高（真实值）
        var lineHeight: CGFloat { uiFont.lineHeight }
    }

    // MARK: - 一行的描述

    /// 一行里的**一件东西**。顺序就是它在界面上从上到下的顺序。
    ///
    /// ★ 这套算法只有一个需要人守的约定：调用点写下的每一个 `Block` 都要对应
    ///   界面上真的画出来的那一件（同一个 VStack 的 spacing、同一个 frame 高度、
    ///   同一个 lineLimit）。那边改了版式，这里要跟着改 —— 它量的是版式，不是数据。
    enum Block {
        /// 一段文字；`cap` 是界面上给它的 `.lineLimit`（那它就不会超过这么多行）
        case text(String, Typo, cap: Int?)
        /// 同一行里的两列（左标签 + 右值）—— 它们是并排的，取高的那一列
        case pair(String, Typo, String, Typo, cap: Int?)
        /// 两件东西之间的距离（VStack 的 `spacing:`）
        case gap(CGFloat)
        /// 与字数无关的高度：光带、图标列、分隔线
        case fixed(CGFloat)
    }

    /// 一行（列表项 / 键值行 / 一段正文）
    ///
    /// `blocks` 的内容由**数据**决定：调用点只在数据里真有这一项时才 append
    ///（例如体检子项的「检测值」只有在报文里带了它时才存在）。
    /// 于是同一张卡里两行的高度可以不同 —— 那正是「按数据算」的意思。
    struct Row {
        var blocks: [Block]
        var padTop: CGFloat
        var padBottom: CGFloat
        /// 这一行的**最小高度**（例如可点那一行走 HIG 的 44）
        var floor: CGFloat

        init(_ blocks: [Block] = [],
             padTop: CGFloat = 0, padBottom: CGFloat = 0, floor: CGFloat = 0) {
            self.blocks = blocks
            self.padTop = padTop
            self.padBottom = padBottom
            self.floor = floor
        }

        /// 一个纯文字块（卡片正文那种）
        static func text(_ text: String, _ style: Typo, cap: Int? = nil,
                         padTop: CGFloat = 0, padBottom: CGFloat = 0) -> Row {
            Row([.text(text, style, cap: cap)], padTop: padTop, padBottom: padBottom)
        }

        /// 一行「键 + 值」—— 与 `DSKeyValueRow` 同一版式（上下 8、13pt 两侧并排）
        static func keyValue(_ key: String, _ value: String,
                             pad: CGFloat = TokensSpacing.sm) -> Row {
            Row([.pair(key, .footnote, value, .footnote, cap: nil)],
                padTop: pad, padBottom: pad)
        }

        /// 一行列表项：主标题 + 可选的副标题/状态行，可点（故带 44 的下限）
        static func item(title: String, titleStyle: Typo = .body, cap: Int? = nil,
                         extras: [Block] = [],
                         padTop: CGFloat = TokensSpacing.sm,
                         padBottom: CGFloat = TokensSpacing.sm) -> Row {
            Row([.text(title, titleStyle, cap: cap)] + extras,
                padTop: padTop, padBottom: padBottom, floor: TokensSpacing.row)
        }
    }

    // MARK: - 量

    /// 只用来问「在这个宽度下会折成几行」—— 高度本身不参与计算
    private static let measuringHeight: CGFloat = 100_000
    /// 只用来问「不折行时它有多宽」—— 宽度本身不参与计算
    private static let measuringWidth: CGFloat = 100_000

    /// 一段文字**不折行**时有多宽（真实测量）。
    ///
    /// 用在「一行里还剩多少宽度」这种地方：标题那一行左边是标题、右边是标签与时间，
    /// 标题实际能用的宽度 = 整行宽 − 右边那些东西的宽。以前这类地方写的是
    /// 「标题按 60% 宽算」——那个 0.6 就是猜的，而它可以量出来。
    static func textWidth(_ text: String, style: Typo) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        return (text as NSString).boundingRect(
            with: CGSize(width: measuringWidth, height: measuringHeight),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: style.uiFont],
            context: nil).width
    }

    /// 一段文字在 `width` 里占几行（真实测量；量不出来时按 1 行算，不按 0）
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

    /// 一行有多高：上下堆的相加，并排的取高的那一列。
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

    /// 一段文字的高度（行数 × 真实行高）
    static func textHeight(_ text: String, style: Typo,
                           width: CGFloat, cap: Int? = nil) -> CGFloat {
        CGFloat(lineCount(text, style: style, width: width, cap: cap)) * style.lineHeight
    }

    /// 在 `lines` 行之内放得下的**最长前缀**（放得下就返回 nil）。
    ///
    /// 它是「这一段太长」的出口：切点不按字数估 —— 二分，每一次都真的量一遍那个
    /// 前缀在**这个宽度、这个字号**下占了几行。于是「切在哪里」是量出来的结果，
    /// 而不是「大概 120 个字」那种常量。
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

    // MARK: - 裁决

    /// 「展开之后有多挤」：三个数都是算出来的。
    struct Verdict {
        /// 展开后的内容总高
        var height: CGFloat
        /// 它被允许占用的高度（视口 − 卡片其他部分）
        var limit: CGFloat
        /// 视口读到了没有。读不到时 `screens` 无意义（调用点不要显示它）
        var isKnown: Bool

        /// 几屏
        var screens: Double {
            guard isKnown, limit > 0 else { return 0 }
            return Double(height / limit)
        }

        /// 是否超过一屏（超过就是「挤」）
        var crowded: Bool { isKnown && screens > 1 }
    }

    static func verdict(_ rows: [Row], width: CGFloat,
                        viewport: CGSize, reserved: CGFloat = 0) -> Verdict {
        let h = height(of: rows, width: width)
        return Verdict(height: h,
                       limit: max(0, viewport.height - reserved),
                       isKnown: viewport.height > 0 && width > 0)
    }

    // MARK: - 一段正文的计划

    /// 一段正文（消息正文、导出预览、说明段）展开后的样子。
    struct TextPlan {
        /// 屏幕上真画出来的那一段（放不下时它只是前缀）
        var text: String
        /// 挂在「还有 N 行」后面的行数（0 = 没卡）
        var restLines: Int
        /// 这一整段占几屏（含 `reserved`）
        var screens: Double
        /// 它本来就长到一屏放不下（哪怕此刻正全放着 —— 那也要能合回去）
        var truncatable: Bool

        static func all(_ text: String) -> TextPlan {
            TextPlan(text: text, restLines: 0, screens: 0, truncatable: false)
        }
    }

    /// 正文放得下就全放；放不下就切在**量出来的行边界**上（`fittingPrefix`）。
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

    // MARK: - 计划

    /// 展开时到底放几行。
    ///
    /// `.unknown`：视口没量到 —— **不做分块**（宁可全放，也不按一个猜的数字砍内容）。
    /// `.all`    ：放得下。
    /// `.chunk`  ：逐行累加到放不下为止；`keep` 至少是 1（一行都放不下也要露出第一行，
    ///             否则用户看到的是「展开后什么都没有」）。
    enum Plan {
        case unknown
        case all
        case chunk(keep: Int, rest: Int)

        /// 该显示几行（`.all` / `.unknown` 时返回 nil = 全放）
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

// =============================================================================
//  卡片视口 —— 算法唯一的外部输入
// =============================================================================

/// 卡片可用区域（宽 × 高）。由 `ArcStack` 用它**真量到的**容器尺寸写进环境。
///
/// 默认值是 `.zero` = 「不知道」。这不是偷懒：这台机器上量不到的时候（预览、
/// 还没布局的第一帧、非叠叠乐的宿主），算法必须能说出「不知道」并**放弃分块**，
/// 而不是拿一个写死的屏高去砍内容 —— 见 `CardFit.Plan.unknown`。
private struct CardViewportKey: EnvironmentKey {
    static let defaultValue = CGSize.zero
}

extension EnvironmentValues {
    var cardViewport: CGSize {
        get { self[CardViewportKey.self] }
        set { self[CardViewportKey.self] = newValue }
    }
}

// =============================================================================
//  叠叠乐的顶部内衬（用户 2026-09-25 第 2 条：子页的顶要和地图页一样）
// =============================================================================

/// 这一叠**滚动内容**的顶部内衬（pt）。
///
/// 为什么它必须从外面给（而不是 `ArcStack` 自己量）：
/// 量到「屏幕顶到这一叠的顶」靠的是 `frame(in: .global)` —— 而能让卡片从时钟下
/// 连续滑过的前提是这一叠自己 `ignoresSafeArea(.top)`，一旦忽略，它就量到 0 了。
/// 所以量的人只能是**还站在安全区里**的宿主（`MapSpineView`，它只忽略底边），
/// 量出来的数（= 灵动岛/涛海那一段安全区）再由这里交下去。
///
/// 默认 0 = 「没人量过」：那一叠就完全按系统布局走（与加这个环境值之前一模一样）——
/// 不会因为缺一个数就把卡片顶到状态栏底下。
private struct StackTopInsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

/// 这一叠**滚动内容**的底部内衬（pt）：底条占掉的那一段（`MapSpineView.barTotal`）。
///
/// 它必须是**内容内衬**，不能是页面的 `.padding(.bottom, …)`：用户 2026-09-26
/// 「地图页和下面的底部导航可以穿过，为什么其他的界面都不能穿过底部的导航」——
/// 给页面加 padding 等于把滚动视口截在条子上沿，卡片永远到不了条子底下，
/// 条子背后只剩壁纸（看起来就是一块不透明的板）。内衬则让两件事同时成立：
/// **卡片从底条下穿过**（与相机里取景框的关系同一种），而最后一张仍能整张
/// 滚到条子上沿之上（够得着、读得完）。
///
/// 默认 0 = 「没有底条」：那一叠完全按系统布局走。
private struct StackBottomInsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

/// 这张卡的**底下是不是一张照片 / 地图**（连续的画面）。
///
/// 用户 2026-09-25 第 1 / 10 条之后追加的那一句：「我追求的就是液态玻璃的美感」——
/// 而 `Glass` 两个变体的**选择规则是 Apple 定的，不是审美定的**：
///   · 底下是连续的画面（照片、地图）→ `.clear`
///     （HIG：*reserve clear Liquid Glass for components over visually rich backgrounds*）
///   · 底下是 App 自己的界面（画布）→ `.regular`
/// 两种情形在我们这里都真实存在：五张子页铺的是**相册选的照片**
///（`MapWallpaperLayer`），而用户没选照片时回落到 `TokensPalette.canvas`（一块纯色）。
/// 一块 `.clear` 玻璃压在纯色上几乎什么都看不见 —— 卡片会像消失。
/// 所以这个值不是开关，是**事实的传递**：由铺背景的那一层（`MapSpineView`）算出
/// 「我底下到底是照片还是纯色」，`GlassCard` 照着选。默认 false ＝ 纯色。
private struct PhotoBackdropKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var photoBackdrop: Bool {
        get { self[PhotoBackdropKey.self] }
        set { self[PhotoBackdropKey.self] = newValue }
    }
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

// =============================================================================
//  DSCardMoreRow —— 分块的那个出口
// =============================================================================

/// 放不下时的那一行：「还有 N 条 · 展开后约 M 屏」。
///
/// `rest` 与 `screens` 都是 `CardFit` 算出来的（N 是逐行累加剩下的条数，M 是按
/// 真实行高与真实视口算出的屏数）—— 不是「只显示前 3 条」那种拍出来的 3。
/// 摊开之后它变成「收起」，这是**同一行**的第二个状态：分块与合起来必须是一处，
/// 否则总有一半地方只会展开、收不回去。
struct DSCardMoreRow: View {
    var rest: Int
    /// 量词：列表是「条」，正文是「行」
    var unit: String = "条"
    /// 展开后占几屏（`CardFit.Verdict.screens`）。0 = 视口没量到，这时**不写屏数**
    ///（不写「约 0 屏」那种假数）。
    var screens: Double
    var open: Bool
    var action: () -> Void

    /// 「收起」那一态。摊开之后必须能合回去，而合回去与摊开必须是**同一行**
    ///（分开写两行的话，总有一处只会摊开、收不回去）。
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

    /// 句子只有一处：「还有 N 条」；量到了视口就再加上「展开后约 M 屏」。
    private var label: String {
        if open { return "收起" }
        guard screens > 0 else { return "还有 \(rest) \(unit)" }
        let m = String(format: "%.1f", screens)
        return "还有 \(rest) \(unit) · 展开后约 \(m) 屏"
    }
}
