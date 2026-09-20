// =============================================================================
// E51-E62 游戏化与激励功能
// =============================================================================

import SwiftUI

// MARK: - E57 成就系统
struct Achievement: Identifiable {
    let id = UUID()
    let title: String
    let description: String
    let icon: String
    let unlocked: Bool
    let unlockCondition: String
}

class AchievementManager: ObservableObject {
    static let shared = AchievementManager()

    @Published var unlockedAchievements: Set<UUID> = []

    let achievements: [Achievement] = [
        Achievement(title: "首次充电", description: "完成第一次充电", icon: "bolt.fill", unlocked: false,
         unlockCondition: "完成1次充电"),
        Achievement(title: "环保先锋", description: "累计减碳100kg", icon: "leaf.fill", unlocked: false,
         unlockCondition: "碳减排100kg"),
        Achievement(title: "里程达人", description: "累计行驶1000km", icon: "tachometer", unlocked: false,
         unlockCondition: "行驶1000km"),
        Achievement(title: "完美驾驶", description: "驾驶评分90分以上", icon: "star.fill", unlocked: false,
         unlockCondition: "评分>=90"),
        Achievement(title: "连续打卡", description: "连续7天上车打卡", icon: "calendar.checkmark", unlocked: false,
         unlockCondition: "连续7天打卡"),
    ]

    func unlock(_ achievement: Achievement) {
        unlockedAchievements.insert(achievement.id)
    }

    func isUnlocked(_ achievement: Achievement) -> Bool {
        return unlockedAchievements.contains(achievement.id)
    }
}

struct AchievementBadge: View {
    let achievement: Achievement
    var body: some View {
        VStack {
            Image(safeSymbol: achievement.icon, fallback: "trophy.fill")
                .font(.title)
                .foregroundColor(achievement.unlocked ? .yellow : .secondary)
                .opacity(achievement.unlocked ? 1 : 0.5)
            Text(achievement.title)
                .font(.caption2)
                .foregroundColor(.primary)
        }
        .frame(width: 60, height: 60)
        .glassCard()
    }
}

// MARK: - E58 连续打卡Streak
struct CheckInStreak: View {
    private let store = AppStore.shared

    var streakDays: Int {
        guard let lastCheck = store.lastCheckInDate else { return 0 }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let lastDay = calendar.startOfDay(for: lastCheck)
        return calendar.dateComponents([.day], from: lastDay, to: today).day ?? 0
    }

    var body: some View {
        HStack {
            Image(systemName: "calendar.checkmark")
                .foregroundColor(Kansei.Color.ambient)
            Text("连续打卡 \(streakDays) 天")
                .font(.subheadline)
            Spacer()
            if streakDays >= 7 {
                Image(systemName: "trophy.fill")
                    .foregroundColor(.yellow)
            }
        }
        .padding()
        .glassCard()
    }
}

// MARK: - E59 碳减排目标挑战
struct CarbonChallenge: View {
    @AppStorage("carbon_goal") private var monthlyGoal: Double = 50.0
    @StateObject private var tracker = CarbonSavingsTracker.shared

    var currentSavings: Double { tracker.getTodayStats().totalCarbonKg }
    var progress: Double { min(currentSavings / monthlyGoal, 1.0) }

    var body: some View {
        VStack(spacing: Kansei.Spacing.sm) {
            Text("本月碳减排目标")
                .font(.subheadline)
                .fontWeight(.semibold)

            ZStack {
                Circle().stroke(Color.secondary.opacity(0.2), lineWidth: 10)
                Circle().stroke(style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .foregroundStyle(.green)
                    .rotationEffect(.degrees(270))
                    .animation(.easeOut, value: progress)
                Text("\(Int(progress * 100))%")
                    .font(.title2).fontWeight(.bold)
                    .foregroundColor(.green)
            }
            .frame(width: 80, height: 80)

            HStack {
                Text("目标: \(monthlyGoal) kg")
                    .font(.caption).foregroundColor(.secondary)
                Spacer()
                Text("当前: \(String(format:"%.1f", currentSavings)) kg")
                    .font(.caption).foregroundColor(.green)
            }
        }
        .padding()
        .glassCard()
    }
}

// MARK: - E60 驾驶行为改善推荐
struct DrivingImprovementTips: View {
    let store: AppStore

    var tips: [String] {
        var t = [String]()
        if store.drivingScore < 70 { t.append("尝试更平稳的加速和减速") }
        if store.drivingScore < 80 { t.append("保持恒定车速可提升效率") }
        if t.isEmpty { t.append("驾驶表现优秀，继续保持！") }
        return t
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("驾驶改善建议")
                .font(.subheadline).fontWeight(.semibold)
            ForEach(tips, id: \.self) { tip in
                HStack {
                    Image(systemName: "lightbulb.fill").foregroundColor(.yellow)
                    Text(tip).font(.caption).foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .glassCard()
    }
}

// MARK: - E61 家庭排行榜
struct FamilyLeaderboard: View {
    @StateObject private var family = FamilyManager.shared

    var body: some View {
        List(Array(family.members.enumerated()), id: \.element.id) { idx, member in
            HStack {
                Text("#\(idx + 1)")
                    .font(.headline)
                    .foregroundColor(idx == 0 ? .yellow : idx == 1 ? .gray : idx == 2 ? .orange : .secondary)
                    .frame(width: 30)
                Circle().fill(Kansei.Color.ambient.opacity(0.2)).frame(width: 36, height: 36)
                    .overlay(Text(member.avatar).font(.title3).fontWeight(.bold).foregroundColor(Kansei.Color.ambient))
                VStack(alignment: .leading) {
                    Text(member.name).font(.subheadline).fontWeight(.medium)
                    Text(member.roles.joined(separator: " · ")).font(.caption2).foregroundColor(.secondary)
                }
                Spacer()
                Text("驾驶评分 \(Int.random(in: 70...95))")
                    .font(.caption).foregroundColor(.green)
            }
        }
        .glassCard()
    }
}

// MARK: - E62 里程碑庆祝动效

