// =============================================================================
// 导出 — CSV/PDF（行程 / 充电 / 指令历史）
//
// 原为独立页面（深链 `carkeeper://export`）。批 5 并进 **保养与钱**：
// 「带走你自己的记录」跟钱与保养是同一件事的一部分。
// 它现在只提供内容（`ExportDataSection`），页面外壳归 `MaintenanceMoneyView`。
// =============================================================================

import SwiftUI
import UIKit

struct ExportDataSection: View {
    private let store = AppStore.shared
    @State private var exportType: ExportType = .trips
    @State private var isExporting = false
    @State private var exportURL: URL?
    @State private var showSuccess = false
    /// 预览被“摊开全部”了吗（见 `previewPlan`）
    @State private var previewFull = false
    /// 卡片量到的可用区域（`ArcStack` 写进来的真数；量不到时是 `.zero`）
    @Environment(\.cardViewport) private var cardViewport

    enum ExportType: String, CaseIterable {
        case trips = "行程记录"
        case charging = "充电记录"
        case commands = "指令历史"
        case diagnostics = "诊断报告"
    }

    var body: some View {
        Group {
            VStack(alignment: .leading, spacing: TokensSpacing.lg) {
                DSSectionHeader(title: "导出")

                // 选择导出类型（四个互斥选项 → 系统的分段语法）
                DSSegmented(options: ExportType.allCases.map { (value: $0, title: $0.rawValue) },
                            selection: $exportType)

                // 导出内容预览
                previewCard

                // 操作：两个格式，不是两个颜色。主操作只有一个（CSV），PDF 是次要的。
                VStack(spacing: TokensSpacing.sm) {
                    Button(action: exportAsCSV) {
                        HStack(spacing: TokensSpacing.sm) {
                            Image(safeSymbol: "doc.plaintext", fallback: "doc.plaintext")
                            Text("导出 CSV")
                        }
                    }
                    .buttonStyle(DSPrimaryButtonStyle())

                    Button(action: exportAsPDF) {
                        HStack(spacing: TokensSpacing.sm) {
                            Image(safeSymbol: "doc.richtext", fallback: "doc.richtext")
                            Text("导出 PDF")
                        }
                    }
                    .buttonStyle(DSSecondaryButtonStyle())
                }
            }
        }
        .alert("导出成功", isPresented: $showSuccess) {
            Button("分享", action: shareExportedFile)
            Button("关闭", role: .cancel) {}
        } message: {
            if let url = exportURL {
                Text("文件已保存至：\(url.lastPathComponent)")
            }
        }
        .accessibilityLabel(Text("数据导出工具"))
    }

    private var previewCard: some View {
        // 容器统一走 DSCard（与其余 20 屏同一张卡片）；底色走令牌，不用 Color.primary 自调透明度。
        DSCard {
            VStack(alignment: .leading, spacing: TokensSpacing.sm) {
                Text("导出预览")
                    .font(TokensTypo.caption)
                    .foregroundStyle(TokensPalette.secondary)

                // 这里原本是 `ScrollView { Text(…).lineLimit(8) }.frame(height: 100)`，一个人占了
                // 两件错：① 卡片里再套一层滚动 —— 叠叠乐自管手势（没有 ScrollView），
                // 内层拿到的又是无限高，于是它永远滚不动、却把拖动吃掉；
                // ② 那个 100 是拍出来的高度，而这个块里真正有几行由**数据**决定
                //（一行 CSV 在窄屏上折成几行，取决于那个时间戳字符串有多长）。
                // 现在整块高度由行数与字号算出来：放得下就全放（内容撑高），
                // 放不下就切在量出来的行边界上，剩下的挂在那张标准行里。
                let plan = previewPlan
                Text(plan.text)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(TokensPalette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(TokensSpacing.sm)
                    .background(TokensPalette.fillSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: TokensRadius.small, style: .continuous))

                if plan.restLines > 0 {
                    DSCardMoreRow(rest: plan.restLines, unit: "行",
                                  screens: plan.screens, open: false) {
                        withAnimation(TokensMotion.count) { previewFull = true }
                    }
                } else if previewFull, plan.truncatable {
                    DSCardMoreRow.collapse {
                        withAnimation(TokensMotion.count) { previewFull = false }
                    }
                }
            }
        }
    }

    /// 预览块的预算：卡片量到的可用高度减去这一块之外的东西（标题行与两处内边距）。
    /// 宽度同理逐层减：叠叠乐左右 18（`GlassCard`）→ 这张卡自己 16（`DSCard`）→ 块内 8。
    private var previewPlan: CardFit.TextPlan {
        let text = previewLines.joined(separator: "\n")
        let width = max(0, cardViewport.width - 2 * StackSpec.Card.padH
                        - 2 * TokensSpacing.md - 2 * TokensSpacing.sm)
        let reserved = CardFit.textHeight("导出预览", style: .caption, width: width)
            + TokensSpacing.sm * 2
        let plan = CardFit.plan(text: text, style: .monoCaption, width: width,
                                viewport: cardViewport, reserved: reserved)
        if previewFull {
            return CardFit.TextPlan(text: text, restLines: 0, screens: plan.screens,
                                    truncatable: plan.truncatable)
        }
        return plan
    }

    private var previewLines: [String] {
        switch exportType {
        case .trips:
            let first = store.tripHistory.first
            return [
                "时间,里程(km),能耗(kWh/100km),开始SOC,结束SOC",
                first.map { row in
                    "\(row.startTime),\(row.distanceKm),\(row.avgEfficiency ?? 0),\(row.startSoc), \(row.endSoc)"
                } ?? "暂无数据"
            ]
        case .charging:
            return [
                "开始时间,结束时间,电量(kWh),费用(元)",
                "暂无充电记录"
            ]
        case .commands:
            let first = store.commandHistory.first
            return [
                "时间,指令,状态,耗时",
                first.map { "\($0.startedAt),\($0.name),\($0.success ? "成功" : "失败"),\($0.durationText)" } ?? "暂无记录"
            ]
        case .diagnostics:
            return ["诊断报告导出功能开发中..."]
        }
    }

    private func exportAsCSV() {
        isExporting = true
        Task {
            defer { isExporting = false }
            let content = csvContent
            let filename = "\(exportType.rawValue)_\(Date().formatted(date: .abbreviated, time: .standard)).csv"
            if let url = saveToFile(content, filename: filename) {
                exportURL = url
                showSuccess = true
            }
        }
    }

    private func exportAsPDF() {
        isExporting = true
        Task {
            defer { isExporting = false }
            let html = pdfHTMLContent
            let filename = "\(exportType.rawValue)_\(Date().formatted(date: .abbreviated, time: .standard)).pdf"
            if let url = saveHTMLAsPDF(html, filename: filename) {
                exportURL = url
                showSuccess = true
            }
        }
    }

    private var csvContent: String {
        var lines: [String] = []
        switch exportType {
        case .trips:
            lines = ["时间,里程(km),能耗(kWh/100km),开始SOC,结束SOC,时长"]
            for t in store.tripHistory {
                var parts: [String] = []
                parts.append("\(t.startTime)")
                parts.append(String(format: "%.1f", t.distanceKm))
                let eff = t.avgEfficiency.map { String(format: "%.1f", $0) } ?? ""
                parts.append(eff)
                parts.append("\(t.startSoc)")
                parts.append("\(t.endSoc)")
                parts.append(t.durationText)
                lines.append(parts.joined(separator: ","))
            }
        case .commands:
            lines = ["时间,指令名称,状态,耗时"]
            for cmd in store.commandHistory {
                lines.append("\(cmd.startedAt),\(cmd.name),\(cmd.success ? "成功" : "失败"),\(cmd.durationText)")
            }
        default:
            lines = ["暂无数据"]
        }
        return lines.joined(separator: "\n")
    }

    private var pdfHTMLContent: String {
        """
        <html><head><style>
            body { font-family: -apple-system, sans-serif; padding: 20px; }
            h1 { color: #007AFF; }
            table { border-collapse: collapse; width: 100%; }
            td, th { border: 1px solid #ddd; padding: 8px; text-align: left; }
            th { background: #f5f5f5; }
        </style></head><body>
        <h1>CarKeeper \(exportType.rawValue) 报告</h1>
        <p>导出时间: \(Date().formatted(date: .numeric, time: .shortened))</p>
        <table>
        <tr><th>项目</th><th>数值</th></tr>
        \(pdfTableRows)
        </table>
        </body></html>
        """
    }

    private var pdfTableRows: String {
        switch exportType {
        case .trips:
            return store.tripHistory.prefix(5).map { t in
                "<tr><td>\(t.startTime)</td><td>\(String(format:"%.1f km", t.distanceKm))</td></tr>"
            }.joined()
        default:
            return "<tr><td colspan='2'>暂无数据</td></tr>"
        }
    }

    private func saveToFile(_ content: String, filename: String) -> URL? {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(filename)
        try? content.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    private func saveHTMLAsPDF(_ html: String, filename: String) -> URL? {
        let tempDir = FileManager.default.temporaryDirectory
        let htmlURL = tempDir.appendingPathComponent("export.html")
        try? html.write(to: htmlURL, atomically: true, encoding: .utf8)

        // Simple approach: return the HTML file as-is for sharing
        return htmlURL
    }

    private func shareExportedFile() {
        guard let url = exportURL else { return }
        let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            windowScene.windows.first?.rootViewController?.present(vc, animated: true)
        }
    }
}

struct ExportDataSection_Previews: PreviewProvider {
    static var previews: some View {
        ScrollView { ExportDataSection() }
    }
}
