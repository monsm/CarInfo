// =============================================================================
// #NEW-124 卡片折叠手势优化 — 左右滑动折叠卡片
// =============================================================================

import SwiftUI

struct SwipeFoldModifier: ViewModifier {
    @State private var offset: CGFloat = 0
    @State private var isFolded = false
    let onFold: () -> Void
    
    func body(content: Content) -> some View {
        content
            .offset(x: isFolded ? offset : 0)
            .rotationEffect(.degrees(isFolded ? offset / 100 * 5 : 0))
            .gesture(
                DragGesture()
                    .onChanged { value in
                        offset = value.translation.width
                    }
                    .onEnded { value in
                        if abs(value.translation.width) > 50 {
                            isFolded.toggle()
                            if isFolded { onFold() }
                        }
                        offset = 0
                    }
            )
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isFolded)
    }
}

extension View {
    func swipeFold(onFold: @escaping () -> Void = {}) -> some View {
        modifier(SwipeFoldModifier(onFold: onFold))
    }
}

// 使用示例
struct SwipeFoldDemo: View {
    @State private var isFolded = false
    
    var body: some View {
        CardBox(title: "可折叠卡片", cornerRadius: 20) {
            Text("左右滑动以折叠/展开")
                .font(Theme.body)
                .foregroundStyle(.secondary)
        }
        .swipeFold {
            isFolded.toggle()
        }
    }
}
