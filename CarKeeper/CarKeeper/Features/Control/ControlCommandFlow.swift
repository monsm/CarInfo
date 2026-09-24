import SwiftUI

// =============================================================================
//  ControlCommandFlow —— 车控指令的**唯一**那道门
// =============================================================================
//
//  用户 2026-09-24：「右下角的控车选了后不用输入密码？不用选温度？」
//
//  是真的，而且原因值得写下来：车控档那条路（`ControlView.onCmd`）走
//  温度 → 生物识别 → 控车码 三步；地图右臂那条路直接调 `AppStore.sendControlCommand`，
//  它从 Keychain 取出上一次存的控车码就发了。同一个动作两套强度 ——
//  于是「门」形同虚设，而且两处谁也不知道对方漏了什么。
//
//  所以这道门只留一处：这个 modifier 挂在**发起指令的屏**上，屏只负责把请求交给它
//  （`request = ControlRequest(key:name:)`），验证、温度、下发全由它做。
//  现在有两处挂它（车控档、地图右臂），强度不可能不一致。
//
//  一条指令刻意**不经**这道门：`UpCarCondition`（刷新车况）。它不改车的任何状态，
//  只是把车端叫醒、让它上报一次（见 `API-FIELD-MAP` §4.9）。门的成本是用户手输控车码，
//  这份成本只该收在「会改变车状态」的动作上 —— 收在刷新上只会让人干脆不刷新。
struct ControlRequest: Equatable {
    /// 每一次点击都是一个**新**请求：带上一个 UUID，所以连点两次同一条指令
    /// 也会各走一遍（`Equatable` 合成时会带上它，`.onChange` 因此不会漏）。
    let uid = UUID()
    /// 真实指令名（与 `ControlView` 的命令表逐字一致，不另造一套简写）
    let key: String
    /// 界面上叫它什么（发起处给：车控档用命令表，地图右臂用按钮上的字）
    let name: String
    /// 预设场景自带温度（`PresetScene.temp`）；nil = 用上一次选的
    var temp: Int? = nil
}

/// 一条车控请求要经过的四步。用状态机而不是四个布尔量：
/// 四个布尔量能表达「同时在选温度又在对 PIN」，而那是一个不该存在的状态。
private enum ControlStage: Equatable {
    case none
    case temp
    case biometric
    case pin
}

struct ControlCommandFlow: ViewModifier {
    /// 发起处把请求写进来；走完这道门由它自己清空（同一个请求不会因为重绘再走一遍）
    @Binding var request: ControlRequest?

    private let store = AppStore.shared
    @ObservedObject private var commands = CommandCenter.shared

    /// 上一次选的温度。空调要先过温度那一步，选过的值就是下一次的默认值。
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
            // ① 空调温度（只有空调有这一步：温度对别的指令没有意义）
            .sheet(isPresented: stageBinding(.temp)) {
                ACStepperView(initialTemp: $temp)
                    .onReceive(NotificationCenter.default.publisher(for: .tempConfirmed)) { note in
                        if let t = note.object as? Int { temp = t }
                        stage = .none
                        gate()
                    }
                    .dsSheetCanvas()
            }
            // ③ 控车码
            .sheet(isPresented: stageBinding(.pin)) {
                PINKeypadView()
                    .onReceive(NotificationCenter.default.publisher(for: .pinConfirmed)) { note in
                        guard let pin = note.object as? String else { return }
                        stage = .none
                        // #8 首次输入 PIN 后保存到 Keychain
                        if store.readPin() == nil {
                            store.savePin(pin)
                            EnhancedToastManager.shared.show("PIN码已安全保存", icon: "key.fill")
                        }
                        fire(pin: pin)
                    }
                    .dsSheetCanvas()
            }
            // ② 生物识别（#N13：敏感操作先验身份，过了再进控车码）
            .overlay {
                if stage == .biometric {
                    BiometricLockOverlay(isAuthenticated: $isAuthed)
                        .onAppear { isAuthed = false }
                        .onChange(of: isAuthed) { _, ok in
                            // 验证通过后进控车码（与验证前的 `gate()` 落点一致：
                            // 生物识别是**加**一道，不是替代控车码）
                            if ok { stage = .pin }
                        }
                }
            }
    }

    /// 一个阶段一个 sheet 开关。用 `stage` 当唯一真相，所以「关掉」与
    /// 「换到下一阶段」是同一件事，不会留下两个都为真的开关。
    private func stageBinding(_ s: ControlStage) -> Binding<Bool> {
        Binding(get: { stage == s },
                set: { if !$0 && stage == s { stage = .none } })
    }

    // MARK: 三步

    private func start(_ r: ControlRequest) {
        // 并发只允许一条指令（`CommandCenter.send` 还会再挡一次 —— 那道闸是给
        // 别的发起处用的：摇一摇锁车、Siri 快捷方式都直接进中心）
        guard !commands.busy, commands.running == nil else { return }
        guard !store.carId.isEmpty else {
            EnhancedToastManager.shared.show("请先选择车辆", icon: "car.fill")
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
        // 温度只对空调有意义；不发空调时传 17，与 API 的默认值一致。
        commands.send(cmd: p.key,
                      temperature: p.key == "OpenAir" ? temp : 17,
                      pin: pin,
                      displayName: p.name)
        pending = nil
        request = nil
    }
}

extension View {
    /// 挂上「温度 → 生物识别 → 控车码 → 下发」这条唯一的门。
    ///
    /// 两处挂它：车控档（`ControlView`）与地图右臂的快捷车控（`MapSpineView`）。
    /// 加第三个发起处时**也挂它** —— 不要另写一遍验证，那正是这一版要修掉的东西。
    func controlCommandFlow(_ request: Binding<ControlRequest?>) -> some View {
        modifier(ControlCommandFlow(request: request))
    }
}
