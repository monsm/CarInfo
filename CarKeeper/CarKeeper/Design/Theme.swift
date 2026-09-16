import SwiftUI

// 设计系统：遵循苹果 HIG 的语义色 / 字体 / 间距令牌。
// 浅色 + 深色模式自动适配（全部用系统语义色，零硬编码）。

enum Theme {
    // 语义色（随系统外观自动切换）
    static var ok: Color { Color.green }
    static var warn: Color { Color.orange }
    static var bad: Color { Color.red }
    static var acc: Color { Color.accentColor }
    static var na: Color { Color.secondary }

    // 状态胶囊配色（ok/warn/bad/na）
    static func statusColor(_ cls: String) -> Color {
        switch cls {
        case "ok": return .green
        case "warn": return .orange
        case "bad": return .red
        case "acc": return .accentColor
        default: return .secondary
        }
    }

    // 字号（SF Pro 系统字体，大数字用 rounded）
    static let d1 = Font.system(size: 64, weight: .ultraLight, design: .rounded)
    static let d2 = Font.system(size: 48, weight: .ultraLight, design: .rounded)
    static let d3 = Font.system(size: 32, weight: .light, design: .rounded)
    static let h1 = Font.system(size: 34, weight: .semibold)
    static let h2 = Font.system(size: 24, weight: .semibold)
    static let t1 = Font.system(size: 18, weight: .semibold)
    static let body = Font.system(size: 16, weight: .regular)
    static let small = Font.system(size: 14, weight: .regular)
    static let fine = Font.system(size: 12, weight: .regular)

    // 间距
    static let cardSpacing: CGFloat = 16
    static let cardPadding: CGFloat = 16
}

// 状态点（小圆点 + 语义色）
struct StatusDot: View {
    let cls: String
    var size: CGFloat = 8
    var body: some View {
        Circle()
            .fill(Theme.statusColor(cls))
            .frame(width: size, height: size)
            .opacity(cls == "na" ? 0.4 : 1)
    }
}

// 语义色胶囊（Pill）
struct Pill: View {
    let text: String
    let cls: String
    var dot: Bool = true

    var body: some View {
        HStack(spacing: 6) {
            if dot { StatusDot(cls: cls, size: 6) }
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.statusColor(cls))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(Theme.statusColor(cls).opacity(0.12))
        )
        .overlay(Capsule().strokeBorder(Theme.statusColor(cls).opacity(0.35), lineWidth: 1))
    }
}

// 键值行（详情页 / 明细）
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
                .font(.system(size: 14, design: mono ? .monospaced : .default, weight: strong ? .semibold : .regular))
                .foregroundStyle(strong ? .primary : .secondary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// 分组卡片（系统分组样式）
struct CardBox<Content: View>: View {
    let title: String
    var side: String? = nil
    var sideCls: String = ""
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
                if let side {
                    Text(side)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.statusColor(sideCls))
                }
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
    }
}
