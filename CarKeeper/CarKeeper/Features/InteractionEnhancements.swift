// =============================================================================
// E17 触觉反馈差异化
// E18 全局下拉刷新涟漪
// E20 数字变化膨胀动效
// E22 长按卡片预览
// E23 滑动删除命令历史
// =============================================================================

import SwiftUI
import CoreHaptics

// MARK: - E17 触觉反馈管理器
class HapticFeedbackManager: ObservableObject {
    static let shared = HapticFeedbackManager()
    private var engine: CHHapticEngine?
    
    private init() {}
    
    func prepare() {
        do {
            engine = try CHHapticEngine()
            try engine?.start()
        } catch {
            print("Haptics not available: \(error)")
        }
    }
    
    // 锁车触觉反馈（短促有力）
    func playLockHaptic() {
        var events: [CHHapticEvent] = []
        events.append(CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.8),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.6)
            ],
            relativeTime: 0
        ))
        events.append(CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.5)
            ],
            relativeTime: 0.1
        ))
        playPattern(events)
    }
    
    // 解锁触觉反馈（轻柔）
    func playUnlockHaptic() {
        var events: [CHHapticEvent] = []
        events.append(CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.4),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.3)
            ],
            relativeTime: 0
        ))
        playPattern(events)
    }
    
    // 空调开启触觉反馈（流畅）
    func playACOnHaptic() {
        var events: [CHHapticEvent] = []
        events.append(CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [],
            relativeTime: 0
        ))
        playPattern(events)
    }
    
    // 警告触觉反馈（强烈）
    func playWarningHaptic() {
        var events: [CHHapticEvent] = []
        for i in 0..<3 {
            events.append(CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.9)
                ],
                relativeTime: Double(i) * 0.15
            ))
        }
        playPattern(events)
    }
    
    private func playPattern(_ events: [CHHapticEvent]) {
        guard let engine = engine else { return }
        Task {
            do {
                let pattern = try CHHapticPattern(events: events, parameters: [])
                let player = try engine.makePlayer(with: pattern)
                try player.start(atTime: 0)
            } catch {
                print("Haptic play error: \(error)")
            }
        }
    }
}

// MARK: - E18 全局下拉刷新涟漪

extension View {
    func glassRefreshRippleBinding(_ isRefreshing: Binding<Bool>) -> some View {
        modifier(GlassRefreshRipple(isRefreshing: isRefreshing))
    }
}

// MARK: - E20 数字膨胀动效
struct PulseNumber: View {
    let value: Int
    let unit: String
    
    var body: some View {
        Text("\(value)\(unit)")
            .font(.system(size: 48, weight: .bold, design: .rounded))
            .scaleEffect(1)
            .animation(.spring(response: 0.4, dampingFraction: 0.5).repeatCount(1), value: value)
    }
}

// MARK: - E22 长按卡片预览
struct LongPressPreview<Content: View>: View {
    @State private var isPressed = false
    @State private var previewOffset: CGSize = .zero
    let content: Content
    let previewContent: () -> Content
    
    init(@ViewBuilder content: () -> Content, @ViewBuilder previewContent: @escaping () -> Content) {
        self.content = content()
        self.previewContent = previewContent
    }
    
    var body: some View {
        ZStack {
            // 原内容
            content
                .scaleEffect(isPressed ? 0.95 : 1)
                .offset(previewOffset)
                .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.6), value: isPressed)
            
            // 预览浮层
            if isPressed {
                previewContent()
                    .glassCard()
                    .shadow(color: .black.opacity(0.3), radius: 10, y: 5)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if value.translation.width > 20 {
                        isPressed = true
                    }
                }
                .onEnded { _ in
                    isPressed = false
                    previewOffset = .zero
                }
        )
    }
}

// MARK: - E23 滑动删除命令历史
struct SwipeToDeleteCommand: View {
    let command: AppStore.HistoryEntry
    let onDelete: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(command.cmd)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(command.startedAt.formatted(date: .numeric, time: .omitted))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            // 原来是文字字符 "✓" / "✗" 当图标用，改成真正的 SF Symbol
            Image(safeSymbol: command.success ? "checkmark.circle.fill" : "xmark.circle.fill",
                  fallback: command.success ? "checkmark" : "xmark")
                .foregroundStyle(command.success ? Color.green : Color.red)
        }
        .padding()
        .glassCard()
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("删除", systemImage: "trash.fill")
            }
        }
    }
}
