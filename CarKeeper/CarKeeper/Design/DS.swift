import SwiftUI
import UIKit



enum DS {
}



struct DSCard<Content: View>: View {
    var padding: CGFloat
    var radius: CGFloat
    var content: () -> Content

    init(padding: CGFloat = TokensSpacing.md,
         radius: CGFloat = TokensRadius.medium,
         @ViewBuilder content: @escaping () -> Content) {
        self.padding = padding
        self.radius = radius
        self.content = content
    }

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(TokensPalette.panel)
            }
    }
}

struct DSDivider: View {
    var inset: CGFloat = 0
    var body: some View {
        Rectangle()
            .fill(TokensPalette.hairline)
            .frame(height: TokensHair.line)
            .padding(.leading, inset)
    }
}

struct DSSeparator: View {
    var inset: CGFloat = TokensHair.inset
    var body: some View {
        DSDivider(inset: inset)
    }
}


struct DSGroup<Content: View>: View {
    var title: String? = nil
    var trailing: String? = nil
    var trailingCls: String = "na"
    var footer: String? = nil
    var onTrailingTap: (() -> Void)? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                DSSectionHeader(title: title, trailing: trailing,
                                trailingCls: trailingCls, action: onTrailingTap)
            }
            VStack(spacing: 0) { content() }
                .clipShape(RoundedRectangle(cornerRadius: TokensRadius.medium, style: .continuous))
            if let footer {
                Text(footer)
                    .font(TokensTypo.footnote)
                    .foregroundStyle(TokensPalette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, TokensSpacing.sm)
            }
        }
    }
}

struct DSGroupRow<Content: View>: View {
    var showsSeparator: Bool = true
    var separatorInset: CGFloat = 0
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            content()
                .padding(.horizontal, TokensSpacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: TokensSpacing.row)
            if showsSeparator { DSSeparator(inset: separatorInset) }
        }
    }
}

struct DSKeyValueRow: View {
    var key: String
    var value: String
    var valueCls: String = "na"
    var mono: Bool = true

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: TokensSpacing.md) {
            Text(key)
                .font(TokensTypo.subheadline)
                .foregroundStyle(TokensPalette.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: TokensSpacing.sm)
            Text(value)
                .font(mono ? TokensTypo.dataSmall : TokensTypo.subheadline)
                .foregroundStyle(valueCls == "na" ? TokensPalette.secondary : TokensPalette.statusColor(valueCls))
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .layoutPriority(1)
        }
        .frame(minHeight: TokensSpacing.row)
        .accessibilityElement(children: .combine)
    }
}


struct DSSectionHeader: View {
    var title: String = ""
    var trailing: String? = nil
    var trailingCls: String = "na"
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            if !title.isEmpty {
                Text(title.uppercased())
                    .font(TokensTypo.fixed(13))
                    .tracking(TokensTracking.label)
                    .foregroundStyle(TokensPalette.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: TokensSpacing.sm)
            if let trailing {
                if let action {
                    Button(trailing, action: action)
                        .font(TokensTypo.footnote)
                        .foregroundStyle(TokensPalette.ambient)
                        .buttonStyle(.plain)
                        .frame(minHeight: TokensSpacing.row)
                        .contentShape(Rectangle())
                } else if trailingCls != "na" {
                    DSChip(text: trailing, cls: trailingCls)
                } else {
                    Text(trailing)
                        .font(TokensTypo.footnote)
                        .foregroundStyle(TokensPalette.tertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
        .padding(.bottom, TokensSpacing.sm)
    }
}

struct DSBigNumber: View {
    var value: String
    var unit: String? = nil
    var caption: String? = nil
    var size: CGFloat = 96
    var tint: Color = TokensPalette.primary
    var alignment: HorizontalAlignment = .leading
    var weight: Font.Weight = .ultraLight

    var body: some View {
        VStack(alignment: alignment, spacing: TokensSpacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: TokensSpacing.xs) {
                Text(value)
                    .font(TokensTypo.display(size, weight: weight))
                    .tracking(-size * 0.035)
                    .foregroundStyle(tint)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let unit {
                    Text(unit)
                        .font(TokensTypo.metric(size * 0.30))
                        .foregroundStyle(TokensPalette.secondary)
                }
            }
            if let caption {
                Text(caption)
                    .font(TokensTypo.footnote)
                    .foregroundStyle(TokensPalette.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

extension View {
    func dsPageTitle(_ title: String, inline: Bool = false) -> some View {
        navigationTitle(title)
            .navigationBarTitleDisplayMode(inline ? .inline : .large)
    }

}


struct DSLightBar: View {
    var progress: Double
    var height: CGFloat = 6
    var showsGlow: Bool = true
    var tint: LinearGradient? = nil
    @State private var revealed: Double = 0

    private var clamped: Double { max(0, min(1, progress)) }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width * revealed
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(TokensPalette.track)
                    .frame(height: height)
                if showsGlow && w > 1 {
                    Capsule()
                        .fill(tint ?? TokensPalette.lightBar)
                        .frame(width: w, height: height)
                        .blur(radius: 9)
                        .opacity(0.75)
                }
                Capsule()
                    .fill(tint ?? TokensPalette.lightBar)
                    .frame(width: w, height: height)
            }
            .frame(height: height)
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .frame(height: height)
        .onAppear {
            withAnimation(TokensMotion.draw) { revealed = clamped }
        }
        .onChange(of: clamped) { _, newValue in
            withAnimation(TokensMotion.value) { revealed = newValue }
        }
        .accessibilityElement()
        .accessibilityLabel(Text("电量比例"))
        .accessibilityValue(Text("\(Int(clamped * 100))%"))
    }
}

struct DSRing<Content: View>: View {
    var progress: Double
    var tint: Color
    var size: CGFloat = 108
    var lineWidth: CGFloat = 12
    @ViewBuilder var content: Content

    private var clamped: Double { max(0, min(1, progress)) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(TokensPalette.track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            content
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .contain)
    }
}

struct DSStatStrip: View {
    struct Item: Identifiable {
        let id = UUID()
        var label: String
        var value: String
        var second: String? = nil
        var cls: String = "na"
        var icon: String? = nil
        init(_ label: String, _ value: String, second: String? = nil,
             cls: String = "na", icon: String? = nil) {
            self.label = label
            self.value = value
            self.second = second
            self.cls = cls
            self.icon = icon
        }
    }

    var items: [Item]

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                if idx > 0 {
                    Rectangle()
                        .fill(TokensPalette.hairline)
                        .frame(width: TokensHair.line)
                        .frame(maxHeight: .infinity)
                }
                VStack(alignment: .leading, spacing: TokensSpacing.xs) {
                    HStack(spacing: TokensSpacing.xs) {
                        if let icon = item.icon {
                            Image(safeSymbol: icon, fallback: "circle")
                                .font(TokensTypo.fixed(10, weight: .semibold))
                        }
                        Text(item.label)
                            .lineLimit(1)
                    }
                    .font(TokensTypo.caption)
                    .foregroundStyle(TokensPalette.secondary)
                    Text(item.value)
                        .font(TokensTypo.data)
                        .foregroundStyle(item.cls == "na" ? TokensPalette.primary : TokensPalette.statusColor(item.cls))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if let second = item.second {
                        Text(second)
                            .font(TokensTypo.data)
                            .foregroundStyle(item.cls == "na"
                                             ? TokensPalette.primary
                                             : TokensPalette.statusColor(item.cls))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, TokensSpacing.md)
                .padding(.vertical, TokensSpacing.md)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
    }
}

struct DSChip: View {
    var text: String
    var cls: String = "na"
    var icon: String? = nil

    private var color: Color { TokensPalette.statusColor(cls) }

    var body: some View {
        HStack(spacing: TokensSpacing.sm) {
            if let icon {
                Image(safeSymbol: icon, fallback: "circle.fill")
                    .font(TokensTypo.fixed(10, weight: .semibold))
                    .foregroundStyle(color)
            } else {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
            }
            Text(text)
                .font(TokensTypo.footnote)
                .foregroundStyle(cls == "na" ? TokensPalette.secondary : color)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}



struct DSRow: View {
    var icon: String?
    var title: String
    var subtitle: String? = nil
    var value: String? = nil
    var valueCls: String = "na"
    var showsChevron: Bool = false
    var action: (() -> Void)? = nil

    var body: some View {
        Group {
            if let action {
                Button(action: action) { rowContent }.buttonStyle(DSRowButtonStyle())
            } else {
                rowContent
            }
        }
    }

    private var rowContent: some View {
        HStack(spacing: TokensSpacing.md) {
            if let icon {
                Image(safeSymbol: icon, fallback: "circle")
                    .font(.system(size: TokensSize.icon))
                    .foregroundStyle(TokensPalette.ambient)
                    .frame(width: TokensSize.iconColumn, alignment: .center)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(TokensTypo.body)
                    .foregroundStyle(TokensPalette.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(TokensTypo.footnote)
                        .foregroundStyle(TokensPalette.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: TokensSpacing.sm)
            if let value {
                Text(value)
                    .font(TokensTypo.data)
                    .foregroundStyle(valueCls == "na" ? TokensPalette.secondary : TokensPalette.statusColor(valueCls))
                    .multilineTextAlignment(.trailing)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(TokensTypo.fixed(13, weight: .semibold))
                    .foregroundStyle(TokensPalette.tertiary)
            }
        }
        .frame(minHeight: TokensSpacing.row)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct DSRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? TokensPalette.fillSubtle : Color.clear)
            .animation(TokensMotion.press, value: configuration.isPressed)
    }
}


struct DSPrimaryButtonStyle: ButtonStyle {
    var tint: Color = TokensPalette.ambient

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TokensTypo.headline)
            .foregroundStyle(TokensPalette.labelOnTint)
            .frame(maxWidth: .infinity)
            .frame(height: TokensSize.button)
            .background(Capsule().fill(tint))
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(TokensMotion.press, value: configuration.isPressed)
    }
}

struct DSSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TokensTypo.headline)
            .foregroundStyle(TokensInk.primary)
            .frame(maxWidth: .infinity)
            .frame(height: TokensSize.button)
            .dsGlassCapsule(interactive: true)
            .animation(TokensMotion.press, value: configuration.isPressed)
    }
}



struct DSNotice: View {
    enum Kind { case info, warning, error, success
        var cls: String {
            switch self {
            case .info: return "acc"
            case .warning: return "warn"
            case .error: return "bad"
            case .success: return "ok"
            }
        }
        var icon: String {
            switch self {
            case .info: return "info.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .error: return "xmark.octagon.fill"
            case .success: return "checkmark.circle.fill"
            }
        }
    }

    var kind: Kind
    var text: String
    var action: (title: String, run: () -> Void)? = nil

    var body: some View {
        HStack(spacing: TokensSpacing.sm) {
            Image(safeSymbol: kind.icon, fallback: "info.circle.fill")
                .font(TokensTypo.fixed(15))
                .foregroundStyle(TokensPalette.statusColor(kind.cls))
            Text(text)
                .font(TokensTypo.footnote)
                .foregroundStyle(TokensPalette.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: TokensSpacing.sm)
            if let action {
                Button(action.title, action: action.run)
                    .font(TokensTypo.footnote.weight(.semibold))
                    .foregroundStyle(TokensPalette.ambient)
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, TokensSpacing.md)
        .padding(.vertical, TokensSpacing.sm)
        .background(RoundedRectangle(cornerRadius: TokensRadius.small, style: .continuous)
            .fill(TokensPalette.panel))
        .accessibilityElement(children: .combine)
    }
}

struct DSPlaceholder: View {
    var icon: String
    var title: String
    var message: String? = nil
    var actionTitle: String? = nil
    var cls: String = "na"
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: TokensSpacing.md) {
            Image(safeSymbol: icon, fallback: "questionmark.circle")
                .font(TokensTypo.fixed(40, weight: .light))
                .foregroundStyle(cls == "na" ? TokensPalette.tertiary : TokensPalette.statusColor(cls))
            Text(title)
                .font(TokensTypo.headline)
                .foregroundStyle(TokensPalette.primary)
                .multilineTextAlignment(.center)
            if let message {
                Text(message)
                    .font(TokensTypo.footnote)
                    .foregroundStyle(TokensPalette.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(DSSecondaryButtonStyle())
                    .frame(maxWidth: 220)
            }
        }
        .padding(.vertical, TokensSpacing.xxxl)
        .padding(.horizontal, TokensSpacing.xl)
        .frame(maxWidth: .infinity)
    }
}

struct DSSkeleton: View {
    var height: CGFloat = 16
    var width: CGFloat? = nil

    var body: some View {
        RoundedRectangle(cornerRadius: TokensRadius.small, style: .continuous)
            .fill(TokensPalette.fillSubtle)
            .frame(width: width, height: height)
            .accessibilityHidden(true)
    }
}

struct DSLoadingSkeleton: View {
    var message: String = "加载中…"
    var heights: [CGFloat]
    var label: String? = nil

    var body: some View {
        if let label {
            stack.accessibilityLabel(Text(label))
        } else {
            stack
        }
    }

    private var stack: some View {
        VStack(alignment: .leading, spacing: TokensSpacing.md) {
            HStack(spacing: TokensSpacing.sm) {
                ProgressView().controlSize(.small)
                Text(message)
                    .font(TokensTypo.footnote)
                    .foregroundStyle(TokensPalette.secondary)
            }
            ForEach(Array(heights.enumerated()), id: \.offset) { _, h in
                DSSkeleton(height: h)
            }
        }
        .accessibilityElement(children: .combine)
    }
}




struct DSExpandGroup<Content: View>: View {
    var title: String
    var trailing: String? = nil
    var trailingCls: String = "na"
    var footer: String? = nil
    var initiallyExpanded: Bool = false
    @ViewBuilder var content: () -> Content

    @State private var expanded: Bool

    init(title: String,
         trailing: String? = nil,
         trailingCls: String = "na",
         footer: String? = nil,
         initiallyExpanded: Bool = false,
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.trailing = trailing
        self.trailingCls = trailingCls
        self.footer = footer
        self.initiallyExpanded = initiallyExpanded
        self.content = content
        _expanded = State(initialValue: initiallyExpanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                TokensHaptic.select()
                withAnimation(TokensMotion.value) { expanded.toggle() }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: TokensSpacing.sm) {
                    Text(title.uppercased())
                        .font(TokensTypo.fixed(13))
                        .tracking(TokensTracking.label)
                        .foregroundStyle(TokensPalette.secondary)
                    Spacer(minLength: TokensSpacing.sm)
                    if let trailing, !trailing.isEmpty {
                        DSChip(text: trailing, cls: trailingCls)
                    }
                    Image(systemName: "chevron.down")
                        .font(TokensTypo.fixed(11, weight: .semibold))
                        .foregroundStyle(TokensPalette.tertiary)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .padding(.bottom, TokensSpacing.sm)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(title))
            .accessibilityValue(Text(expanded ? "已展开" : "已收起"))

            if expanded {
                VStack(spacing: 0) { content() }
                    .background {
                        RoundedRectangle(cornerRadius: TokensRadius.medium, style: .continuous)
                            .fill(TokensPalette.panel)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: TokensRadius.medium, style: .continuous))
            }

            if let footer {
                Text(footer)
                    .font(TokensTypo.footnote)
                    .foregroundStyle(TokensPalette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, TokensSpacing.sm)
            }
        }
    }
}

struct DSSection<Content: View>: View {
    var title: String
    var trailing: String? = nil
    var trailingCls: String = "na"
    var footer: String? = nil
    @ViewBuilder var content: () -> Content

    @State private var expanded: Bool = false

    init(title: String,
         trailing: String? = nil,
         trailingCls: String = "na",
         footer: String? = nil,
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.trailing = trailing
        self.trailingCls = trailingCls
        self.footer = footer
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                TokensHaptic.select()
                withAnimation(TokensMotion.value) { expanded.toggle() }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: TokensSpacing.sm) {
                    Text(title.uppercased())
                        .font(TokensTypo.fixed(13))
                        .tracking(TokensTracking.label)
                        .foregroundStyle(TokensPalette.secondary)
                    Spacer(minLength: TokensSpacing.sm)
                    if let trailing, !trailing.isEmpty {
                        DSChip(text: trailing, cls: trailingCls)
                    }
                    Image(systemName: "chevron.down")
                        .font(TokensTypo.fixed(11, weight: .semibold))
                        .foregroundStyle(TokensPalette.tertiary)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .padding(.bottom, TokensSpacing.sm)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(title))
            .accessibilityValue(Text(expanded ? "已展开" : "已收起"))

            if expanded {
                VStack(spacing: 0) { content() }
            }

            if let footer {
                Text(footer)
                    .font(TokensTypo.footnote)
                    .foregroundStyle(TokensPalette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, TokensSpacing.sm)
            }
        }
    }
}

struct DSSurfaceModifier: ViewModifier {
    var padding: CGFloat
    var radius: CGFloat
    var subtle: Bool

    init(padding: CGFloat, radius: CGFloat, subtle: Bool) {
        self.padding = padding
        self.radius = radius
        self.subtle = subtle
    }

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(subtle ? TokensPalette.fillSubtle : TokensPalette.panel)
            }
    }
}

extension View {
    func dsSurface(padding: CGFloat = TokensSpacing.md,
                   radius: CGFloat = TokensRadius.medium,
                   subtle: Bool = false) -> some View {
        modifier(DSSurfaceModifier(padding: padding, radius: radius, subtle: subtle))
    }
}


