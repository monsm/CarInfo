// =============================================================================
// N6 全局 Toast + N7 空状态插画
// =============================================================================

import SwiftUI

// MARK: - N6 增强版 Toast（带滑动消失 + 音效）
class EnhancedToastManager: ObservableObject {
    static let shared = EnhancedToastManager()

    @Published var currentItem: (text: String, icon: String, duration: Double)? = nil
    @Published var isAnimating: Bool = false
    @Published var dismissProgress: CGFloat = 1.0  // 1=显示，0=完全消失

    private var dismissHandle: DispatchWorkItem?
    private var swipeGesture: UIPanGestureRecognizer?

    private init() {}

    func show(_ text: String, icon: String = "checkmark.circle.fill", duration: Double = 2.0) {
        dismissHandle?.cancel()
        currentItem = (text, icon, duration)
        isAnimating = true
        dismissProgress = 1.0

        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            withAnimation(.easeIn(duration: 0.3)) {
                self.dismissProgress = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.currentItem = nil
                self.isAnimating = false
                self.dismissProgress = 1.0
            }
        }
        dismissHandle = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    func swipeToDismiss() {
        dismissHandle?.cancel()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            dismissProgress = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.currentItem = nil
            self.isAnimating = false
            self.dismissProgress = 1.0
        }
    }
}


// MARK: - N7 空状态插画升级
