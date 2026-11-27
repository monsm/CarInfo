import SwiftUI

struct MapCarPin: View {
    var lamp: Double = 0

    var body: some View {
        ZStack {
            lampBloom
            groundShadow(opacity: 0.34)
            capsule
        }
        .frame(width: 68, height: 44)
        .accessibilityElement()
        .accessibilityLabel(Text("车的位置"))
    }

    private var capsule: some View {
        Image(safeSymbol: "car.fill", fallback: "car.fill")
            .font(TokensTypo.fixed(19, weight: .semibold))
            .foregroundStyle(TokensInk.primary)
            .padding(.horizontal, TokensSpacing.snug)
            .padding(.vertical, TokensSpacing.xs)
            .dsGlassCapsule()
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var lampBloom: some View {
        if lamp > 0.05 {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [TokensPalette.lightSource.opacity(0.34 * lamp),
                                 TokensPalette.lightSource.opacity(0)],
                        center: .center,
                        startRadius: 0,
                        endRadius: 78
                    )
                )
                .frame(width: 156, height: 156)
        }
    }

    private func groundShadow(opacity: Double) -> some View {
        Ellipse()
            .fill(TokensPalette.scrim.opacity(opacity))
            .frame(width: 34, height: 8)
            .blur(radius: 5)
            .offset(y: 17)
    }
}

struct MapClusterPin: View {
    let count: Int

    var body: some View {
        Text("\(count)")
            .font(TokensTypo.dataSmall)
            .foregroundStyle(TokensPalette.labelOnTint)
            .frame(width: 30, height: 30)
            .background(Circle().fill(TokensPalette.ambient))
            .overlay(Circle().strokeBorder(TokensPalette.canvas, lineWidth: 1.5))
            .accessibilityLabel(Text("\(count) 个充电站"))
    }
}

struct MapSpotPin: View {
    enum Kind {
        case hold(isLatest: Bool)
        case charger(distanceText: String)
        case issue
    }

    var kind: Kind
    var label: String? = nil

    var body: some View {
        VStack(spacing: TokensSpacing.xs) {
            switch kind {
            case .hold(let isLatest):
                holdPin(isLatest: isLatest)
            case .charger(let distanceText):
                chargerPin(distanceText: distanceText)
            case .issue:
                issuePin
            }
            if let label, !label.isEmpty {
                Text(label)
                    .font(TokensTypo.digits(11))
                    .tracking(TokensTracking.label)
                    .foregroundStyle(TokensPalette.error)
                    .shadow(color: TokensPalette.scrim.opacity(0.55), radius: 3, y: 1)
                    .fixedSize()
            }
        }
    }

    private var ink: Color { TokensPalette.primary }
    private var inkSoft: Color { TokensPalette.secondary }

    private func holdPin(isLatest: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(TokensPalette.surface)
                .frame(width: isLatest ? 20 : 16, height: isLatest ? 20 : 16)
                .overlay {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(ink.opacity(isLatest ? 0.85 : 0.45),
                                      lineWidth: isLatest ? 1.6 : 1)
                }
                .shadow(color: TokensPalette.scrim.opacity(0.35), radius: 8, y: 4)
            if isLatest {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(ink)
                    .frame(width: 7, height: 7)
            }
        }
        .frame(width: 44, height: 44)
        .accessibilityLabel(Text(isLatest ? "上次停车位置" : "更早的停车位置"))
    }

    private func chargerPin(distanceText: String) -> some View {
        VStack(spacing: TokensSpacing.xs) {
            ZStack {
                Circle()
                    .fill(TokensPalette.surface)
                    .frame(width: 22, height: 22)
                    .overlay { Circle().strokeBorder(inkSoft.opacity(0.6), lineWidth: 1) }
                Image(safeSymbol: "bolt.fill", fallback: "bolt.fill")
                    .font(TokensTypo.fixed(10, weight: .semibold))
                    .foregroundStyle(TokensPalette.info)
            }
            Text(distanceText)
                .font(TokensTypo.digits(10).weight(.medium))
                .foregroundStyle(ink)
                .padding(.horizontal, TokensSpacing.xs)
                .padding(.vertical, TokensSpacing.xxs)
                .background {
                    Capsule().fill(TokensPalette.surface.opacity(0.92))
                }
                .overlay { Capsule().strokeBorder(TokensPalette.hairline, lineWidth: 0.5) }
        }
        .frame(width: 60, height: 40)
        .accessibilityLabel(Text("充电站，距离 \(distanceText)"))
    }

    private var issuePin: some View {
        ZStack {
            Triangle()
                .fill(TokensPalette.error)
                .frame(width: 20, height: 18)
            Text("!")
                .font(TokensTypo.fixed(11, weight: .bold))
                .foregroundStyle(TokensPalette.labelOnTint)
                .offset(y: 1)
        }
        .frame(width: 44, height: 44)
        .shadow(color: TokensPalette.error.opacity(0.6), radius: 8)
        .accessibilityLabel(Text("有一条异常"))
    }
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

