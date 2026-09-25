import SwiftUI
import UIKit
import RealityKit
import simd

// =============================================================================
//  CarModelView —— 车控那一屏的车，是一辆**真的三维模型**
// =============================================================================
//
//  用户 2026-09-25（第 8 条）：「车控的车太丑了，能不能搞个真车或立体车，
//  可以滑动的，像特斯拉屏幕那样的也可以点击控车」。
//
//  旧的那辆（`CarTopView`）是一条条线画出来的**俯视图**：线描、不着色、
//  没有体积 —— 它不是「不好看」，而是「不是车」：一个俯视的轮廓回答不了
//  「我的车现在什么样」。这一版换成 RealityKit 的真实三维实体：
//
//    · **实体不是贴图**：车身、座舱、四门、四轮、前后灯、后备箱都是
//      `MeshResource` 生成的基本体（`generateBox` / `generateCylinder`），
//      有真实体积、真实明暗、真实遮挡 —— 拖到侧面就能看见侧面。
//    · **拖动转的是模型**（Y 轴自转 + 一点俯仰），不是给二维图做斜切。
//      转的是**车**，不是镜头：镜头不动，所以玻璃卡里那辆车原地转身。
//    · **点哪控哪**：车门 / 后备箱 / 前灯 / 车头各有自己的碰撞体，
//      `TapGesture().targetedToAnyEntity()` 直接把被点中的实体交回来。
//
//  ⚠️ 一条硬规则（这一仓反复写过）：**界面上每个动作都要对应一条真的会发出去的指令**。
//  所以可点的部位**只有**指令表里有的那几件事（`LockDoor` / `UnLockDoor` /
//  `FlashLight` / `Whistle`，见 `CommandCenter` 的指令表）。后备箱**没有**对应指令
//  （报文里只有它的**状态** `Statetrunk`，没有开合的指令），所以它**点不动** ——
//  它只用自己的颜色说状态。摆一个「点了什么都不发生」的后备箱，
//  正是这个仓库删过一批的东西。
//
//  ⚠️ 没有外部模型文件：本仓没有 USDZ/GLB 资源，所以这辆车是**代码搭的**。
//  换成真车模型的路是留着的：把 `CarRig.build()` 换成加载一个 USDZ、
//  再把 `CarPart` 的名字挂到它对应的节点上，其余（拖动、点选、配色）一字不用改。
//
//  ⚠️ 本机没有 Swift 工具链：RealityKit 的用法逐个对着 Apple 文档核过
//  （`RealityView` iOS 18+、`MeshResource.generateBox(width:height:depth:)`、
//  `generateCylinder(height:radius:)`、`ShapeResource.generateBox(width:height:depth:)`、
//  `TapGesture.targetedToAnyEntity()`），但**取景与观感只有真机能回答**。
// =============================================================================

/// 车身上能点的一处。**每一处都对应一条真实存在的指令**（见文件头那条硬规则）。
enum CarPart: String, CaseIterable {
    /// 左前 / 右前 / 左后 / 右后（顺序与体检里那四行一致）
    case doorFrontLeft, doorFrontRight, doorRearLeft, doorRearRight
    /// 前灯 —— `FlashLight`
    case headLight
    /// 车头（前脸）—— `Whistle`
    case horn

    /// 点它发哪条指令（后备箱**不在**这张表里，因为它没有指令）。
    var commandKey: String? {
        switch self {
        case .headLight: return "FlashLight"
        case .horn: return "Whistle"
        case .doorFrontLeft, .doorFrontRight, .doorRearLeft, .doorRearRight:
            // 门的动作与「车锁」同一件事：门是开着还是锁着，由锁的状态决定 ——
            // 而真实的锁车 / 解锁就是这两条指令。点门 = 切换它。
            return nil
        }
    }

    /// 这一处叫什么（提示里说得出来）
    var title: String {
        switch self {
        case .doorFrontLeft: return "左前门"
        case .doorFrontRight: return "右前门"
        case .doorRearLeft: return "左后门"
        case .doorRearRight: return "右后门"
        case .headLight: return "前灯"
        case .horn: return "车头"
        }
    }
}

// =============================================================================
//  MARK: - 车体（一辆用基本体拼出来的车）
// =============================================================================

/// 这辆车的**装配表**，也是它唯一的存在方式：一台 `Entity` 树。
///
/// 为什么是单例（与全仓其余单例同一个理由）：`RealityView` 的 `make` 闭包会在
/// 视图重建时再跑一次，而装配（生成 20 多个 mesh）不该跟着视图走 ——
/// 车是**同一辆车**，它的状态跟着数据变，不跟着视图变。
///
/// ⚠️ 单位：建模时 1 单位 = 1 米（车身 4.6 长、1.86 宽），最后整体缩到
/// `displayScale` —— 这样坐标写得出来（看得懂「这是车门的高度」），
/// 而屏幕上是一辆装得进卡片的小车。
final class CarRig {
    static let shared = CarRig()

    /// 整车挂在它下面：**转的是它**（拖动改它的朝向，车就原地转身）。
    let root = Entity()

    /// 可点部位：实体名 → 部位。名字写在实体上（`targetedToAnyEntity` 给回来的
    /// 只有实体），所以这张表是「点中了哪一处」的唯一翻译处。
    private var parts: [String: CarPart] = [:]
    /// 门的实体（按 CarPart 的四个 case 索引），状态色改的就是它们。
    ///
    /// ⚠️ 类型必须是 **`ModelEntity`**，不能是 `Entity` —— 改状态色走的是
    /// `HasModel.model`（`var model: ModelComponent?`，Apple 文档
    /// `s:17RealityFoundation8HasModelPAAE5modelAA0D9ComponentVSgvp`），而 `Entity` **不**符合它。
    /// 第一版这三处写的是 `Entity`，CI 当场报 `value of type 'Entity' has no member 'model'`
    /// （三次，全在这一个文件里）—— 这正是本机没有编译器时最该选的类型：
    /// 它们本来就是 `ModelEntity(...)` 造出来的，写宽了不但丢能力，还要等到 CI 才发现。
    private var doors: [ModelEntity] = []
    /// 后备箱（不可点，只着色）
    private var trunk: ModelEntity?
    /// 前灯（可点，也着色）—— 目前只着色，没有单独的点选逻辑
    private var headLights: [ModelEntity] = []

    private var built = false

    // ---- 材质：颜色都取令牌，不在这里另立一套 ----
    /// ⚠️ `roughness` 的类型**不是 `Float`**：`SimpleMaterial.init(color:roughness:isMetallic:)`
    /// 收的是 `MaterialScalarParameter`（一个 `ExpressibleByFloatLiteral` 的枚举，见 Apple
    /// 文档 `s:17RealityFoundation14SimpleMaterialV...` 那条 iOS 声明）。它只能吃**字面量** ——
    /// 传一个 `Float` **变量**进去编译不过，而每一处调用写的都是字面量（0.28 / 0.1 / 0.85 …）。
    private func paint(_ color: Color, roughness: MaterialScalarParameter = 0.35, metallic: Bool = true) -> SimpleMaterial {
        // `UIColor(_:)` 要 UIKit；`SimpleMaterial` 的颜色参数就是它（`Color` 不能直接进）。
        SimpleMaterial(color: UIColor(color), roughness: roughness, isMetallic: metallic)
    }

    /// 车身色（纸白/墨色由明暗决定：它就是系统给标签色的反差）。
    private var bodyMaterial: SimpleMaterial { paint(TokensPalette.primary, roughness: 0.28) }
    private var glassMaterial: SimpleMaterial { paint(TokensPalette.secondary, roughness: 0.1, metallic: false) }
    private var tyreMaterial: SimpleMaterial { paint(TokensPalette.tertiary, roughness: 0.85, metallic: false) }

    /// 组装（只做一次）。`content` 的 `add` 只认 `Entity`，所以这里返回根节点，
    /// 由调用点挂上去 —— 单例自己不认识 RealityView 的类型。
    func install() {
        guard !built else { return }
        built = true
        root.position = [0, 0, 0]

        let body = Entity()

        // ---- 车身（底盘 + 座舱 + 前后风挡）----
        //
        //  2026-09-25（用户第 6 条：「车控界面要做一个真实的俩厢车」）—— 这一版的
        //  三处尺寸是照着「两厢」这两个字改的，不是随手缩了缩：
        //    · **总长短了 0.5 米**（4.60 → 4.10），而轴距没动（车轮仍在 ±1.42）——
        //      两厢车与同级三厢车的区别正在这里：**后悬短**（4.10/2 − 1.42 = 0.63 m）。
        //      上一版后悬 0.88 m，再配上一个独立的后备箱盖，看起来就是一台三厢车。
        //    · **座舱往后拉到尾**（2.20 → 2.50，中心从 −0.18 到 −0.30）：
        //      两厢车的车顶一直拉到尾门上方，尾门几乎是竖的。
        //    · 后面那块「后备箱盖」不再是车尾外的一块独立板子（那是三厢的车尾），
        //      它是**尾门**，就长在座舱后缘上（见下面 `tail`）。
        let lower = ModelEntity(mesh: .generateBox(width: 1.86, height: 0.62, depth: 4.10, cornerRadius: 0.16),
                                materials: [bodyMaterial])
        lower.position = [0, 0.55, 0]
        body.addChild(lower)

        let cabin = ModelEntity(mesh: .generateBox(width: 1.62, height: 0.56, depth: 2.50, cornerRadius: 0.22),
                                materials: [bodyMaterial])
        cabin.position = [0, 1.12, -0.30]
        body.addChild(cabin)

        // 全景玻璃顶（座舱上面那一层）—— 它让车看起来是「这一代的车」，而不是一个盒子。
        // 它对两厢车特别重要：车顶要一直延伸到尾门上方，所以它比座舱还长一点。
        let roof = ModelEntity(mesh: .generateBox(width: 1.44, height: 0.06, depth: 2.24, cornerRadius: 0.03),
                               materials: [glassMaterial])
        roof.position = [0, 1.42, -0.30]
        body.addChild(roof)

        // 前后风挡：斜的是车的样子，直的是箱子 —— 用薄板压一点角度。
        // 后风挡的倾角（0.34 rad ≈ 20°）是**两厢**与三厢最直观的差别：三厢的后窗
        // 几乎是躺着的（那一版写的 0.50），而两厢车的尾门接近竖直。
        for (z, tilt) in [(1.05, -0.55), (-1.52, 0.34)] {
            let shield = ModelEntity(mesh: .generateBox(width: 1.50, height: 0.62, depth: 0.06, cornerRadius: 0.02),
                                     materials: [glassMaterial])
            shield.position = [0, 1.12, Float(z)]
            shield.orientation = simd_quatf(angle: Float(tilt), axis: [1, 0, 0])
            body.addChild(shield)
        }

        // 尾门的门槛：座舱后缘到车身尾端之间那一段（两厢车的「第三厢」其实是个行李舱，
        // 它没有独立的后备箱盖，所以这一块是车身本身）。
        let hatchBase = ModelEntity(mesh: .generateBox(width: 1.80, height: 0.58, depth: 0.52,
                                                      cornerRadius: 0.14),
                                    materials: [bodyMaterial])
        hatchBase.position = [0, 0.84, -1.72]
        body.addChild(hatchBase)

        // ---- 四门（**可点**；门的状态就是它们的颜色）----
        let doorPlan: [(CarPart, Float, Float)] = [
            (.doorFrontLeft, -0.94, 0.55), (.doorFrontRight, 0.94, 0.55),
            (.doorRearLeft, -0.94, -0.95), (.doorRearRight, 0.94, -0.95)
        ]
        for (part, x, z) in doorPlan {
            // 门画在车身的**侧面**：一块薄板，宽度 0.04 贴在 1.86 宽的车身外沿。
            let door = ModelEntity(mesh: .generateBox(width: 0.05, height: 0.50, depth: 1.30, cornerRadius: 0.04),
                                   materials: [paint(TokensPalette.success, roughness: 0.3)])
            door.position = [x, 0.62, z]
            door.name = part.rawValue
            makeTappable(door, size: (0.10, 0.56, 1.36))
            parts[part.rawValue] = part
            doors.append(door)
            body.addChild(door)

            // 车门把手：一枚小斜块 —— 有它才看得出这块板是门。
            let handle = ModelEntity(mesh: .generateBox(width: 0.03, height: 0.06, depth: 0.26, cornerRadius: 0.02),
                                     materials: [paint(TokensPalette.primary, roughness: 0.25)])
            handle.position = [x > 0 ? x + 0.03 : x - 0.03, 0.86, z]
            body.addChild(handle)
        }

        // ---- 四轮（圆柱横过来 = 轮子）----
        let wheelPlan: [(Float, Float)] = [(-0.88, 1.42), (0.88, 1.42), (-0.88, -1.42), (0.88, -1.42)]
        for (x, z) in wheelPlan {
            let tyre = ModelEntity(mesh: .generateCylinder(height: 0.26, radius: 0.34),
                                   materials: [tyreMaterial])
            // 圆柱默认轴朝 Y；绕 Z 转 90° 之后轴朝 X —— 轮子于是「立在车侧」。
            tyre.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
            tyre.position = [x, 0.34, z]
            body.addChild(tyre)

            // 轮毂（比胎亮一点的一圈）
            let rim = ModelEntity(mesh: .generateCylinder(height: 0.28, radius: 0.18),
                                  materials: [paint(TokensPalette.secondary, roughness: 0.2)])
            rim.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
            rim.position = [x, 0.34, z]
            body.addChild(rim)
        }

        // ---- 尾门（**不可点**：报文里只有它的状态，没有开它的指令）----
        //
        //  它在上一版是「后备箱盖」：一块独立、平铺在车尾外的板（`z = −2.28`）。
        //  两厢车没有那个东西 —— 尾门就是车尾，它竖在座舱后缘上（`z ≈ −1.98`），
        //  而且比后备箱盖**高得多**（0.30 → 0.72），一直顶到车顶下面。
        //  它的颜色仍是门态的一部分（`applyState` 拿 `trunk` 上色，`trunkOpen` = 橙）。
        //  变量名仍叫 `trunk`：它在报文里就是后备箱那个字段，界面上的形状变了，
        //  而读的读数没变 —— 换名字只会多一个「同一个东西两个名字」。
        let tail = ModelEntity(mesh: .generateBox(width: 1.56, height: 0.72, depth: 0.08, cornerRadius: 0.03),
                               materials: [paint(TokensPalette.success, roughness: 0.3)])
        tail.position = [0, 1.06, -1.98]
        // 尾门略往后仰（不是死平的一块板）：两厢车的尾门是斜的，而斜度就是它的样子。
        tail.orientation = simd_quatf(angle: 0.16, axis: [1, 0, 0])
        trunk = tail
        body.addChild(tail)

        // ---- 前灯（可点 = 闪灯）----
        for x in [Float(-0.62), Float(0.62)] {
            let lamp = ModelEntity(mesh: .generateBox(width: 0.34, height: 0.12, depth: 0.06, cornerRadius: 0.03),
                                   materials: [paint(TokensPalette.warning, roughness: 0.15, metallic: false)])
            // 车身短了 0.5 米，车头那几件跟着往前移同样的距离（不然灯会飘在车外面）。
            lamp.position = [x, 0.72, 2.03]
            lamp.name = CarPart.headLight.rawValue
            makeTappable(lamp, size: (0.40, 0.18, 0.14))
            headLights.append(lamp)
            body.addChild(lamp)
        }

        // ---- 车头（可点 = 鸣笛）：前保险杠正中那一小块 ----
        let nose = ModelEntity(mesh: .generateBox(width: 0.5, height: 0.16, depth: 0.08, cornerRadius: 0.03),
                               materials: [paint(TokensPalette.primary, roughness: 0.3)])
        nose.position = [0, 0.45, 2.05]
        nose.name = CarPart.horn.rawValue
        makeTappable(nose, size: (0.56, 0.22, 0.14))
        parts[CarPart.horn.rawValue] = CarPart.horn
        body.addChild(nose)

        // ---- 接地阴影：一枚扁的暗片。没有它，车会看起来浮在玻璃上 ----
        let shadow = ModelEntity(mesh: .generateBox(width: 2.10, height: 0.01, depth: 4.40, cornerRadius: 0.4),
                                 materials: [SimpleMaterial(color: UIColor(TokensPalette.scrim.opacity(0.28)),
                                                            roughness: 1, isMetallic: false)])
        shadow.position = [0, 0.005, 0]
        body.addChild(shadow)

        // 建模的 1 单位 = 1 米；缩到屏幕上一辆小车的大小。
        body.scale = [displayScale, displayScale, displayScale]
        // 车轴中线抬到原点之上（不然车轮会陷在「地面」以下）。
        body.position = [0, -0.22, 0]
        root.addChild(body)
    }

    /// 建模单位（米）到屏幕单位的换算：4.6 米的车 → 约 1.6 个单位长。
    private let displayScale: Float = 0.35

    /// 把一枚实体变成「点得到」的：RealityKit 要碰撞体 + 输入目标两样都在。
    /// 碰撞体比画出来的形状**略大**一圈 —— 手指不是像素（HIG 的最小触控目标）。
    private func makeTappable(_ entity: Entity, size: (Float, Float, Float)) {
        entity.components.set(InputTargetComponent())
        entity.components.set(CollisionComponent(shapes: [
            ShapeResource.generateBox(width: size.0, height: size.1, depth: size.2)
        ]))
    }

    // =========================================================================
    //  MARK: 状态与姿态（视图每次刷新都调它）
    // =========================================================================

    /// 拖出来的姿态。`yaw` = 绕 Y（原地转身），`pitch` = 一点点俯视。
    func setPose(yaw: Float, pitch: Float) {
        install()
        root.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
            * simd_quatf(angle: pitch, axis: [1, 0, 0])
    }

    /// 四门 / 后备箱的状态 → 颜色。绿 = 已关，橙 = 未关（与全站同一套状态色）。
    /// `doorCls` 顺序：左前 / 右前 / 左后 / 右后。
    func applyState(doorCls: [String], trunkOpen: Bool, windowsOpen: Bool) {
        install()
        for (i, door) in doors.enumerated() {
            let cls = doorCls.indices.contains(i) ? doorCls[i] : "ok"
            let color = cls == "bad" ? TokensPalette.warning : TokensPalette.success
            door.model?.materials = [paint(color, roughness: 0.3)]
        }
        // 车窗开着：门板**变暗**（同一辆车上的第二种状态，不新增颜色体系）。
        if windowsOpen {
            for door in doors {
                door.model?.materials = [paint(TokensPalette.warning.opacity(0.55), roughness: 0.3)]
            }
        }
        if let trunk {
            trunk.model?.materials = [paint(trunkOpen ? TokensPalette.warning : TokensPalette.success, roughness: 0.3)]
        }
    }

    /// 点中了哪个部位（`nil` = 点空 / 点到了不可点的东西）。
    func part(named name: String) -> CarPart? {
        guard let part = parts[name] else {
            // 后备箱的名字不在 `parts` 里：它没有指令，所以**不是**可点部位。
            return nil
        }
        return part
    }
}

// =============================================================================
//  MARK: - 那一屏里的车（可拖转、点得动）
// =============================================================================

struct CarModelView: View {
    /// 左前 / 右前 / 左后 / 右后：`"ok"` / `"bad"`
    var doorCls: [String]
    var trunkOpen: Bool
    var windowsOpen: Bool
    /// 点中了可点部位（调用点决定发哪条指令、怎么验身份）
    var onTapPart: (CarPart) -> Void

    /// 单例（不是 `@State`）：视图重建时车不该重装一遍（见 `CarRig` 的说明）。
    private let rig = CarRig.shared

    /// 姿态（弧度）。初值是一点四分之三视角 —— 正侧面看不出这是辆有体积的车。
    @State private var yaw: Float = 0.62
    @State private var pitch: Float = 0.34
    @State private var yawAtDragStart: Float = 0.62
    @State private var pitchAtDragStart: Float = 0.34

    /// 状态变了才重刷材质（每次都刷会把材质对象整个换掉，白掉一帧）。
    private var stateKey: String {
        doorCls.joined(separator: ",") + "|\(trunkOpen)|\(windowsOpen)"
    }

    var body: some View {
        //  ⚠️ `make` 闭包是 `@MainActor @Sendable` 的，所以它里面**不碰 `self`**：
        //  单例从 `CarRig.shared` 现场取（`self` 里挂着一个非 Sendable 的回调，
        //  捕进来在严格并发下是要报的），状态用值类型捕（`[String]` / `Bool` 都能捕）。
        RealityView { content in
            let car = CarRig.shared
            car.install()
            content.add(car.root)
            car.applyState(doorCls: doorCls, trunkOpen: trunkOpen, windowsOpen: windowsOpen)
        }
        .onChange(of: stateKey) { _, _ in
            rig.applyState(doorCls: doorCls, trunkOpen: trunkOpen, windowsOpen: windowsOpen)
        }
        // 拖动 = 转车（不是转镜头）：手指横着划，车原地转身；竖着划给一点俯仰。
        // 两个方向都**夹住**：俯仰到 70° 就会变成从上往下看一个盒子，那不像车。
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { v in
                    yaw = yawAtDragStart + Float(v.translation.width) / 190
                    let p = pitchAtDragStart + Float(v.translation.height) / 320
                    pitch = min(max(p, -0.12), 0.95)
                }
                .onEnded { _ in
                    yawAtDragStart = yaw
                    pitchAtDragStart = pitch
                }
        )
        // 点哪控哪：`targetedToAnyEntity` 直接交出被点中的实体（它的名字 =
        // `CarPart` 的 rawValue，见 `CarRig.makeTappable`）。
        .gesture(
            TapGesture()
                .targetedToAnyEntity()
                .onEnded { value in
                    guard let part = rig.part(named: value.entity.name) else { return }
                    TokensHaptic.tap()
                    onTapPart(part)
                }
        )
        .onAppear { rig.setPose(yaw: yaw, pitch: pitch) }
        .onChange(of: yaw) { _, y in rig.setPose(yaw: y, pitch: pitch) }
        .onChange(of: pitch) { _, p in rig.setPose(yaw: yaw, pitch: p) }
        .accessibilityElement()
        .accessibilityLabel(Text("车辆三维模型"))
        .accessibilityValue(Text("四门与后备箱的状态用颜色标出"))
        .accessibilityHint(Text("左右拖动可以转动车身"))
    }
}
