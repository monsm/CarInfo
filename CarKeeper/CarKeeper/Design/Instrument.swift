// =============================================================================
// Instrument.swift — 仪表组件
// 112pt thin 数字 + 进度弧 + 状态指示
// =============================================================================
import SwiftUI

// MARK: - 巨型数字
struct DSBigNumber: View {
    let value: String
    let unit: String?
    let caption: String?
    let size: CGFloat
    let tint: Color
    let alignment: HorizontalAlignment

    init(
        value: String,
        unit: String? = nil,
        caption: String? = nil,
        size: CGFloat = 112,
        tint: Color = Kansei.Color.primary,
        alignment: HorizontalAlignment = .leading
    ) {
        self.value = value
        self.unit = unit
        self.caption = caption
        self.size = size
        self.tint = tint
        self.alignment = alignment
    }

    var body: some View {
        VStack(alignment: alignment, spacing: Kansei.Spacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Kansei.Spacing.sm) {
                Text(value)
                    .font(.system(size: size, weight: .thin).monospacedDigit())
                    .foregroundColor(tint)
                    .tracking(-size * 0.02)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)

                if let unit {
                    Text(unit)
                        .font(.system(size: size * 0.25, weight: .regular))
                        .foregroundColor(Kansei.Color.secondary)
                }
            }

            if let caption {
                Text(caption)
                    .font(Kansei.Type.caption)
                    .foregroundColor(Kansei.Color.tertiary)
            }
        }
    }
}

// MARK: - 进度弧
struct DSArcProgress: View {
    let progress: Double
    let size: CGFloat
    let lineWidth: CGFloat
    let tint: Color
    let trackColor: Color
    let showValue: Bool

    init(
        progress: Double,
        size: CGFloat = 200,
        lineWidth: CGFloat = 8,
        tint: Color = Kansei.Color.ambient,
        trackColor: Color = Kansei.Color.glassBorder,
        showValue: Bool = true
    ) {
        self.progress = max(0, min(1, progress))
        self.size = size
        self.lineWidth = lineWidth
        self.tint = tint
        self.trackColor = trackColor
        self.showValue = showValue
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(trackColor, style: StrokeStyle(lineWidth: lineWidth))

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    tint,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.5, dampingFraction: 0.7), value: progress)

            if showValue {
                Circle()
                    .fill(Kansei.Color.nightSurface.opacity(0.8))
                    .frame(width: size * 0.7, height: size * 0.7)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - 三列状态条
struct DSStatStrip: View {
    struct Item: Identifiable {
        let id = UUID()
        let label: String
        let value: String
        let cls: String
        let icon: String?

        init(_ label: String, _ value: String, cls: String = "na", icon: String? = nil) {
            self.label = label
            self.value = value
            self.cls = cls
            self.icon = icon
        }
    }

    let items: [Item]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                if idx > 0 {
                    Rectangle()
                        .fill(Kansei.Color.glassBorder)
                        .frame(width: 0.5)
                        .frame(maxHeight: .infinity)
                }

                VStack(alignment: .leading, spacing: Kansei.Spacing.xs) {
                    HStack(spacing: Kansei.Spacing.xs) {
                        if let icon = item.icon {
                            Image(systemName: icon)
                                .font(.system(size: 10))
                                .foregroundColor(Kansei.Color.tertiary)
                        }
                        Text(item.label)
                            .font(Kansei.Type.caption)
                            .foregroundColor(Kansei.Color.tertiary)
                    }

                    Text(item.value)
                        .font(.system(size: 17, weight: .regular).monospacedDigit())
                        .foregroundColor(statusColor(item.cls))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Kansei.Spacing.md)
                .padding(.vertical, Kansei.Spacing.sm)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: Kansei.Radius.medium, style: .continuous)
                .fill(Kansei.Color.nightSurface.opacity(0.4))
        )
    }

    private func statusColor(_ cls: String) -> Color {
        switch cls {
        case "ok", "normal": return Kansei.Color.success
        case "warn", "warning": return Kansei.Color.warning
        case "bad", "fault", "danger": return Kansei.Color.error
        case "charge": return Kansei.Color.info
        default: return Kansei.Color.secondary
        }
    }
}

// MARK: - 状态标签
struct DSChip: View {
    let text: String
    let cls: String
    let icon: String?

    var body: some View {
        HStack(spacing: Kansei.Spacing.xs) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundColor(statusColor)
            } else {
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)
            }

            Text(text)
                .font(Kansei.Type.caption)
                .foregroundColor(statusColor)
                .lineLimit(1)
        }
        .padding(.horizontal, Kansei.Spacing.sm)
        .padding(.vertical, Kansei.Spacing.xs)
        .background(statusColor.opacity(0.15))
        .cornerRadius(Kansei.Radius.pill)
    }

    private var statusColor: Color {
        switch cls {
        case "ok", "normal": return Kansei.Color.success
        case "warn", "warning": return Kansei.Color.warning
        case "bad", "fault", "danger": return Kansei.Color.error
        case "charge": return Kansei.Color.info
        default: return Kansei.Color.secondary
        }
    }
}

// MARK: - 行项目
struct DSRow: View {
    let icon: String?
    let title: String
    let subtitle: String?
    let value: String?
    let valueCls: String
    let showsChevron: Bool

    init(
        icon: String? = nil,
        title: String,
        subtitle: String? = nil,
        value: String? = nil,
        valueCls: String = "na",
        showsChevron: Bool = false
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.value = value
        self.valueCls = valueCls
        self.showsChevron = showsChevron
    }

    var body: some View {
        HStack(spacing: Kansei.Spacing.md) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 17))
                    .foregroundColor(Kansei.Color.ambient)
                    .frame(width: 29)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Kansei.Type.subtitle)
                    .foregroundColor(Kansei.Color.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(Kansei.Type.caption)
                        .foregroundColor(Kansei.Color.tertiary)
                        .lineLimit(2)
                }
            }

            Spacer()

            if let value {
                Text(value)
                    .font(.system(size: 17).monospacedDigit())
                    .foregroundColor(valueColor)
            }

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Kansei.Color.tertiary)
            }
        }
        .frame(minHeight: 44)
    }

    private var valueColor: Color {
        valueCls == "na" ? Kansei.Color.secondary : statusColor(valueCls)
    }

    private func statusColor(_ cls: String) -> Color {
        switch cls {
        case "ok", "normal": return Kansei.Color.success
        case "warn", "warning": return Kansei.Color.warning
        case "bad", "fault", "danger": return Kansei.Color.error
        default: return Kansei.Color.secondary
        }
    }
}
