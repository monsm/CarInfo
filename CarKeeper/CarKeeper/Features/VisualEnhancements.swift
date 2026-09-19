// =============================================================================
// E79-E80 视觉与动画升级
// =============================================================================

import SwiftUI

// MARK: - E79 Lottie风格动画（使用SwiftUI实现）
struct ConfettiAnimation: View {
    @State private var particles: [ConfettiParticle] = []
    
    var body: some View {
        ZStack {
            Color.clear
            ForEach(particles) { particle in
                Circle()
                    .fill(particle.color)
                    .frame(width: particle.size, height: particle.size)
                    .position(x: particle.x, y: particle.y)
                    .opacity(particle.opacity)
            }
        }
        .onAppear(perform: spawnParticles)
    }
    
    func spawnParticles() {
        particles = (0..<50).map { ConfettiParticle(index: $0) }
        withAnimation(.linear(duration: 2.5)) {
            for i in particles.indices {
                particles[i].animate()
            }
        }
    }
}

struct ConfettiParticle: Identifiable {
    let id = UUID()
    let index: Int
    let color: Color
    let size: CGFloat
    var x: CGFloat
    var y: CGFloat
    var opacity: Double
    
    init(index: Int) {
        let palette: [Color] = [.red, .blue, .green, .yellow, .purple, .orange]
        self.index = index
        self.color = palette[index % palette.count]
        self.size = CGFloat.random(in: 4...12)
        self.x = CGFloat.random(in: 100...300)
        self.y = -20
        self.opacity = 1
    }
    
    mutating func animate() {
        y = CGFloat.random(in: 400...600)
        x += CGFloat.random(in: -50...50)
        opacity = 0
    }
}

// MARK: - E80 深色/浅色模式过渡动画
struct ColorSchemeTransition: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @State private var overlayOpacity: Double = 0
    
    func body(content: Content) -> some View {
        content
            .overlay(
                Color.white.opacity(overlayOpacity)
                    .ignoresSafeArea()
            )
            .onChange(of: colorScheme) { _ in
                withAnimation(.easeInOut(duration: 0.3)) {
                    overlayOpacity = 1
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        overlayOpacity = 0
                    }
                }
            }
    }
}

extension View {
    func colorSchemeTransition() -> some View {
        modifier(ColorSchemeTransition())
    }
}

// MARK: - 玻璃卡片3D倾斜效果（增强版）
struct GlassCard3D: ViewModifier {
    @GestureState private var isDragging = false
    @State private var tiltX: CGFloat = 0
    @State private var tiltY: CGFloat = 0
    
    func body(content: Content) -> some View {
        content
            .rotation3DEffect(
                .degrees(tiltY),
                axis: (x: tiltX, y: tiltY, z: 0)
            )
            .scaleEffect(isDragging ? 0.96 : 1)
            .shadow(color: .black.opacity(isDragging ? 0.3 : 0.1), radius: isDragging ? 20 : 10, y: isDragging ? 10 : 5)
            .gesture(
                DragGesture()
                    .updating($isDragging) { _, state, _ in state = true }
                    .onChanged { value in
                        tiltX = value.translation.height / 10
                        tiltY = -value.translation.width / 10
                    }
                    .onEnded { _ in
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            tiltX = 0
                            tiltY = 0
                        }
                    }
            )
    }
}

extension View {
    func glassCard3D() -> some View {
        modifier(GlassCard3D())
    }
}

// MARK: - 数字翻转动画（增强版）
struct FlipNumberEnhanced: View {
    let value: Int
    let previousValue: Int
    let fontSize: CGFloat = 48
    
    @State private var isFlipping = false
    
    var body: some View {
        ZStack {
            if isFlipping {
                Text("\(previousValue)")
                    .font(.system(size: fontSize, weight: .bold, design: .rounded))
                    .rotation3DEffect(.degrees(90), axis: (x: 1, y: 0, z: 0))
                    .opacity(0)
            }
            Text("\(value)")
                .font(.system(size: fontSize, weight: .bold, design: .rounded))
                .scaleEffect(isFlipping ? 1.2 : 1)
                .animation(.spring(response: 0.4, dampingFraction: 0.5), value: value)
        }
        .onChange(of: value) { newValue in
            if newValue != previousValue {
                isFlipping = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    isFlipping = false
                }
            }
        }
    }
}
