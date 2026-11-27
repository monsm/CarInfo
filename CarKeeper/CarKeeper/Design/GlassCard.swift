import SwiftUI

struct GlassCard<Content: View>: View {
    var accent: Color = TokensPalette.accent
    var accentWash: Double = 0.16
    @ViewBuilder var content: Content

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: StackSpec.Card.radius, style: .continuous)
    }

    var body: some View {
        content
            .padding(.horizontal, StackSpec.Card.padH)
            .padding(.top, StackSpec.Card.padTop)
            .padding(.bottom, StackSpec.Card.padBottom)
            .frame(maxWidth: .infinity, alignment: .leading)
            .dsGlass(in: shape, hairline: false)
            .overlay { accentWashOverlay }
            .overlay { shape.strokeBorder(TokensPalette.hairline, lineWidth: TokensHair.border) }
            .clipShape(shape)
            .accessibilityElement(children: .contain)
    }

    private var accentWashOverlay: some View {
        RadialGradient(colors: [accent.opacity(accentWash), accent.opacity(0)],
                       center: .topLeading, startRadius: 0, endRadius: 260)
            .allowsHitTesting(false)
            .clipShape(shape)
    }
}

struct GlassCardHead: View {
    let title: String
    var value: String? = nil
    var cls: String = "na"
    var at: Date? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: TokensSpacing.sm) {
            Text(title)
                .font(TokensTypo.fixed(13))
                .tracking(TokensTracking.label)
                .foregroundStyle(TokensInk.secondary)
                .textCase(.uppercase)
            Spacer(minLength: TokensSpacing.sm)
            if let value {
                Text(value)
                    .font(TokensTypo.dataSmall)
                    .foregroundStyle(TokensPalette.statusColor(cls))
            }
            if let at {
                Text(at.formatted(date: .omitted, time: .shortened))
                    .font(TokensTypo.micro)
                    .foregroundStyle(TokensInk.tertiary)
            }
        }
    }
}


struct GlassCardEmpty: View {
    let text: String
    var icon: String = "tray"

    var body: some View {
        HStack(spacing: TokensSpacing.sm) {
            Image(safeSymbol: icon, fallback: icon)
                .font(TokensTypo.footnote)
                .foregroundStyle(TokensInk.tertiary)
            Text(text)
                .font(TokensTypo.footnote)
                .foregroundStyle(TokensInk.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, TokensSpacing.xs)
    }
}
