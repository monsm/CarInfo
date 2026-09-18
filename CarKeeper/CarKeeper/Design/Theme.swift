import SwiftUI

// 设计系统 v3 —— Apple Premium Design Language
// 参考：Apple Watch Series 10 / HomePod 2 / iOS 27
// 核心理念：大留白、大圆角、多层玻璃、渐变光晕、精确的字体层级

enum Theme {
    // 语义色
    static var ok: Color { Color.green }
    static var warn: Color { Color.orange }
    static var bad: Color { Color.red }
    static var acc: Color { Color.accentColor }
    static var na: Color { Color.secondary }

    // 状态 → 语义色
    static func statusColor(_ cls: String) -> Color {
        switch cls {
        case "ok": return .green
        case "warn": return .orange
        case "bad": return .red
        case "acc": return .accentColor
        case "idle", "off": return Color.secondary
        default: return Color.secondary
        }
    }

    // 字号体系 — Apple 标准
    static let d1 = Font.system(size: 80, weight: .bold, design: .rounded)     // Hero 大数字
    static let d2 = Font.system(size: 52, weight: .semibold, design: .rounded) // 二级数字
    static let d3 = Font.system(size: 34, weight: .medium, design: .rounded)   // 三级数字
    static let h1 = Font.system(size: 28, weight: .bold)                       // 页面标题
    static let h2 = Font.system(size: 20, weight: .semibold)                   // 卡片标题
    static let t1 = Font.system(size: 17, weight: .semibold)                   // 正文强调
    static let body = Font.system(size: 16, weight: .regular)                  // 正文
    static let small = Font.system(size: 14, weight: .regular)                 // 辅助文字
    static let fine = Font.system(size: 12, weight: .regular)                  // 微文字

    // 间距与圆角
    static let cardSpacing: CGFloat = 16
    static let cardPadding: CGFloat = 20
    static let radius: CGFloat = 28
}

// MARK: - 页面底色：多层次渐变光晕
struct PageBackground: View {
    var tint: Color = .accentColor
    var body: some View {
        ZStack {
            // 底层：系统分组背景
            Color(.systemGroupedBackground)
            // 中层：主题色渐变光晕（大面积、柔和）
            LinearGradient(colors: [tint.opacity(0.20), tint.opacity(0.05), .clear],
                           startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.6))
            // 顶层：径向光晕（右上角）
            RadialGradient(colors: [tint.opacity(0.12), .clear],
                           center: .topTrailing, startRadius: 30, endRadius: 500)
        }
        .ignoresSafeArea()
    }
}

extension View {
    /// 页面底：系统分组底色 + 多层次主题色光晕
    func pageBackground(_ tint: Color = .accentColor) -> some View {
        background(PageBackground(tint: tint))
    }

    /// 苹果级玻璃卡片：薄材质 + 顶部高光描边 + 大圆角 + 柔和投影
    func glassCard(corner: CGFloat = Theme.radius) -> some View {
        self
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [.white.opacity(0.40), .white.opacity(0.08)],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 0.8)
            )
            .shadow(color: .black.opacity(0.06), radius: 20, y: 8)
    }

    /// 更大的玻璃卡片（用于 Hero 区域）
    func glassHeroCard(corner: CGFloat = 32) -> some View {
        self
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0.10)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1.2)
            )
            .shadow(color: .black.opacity(0.08), radius: 24, y: 10)
    }
}

// MARK: - 状态点（带同色光晕）
struct StatusDot: View {
    let cls: String
    var size: CGFloat = 8
    var body: some View {
        Circle()
            .fill(Theme.statusColor(cls))
            .frame(width: size, height: size)
            .opacity(cls == "na" ? 0.4 : 1)
            .shadow(color: Theme.statusColor(cls).opacity(0.55), radius: 3)
    }
}

// MARK: - 语义色玻璃胶囊
struct Pill: View {
    let text: String
    let cls: String
    var dot: Bool = true

    var body: some View {
        HStack(spacing: 6) {
            if dot { StatusDot(cls: cls, size: 6) }
            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.statusColor(cls))
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.statusColor(cls).opacity(0.30), lineWidth: 1))
    }
}

// MARK: - 键值行（详情 / 明细）
struct KVRow: View {
    let k: String
    let v: String
    var mono: Bool = false
    var strong: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(k)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            Spacer(minLength: 16)
            Text(v)
                .font(.system(size: 14, weight: strong ? .semibold : .medium,
                              design: mono ? .monospaced : .rounded))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 玻璃分组卡片（全局容器：标题 + 状态胶囊 + 内容）
struct CardBox<Content: View>: View {
    let title: String
    var side: String? = nil
    var sideCls: String = ""
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if let side, !side.isEmpty {
                    Pill(text: side, cls: sideCls.isEmpty ? "na" : sideCls, dot: false)
                }
            }
            content()
        }
        .padding(Theme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}

// MARK: - 统计小磁贴
struct StatTile: View {
    let icon: String
    let label: String
    let value: String
    var unit: String = ""
    var tint: Color = .accentColor

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(value)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    if !unit.isEmpty {
                        Text(unit).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - 列表分隔行
struct ListDivider: View {
    var body: some View {
        Divider().opacity(0.6)
    }
}

// MARK: - 分区标题
struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }
}

// MARK: - 指标徽章（用于车控大圆钮等场景）
struct MetricPill: View {
    let icon: String
    let value: String
    let unit: String
    var tint: Color = .accentColor

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint.opacity(0.8))
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)
            if !unit.isEmpty {
                Text(unit)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
