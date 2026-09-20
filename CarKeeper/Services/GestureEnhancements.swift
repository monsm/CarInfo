// =============================================================================
// N46 摇一摇锁车 + N47 SOC 长按详情 + N48 左右滑动换车
// =============================================================================

import SwiftUI
import CoreMotion

// MARK: - N46 摇一摇锁车
class ShakeDetector: ObservableObject {
    static let shared = ShakeDetector()
    private let motionManager = CMMotionManager()
    private var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: "carkeeper_shake_to_lock")
    }

    private init() {}

    func startMonitoring() {
        guard motionManager.isAccelerometerAvailable, isEnabled else { return }
        motionManager.accelerometerUpdateInterval = 0.1
        motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, error in
            guard let data = data, let self = self else { return }
            let acceleration = sqrt(data.acceleration.x * data.acceleration.x +
                                    data.acceleration.y * data.acceleration.y +
                                    data.acceleration.z * data.acceleration.z)
            if acceleration > 1.5 { // 检测到明显摇动
                self.onShake?(data.acceleration)
            }
        }
    }

    func stopMonitoring() {
        motionManager.stopAccelerometerUpdates()
    }

    var onShake: ((CMAcceleration) -> Void)?
}

// MARK: - N47 SOC 长按详情
struct SOCDetailSheet: View {
    let soc: Int
    let range: Int
    let timeToFull: Int?
    let timeToEmpty: Int?
    let charging: Bool
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("电量信息") {
                    LabeledContent("当前 SOC", value: "\(soc)%")
                    LabeledContent("剩余续航", value: "\(range) km")
                    if let ttf = timeToFull, ttf > 0 {
                        LabeledContent("充满时间", value: "\(ttf) 分钟")
                    }
                    if let tte = timeToEmpty {
                        LabeledContent("耗尽时间", value: "\(tte) 分钟")
                    }
                }
                Section("充电状态") {
                    LabeledContent("状态", value: charging ? "充电中" : "未充电")
                    if charging {
                        LabeledContent("功率", value: "3.7 kW")
                    }
                }
                Section("预估成本") {
                    let cost = Double(soc) * 0.15
                    LabeledContent("满电成本", value: "约 ¥\(String(format: "%.0f", cost))")
                }
            }
            .navigationTitle("电量详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
        }
    }
}

// MARK: - N48 左右滑动切换车辆
struct CarSwitchGesture: ViewModifier {
    @Binding var selectedCarIndex: Int
    let carCount: Int
    let onSwitch: (Int) -> Void

    @State private var dragOffset: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .gesture(
                DragGesture()
                    .onChanged { value in
                        dragOffset = value.translation.width
                    }
                    .onEnded { value in
                        let threshold: CGFloat = 60
                        if value.translation.width < -threshold && selectedCarIndex < carCount - 1 {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                                selectedCarIndex += 1
                            }
                            onSwitch(selectedCarIndex)
                        } else if value.translation.width > threshold && selectedCarIndex > 0 {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                                selectedCarIndex -= 1
                            }
                            onSwitch(selectedCarIndex)
                        }
                        dragOffset = 0
                    }
            )
            .offset(x: dragOffset * 0.3)
            .animation(.interactiveSpring(response: 0.4, dampingFraction: 0.6), value: dragOffset)
    }
}

extension View {
    func carSwitchGesture(selectedCarIndex: Binding<Int>, carCount: Int, onSwitch: @escaping (Int) -> Void) -> some View {
        modifier(CarSwitchGesture(selectedCarIndex: selectedCarIndex, carCount: carCount, onSwitch: onSwitch))
    }
}
