import SwiftUI
import UIKit


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


    @MainActor
    private func run() {
        guard !running else { return }
        running = true
        results = []
        Task {
            let now = Date()
            var out: [APIClient.MessageProbe] = []

            out.append(await APIClient.shared.probeMessageWindow(
                "30 天一段", from: now.addingTimeInterval(-30 * 24 * 3600), to: now))

            let wins = APIClient.messageWindows(days: APIClient.messageDays,
                                                sliceDays: APIClient.messageSliceDays, now: now)
            var parts: [APIClient.MessageProbe] = []
            for w in wins {
                parts.append(await APIClient.shared.probeMessageWindow(
                    "段", from: w.start, to: w.end))
            }
            out.append(Self.combine(parts, title: "30 天分五段", slices: wins.count))

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


    private static func statusText(_ s: Int?) -> String {
        s.map(String.init) ?? "没发出去"
    }

    private static func cls(_ s: Int?) -> String {
        s == 200 ? "ok" : "bad"
    }

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

    private static func combine(_ parts: [APIClient.MessageProbe], title: String,
                                slices: Int) -> APIClient.MessageProbe {
        let ok = parts.filter { $0.status == 200 }
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
