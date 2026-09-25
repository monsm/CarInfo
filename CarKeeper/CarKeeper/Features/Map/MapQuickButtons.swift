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
//  第 9 条那一轮以为「系统的 `MapCompass` 位置由 MapKit 定、搬不动」，于是自己画了一枚。
//  2026-09-25 **第十一轮把那个判断推翻了**（用户：「我要的是系统罗盘和系统比例尺，
//  只是他们被时间压住了，往下调整下」）：`MapCompass(scope:)` 可以当**独立视图**挂，
//  位置由这一列决定 —— 所以这一列的第一件就是系统罗盘本身（我们画的那一枚连同
//  `resetNorth` 一起删掉，它做的事系统那枚点一下也会做）。
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
            // 罗盘 = **系统的**那一枚（`MapCompass`，第十一轮）：位置由这一列给，
            // 不再是 MapKit 贴在状态栏里的那个角。
            // 固定一格尺寸：北朝上时系统那枚自己不画（Apple 的行为），
            // 留出这一格，下面两枚钮就不会随它上下跳。
            MapCompass(scope: mapScope)
                .frame(width: TokensSize.tap, height: TokensSize.tap)

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
        // 三枚钮是**挨着的三块玻璃**（间距就是那个 snug）—— 交给 `GlassEffectContainer`，
        // 它们的边缘才会互相折射、看起来是**同一层材质上的三个形状**，而不是三张各自
        // 画好再贴上去的圆片（见 `DSGlass.swift`）。地图那一屏的另一处（底条 + 两臂）
        // 早就是这么包的，这一列此前漏了。
        .dsGlassLayer(spacing: TokensSpacing.snug)
    }

    //  这里原本有 `compassButton`（自己画的一枚罗盘：`Triangle` 红针 + 点一下回正北）
    //  与它调用的 `resetNorth`（把镜头朝向归零、中心与缩放照旧）。
    //  **第十一轮一起删了**：系统那一枚（`MapCompass(scope:)`）点一下也会回正北，
    //  而它的朝向由它自己知道 —— 不必再让 `onMapCameraChange` 每帧喂一个数进来。
    //  形状原语 `Triangle` 没有跟着走：警示钉（`MapSpotPin.issuePin`）还在用它。

    /// 一枚钮的图形：圆底玻璃 + 安全取符号。
    @MainActor
    private func quickIcon(_ symbol: String, fallback: String,
                           dimmed: Bool) -> some View {
        Image(safeSymbol: symbol, fallback: fallback)
            .font(TokensTypo.fixed(17, weight: .semibold))
            // 圆底是真玻璃、底下是**连续的画面**（地图瓦片）→ `TokensInk`：
            // 系统会按材质调它，固定标签色在瓦片上会糊掉（用户第 10 条）。
            .foregroundStyle(dimmed ? TokensInk.tertiary : TokensInk.primary)
            // 符号外面一圈反色外发光（用户 2026-09-25 第 8 条）：
            // 这三枚钳底的是地图（`.clear`，不磨砂）—— 白色符号压在雪地/浅色楼盘上时
            // 就消失了一半。发光不改变符号色，只给它一个与底相反的轮廓。
            .dsInkGlow()
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
            fly(to: phone.mapCoordinate)
            ToastManager.shared.show("位置精度较低，正在再取一次", icon: "location")
        case .found:
            phone.request()          // 重新取一次（它取到就停，所以这次是「刷新」）
            fly(to: phone.mapCoordinate)
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
                                       // 与「回到车」同一个俯仰角（见 `cameraPitch`）——
                                       // 一次镜头移动不该把用户的视角从 3D 打回平面。
                                       pitch: cameraPitch))
        }
    }

    /// 手机自己在地图上的那一点（iOS 的蓝点：实心圆 + 一圈底色描边）。
    /// 只在真的拿到位置时出现 —— 不摆一个假点，坐标也不会是 (0,0)。
    @MapContentBuilder
    func phonePin() -> some MapContent {
        // `mapCoordinate` 而不是 `coordinate`：后者是 WGS-84 的原始读数，
        // 在中国区的地图上会偏 300–600 m（用户 2026-09-25：蓝点落在湖里）。
        if let c = PhoneLocation.shared.mapCoordinate {
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
