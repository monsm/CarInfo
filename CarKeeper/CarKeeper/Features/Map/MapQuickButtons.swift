import SwiftUI
import MapKit

extension MapSpineView {

    static let quickColumnHeight: CGFloat =
        3 * TokensSize.tap + 2 * TokensSpacing.snug

    @MainActor
    func followsDrawer(_ d: MapSpineData, top: Anchor<CGRect>?) -> some View {
        GeometryReader { proxy in
            let raw = top.map { max(0, proxy.size.height - proxy[$0].minY + TokensSpacing.snug) } ?? 0
            let below = (raw / 2).rounded() * 2
            let ceiling = max(0, proxy.size.height - Self.quickColumnHeight)
            quickMapButtons(d)
                .frame(maxWidth: .infinity, maxHeight: .infinity,
                       alignment: top == nil ? .topTrailing : .bottomTrailing)
                .padding(.top, top == nil ? TokensSpacing.xxxl : 0)
                .padding(.bottom, min(below, ceiling))
        }
    }

    @MainActor
    func quickMapButtons(_ d: MapSpineData) -> some View {
        VStack(spacing: TokensSpacing.snug) {
            MapCompass(scope: mapScope)
                .frame(width: TokensSize.tap, height: TokensSize.tap)

            Button {
                TokensHaptic.tap()
                recenterCar(d)
            } label: {
                quickIcon("car.fill", fallback: "car",
                          dimmed: d.carCoordinate == nil)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("回到车"))
            .accessibilityHint(Text("把地图移到车所在的位置"))

            Button {
                TokensHaptic.tap()
                moveCameraToPhone()
            } label: {
                quickIcon(phoneSymbol, fallback: "location", dimmed: false)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("手机的位置"))
            .accessibilityHint(Text(phoneHint))
        }
        .padding(.trailing, TokensSpacing.md)
        .dsGlassLayer(spacing: TokensSpacing.snug)
    }


    @MainActor
    private func quickIcon(_ symbol: String, fallback: String,
                           dimmed: Bool) -> some View {
        Image(safeSymbol: symbol, fallback: fallback)
            .font(TokensTypo.fixed(17, weight: .semibold))
            .foregroundStyle(dimmed ? TokensInk.tertiary : TokensInk.primary)
            .frame(width: TokensSize.tap, height: TokensSize.tap)
            .dsGlass(in: Circle(), interactive: true)
            .contentShape(Circle())
    }

    private var phoneSymbol: String {
        switch PhoneLocation.shared.status {
        case .found, .coarse: return "location.fill"
        case .denied, .failed: return "location.slash"
        case .idle, .asking, .locating: return "location"
        }
    }

    private var phoneHint: String {
        switch PhoneLocation.shared.status {
        case .idle: return "把地图移到手机所在的位置（第一次会问权限）"
        case .asking: return "正在等定位权限"
        case .locating: return "正在取手机的位置（尽量取准的那一个）"
        case .found: return "再按一次：重新取手机的位置"
        case .coarse: return "只拿到粗定位：蓝点外面那圈就是误差范围"
        case .denied: return "定位权限没开 —— 去系统设置里允许这个 App 使用位置"
        case .failed: return "取不到手机的位置（室内或没有信号时常见）"
        }
    }


    @MainActor
    func recenterCar(_ d: MapSpineData) {
        guard d.carCoordinate != nil else {
            ToastManager.shared.show("还没收到车的位置", icon: "car")
            return
        }
        follow = .car
        centerOnCar(force: true)
    }

    @MainActor
    func moveCameraToPhone() {
        let phone = PhoneLocation.shared
        switch phone.status {
        case .denied:
            ToastManager.shared.show("定位权限没开，去「设置 → 隐私」里允许", icon: "location.slash")
        case .failed:
            ToastManager.shared.show("取不到手机的位置", icon: "location.slash")
        case .idle, .asking, .locating:
            phone.request()
        case .coarse:
            follow = .phone
            phone.request()
            fly(to: phone.mapCoordinate)
            ToastManager.shared.show("位置精度较低，正在再取一次", icon: "location")
        case .found:
            follow = .phone
            phone.request()
            fly(to: phone.mapCoordinate)
        }
    }

    @MainActor
    func fly(to coordinate: CLLocationCoordinate2D?) {
        guard let pos = MapCameraFollow.camera(on: coordinate, heading: 0,
                                               distance: cameraDistance,
                                               pitch: cameraPitch) else { return }
        withAnimation(TokensMotion.value) { camera = pos }
    }

    @MapContentBuilder
    func phonePin() -> some MapContent {
        if let c = PhoneLocation.shared.mapCoordinate {
            if let acc = PhoneLocation.shared.accuracy, acc > 20 {
                MapCircle(center: c, radius: acc)
                    .foregroundStyle(TokensPalette.info.opacity(0.16))
                    .stroke(TokensPalette.info.opacity(0.40), lineWidth: 1)
            }
            Annotation("我的位置", coordinate: c) {
                Circle()
                    .fill(TokensPalette.info)
                    .frame(width: TokensSpacing.md, height: TokensSpacing.md)
                    .overlay {
                        Circle().strokeBorder(TokensPalette.canvas.opacity(0.9),
                                              lineWidth: TokensHair.border * 3)
                    }
                    .shadow(color: TokensPalette.scrim.opacity(0.25), radius: 3, y: 1)
            }
        }
    }
}
