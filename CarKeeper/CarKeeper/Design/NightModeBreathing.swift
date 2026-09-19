// =============================================================================
// #NEW-123 夜间呼吸灯效果 — 深色模式下 TabBar 图标微光呼吸频率加快
// =============================================================================

import SwiftUI

extension View {
    /// 夜间呼吸灯效果：深色模式下图标微光呼吸
    func nightModeBreathing(enabled: Bool = true) -> some View {
        if enabled && AppStore.shared.shouldUseDarkMode() {
            self
                .opacity(0.85 + 0.15 * sin(Date().timeIntervalSince1970 * 2)) // 频率加快
                .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: Date())
        } else {
            self
        }
    }
}

struct NightModeBreathingPreview: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "car.fill")
                .font(.system(size: 48))
                .nightModeBreathing()
            Text("呼吸动画激活中").font(.caption).foregroundStyle(.secondary)
        }
        .preferredColorScheme(.dark)
        .padding()
    }
}
