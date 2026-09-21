// =============================================================================
// OrbitNav.swift — 弧形轨道导航
// 取代传统 TabBar，提供沉浸式底部导航体验
// =============================================================================
import SwiftUI

struct OrbitNav: View {
    let items: [OrbitNavItem]
    @Binding var selected: Int

    init(items: [OrbitNavItem], selected: Binding<Int>) {
        self.items = items
        self._selected = selected
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                Button {
                    withAnimation(KanseiMotion.tap) {
                        selected = index
                    }
                    KanseiHaptic.select()
                } label: {
                    OrbitNavItemView(
                        item: item,
                        isSelected: selected == index
                    )
                }
                .buttonStyle(.plain)

                if index < items.count - 1 {
                    Rectangle()
                        .fill(KanseiPalette.glassBorder)
                        .frame(width: 0.5, height: 24)
                }
            }
        }
        .padding(.horizontal, KanseiSpacing.sm)
        .padding(.vertical, KanseiSpacing.sm)
        .background(
            Material.thickMaterial
                .blendMode(.overlay)
        )
        .background(Color.black.opacity(0.2))
        .overlay(alignment: .top) {
            DSDivider()
        }
    }
}

// MARK: - 导航项视图
struct OrbitNavItemView: View {
    let item: OrbitNavItem
    let isSelected: Bool

    var body: some View {
        VStack(spacing: KanseiSpacing.xs) {
            ZStack {
                Image(systemName: isSelected ? (item.activeIcon ?? item.icon) : item.icon)
                    .font(.system(size: 22, weight: isSelected ? .medium : .regular))
                    .foregroundColor(isSelected ? KanseiPalette.ambient : KanseiPalette.tertiary)

                if let badge = item.badge {
                    Text(badge)
                        .font(KanseiTypo.micro)
                        .foregroundColor(.white)
                        .frame(width: 16, height: 16)
                        .background(KanseiPalette.error)
                        .clipShape(Circle())
                        .position(x: 18, y: -2)
                }
            }

            Text(item.label)
                .font(KanseiTypo.micro)
                .foregroundColor(isSelected ? KanseiPalette.ambient : KanseiPalette.tertiary)

            if isSelected {
                Capsule()
                    .fill(KanseiPalette.ambient)
                    .frame(width: 4, height: 4)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 60)
    }
}

// MARK: - 导航项数据
struct OrbitNavItem: Identifiable {
    let id = UUID()
    let icon: String
    let activeIcon: String?
    let label: String
    let badge: String?
}
