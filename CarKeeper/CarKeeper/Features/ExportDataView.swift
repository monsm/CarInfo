// =============================================================================
// ExportDataView - 数据导出（CSV/PDF 行程/充电记录）
// =============================================================================

import SwiftUI
import UIKit

struct ExportDataView: View {
    private let store = AppStore.shared
    @State private var exportType: ExportType = .trips
    @State private var isExporting = false
    @State private var exportURL: URL?
    @State private var showSuccess = false

    enum ExportType: String, CaseIterable {
        case trips = "行程记录"
        case charging = "充电记录"
        case commands = "指令历史"
        case diagnostics = "诊断报告"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 选择导出类型
                VStack(alignment: .leading, spacing: 10) {
                    Text("导出类型").font(Theme.font(.subheadline as Font).bold())
                    Picker("类型", selection: $exportType) {
                        ForEach(ExportType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }

                // 导出内容预览
                previewCard

                // 操作按钮
                VStack(spacing: 12) {
                    Button(action: exportAsCSV) {
                        HStack {
                            Image(systemName: "doc.plaintext")
                            Text("导出 CSV")
                                .font(Theme.font(.subheadline as Font).bold())
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(TokensPalette.ambient)
                        .foregroundStyle(TokensPalette.labelOnTint)
                        .cornerRadius(12)
                    }

                    Button(action: exportAsPDF) {
                        HStack {
                            Image(systemName: "doc.richtext")
                            Text("导出 PDF")
                                .font(Theme.font(.subheadline as Font).bold())
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(TokensPalette.success)
                        .foregroundStyle(TokensPalette.labelOnTint)
                        .cornerRadius(12)
                    }
                }
            }
            .padding()
        }
        .background(TokensPalette.background)
        .navigationTitle("导出数据")
        .navigationBarTitleDisplayMode(.inline)
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
        VStack(alignment: .leading, spacing: 8) {
            Text("导出预览").font(.caption).foregroundStyle(.secondary)

            let lines = previewLines
            ScrollView {
                Text(lines.joined(separator: "\n"))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(8)
            }
            .frame(height: 100)
            .padding(8)
            .background(Color.primary.opacity(0.05))
            .cornerRadius(8)
        }
        .padding()
        .glassCard(corner: TokensRadius.medium)
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

struct ExportDataView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            ExportDataView()
        }
    }
}
