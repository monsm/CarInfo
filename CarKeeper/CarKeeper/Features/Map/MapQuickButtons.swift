import SwiftUI
import MapKit

// =============================================================================
//  MapSpineView · 地图右侧的两枚快速钮（回到车 / 手机的位置）
// =============================================================================
//
//  用户 2026-09-25：「地图页要像 ios 地图 app 右侧的图标一样加入快速回到车的位置
//  和手机的位置」。
//
//  两件事在这一轮之前分别是：
//    · 「回到车」在**图层菜单**里 —— 一个要打开才知道有的位置。它在 iOS 地图里
//      是一枚常驻的钮，因为它回答的是「我迷路了」时第一个问题：车在哪。
//      于是菜单里那一条删掉、这里留下（同一件事两个入口就是重复）。
//    · 「手机的位置」**根本不存在**：全仓没有任何 CoreLocation 代码，
//      地图上只有车（见 `Services/PhoneLocation.swift` 的文件头）。
//
//  观感照 iOS 地图右侧那一列：44×44 的圆钮（`TokensSize.tap` = HIG 最小触控目标），
//  竖着排成一条，间距 12，右边与卡同一条边距（`TokensSpacing.md`），
//  顶从安全区下 `TokensSpacing.xxxl` 起。
//
//  2026-09-25 第 9 条：这一列从**两枚**变成**三枚** —— 罗盘也搬进来了。
//  原来那个罗盘是系统的（`MapCompass`），它的位置由 MapKit 定（安全区紧下沿的角落），
//  搬不动 —— 而用户要它下来一点（「太上了」）。现在它是我们自己画的一枚：
//  一根指向正北的针（`Triangle`，与警示钉同一个形状原语）+ 点一下回正北。
//  它与另两枚同一行、同一种材质、同一个尺寸 —— 这才看起来是「同一列控件」。
//
//  材质：`.overMedia` —— 它们浮在**连续的画面**（地图瓦片）上，不是卡的面。
//  可点 → `interactive`：按下去的压缩与折射由系统演（`DSGlass.swift` 的三条规则）。
extension MapSpineView {

    /// 右侧那一列。锚在 `.topTrailing`（由调用点决定），本函数只管这两枚钮。
    /// `d` 是调用点手上那一份（跟 `nowCard(d)` / `readoutRow(_:)` 同一个写法）：
    /// 「有没有车的位置」决定第一枚钮亮不亮。
    @MainActor
    func quickMapButtons(_ d: MapSpineData) -> some View {
        // 两枚钮直接写在这里，不抽「一个带闭包参数的通用钮」：
        // 两者要的东西不同（一枚图形固定、另一枚的图形**就是它的状态**），
        // 而把动作当参数传会引入两层新东西 —— 闭包的 actor 归属与它的类型 ——
        // 换不来任何复用。
        VStack(spacing: TokensSpacing.snug) {
            compassButton

            Button {
                TokensHaptic.tap()
                recenterCar(d)
            } label: {
                // `dimmed` 不是「禁用」而是「这件事现在没有结果」—— 按下去仍然会
                // 给一句**说得出来**的话（见 `recenterCar`），而不是像上一轮删掉的
                // 那批按钮那样，按了什么都不发生。
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
        .padding(.top, TokensSpacing.xxxl)
    }

    /// 罗盘：一根**永远指向正北**的针 + 点一下回正北。
    ///
    /// 为什么不是 SF Symbol：`location.north.fill` 那一类符号是「箭头」，
    /// 而罗盘读的是**北在哪** —— 一根红针是全世界的地图 App 共用的一种画法，
    /// 而 `Triangle` 这个形状原语本仓已经有了（警示钉）。
    ///
    /// 针转的是 `-cameraHeading`：镜头朝哪，北就在相反的方向。
    /// 那个数只有 `onMapCameraChange` 说得出（见 `MapSpineView.cameraHeading`）。
    var compassButton: some View {
        Button {
            TokensHaptic.tap()
            resetNorth()
        } label: {
            ZStack {
                // 针：一半实一半虚 —— 地图上它是「北指向」，不是装饰。
                Triangle()
                    .fill(TokensPalette.error)
                    .frame(width: 11, height: 10)
                    .rotationEffect(.degrees(-cameraHeading))
                // 南针的半边也走 `TokensInk`（它坐在罗盘的玻璃上，见 `compassButton`）。
                Triangle()
                    .fill(TokensInk.secondary)
                    .frame(width: 11, height: 10)
                    .rotationEffect(.degrees(180 - cameraHeading))
                    .opacity(0.7)
            }
            .frame(width: TokensSize.tap, height: TokensSize.tap)
            .dsGlass(in: Circle(), variant: .overMedia, interactive: true)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("罗盘"))
        .accessibilityValue(Text(cameraHeading == 0 ? "已朝正北" : "北在 \(Int((360 - cameraHeading).rounded()) % 360) 度方向"))
        .accessibilityHint(Text("回到正北朝上"))
    }

    /// 回正北：**只把朝向归零**，中心与缩放照旧。
    ///
    /// `MapCamera` 要一个完整的镜头（中心 + 距离 + 朝向 + 俯仰），所以这三个数得从
    /// 手里有的地方来：中心取镜头自己的（拿不到就退回车），距离取**镜头此刻的**
    /// （写死 `cameraDistance` 会把用户缩放好的尺度一把推回默认 —— 那是另一种“"
    /// 点了什么都不对”）。
    @MainActor
    func resetNorth() {
        guard let c = cameraCenter ?? store.currentLocation?.coordinate else { return }
        withAnimation(TokensMotion.value) {
            camera = .camera(MapCamera(centerCoordinate: c,
                                       distance: cameraDistanceNow,
                                       heading: 0,
                                       pitch: 0))
        }
    }

    /// 一枚钮的图形：圆底玻璃 + 安全取符号。
    @MainActor
    private func quickIcon(_ symbol: String, fallback: String,
                           dimmed: Bool) -> some View {
        Image(safeSymbol: symbol, fallback: fallback)
            .font(TokensTypo.fixed(17, weight: .semibold))
            // 圆底是真玻璃、底下是**连续的画面**（地图瓦片）→ `TokensInk`：
            // 系统会按材质调它，固定标签色在瓦片上会糊掉（用户第 10 条）。
            .foregroundStyle(dimmed ? TokensInk.tertiary : TokensInk.primary)
            .frame(width: TokensSize.tap, height: TokensSize.tap)
            .dsGlass(in: Circle(), variant: .overMedia, interactive: true)
            .contentShape(Circle())
    }

    /// 手机位置那枚钮的图形：**它自己就是状态**。
    /// `location.fill` = 已经在用手机的位置；`location` = 还没开始 / 正在取；
    /// `location.slash` = 拿不到（被拒或取不到）—— iOS 地图也是这么表示的。
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

    // =========================================================================
    // MARK: 两个动作
    // =========================================================================

    /// 回到车。没有车的位置时**说出来**（这也是那枚钮变暗的理由）。
    @MainActor
    func recenterCar(_ d: MapSpineData) {
        guard d.carCoordinate != nil else {
            ToastManager.shared.show("还没收到车的位置", icon: "car")
            return
        }
        centerOnCar(force: true)
    }

    /// 手机的位置。三种情形分开：
    ///   · 还没权限 → 要权限（拿到点之后由地图页那条 `onChange` 把镜头移过去）
    ///   · 已经有点 → 直接移过去，并且**重新取一次**（用户可能已经开出去一段了）
    ///   · 拿不到 → 说清是哪一种（被拒 / 取不到），而不是让钮看起来没反应
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
            // 手上是个粗点：先移过去（总比没反应好），同时**再要一次** ——
            // 走两步常常就能拿到准的点。取到之后由那条 `onChange` 再移一次镜头。
            phone.request()
            fly(to: phone.coordinate)
            ToastManager.shared.show("位置精度较低，正在再取一次", icon: "location")
        case .found:
            phone.request()          // 重新取一次（它取到就停，所以这次是「刷新」）
            fly(to: phone.coordinate)
        }
    }

    /// 把镜头移到手机那里。**不跟**手机的方向 —— iOS 地图那枚钮在没有抬头时
    /// 是把镜头放过去（跟方向是另一次点按的事），这里只做前半件。
    ///
    /// **不是 `private`**：`MapSpineView` 的 `body` 里那条 `onChange`
    ///（手机位置取回来就移镜头）要调它 —— 与 `camera` / `cameraDistance` 那两处同一个理由：
    /// 一件事只有一处实现，跨文件时不复制第二份。
    @MainActor
    func fly(to coordinate: CLLocationCoordinate2D?) {
        guard let c = coordinate else { return }
        withAnimation(TokensMotion.value) {
            camera = .camera(MapCamera(centerCoordinate: c,
                                       distance: cameraDistance,
                                       heading: 0,
                                       pitch: 0))
        }
    }

    /// 手机自己在地图上的那一点（iOS 的蓝点：实心圆 + 一圈底色描边）。
    /// 只在真的拿到位置时出现 —— 不摆一个假点，坐标也不会是 (0,0)。
    @MapContentBuilder
    func phonePin() -> some MapContent {
        if let c = PhoneLocation.shared.coordinate {
            // 不确定范围：`horizontalAccuracy` 就是**半径**（CoreLocation 给的 95% 置信圆）。
            // iOS 地图的蓝点外面那圈淡圆就是它 —— 而它是用户第 9 条（「手机的位置飘逸
            // 很严重」）在界面上的答案：点到底准不准，图上自己说得出，不再偷偷地错。
            // 只画出「看得出来」的那个量级（>20 m），否则一圈比点还小的圆只是噪声。
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
