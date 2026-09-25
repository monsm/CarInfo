import SwiftUI
// `UIPasteboard` 要它（与 DevView 一样：复制结果那一行）。
import UIKit

// =============================================================================
//  消息自检 —— 「到底返回了啥」
// =============================================================================
//
//  它不给结论，只把四个数并排放：HTTP 状态 / 响应字节数 / 服务端自报条数 /
//  我们解析到的条数。理由只有一条 —— 这条路的失败有四种**长得一模一样**的形态：
//    ① 请求根本没发出去（没登录 / URL 拼错 / 断网）
//    ② 发出去了但被拒（401 / 403 …）
//    ③ 200，服务端说这个区间 0 条
//    ④ 200，服务端给了 55 条，而**我们解析成 0 条**（解析没命中）
//  而它们在界面上都是「暂无消息」。用户 2026-09-24 的原话是「或者写个单独的测试页，
//  看看为什么获取不到，到底返回了啥」—— 这一组就是那台仪器：不再问、不再猜。
//
//  一次跑三种形状并排放：
//    · 一段 30 天   —— 用户认为接口要的那种（一个请求，覆盖 30 天）
//    · 30 天分五段 —— App 现在真正发的形状（7 天一段 × 5）
//    · 一段 7 天   —— 抓包里验证过的那个形状
//  三份答案放在一起，「区间长度是问题」与「请求形状是问题」才有得比：
//  如果三种都是 200 且有 55 条，那问题就不在接口上，而在我们收到之后的那一段。
//
//  它住在「我的 → 诊断」里、紧挨着「原始日志」—— 同一个问题只该有一个地方看。
// =============================================================================

struct MessageProbeSection: View {
    @State private var running = false
    @State private var results: [APIClient.MessageProbe] = []
    @State private var ranAt: String = ""

    var body: some View {
        DSGroup(title: "消息自检", trailing: results.isEmpty ? nil : ranAt,
                footer: "发 7 次原样请求，不加工：状态、长度、条数都照实报。") {
            DSGroupRow {
                DSRow(icon: "waveform.path.ecg",
                      title: running ? "正在测…" : "测三种窗口") { run() }
            }
            DSGroupRow(showsSeparator: !results.isEmpty) {
                DSRow(icon: "doc.on.doc", title: "复制结果") { copy() }
            }
            ForEach(Array(results.enumerated()), id: \.offset) { idx, r in
                DSGroupRow(showsSeparator: idx < results.count - 1) {
                    VStack(alignment: .leading, spacing: TokensSpacing.xs) {
                        HStack(alignment: .firstTextBaseline, spacing: TokensSpacing.sm) {
                            Text(r.title)
                                .font(TokensTypo.fixed(13, weight: .semibold))
                                .foregroundStyle(TokensPalette.primary)
                            Spacer(minLength: 0)
                            Text(Self.statusText(r.status))
                                .font(TokensTypo.fixed(12, weight: .semibold).monospacedDigit())
                                .foregroundStyle(TokensPalette.statusColor(Self.cls(r.status)))
                        }
                        ForEach(Self.facts(r), id: \.self) { line in
                            Text(line)
                                .font(TokensTypo.fixed(11, weight: .regular).monospacedDigit())
                                .foregroundStyle(TokensPalette.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        // URL 放最后一行：它是**证据**（区间、形状、token 已打码都在里面），
                        // 但读的人先要的是上面那四个数。
                        Text(r.url)
                            .font(TokensTypo.fixed(10, weight: .regular))
                            .foregroundStyle(TokensPalette.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
        }
    }

    // MARK: - 跑

    /// 三次形状、七次请求，**顺序**发出（同时发会互相掩盖时序，而诊断要的正是时序）。
    @MainActor
    private func run() {
        guard !running else { return }
        running = true
        results = []
        Task {
            let now = Date()
            var out: [APIClient.MessageProbe] = []

            // ① 一段 30 天
            out.append(await APIClient.shared.probeMessageWindow(
                "30 天一段", from: now.addingTimeInterval(-30 * 24 * 3600), to: now))

            // ② 30 天分五段 —— App 现在真正发的形状，逐段发完合成一行
            let wins = APIClient.messageWindows(days: APIClient.messageDays,
                                                sliceDays: APIClient.messageSliceDays, now: now)
            var parts: [APIClient.MessageProbe] = []
            for w in wins {
                parts.append(await APIClient.shared.probeMessageWindow(
                    "段", from: w.start, to: w.end))
            }
            out.append(Self.combine(parts, title: "30 天分五段", slices: wins.count))

            // ③ 一段 7 天（抓包里验证过的那个形状）
            out.append(await APIClient.shared.probeMessageWindow(
                "7 天一段", from: now.addingTimeInterval(-7 * 24 * 3600), to: now))

            ranAt = DateText.shared.string(Date(), "HH:mm:ss", locale: "en_US_POSIX")
            results = out
            running = false
        }
    }

    private func copy() {
        guard !results.isEmpty else { return }
        UIPasteboard.general.string = Self.report(results)
        TokensHaptic.result(true)
        ToastManager.shared.show("自检结果已复制", icon: "doc.on.doc.fill")
    }

    // MARK: - 读法

    private static func statusText(_ s: Int?) -> String {
        s.map(String.init) ?? "没发出去"
    }

    private static func cls(_ s: Int?) -> String {
        s == 200 ? "ok" : "bad"
    }

    /// 一行一个事实。「服务端自报」与「我们解析到」必须同时出现 ——
    /// 这两个数不一样时，凶手就是它们之间的那一段（解析），而不是接口。
    private static func facts(_ r: APIClient.MessageProbe) -> [String] {
        var out = ["响应 \(r.bytes) 字节"]
        out.append("服务端自报 \(r.declared.map(String.init) ?? "无") · 我们解析到 \(r.parsed)")
        if r.oldest != nil || r.newest != nil {
            out.append("正文时间 \(r.oldest ?? "?") → \(r.newest ?? "?")")
        }
        if !r.keys.isEmpty { out.append("顶层键 \(r.keys.joined(separator: ","))") }
        if let p = r.pages { out.append("服务端总页数 \(p)") }
        if !r.note.isEmpty { out.append(r.note) }
        return out
    }

    /// 把五段合成一行：一次看完整跨度，同时保留每段各自的条数（那才是形状的证据）。
    private static func combine(_ parts: [APIClient.MessageProbe], title: String,
                                slices: Int) -> APIClient.MessageProbe {
        let ok = parts.filter { $0.status == 200 }
        // 型书写在左边：三元与 `reduce` 挤在一行时，让编译器去猜返回类型不值得。
        let declared: Int? = parts.allSatisfy { $0.declared == nil }
            ? nil
            : parts.reduce(0) { $0 + ($1.declared ?? 0) }
        let perSlice = parts.map { "\($0.parsed)" }.joined(separator: "/")
        var note = "每段解析到 \(perSlice)"
        if ok.count != parts.count {
            note = "\(parts.count - ok.count) 段没拿到；" + note
        }
        return APIClient.MessageProbe(
            title: title,
            url: parts.first?.url ?? "",
            status: ok.count == parts.count ? 200 : nil,
            bytes: parts.reduce(0) { $0 + $1.bytes },
            keys: parts.first?.keys ?? [],
            declared: declared,
            pages: nil,
            parsed: parts.reduce(0) { $0 + $1.parsed },
            newest: parts.compactMap { $0.newest }.max(),
            oldest: parts.compactMap { $0.oldest }.min(),
            note: note)
    }

    /// 复制出去的那份文本：先给人看结论行（四个数），再给三次请求的 URL。
    private static func report(_ all: [APIClient.MessageProbe]) -> String {
        var lines = ["【CarKeeper 消息自检】"]
        for r in all {
            lines.append("\(r.title)：状态 \(statusText(r.status))")
            lines.append(contentsOf: facts(r).map { "  " + $0 })
            lines.append("  " + r.url)
        }
        return lines.joined(separator: "\n")
    }
}
