import SwiftUI




extension View {
    @ViewBuilder
    func dsGlass<S: InsettableShape>(in shape: S,
                                     interactive: Bool = false,
                                     hairline: Bool = true,
                                     dim: Double = 1) -> some View {
        if UIAccessibility.isReduceTransparencyEnabled {
            shape.fill(TokensPalette.surface)
                .overlay {
                    if hairline {
                        shape.strokeBorder(TokensPalette.hairline, lineWidth: TokensHair.border)
                    }
                }
        } else {
            glassEffect(dsGlassMaterial(interactive: interactive), in: shape)
                .background {
                    if dim > 0 {
                        shape.fill(TokensPalette.glassDim.opacity(dim))
                    }
                }
                .overlay {
                    if hairline {
                        shape.strokeBorder(TokensPalette.hairline, lineWidth: TokensHair.border)
                    }
                }
        }
    }

    private func dsGlassMaterial(interactive: Bool) -> Glass {
        let base: Glass = .clear
        return interactive ? base.interactive(true) : base
    }

    func dsGlassCapsule(interactive: Bool = false,
                        hairline: Bool = true,
                        dim: Double = 1) -> some View {
        dsGlass(in: Capsule(), interactive: interactive, hairline: hairline, dim: dim)
    }

    func dsGlassRounded(_ radius: CGFloat = TokensRadius.large,
                        interactive: Bool = false,
                        hairline: Bool = true,
                        dim: Double = 1) -> some View {
        dsGlass(in: RoundedRectangle(cornerRadius: radius, style: .continuous),
                interactive: interactive, hairline: hairline, dim: dim)
    }

    func dsGlassLayer(spacing: CGFloat = TokensSpacing.lg) -> some View {
        GlassEffectContainer(spacing: spacing) { self }
    }
}
