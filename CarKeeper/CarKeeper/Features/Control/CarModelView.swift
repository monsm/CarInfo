import SwiftUI
import UIKit
import RealityKit
import simd


enum CarPart: String, CaseIterable {
    case doorFrontLeft, doorFrontRight, doorRearLeft, doorRearRight
    case headLight
    case horn

    var commandKey: String? {
        switch self {
        case .headLight: return "FlashLight"
        case .horn: return "Whistle"
        case .doorFrontLeft, .doorFrontRight, .doorRearLeft, .doorRearRight:
            return nil
        }
    }

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


final class CarRig {
    static let shared = CarRig()

    let root = Entity()

    private var parts: [String: CarPart] = [:]
    private var doors: [ModelEntity] = []
    private var trunk: ModelEntity?
    private var headLights: [ModelEntity] = []

    private var built = false

    private func paint(_ color: Color, roughness: MaterialScalarParameter = 0.35,
                       metallic: Bool = true) -> SimpleMaterial {
        SimpleMaterial(color: UIColor(color), roughness: roughness, isMetallic: metallic)
    }

    private var bodyMaterial: SimpleMaterial { paint(TokensPalette.primary, roughness: 0.28) }
    private var glassMaterial: SimpleMaterial { paint(TokensPalette.secondary, roughness: 0.1, metallic: false) }
    private var tyreMaterial: SimpleMaterial { paint(TokensPalette.tertiary, roughness: 0.85, metallic: false) }

    func install() {
        guard !built else { return }
        built = true
        root.position = [0, 0, 0]

        let body = Entity()

        let lower = ModelEntity(mesh: .generateBox(width: 1.86, height: 0.62, depth: 4.10, cornerRadius: 0.16),
                                materials: [bodyMaterial])
        lower.position = [0, 0.55, 0]
        body.addChild(lower)

        let cabin = ModelEntity(mesh: .generateBox(width: 1.62, height: 0.56, depth: 2.50, cornerRadius: 0.22),
                                materials: [bodyMaterial])
        cabin.position = [0, 1.12, -0.30]
        body.addChild(cabin)

        let roof = ModelEntity(mesh: .generateBox(width: 1.44, height: 0.06, depth: 2.24, cornerRadius: 0.03),
                               materials: [glassMaterial])
        roof.position = [0, 1.42, -0.30]
        body.addChild(roof)

        for (z, tilt) in [(1.05, -0.55), (-1.52, 0.34)] {
            let shield = ModelEntity(mesh: .generateBox(width: 1.50, height: 0.62, depth: 0.06, cornerRadius: 0.02),
                                     materials: [glassMaterial])
            shield.position = [0, 1.12, Float(z)]
            shield.orientation = simd_quatf(angle: Float(tilt), axis: [1, 0, 0])
            body.addChild(shield)
        }

        let hatchBase = ModelEntity(mesh: .generateBox(width: 1.80, height: 0.58, depth: 0.52,
                                                      cornerRadius: 0.14),
                                    materials: [bodyMaterial])
        hatchBase.position = [0, 0.84, -1.72]
        body.addChild(hatchBase)

        let doorPlan: [(CarPart, Float, Float)] = [
            (.doorFrontLeft, -0.94, 0.55), (.doorFrontRight, 0.94, 0.55),
            (.doorRearLeft, -0.94, -0.95), (.doorRearRight, 0.94, -0.95)
        ]
        for (part, x, z) in doorPlan {
            let door = ModelEntity(mesh: .generateBox(width: 0.05, height: 0.50, depth: 1.30, cornerRadius: 0.04),
                                   materials: [paint(TokensPalette.success, roughness: 0.3)])
            door.position = [x, 0.62, z]
            door.name = part.rawValue
            makeTappable(door, size: (0.10, 0.56, 1.36))
            parts[part.rawValue] = part
            doors.append(door)
            body.addChild(door)

            let handle = ModelEntity(mesh: .generateBox(width: 0.03, height: 0.06, depth: 0.26, cornerRadius: 0.02),
                                     materials: [paint(TokensPalette.primary, roughness: 0.25)])
            handle.position = [x > 0 ? x + 0.03 : x - 0.03, 0.86, z]
            body.addChild(handle)
        }

        let wheelPlan: [(Float, Float)] = [(-0.88, 1.42), (0.88, 1.42), (-0.88, -1.42), (0.88, -1.42)]
        for (x, z) in wheelPlan {
            let tyre = ModelEntity(mesh: .generateCylinder(height: 0.26, radius: 0.34),
                                   materials: [tyreMaterial])
            tyre.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
            tyre.position = [x, 0.34, z]
            body.addChild(tyre)

            let rim = ModelEntity(mesh: .generateCylinder(height: 0.28, radius: 0.18),
                                  materials: [paint(TokensPalette.secondary, roughness: 0.2)])
            rim.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
            rim.position = [x, 0.34, z]
            body.addChild(rim)
        }

        let tail = ModelEntity(mesh: .generateBox(width: 1.56, height: 0.72, depth: 0.08, cornerRadius: 0.03),
                               materials: [paint(TokensPalette.success, roughness: 0.3)])
        tail.position = [0, 1.06, -1.98]
        tail.orientation = simd_quatf(angle: 0.16, axis: [1, 0, 0])
        trunk = tail
        body.addChild(tail)

        for x in [Float(-0.62), Float(0.62)] {
            let lamp = ModelEntity(mesh: .generateBox(width: 0.34, height: 0.12, depth: 0.06, cornerRadius: 0.03),
                                   materials: [paint(TokensPalette.warning, roughness: 0.15, metallic: false)])
            lamp.position = [x, 0.72, 2.03]
            lamp.name = CarPart.headLight.rawValue
            makeTappable(lamp, size: (0.40, 0.18, 0.14))
            headLights.append(lamp)
            body.addChild(lamp)
        }

        let nose = ModelEntity(mesh: .generateBox(width: 0.5, height: 0.16, depth: 0.08, cornerRadius: 0.03),
                               materials: [paint(TokensPalette.primary, roughness: 0.3)])
        nose.position = [0, 0.45, 2.05]
        nose.name = CarPart.horn.rawValue
        makeTappable(nose, size: (0.56, 0.22, 0.14))
        parts[CarPart.horn.rawValue] = CarPart.horn
        body.addChild(nose)

        let shadow = ModelEntity(mesh: .generateBox(width: 2.10, height: 0.01, depth: 4.40, cornerRadius: 0.4),
                                 materials: [SimpleMaterial(color: UIColor(TokensPalette.scrim.opacity(0.28)),
                                                            roughness: 1, isMetallic: false)])
        shadow.position = [0, 0.005, 0]
        body.addChild(shadow)

        body.scale = [displayScale, displayScale, displayScale]
        body.position = [0, -0.22, 0]
        root.addChild(body)
    }

    private let displayScale: Float = 0.35

    private func makeTappable(_ entity: Entity, size: (Float, Float, Float)) {
        entity.components.set(InputTargetComponent())
        entity.components.set(CollisionComponent(shapes: [
            ShapeResource.generateBox(width: size.0, height: size.1, depth: size.2)
        ]))
    }


    func setPose(yaw: Float, pitch: Float) {
        install()
        root.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
            * simd_quatf(angle: pitch, axis: [1, 0, 0])
    }

    func applyState(doorCls: [String], trunkOpen: Bool, windowsOpen: Bool) {
        install()
        for (i, door) in doors.enumerated() {
            let cls = doorCls.indices.contains(i) ? doorCls[i] : "ok"
            let color = cls == "bad" ? TokensPalette.warning : TokensPalette.success
            door.model?.materials = [paint(color, roughness: 0.3)]
        }
        if windowsOpen {
            for door in doors {
                door.model?.materials = [paint(TokensPalette.warning.opacity(0.55), roughness: 0.3)]
            }
        }
        if let trunk {
            trunk.model?.materials = [paint(trunkOpen ? TokensPalette.warning : TokensPalette.success, roughness: 0.3)]
        }
    }

    func part(named name: String) -> CarPart? {
        guard let part = parts[name] else {
            return nil
        }
        return part
    }
}


struct CarModelView: View {
    var doorCls: [String]
    var trunkOpen: Bool
    var windowsOpen: Bool
    var onTapPart: (CarPart) -> Void

    private let rig = CarRig.shared

    @State private var yaw: Float = 0.62
    @State private var pitch: Float = 0.34
    @State private var yawAtDragStart: Float = 0.62
    @State private var pitchAtDragStart: Float = 0.34

    private var stateKey: String {
        doorCls.joined(separator: ",") + "|\(trunkOpen)|\(windowsOpen)"
    }

    var body: some View {
        RealityView { content in
            let car = CarRig.shared
            car.install()
            content.add(car.root)
            car.applyState(doorCls: doorCls, trunkOpen: trunkOpen, windowsOpen: windowsOpen)
        }
        .onChange(of: stateKey) { _, _ in
            rig.applyState(doorCls: doorCls, trunkOpen: trunkOpen, windowsOpen: windowsOpen)
        }
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
