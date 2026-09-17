import SwiftUI

// 设计系统 v2 —— iOS 27「Liquid Glass」设计语言。
// 玻璃材质卡片 + 渐变光晕页底 + SF 圆体数字层级 + 语义色系统。
// 材质全部走系统 Material / glassEffect，深浅色模式自动适配，零硬编码颜色。

enum Theme {
    // 语义色（随系统外观自动切换）
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

    // 字号（SF Pro；大数字用 rounded，凸显数字产品的仪表感）
    static let d1 = Font.system(size: 76, weight: .bold, design: .rounded)
    static let d2 = Font.system(size: 48, weight: .semibold, design: .rounded)
    static let d3 = Font.system(size: 30, weight: .medium, design: .rounded)
    static let h1 = Font.system(size: 34, weight: .bold)
    static let h2 = Font.system(size: 22, weight: .semibold)
    static let t1 = Font.system(size: 17, weight: .semibold)
    static let body = Font.system(size: 16, weight: .regular)
    static let small = Font.system(size: 14, weight: .regular)
    static let fine = Font.system(size: 12, weight: .regular)

    // 间距与圆角令牌
    static let cardSpacing: CGFloat = 14
    static let cardPadding: CGFloat = 18
    static let radius: CGFloat = 26
}

// MARK: - 页面底色：柔和主题色光晕（每页可传 tint）
struct PageBackground: View {
    var tint: Color = .accentColor
    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
            LinearGradient(colors: [tint.opacity(0.16), .clear],
                           startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.42))
            RadialGradient(colors: [tint.opacity(0.10), .clear],
                           center: .topTrailing, startRadius: 20, endRadius: 460)
        }
        .ignoresSafeArea()
    }
}

extension View {
    /// 页面底：系统分组底色 + 主题色光晕
    func pageBackground(_ tint: Color = .accentColor) -> some View {
        background(PageBackground(tint: tint))
    }

    /// 玻璃卡片：ultraThin 材质 + 顶部高光描边 + 柔和投影
    func glassCard(corner: CGFloat = Theme.radius) -> some View {
        self
            .background(.ultraThinMaterial,
                        in: RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0.06)],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.08), radius: 18, y: 6)
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
        VStack(alignment: .leading, spacing: 12) {
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

// MARK: - 统计小磁贴（图标 + 标签 + 大数字）
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

// MARK: - 列表分隔行（分组内标准行高）
struct ListDivider: View {
    var body: some View {
        Divider().opacity(0.6)
    }
}
