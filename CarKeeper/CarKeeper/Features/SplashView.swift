// =============================================================================
// #NEW-112 启动画面 Splash — 液态玻璃溶解动画
// =============================================================================

import SwiftUI
import UIKit

struct SplashView: View {
    @State private var progress: CGFloat = 0
    @State private var showMain = false
    @State private var dissolved = false
    
    let duration: TimeInterval = 2.0
    
    var body: some View {
        ZStack {
            // 背景渐变
            LinearGradient(
                colors: [
                    .accent.opacity(0.3),
                    Color.purple.opacity(0.2),
                    Color.blue.opacity(0.1)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            if !dissolved {
                // Logo + 进度
                VStack(spacing: 24) {
                    // 液态玻璃圆环动画
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.2), lineWidth: 2)
                            .frame(width: 120, height: 120)
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(
                                AngularGradient(
                                    colors: [.white, .accent],
                                    center: .center
                                ),
                                style: StrokeStyle(lineWidth: 3, lineCap: .round)
                            )
                            .frame(width: 120, height: 120)
                            .rotationEffect(.degrees(-90))
                        
                        // Logo 图标
                        Image(systemName: "car.side.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.white)
                    }
                    .shadow(color: .accent.opacity(0.5), radius: 20, y: 10)
                    
                    Text("长安车管家")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)
                        .letterSpacing(3)
                    
                    Text("CHANGAN CONNECT")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .letterSpacing(4)
                    
                    // 进度条
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color.white.opacity(0.2))
                            .frame(height: 3)
                        Rectangle()
                            .fill(LinearGradient(
                                colors: [.white, .accent],
                                startPoint: .leading,
                                endPoint: .trailing
                            ))
                            .frame(width: progress * 200, height: 3)
                    }
                    .frame(width: 200)
                    .cornerRadius(2)
                }
            }
        }
        .onAppear {
            // 动画序列
            withAnimation(.linear(duration: duration)) {
                progress = 1.0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                withAnimation(.easeOut(duration: 0.5)) {
                    dissolved = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    showMain = true
                }
            }
        }
    }
}

struct SplashView_Previews: PreviewProvider {
    static var previews: some View {
        SplashView()
    }
}
