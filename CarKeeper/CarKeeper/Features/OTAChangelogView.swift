// =============================================================================
// #NEW-120 OTA 版本日志 — DevView 增加"更新日志"面板
// =============================================================================

import SwiftUI

struct OTAChangelogView: View {
    @State private var versionLogs: [VersionLog] = []

    struct VersionLog: Identifiable, Codable {
        var id = UUID()
        let version: String
        let date: Date
        let changes: [String]
    }

    var body: some View {
        // 清单不再用 List：版本 = 一个分组，改动 = 分组里的行。
        // 这样它与全 App 其它「分组」是同一件东西（同一个圆角、同一条发丝线）。
        ScrollView {
            LazyVStack(alignment: .leading, spacing: TokensSpacing.lg) {
                ForEach(versionLogs) { log in
                    DSGroup(title: log.version, footer: dateText(log.date)) {
                        ForEach(log.changes, id: \.self) { change in
                            DSGroupRow {
                                HStack(alignment: .firstTextBaseline, spacing: TokensSpacing.sm) {
                                    // 项目符号是图标，不是「一个纯色圆点」—— 形状扛得住色弱
                                    Image(safeSymbol: "checkmark.circle.fill", fallback: "checkmark")
                                        .font(TokensTypo.caption)
                                        .foregroundStyle(TokensPalette.ambient)
                                    Text(change)
                                        .font(TokensTypo.subheadline)
                                        .foregroundStyle(TokensPalette.primary)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Spacer(minLength: 0)
                                }
                                .padding(.vertical, TokensSpacing.xs)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, TokensSpacing.page)
            .padding(.vertical, TokensSpacing.lg)
        }
        .scrollBounceBehavior(.basedOnSize)
        .dsPageTitle("更新日志", inline: true)
        .onAppear { loadVersionLogs() }
    }

    /// 日期的格式化只在这一处 —— 界面上只出现一种日期写法
    private func dateText(_ d: Date) -> String {
        d.formatted(date: .long, time: .omitted)
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
