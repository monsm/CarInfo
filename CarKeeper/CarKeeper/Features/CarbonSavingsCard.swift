// =============================================================================
// #NEW-107 CarbonSavingsCard — HomeView 碳减排显示卡片
// =============================================================================

import SwiftUI

struct CarbonSavingsCard: View {
    let stats: CarbonSavingStats
    let showDetails: Bool = false
    
    var body: some View {
        CardBox(title: "碳减排", side: "\(stats.equivalentTrees) 棵树", cornerRadius: Theme.Radius.card) {
            VStack(spacing: 12) {
                // 主统计
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("今日步行")
                            .font(Theme.caption)
                            .foregroundStyle(.secondary)
                        Text("\(stats.todaySteps) 步")
                            .font(Theme.d3)
                            .foregroundStyle(.primary)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("减碳量")
                            .font(Theme.caption)
                            .foregroundStyle(.secondary)
                        Text("\(String(format: "%.2f", stats.todayCarbonKg)) kg")
                            .font(Theme.d3)
                            .foregroundStyle(.green)
                    }
                }
                
                // 等效树木
                HStack {
                    Image(systemName: "tree.fill")
                        .foregroundStyle(.green)
                    Text("相当于 \(stats.equivalentTrees) 棵树吸收的碳")
                        .font(Theme.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                
                // 模拟按钮（测试用）
                if showDetails {
                    Button("模拟今日步数") {
                        CarbonSavingsTracker.shared.simulateDailySteps()
                    }
                    .font(Theme.caption)
                    .foregroundStyle(Color.accent)
                }
            }
        }
    }
}
