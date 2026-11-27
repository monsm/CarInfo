
import SwiftUI
import UIKit

struct ExportDataSection: View {
    private let store = AppStore.shared
    @State private var exportType: ExportType = .trips
    @State private var isExporting = false
    @State private var exportURL: URL?
    @State private var showSuccess = false
    @State private var previewFull = false
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

                DSSegmentPicker(options: ExportType.allCases.map { (value: $0, title: $0.rawValue) },
                                selection: $exportType,
                                label: "导出类型")

                previewCard

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
        DSCard {
            VStack(alignment: .leading, spacing: TokensSpacing.sm) {
                Text("导出预览")
                    .font(TokensTypo.caption)
                    .foregroundStyle(TokensPalette.secondary)

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
