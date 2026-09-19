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
            VStack(spacing: 16) {
                // 统计卡片
                statsCard
                
                // 筛选
                filterBar
                
                // 列表
                commandList
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.md)
        }
        .pageBackground(Theme.pageBlue)
        .navigationTitle("指令历史")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityLabel(Text("指令历史"))
    }
    
    // MARK: - 统计卡片
    private var statsCard: some View {
        HStack(spacing: 0) {
            statBubble(label: "总指令", value: "\(store.commandHistory.count)", tint: .blue)
            statBubble(label: "成功率", value: successRate > 0 ? String(format: "%.0f%%", successRate * 100) : "—", tint: .green)
            statBubble(label: "进行中", value: "\(inProgressCount)", tint: .orange)
        }
        .glassCard(corner: Theme.Radius.medium)
    }
    
    private func statBubble(label: String, value: String, tint: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(Theme.h2)
                .foregroundStyle(tint)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - 筛选
    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(filters, id: \.self) { f in
                    Button(role: nil, action: { filter = f }) {
                        Text(f)
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(filter == f ? Theme.Colors.accent.opacity(0.2) : Color.clear)
                            .foregroundStyle(filter == f ? Theme.Colors.accent : .secondary)
                            .cornerRadius(20)
                    }
                }
            }
        }
    }
    
    // MARK: - 列表
    private var commandList: some View {
        if filteredCommands.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "list.bullet.clipboard")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary.opacity(0.4))
                Text("暂无指令记录").font(.subheadline).foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        } else {
            VStack(spacing: 8) {
                ForEach(Array(filteredCommands.enumerated()), id: \.element.id) { idx, cmd in
                    commandRow(cmd, idx: idx)
                }
            }
        }
    }
    
    private func commandRow(_ cmd: AppStore.HistoryEntry, idx: Int) -> some View {
        let isExpanded = expandedCmds.contains(cmd.id)
        
        Button(role: nil, action: {
            withAnimation(.spring(response: 0.35)) {
                if isExpanded { expandedCmds.remove(cmd.id) }
                else { expandedCmds.insert(cmd.id) }
            }
        }) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    // 状态指示
                    Circle()
                        .fill(cmd.statusColor.opacity(0.2))
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(cmd.statusColor, lineWidth: 1.5))
                    
                    // 图标
                    Image(systemName: cmd.iconName)
                        .font(.caption)
                        .foregroundStyle(cmd.statusColor)
                        .frame(width: 28, height: 28)
                        .background(cmd.statusColor.opacity(0.1))
                        .cornerRadius(6)
                    
                    // 名称
                    Text(cmd.name)
                        .font(Theme.subheadline)
                        .foregroundStyle(.primary)
                    
                    Spacer()
                    
                    // 时间
                    Text(cmd.startedAt, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    
                    // 状态图标
                    if cmd.finishedAt != nil {
                        Image(systemName: cmd.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(cmd.statusColor)
                    } else {
                        Image(systemName: "circle.dashed")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .spinSymbol()
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                
                // 展开详情
                if isExpanded, let finishedAt = cmd.finishedAt {
                    VStack(alignment: .leading, spacing: 6) {
                        DetailRow(label: "开始时间", value: cmd.startedAt.formatted(date: .omitted, time: .standard))
                        DetailRow(label: "结束时间", value: finishedAt.formatted(date: .omitted, time: .standard))
                        DetailRow(label: "耗时", value: cmd.durationText)
                        DetailRow(label: "结果", value: cmd.success ? "成功" : "失败")
                        if !cmd.success {
                            DetailRow(label: "错误", value: "服务端返回异常（模拟）")
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                    .font(.caption)
                }
            }
            .glassCard(corner: Theme.Radius.small)
            .onTapGesture {
                withAnimation(.spring(response: 0.35)) {
                    if isExpanded { expandedCmds.remove(cmd.id) }
                    else { expandedCmds.insert(cmd.id) }
                }
            }
            .pressFeedbackLegacy()
        }
    }
}

struct DetailRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).foregroundStyle(.primary)
        }
    }
}

// MARK: - Spin Symbol
extension View {
    func spinSymbol() -> some View {
        self.modifier(SpinningSymbolModifier())
    }
}

struct SpinningSymbolModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .rotationEffect(.init(degrees: 360))
            .animation(.linear(duration: 1.5).repeatForever(autoreverses: false), value: UUID())
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
