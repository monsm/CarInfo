import SwiftUI

struct ControlRequest: Equatable {
    let uid = UUID()
    let key: String
    let name: String
    var temp: Int? = nil
}

private enum ControlStage: Equatable {
    case none
    case temp
    case biometric
    case pin
}

struct ControlCommandFlow: ViewModifier {
    @Binding var request: ControlRequest?

    private let store = AppStore.shared
    @ObservedObject private var commands = CommandCenter.shared

    @State private var temp = 25
    @State private var pending: ControlRequest?
    @State private var stage: ControlStage = .none
    @State private var isAuthed = false

    func body(content: Content) -> some View {
        content
            .onChange(of: request) { _, r in
                guard let r else { return }
                start(r)
            }
            .sheet(isPresented: stageBinding(.temp)) {
                ACStepperView(initialTemp: $temp)
                    .onReceive(NotificationCenter.default.publisher(for: .tempConfirmed)) { note in
                        if let t = note.object as? Int { temp = t }
                        stage = .none
                        gate()
                    }
            }
            .sheet(isPresented: stageBinding(.pin)) {
                PINKeypadView()
                    .onReceive(NotificationCenter.default.publisher(for: .pinConfirmed)) { note in
                        guard let pin = note.object as? String else { return }
                        stage = .none
                        if store.readPin() == nil {
                            store.savePin(pin)
                            ToastManager.shared.show("PIN码已安全保存", icon: "key.fill")
                        }
                        fire(pin: pin)
                    }
            }
            .overlay {
                if stage == .biometric {
                    BiometricLockOverlay(isAuthenticated: $isAuthed)
                        .onAppear { isAuthed = false }
                        .onChange(of: isAuthed) { _, ok in
                            if ok { stage = .pin }
                        }
                }
            }
    }

    private func stageBinding(_ s: ControlStage) -> Binding<Bool> {
        Binding(get: { stage == s },
                set: { if !$0 && stage == s { stage = .none } })
    }


    private func start(_ r: ControlRequest) {
        guard !commands.busy, commands.running == nil else { return }
        guard !store.carId.isEmpty else {
            ToastManager.shared.show("请先选择车辆", icon: "car.fill")
            return
        }
        pending = r
        if let t = r.temp { temp = t }
        if r.key == "OpenAir" { stage = .temp } else { gate() }
    }

    private func gate() {
        if store.canUseBiometric() && store.hasBiometricSetup {
            stage = .biometric
        } else {
            stage = .pin
        }
    }

    private func fire(pin: String) {
        guard let p = pending else { return }
        commands.send(cmd: p.key,
                      temperature: p.key == "OpenAir" ? temp : 17,
                      pin: pin,
                      displayName: p.name)
        pending = nil
        request = nil
    }
}

extension View {
    func controlCommandFlow(_ request: Binding<ControlRequest?>) -> some View {
        modifier(ControlCommandFlow(request: request))
    }
}
