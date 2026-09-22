// =============================================================================
// CommandHistoryView —— 指令历史页（远程操控记录 + 成功率统计）
// =============================================================================

import SwiftUI

struct CommandHistoryView: View {
    private let store = AppStore.shared
    @State private var filter: String = "all"
    @State private var expandedCmds: Set<UUID> = []

    private let filters = ["全部", "成功", "失败", "进行中"]

    var filteredCommands: [AppStore.HistoryEntry] {
        store.commandHistory
            .filter { entry in
                switch filter {
                case "成功": return entry.success
                case "失败": return !entry.success && entry.finishedAt != nil
                case "进行中": return entry.finishedAt == nil
                default: return true
                }
            }
    }

    var successRate: Double {
        guard !store.commandHistory.isEmpty else { return 0 }
        let succeeded = store.commandHistory.filter { $0.success }.count
        return Double(succeeded) / Double(store.commandHistory.count)
    }

    var inProgressCount: Int {
        store.commandHistory.filter { $0.finishedAt == nil }.count
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: TokensSpacing.lg) {
                DSPageTitle(title: "指令历史", subtitle: "每一次远程操作与它的结果")

                // 统计（一组，不是三张各自带底的卡）
                statsCard

                // 筛选
                filterBar

                // 列表
                commandList
            }
            .padding(.horizontal, TokensSpacing.page)
            .padding(.vertical, TokensSpacing.lg)
        }
        .dsPageTitle("指令历史", inline: true)
        .accessibilityLabel(Text("指令历史"))
    }

    // MARK: - 统计卡片
    private var statsCard: some View {
        // 三个统计本来就是同一组事实：给它们一个面，而不给三个颜色。
        // 「成功率」不是状态，用正文色；「进行中」超过 0 才真的是一种状态，那时才带警示色。
        DSGroup {
            DSGroupRow {
                HStack(spacing: 0) {
                    statBubble(label: "总指令", value: "\(store.commandHistory.count)",
                               tint: TokensPalette.primary)
                    let rateStr = successRate > 0 ? String(format: "%.0f%%", successRate * 100) : "—"
                    statBubble(label: "成功率", value: rateStr, tint: TokensPalette.primary)
                    statBubble(label: "进行中", value: "\(inProgressCount)",
                               tint: inProgressCount > 0 ? TokensPalette.warning : TokensPalette.primary)
                }
                .padding(.vertical, TokensSpacing.xs)
            }
        }
    }

    private func statBubble(label: String, value: String, tint: Color) -> some View {
        VStack(spacing: TokensSpacing.xs) {
            Text(value)
                .font(TokensTypo.title)
                .foregroundStyle(tint)
            Text(label)
                .font(TokensTypo.caption2)
                .foregroundStyle(TokensPalette.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 筛选
    private var filterBar: some View {
        // 用系统的分段控件语法，不再自造一排药丸（自造药丸是「理工男」气质的第二来源：
        // 四种筛选本来就该长得像四个互斥的选项）
        DSSegmented(options: filters.map { (value: $0, title: $0) }, selection: $filter)
    }

    // MARK: - 列表
    @ViewBuilder
    private var commandList: some View {
        if filteredCommands.isEmpty {
            DSPlaceholder(icon: "list.bullet.clipboard",
                          title: "暂无指令记录",
                          message: "在「车控」里操作一次，这里会留下那一次的指令与结果。")
        } else {
            // 一叠各自带底的卡片 → 一个分组：行的分隔靠发丝线，不靠每行再画一个圆角矩形。
            DSGroup(title: "记录") {
                ForEach(Array(filteredCommands.enumerated()), id: \.element.id) { _, cmd in
                    DSGroupRow {
                        commandRow(cmd)
                    }
                }
            }
        }
    }

    private func commandRow(_ cmd: AppStore.HistoryEntry) -> some View {
        let isExpanded = expandedCmds.contains(cmd.id)

        // 原来一行里有两个状态图标（左侧印章 + 右侧对/叉）与两种转场（按钮 + onTapGesture）。
        // 现在只有一处状态、一种交互：点整行展开。
        return Button {
            withAnimation(.spring(response: 0.35)) {
                if isExpanded { expandedCmds.remove(cmd.id) }
                else { expandedCmds.insert(cmd.id) }
            }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: TokensSpacing.md) {
                    Image(safeSymbol: cmd.iconName, fallback: "checkmark.circle.fill")
                        .font(TokensTypo.caption)
                        .foregroundStyle(cmd.statusColor)
                        .frame(width: TokensSize.iconColumn, alignment: .center)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(cmd.name)
                            .font(TokensTypo.body)
                            .foregroundStyle(TokensPalette.primary)
                        Text(cmd.startedAt, style: .time)
                            .font(TokensTypo.caption2)
                            .foregroundStyle(TokensPalette.secondary)
                    }

                    Spacer(minLength: TokensSpacing.sm)

                    Image(systemName: cmd.finishedAt == nil
                          ? "circle.dashed"
                          : (cmd.success ? "checkmark.circle.fill" : "xmark.circle.fill"))
                        .font(TokensTypo.caption)
                        .foregroundStyle(cmd.finishedAt == nil ? TokensPalette.warning : cmd.statusColor)
                        .accessibilityLabel(Text(cmd.finishedAt == nil
                            ? "进行中"
                            : (cmd.success ? "执行成功" : "执行失败")))
                }

                // 展开详情：四个字段就是四条键值行（与「全量数据」同一种写法）
                if isExpanded, let finishedAt = cmd.finishedAt {
                    VStack(alignment: .leading, spacing: 0) {
                        DSKeyValueRow(key: "开始", value: cmd.startedAt.formatted(date: .omitted, time: .standard))
                        DSKeyValueRow(key: "结束", value: finishedAt.formatted(date: .omitted, time: .standard))
                        DSKeyValueRow(key: "耗时", value: cmd.durationText)
                        DSKeyValueRow(key: "结果",
                                      value: cmd.success ? "成功" : "失败",
                                      valueCls: cmd.success ? "ok" : "err")
                        // 失败的原因不在这里编：`HistoryEntry` 只记了「成没成」，
                        // 没记服务端返回了什么。要写原因，得先把它真的存下来。
                    }
                    .padding(.top, TokensSpacing.sm)
                }
            }
        }
        .buttonStyle(DSRowButtonStyle())
    }
}

// MARK: - Preview
struct CommandHistoryView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            CommandHistoryView()
        }
    }
}
