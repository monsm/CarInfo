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

// MARK: - N6 Toast 视图
struct EnhancedToastView: View {
    @StateObject private var manager = EnhancedToastManager.shared
    var item: (text: String, icon: String, duration: Double)

    var body: some View {
        HStack(spacing: 10) {
            Image(safeSymbol: item.icon, fallback: "checkmark.circle.fill")
                .font(.title3)
            Text(item.text)
                .font(.subheadline)
                .lineLimit(2)
        }
        .padding(.horizontal, TokensSpacing.lg)
        .padding(.vertical, TokensSpacing.md)
        .background(Color(.systemBackground).opacity(0.95))
        .foregroundColor(.primary)
        .cornerRadius(TokensRadius.medium)
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        .scaleEffect(manager.dismissProgress)
        .opacity(manager.dismissProgress)
        .gesture(
            DragGesture()
                .onEnded { value in
                    if abs(value.translation.width) > 50 {
                        manager.swipeToDismiss()
                    }
                }
        )
        .transition(.asymmetric(
            insertion: .move(edge: .top).combined(with: .opacity),
            removal: .move(edge: .bottom).combined(with: .opacity)
        ))
    }
}

// MARK: - N7 空状态插画升级
struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?

    init(icon: String = "car.fill", title: String = "暂无数据", message: String = "", actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.icon = icon
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        VStack(spacing: TokensSpacing.lg) {
            // 动态图标（根据内容变化）
            // 旧版：渐变圆 + 持续重复的缩放动画（提示图标一直在跳）。
            // 新版：一个扁平色块承载图标，提示本身不需要动。
            Image(safeSymbol: icon, fallback: "checkmark.circle.fill")
                .font(.system(size: 32, weight: .regular))
                .foregroundStyle(TokensPalette.ambient)
                .frame(width: 72, height: 72)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(TokensPalette.ambient))

            Text(title)
                .font(.title3)
                .fontWeight(.semibold)

            if !message.isEmpty {
                Text(message)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            if let actionTitle = actionTitle, let action = action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(TokensPalette.labelOnTint)
                        .padding(.horizontal, TokensSpacing.xl)
                        .padding(.vertical, TokensSpacing.sm)
                        .background(TokensPalette.ambient)
                        .cornerRadius(TokensRadius.medium)
                }
            }
        }
        .padding(.vertical, TokensSpacing.xl)
    }
}
