// =============================================================================
// N6 全局 Toast 动画增强 + N7 空状态插画升级 + N8 下拉刷新涟漪统一
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
            Image(systemName: item.icon)
                .font(.title3)
            Text(item.text)
                .font(.subheadline)
                .lineLimit(2)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
        .background(Color(.systemBackground).opacity(0.95))
        .foregroundColor(.primary)
        .cornerRadius(Theme.Radius.lg)
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
        VStack(spacing: Theme.Spacing.lg) {
            // 动态图标（根据内容变化）
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [.accentColor.opacity(0.2), .accentColor.opacity(0.05)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 100, height: 100)
                Image(systemName: icon)
                    .font(.system(size: 40))
                    .foregroundColor(.accentColor)
                    .scaleEffect(1)
                    .animation(.spring(response: 0.5, dampingFraction: 0.5).repeatAutologically(), value: icon)
            }
            
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
                        .foregroundColor(.white)
                        .padding(.horizontal, Theme.Spacing.xl)
                        .padding(.vertical, Theme.Spacing.sm)
                        .background(.accentColor)
                        .cornerRadius(Theme.Radius.md)
                }
            }
        }
        .padding(.vertical, Theme.Spacing.xl)
    }
}

struct PageEmptyView: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?
    
    var body: some View {
        EmptyStateView(icon: icon, title: title, message: message,
                       actionTitle: actionTitle, action: action)
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - N8 下拉刷新涟漪统一（所有 ScrollView）
struct GlassRefreshRipple: ViewModifier {
    @Binding var isRefreshing: Bool
    @State private var ripplePosition: CGPoint = .zero
    @State private var rippleRadius: CGFloat = 0
    @State private var rippleOpacity: CGFloat = 0
    
    func body(content: Content) -> some View {
        content
            .onAppear {
                // 注册下拉刷新回调
            }
            .overlay(alignment: .top) {
                if isRefreshing {
                    GeometryReader { geo in
                        ZStack {
                            // 多个同心圆涟漪
                            ForEach(0..<3, id: \.self) { i in
                                Circle()
                                    .fill(Color.accentColor.opacity(0.1 * CGFloat(3 - i)))
                                    .frame(width: rippleRadius + CGFloat(i) * 40,
                                           height: rippleRadius + CGFloat(i) * 40)
                                    .offset(y: -20)
                            }
                        }
                        .position(ripplePosition)
                        .onAppear {
                            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                                rippleRadius = min(geo.size.width, geo.size.height)
                                rippleOpacity = 0.3
                            }
                        }
                        .onChange(of: isRefreshing) { refreshing in
                            if !refreshing {
                                withAnimation(.easeOut(duration: 0.3)) {
                                    rippleRadius = 0
                                    rippleOpacity = 0
                                }
                            }
                        }
                    }
                    .allowsHitTesting(false)
                }
            }
    }
}

extension View {
    func glassRefreshRipple(isRefreshing: Binding<Bool>) -> some View {
        modifier(GlassRefreshRipple(isRefreshing: isRefreshing))
    }
}
