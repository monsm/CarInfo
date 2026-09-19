// =============================================================================
// #NEW-120 OTA 版本日志 — DevView 增加"更新日志"面板
// =============================================================================

import SwiftUI

struct OTAChangelogView: View {
    @State private var versionLogs: [VersionLog] = []
    
    struct VersionLog: Identifiable {
        let id = UUID()
        let version: String
        let date: Date
        let changes: [String]
    }
    
    var body: some View {
        List(versionLogs) { log in
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(log.version)
                        .font(.headline)
                    Spacer()
                    Text(log.date, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(log.changes, id: \.self) { change in
                    HStack {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 6))
                            .foregroundStyle(.accentColor)
                        Text(change)
                            .font(.caption)
                            .foregroundStyle(.primary)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .listStyle(.plain)
        .navigationTitle("更新日志")
        .onAppear { loadVersionLogs() }
    }
    
    private func loadVersionLogs() {
        // 从 UserDefaults 加载历史记录
        guard let data = UserDefaults.standard.data(forKey: "carkeeper_version_logs"),
              let logs = try? JSONDecoder().decode([VersionLog].self, from: data) else {
            // 默认日志
            versionLogs = [
                VersionLog(
                    version: "v1.0.0",
                    date: Date(),
                    changes: [
                        "初始化项目，实现基础车况查看功能",
                        "集成长安官方 API",
                        "实现 iOS 27 Liquid Glass 设计风格"
                    ]
                )
            ]
            return
        }
        versionLogs = logs
    }
    
    /// 保存新版本日志
    static func saveVersionLog(_ log: VersionLog) {
        var logs = UserDefaults.standard.object(forKey: "carkeeper_version_logs") as? [VersionLog] ?? []
        logs.insert(log, at: 0)
        if let data = try? JSONEncoder().encode(logs) {
            UserDefaults.standard.set(data, forKey: "carkeeper_version_logs")
        }
    }
}
