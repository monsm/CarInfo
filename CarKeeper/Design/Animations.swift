// =============================================================================
// N49 数字翻转动画 + N50 3D 玻璃卡片倾斜
// =============================================================================

import SwiftUI

// MARK: - N49 数字翻转动画
struct FlipNumberView: View {
    let value: Int
    let previousValue: Int
    let fontSize: CGFloat
    
    var body: some View {
        ZStack {
            // 旧数字（翻转出去）
            Text("\(previousValue)")
                .font(.system(size: fontSize, weight: .bold, design: .rounded))
                .opacity(0)
                .rotation3DEffect(
                    .degrees(90),
                    axis: (x: 1, y: 0, z: 0)
                )
                .scaleEffect(0.8)
                .animation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.15), value: value)
            
            // 新数字（翻转进来）
            Text("\(value)")
                .font(.system(size: fontSize, weight: .bold, design: .rounded))
                .rotation3DEffect(
                    .degrees(0),
                    axis: (x: 1, y: 0, z: 0)
                )
                .scaleEffect(1)
                .animation(.spring(response: 0.5, dampingFraction: 0.6), value: value)
        }
    }
}

struct AnimatedFlipNumber: View {
    let value: Int
    @State private var previousValue: Int = 0
    let fontSize: CGFloat = 48
    
    var body: some View {
        FlipNumberView(value: value, previousValue: previousValue, fontSize: fontSize)
            .onChange(of: value) { newValue in
                previousValue = value
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    // 触发翻转
                }
            }
    }
}

// MARK: - N50 3D 玻璃卡片倾斜（跟随手指）
struct TiltGlassCardModifier: ViewModifier {
    @GestureState private var isDragging = false
    @State private var tiltAngle: CGFloat = 0
    @State private var tiltAxis: (x: CGFloat, y: CGFloat) = (0, 0)
    
    func body(content: Content) -> some View {
        content
            .gesture(
                DragGesture()
                    .updating($isDragging) { _, state, _ in state = true }
                    .onChanged { value in
                        let centerX: CGFloat = 200 // 卡片中心近似值
                        let centerY: CGFloat = 150
                        let dx = (value.location.x - centerX) / centerX
                        let dy = (value.location.y - centerY) / centerY
                        tiltAxis = (x: dy * 8, y: -dx * 8) // 最大 8 度倾斜
                    }
                    .onEnded { _ in
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                            tiltAxis = (0, 0)
                        }
                    }
            )
            .rotation3DEffect(
                .degrees(tiltAxis.y),
                axis: (x: tiltAxis.x, y: tiltAxis.y, z: 0)
            )
            .scaleEffect(isDragging ? 0.97 : 1)
            .animation(.interactiveSpring(response: 0.4, dampingFraction: 0.7), value: isDragging)
    }
}

extension View {
    func tiltGlassCard() -> some View {
        modifier(TiltGlassCardModifier())
    }
}

// MARK: - N9 夜间呼吸灯增强（SOC 绑定频率）
struct EnhancedBreathingView: View {
    let soc: Int
    let color: Color
    let size: CGFloat
    
    private var pulseSpeed: Double {
        // SOC 越低，呼吸越快
        guard soc > 0 else { return 0.8 }
        return max(0.3, Double(soc) / 100.0)
    }
    
    var body: some View {
        Circle()
            .fill(color.opacity(0.15))
            .frame(width: size, height: size)
            .scaleEffect(1 + sin(Date().timeIntervalSince1970 * .pi * 2 / pulseSpeed) * 0.05)
            .opacity(0.6 + sin(Date().timeIntervalSince1970 * .pi * 2 / pulseSpeed) * 0.4)
            .animation(.linear(duration: pulseSpeed).repeatForever(autoreverses: false), value: soc)
    }
}
