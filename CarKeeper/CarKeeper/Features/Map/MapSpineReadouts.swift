import SwiftUI
import MapKit
import CoreLocation

// =============================================================================
//  MapSpineView · 「现在」这一档里的读数，以及地图上那两个数
//（收起时那一横：续航 / 电量 / 车速；拉出来：其余读数；外加比例尺）
// =============================================================================
//
//  与 `MapSpineLayers.swift` 同一个理由 —— 关切不同：`MapSpineView` 管这一屏的
//  骨架（六页同屏、底条、镜头、图层、手势），这里只回答一件事：
//  「一瞥的那几个数从哪来、取不到时写什么、其余的怎么让人看到」，
//  外加「比例尺那个数从哪来」—— 它也是地图上的一个数。
//
//  另一条理由更实际：`scan/lintcfg.py` 的 `file_length` 盯着最大那个文件。
//  2026-09-24 骨架那一份涨到 1206 行（阈值 1200），差 6 行就红。
//  不选「把阈值抬到刚够」：贴着阈值的代价是下一次**任何**小改动都要先做一遍取舍，
//  而 `MapSpineLayers.swift` 的头注里已经写过一次这个账。
//
//  注：下面用到的 `store` / `layerMenu` / `drawerOpen` / `toggleDrawer` / `setDrawer`
//  因此**不是 `private`** ——
//  `private` 的作用域是文件，跨文件看不见。它们在骨架里的注释写明了为什么。
//
//  ===========================================================================
//  「其余读数」这一格的三代写法（用户三次提同一件事，每次的答复都不一样）
//  ===========================================================================
//
//   ① 一版：卡里自己拉的一道抽屉 —— 一枚自画的拉手 + `drawerReveal` 连续量
//      + 自算的两个落点 + 把内容藏起来量自然高度（`drawerMeasure`）。三个状态。
//      删掉的理由：**每一条都在重做系统已经做好的事，而且做得少**（落点少一个、
//      没有橡皮筋、没有下拉关闭、没有 VoiceOver 的收起/展开）。
//   ② 二版：换成**系统的 sheet**（用户在我列的候选里选了「系统 sheet + `detents`」）。
//      删掉的理由：系统 sheet 永远是**屏幕底部**的一张新面 —— 它会盖住模式条
//      （全站唯一的入口），而卡片浮在模式条**上面**；于是「拉开的抽屉」与
//      「卡片自己」成了两处内容，用户看到的仍不是他要的那张图。
//   ③ 现在（用户 2026-09-25 第 2 条：「下面的卡片不是抽屉样，不是我发的图片的参考，
//      我再发一次，默认只显示一横，拉出来才是全部」）：**抽屉就是这张卡**。
//      收起 = 一枚拉手 + 三个数 + 图层胶囊；拉出来 = 卡的全部内容。
//      状态因此又回到**一个** `Bool`（`drawerOpen`），而 `readoutsDisclosure`
//      （那行「其余读数」入口）与 `readoutsSheet` 一起删除：同一个抽屉只有一个开法。
//
//      为什么这次不做「连续跟手」（① 的 `drawerReveal`）：两个落点是固定的
//      （收起 / 拉出），中间没有第三种停法。连续跟手要自己算高度、自己夹边界、
//      自己判方向 —— 那是 ① 删掉的那部分，而它换来的只有「拖动过程中卡片跟着手指长」。
//      拖动仍然看**速度**（`predictedEndTranslation`），所以轻甩一下就走过去，
//      与模式条的吸附是同一条规矩。
// =============================================================================

extension MapSpineView {
    // ---- 读数格 ----
    //
    //  原型 `.card.chips`：车速 / 电量 / 胎压 / 车门，四格一行。
    //
    //  原型还带一手 `.chip:nth-child(odd){translateY(-7px)}`（奇偶上下错开 7px）。
    //  上一版照搬了它，用户 2026-09-24 的回应是：「下面 4 个按钮要规整，不要歪歪扭扭」
    //  —— 样品期的「错位手感」在真机上读出来只是「没对齐」，已删。
    //  四格现在是**同高同宽、同一基线**的一行，排版权全部交给 `HStack`。
    //
    //  四格是**读数**，不是按钮：车控那一档已经有一整排真控件了，
    //  同一个动作在首页再摆一遍就是第二个入口。

    /// 一格读数
    struct Readout: Identifiable {
        let id: String
        let key: String
        let value: String
        var unit: String? = nil
        var cls: String = "na"
    }

    /// 一排读数格（同一行、同一基线；裸的一行，不含玻璃壳）。
    /// 抽屉里那两排都是它 —— 形状一模一样，所以「拉出来」看起来是
    /// 「同一套读数多出来两排」，而不是换了一套排版。
    ///
    /// 排版权：**居中、各格等宽平分、彼此不留间距**（位置由「平分」给，
    /// 而不是由间距给 —— 三个数与五个数才能看起来是同一种排版）。
    func readoutRow(_ items: [Readout]) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(items) { c in
                readoutCell(c)
            }
        }
    }

    /// 收起时那一横上的三个数，也是抽屉里那一排的来源：**续航 / 电量 / 车速**。
    ///
    /// 「续航」2026-09-25 第三轮才补进来：它此前是这张卡的**巨字**
    ///（原型 `.big` 就是 412 km 续航），所以不在这排里 —— 一个数不该在同一屏说两遍。
    /// 现在卡片收起时只剩这一横，那个数必须有地方去：巨字搬到这里成了三格里的第一格。
    /// 于是「默认只有续航 电量 车速」这句话（用户 2026-09-25 第二轮的原话）在
    /// **卡片长什么样**这一层上才真的成立：一台车此刻的三个数，一行读完。
    @MainActor
    func readoutsPrimary(_ d: MapSpineData) -> [Readout] {
        let speed = VM.driveStatus(store.caches).speed
        return [
            Readout(id: "range", key: "续航",
                    value: d.rangeText == "--" ? "无数据" : d.rangeText,
                    unit: d.rangeText == "--" ? nil : "km"),
            Readout(id: "soc", key: "电量", value: "\(d.socPct)", unit: "%", cls: d.socCls),
            Readout(id: "speed", key: "车速",
                    value: speed == "--" ? "无数据" : speed,
                    unit: speed == "--" ? nil : "km/h")
        ]
    }

    /// 抽屉里的第一排（一瞬看不出来的那半）。顺序 = 关心的顺序：胎压 → 车锁 → 还要充多久。
    ///
    /// 取不到的那一格**照实说「无数据」**：不摆 `--`、也不拿别的数顶上（全站同一条）。
    /// 「还要充多久」只在充电时存在（`timeToFull` 为 nil 就是没有这件事），
    /// 所以它不占一格 —— 没在充电时只有胎压与车锁，而不是一格空着。
    @MainActor
    func readoutsMore(_ d: MapSpineData) -> [Readout] {
        let lock = VM.bodyStatus(store.caches).first { $0.label == "车锁" }
        // 胎压取**最低的那一条**：一格放不下四条，而四轮里最危险的就是它。
        // 「哪一轮低」在「车辆 → 体检」里有完整的一行，这里只做一瞥。
        let lowest = d.tyres.min { (Int($0.kpa) ?? Int.max) < (Int($1.kpa) ?? Int.max) }
        var out: [Readout] = [
            Readout(id: "tyre", key: "胎压",
                    value: lowest?.kpa ?? "无数据",
                    unit: lowest == nil ? nil : "kPa",
                    cls: lowest?.warn == true ? "bad" : "na"),
            Readout(id: "lock", key: "车锁",
                    value: lock?.text ?? "无数据",
                    cls: lock?.cls ?? "na")
        ]
        if let ttf = d.timeToFull, !ttf.isEmpty {
            out.append(Readout(id: "ttf", key: "充满", value: ttf))
        }
        return out
    }

    /// 抽屉里的第二排：**其余读数里还有的那几个**。
    ///
    /// 用户 2026-09-25 要的是 iOS 地图那种抽屉：「仅显示重要项，拉开抽屉就是剩余数据」——
    /// 只多一排（胎压/车锁/充满）不算兑现「剩余」。这三个都是 `MapSpineData` 里
    /// **真实存在**的字段，推不出来就整格不出现：
    ///   · 平均电耗（`avgConsumption`）—— 车端报的，不是我们算的
    ///   · 航向（`headingText`）—— 车头朝哪儿，地图上那个钉子在转，但看不到度数
    ///   · GPS（`gpsText`）—— 定位质量；它不好时上面每个数都该打折看
    @MainActor
    func readoutsRest(_ d: MapSpineData) -> [Readout] {
        var out: [Readout] = []
        if let avg = d.avgConsumption, !avg.isEmpty, avg != "--" {
            out.append(Readout(id: "avg", key: "平均电耗", value: avg))
        }
        if !d.headingText.isEmpty, d.headingText != "--" {
            out.append(Readout(id: "heading", key: "航向", value: d.headingText))
        }
        if !d.gpsText.isEmpty, d.gpsText != "--" {
            out.append(Readout(id: "gps", key: "GPS", value: d.gpsText, cls: d.gpsCls))
        }
        return out
    }

    /// 一格：**上面是数、下面是它的名字**，居中。
    ///
    /// 2026-09-25 第 9 条（用户：「抽屉里面的参数不要框选了，直接平铺在卡片上，
    /// 这些参数要重新思考下怎么布局优雅！大前提是要居中显示」）。两处都是真的：
    ///
    ///   · **框删了**：原来每格一个圆角矩形 + 一圈发丝线 —— 而那不是在「分组」，
    ///     是给每一个数各配了一个容器，于是同一行读数被切成四块牌子。
    ///     现在没有底、没有描边，数就贴在卡片上（卡片自己已经是玻璃，见 `dsGlass` 三层规则）。
    ///   · **居中**：原来一行里的格是 `leading` 对齐 —— 四个数长短不一，左对齐之后
    ///     整行的重心看起来是歪的。现在每个格自己居中对齐，格与格等宽平分，
    ///     于是无论这一行有两个数还是五个数，整行都是**同一条中轴**。
    ///
    /// 顺序也换了（数与名字）：数字当头、名字在下面一行小字 —— 与 Apple 地图那张卡
    /// 的收起态一致（`12:51 到达 / 16 分钟 / 12 公里`），也与 `summaryBar` 同一套读法。
    func readoutCell(_ r: Readout) -> some View {
        VStack(spacing: TokensSpacing.xxs) {
            HStack(alignment: .firstTextBaseline, spacing: TokensSpacing.xxs) {
                Text(r.value)
                    .font(TokensTypo.digits(16))
                    .foregroundStyle(r.cls == "na" ? TokensPalette.primary
                                                   : TokensPalette.statusColor(r.cls))
                if let unit = r.unit {
                    Text(unit)
                        .font(TokensTypo.caption2)
                        .foregroundStyle(TokensPalette.tertiary)
                }
            }
            Text(r.key)
                .font(TokensTypo.caption2)
                .foregroundStyle(TokensPalette.tertiary)
                .lineLimit(1)
        }
        // 各格等宽平分（没有间距，位置全由平分给），文字居中。
        .frame(maxWidth: .infinity, alignment: .center)
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(r.unit.map { "\(r.key) \(r.value) \($0)" } ?? "\(r.key) \(r.value)"))
    }

    // =========================================================================
    // MARK: 抽屉（收起 = 一横，拉出来 = 全部）
    // =========================================================================

    /// 抽屉的头：**那「一横」**（可以拖的拉手，居中）+ 图层胶囊（右侧），
    /// 下面就是收起时唯一露出来的三个数。
    ///
    /// 两态都长这样：收起时它**就是**整张卡，拉出来时它是卡的头。
    /// 图层胶囊两态都在 —— 它是换图层的唯一入口，收起时把它藏起来等于把
    /// 「图上看哪一件事」藏起来（而这一屏的整个骨架就是这个选择）。
    @MainActor
    func drawerHead(_ d: MapSpineData) -> some View {
        VStack(alignment: .leading, spacing: TokensSpacing.sm) {
            ZStack {
                drawerGrabber()
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    layerMenu(d)
                }
            }
            summaryBar(d)
        }
    }

    /// 收起时露出来的那三个数。照用户给的参考图（Apple 地图那张导航卡的收起态：
    /// 「12:51 到达 / 16 分钟 / 12 公里」）—— 三个数并排，下面一行小字说它们是什么。
    ///
    /// 用的就是全 App 已有的巨字原语（`DSBigNumber`），只是把字号从 96 收到 30：
    /// 「巨字」与「一横上的三个数」是同一个排版，差的只有字号 ——
    /// 于是它继承了那个原语的等宽数字与 `contentTransition(.numericText())`
    ///（换数时数字自己滚，而不是整块跳）。
    ///
    /// ⚠️ 它**不随抽屉开合而消失**：收起时它是整张卡，拉出来时它是卡的头 ——
    /// 参考图里那三个数在两种状态下也在同一个位置。这正是「一个事实一个出处」的做法：
    /// 它们留在这一行，抽屉里的正文就**不再重复**这三个数（见 `readoutsDrawer`）。
    @MainActor
    func summaryBar(_ d: MapSpineData) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: TokensSpacing.sm) {
            ForEach(readoutsPrimary(d)) { r in
                // 居中（用户第 9 条的大前提）：三个数各占一份等宽，
                // 数与它下面那行名字同一中轴 —— 与抽屉里那两排是同一种排版。
                DSBigNumber(value: r.value,
                            unit: r.unit,
                            caption: r.key,
                            size: 30,
                            tint: r.cls == "na" ? TokensPalette.primary
                                                : TokensPalette.statusColor(r.cls),
                            alignment: .center)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// 那「一横」：一枚可以**拖**、也可以**点**的拉手。
    ///
    /// 命中区是**整行宽 × 一格间距**：胶囊画出来的尺寸只有 36×5，那是画出来的样子、
    /// 不是可点的样子（这一仓反复写过同一条：HIG 最小触控目标 44pt）。
    /// 点它与拉它是同一个动作的两种做法 —— 有人会去拉，有人会去点，
    /// 而这个仓库的规矩是「两种都该成立，但只留一个实现」（同一处状态）。
    @MainActor
    func drawerGrabber() -> some View {
        Capsule()
            .fill(TokensPalette.track)
            .frame(width: 36, height: 5)
            .frame(maxWidth: .infinity)
            .frame(height: TokensSpacing.lg)
            .contentShape(Rectangle())
            .onTapGesture { toggleDrawer() }
            .gesture(drawerDrag)
            .accessibilityElement()
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(Text("更多读数"))
            .accessibilityValue(Text(drawerOpen ? "已展开" : "已收起"))
            .accessibilityAction { toggleDrawer() }
    }

    /// 拉手（以及卡的头那一行）上的那一下拖动。
    ///
    /// 判据只有方向和阈值，**不做连续跟手**：两个落点是固定的（收起 / 拉出），
    /// 中间没有第三种停法（理由见本文件头注的 ③）。
    /// 看的是 `predictedEndTranslation`：轻甩一下就该走过去 ——
    /// 与模式条的吸附、与系统的 sheet 是同一条规矩，只按「松手那一刻的位置」判的话，
    /// 「甩」与「停」会得到同一个结果（那正是「不跟手」）。
    var drawerDrag: some Gesture {
        DragGesture(minimumDistance: 8)
            .onEnded { v in
                let dy = v.predictedEndTranslation.height
                if dy < -60 { setDrawer(open: true) }
                else if dy > 60 { setDrawer(open: false) }
            }
    }

    func toggleDrawer() {
        TokensHaptic.select()
        setDrawer(open: !drawerOpen)
    }

    /// 唯一的写点（拉手、点按、换图层三处都走它）。
    /// 它自己**不出触觉**：点击与拖动各有自己的手感，谁也不该替谁发。
    func setDrawer(open: Bool) {
        guard open != drawerOpen else { return }
        withAnimation(TokensMotion.value) { drawerOpen = open }
    }

    /// 抽屉里属于「读数」的那一半：一瞬看不出来的那些数。
    ///
    /// **不重复收起时那一横上的三个数**（续航 / 电量 / 车速）—— 一个事实一个出处是
    /// 这一仓反复删出来的规矩，而它们此刻就在抽屉头上。
    ///
    /// 这里**没有 `ScrollView`**：卡里再套一层滚动，那一片区域的竖直拖动就归内层了
    ///（`DS.swift` 删「纸页外壳」时记过同一条）。上一版它是 sheet 的内容，而 sheet
    /// 本来就该能滚；搬进卡里就不能了 —— 也不必要：它装的是固定的两排。
    @MainActor
    func readoutsDrawer(_ d: MapSpineData) -> some View {
        let rest = readoutsRest(d)
        return VStack(alignment: .leading, spacing: TokensSpacing.md) {
            readoutRow(readoutsMore(d))
            if !rest.isEmpty {
                // 两排之间用一条发丝线分开（全站分组就这一种做法：线内缩、不通栏）。
                // 少了它，五个数连成一片时看不出「这里是两件事」。
                DSDivider()
                readoutRow(rest)
            }
        }
    }

    // =========================================================================
    // MARK: 比例尺（地图自己的仪器，挂在灵动岛下面）
    // =========================================================================

    /// 比例尺。**那个数不是估的**：把屏幕上相距 200pt 的两点交给 `MapProxy` 换成经纬度，
    /// 再用 `CLLocation.distance` 量出地面距离 —— 除下来就是「一个点多少米」。
    ///
    /// 为什么不再用系统的 `MapScaleView`（2026-09-25 之前一直是它）：它的位置由 MapKit
    /// 定（贴在地图角落），而用户要的是**灵动岛下面**（第 2 条）。系统控件搬不动，
    /// 所以量法自己来、位置也自己来。**尺子上的数仍然是真的量出来的**，
    /// 不是按镜头距离估的 —— 一支会撒谎的尺子比没有尺子更糟（这一仓对
    /// 「看起来像有数据、其实是猜的」一律零容忍）。
    ///
    /// 只量**横向**两点的距离：同一个 y 上，两点之间只差经度 ——
    /// 墨卡托的横向尺度只跟纬度有关，而这一屏最多几百米，纬度变化带来的偏差
    /// 远小于 1%。纵向落在哪儿因此不影响结果（这也是为什么它不必知道安全区高度）。
    @MainActor
    func scaleRuler(_ proxy: MapProxy) -> some View {
        GeometryReader { geo in
            if let meters = metersPerPoint(proxy, size: geo.size),
               let bar = scaleBar(metersPerPoint: meters, maxWidth: geo.size.width * 0.42) {
                VStack(spacing: TokensSpacing.xs) {
                    Text(bar.label)
                        .font(TokensTypo.caption2)
                        .foregroundStyle(TokensPalette.secondary)
                    ruler(bar.width)
                }
                .padding(.horizontal, TokensSpacing.sm)
                .padding(.vertical, TokensSpacing.xs)
                // 它压在瓦片上，所以给一层与画布同色的阴影 —— 「地图上的一行字怎么读得出来」
                // 只有这一条路（地图自己的地名也是这么做的）。暗层不回归（用户 2026-09-24）。
                .shadow(color: TokensPalette.canvas.opacity(0.55), radius: 4)
                .opacity(scaleShown ? 1 : 0)
                .frame(maxWidth: .infinity, alignment: .top)
                .padding(.top, TokensSpacing.sm)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text("比例尺 \(bar.label)"))
            }
        }
        .allowsHitTesting(false)
    }

    /// 一把尺子的形状：一条横线 + 两端各一枚短竖。带端帽才是「距离」；
    /// 光秃秃一根横条看起来像分隔线，而不是尺子。
    func ruler(_ width: CGFloat) -> some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(TokensPalette.secondary)
                .frame(width: width, height: 1)
            HStack(spacing: 0) {
                Rectangle().fill(TokensPalette.secondary).frame(width: 1, height: 5)
                Spacer(minLength: 0)
                Rectangle().fill(TokensPalette.secondary).frame(width: 1, height: 5)
            }
            .frame(width: width)
        }
        .frame(width: width, height: 5)
    }

    /// 屏幕上一个点等于多少米。取不到就返回 nil（那时**不画尺子**）——
    /// 而「画一把猜的尺子」是这一仓最不接受的那种做法。
    @MainActor
    func metersPerPoint(_ proxy: MapProxy, size: CGSize) -> CGFloat? {
        guard size.width > 80, size.height > 80 else { return nil }
        let dx = min(200, size.width * 0.4)
        let y = size.height / 2
        guard let a = proxy.convert(CGPoint(x: size.width / 2 - dx / 2, y: y), from: .local),
              let b = proxy.convert(CGPoint(x: size.width / 2 + dx / 2, y: y), from: .local)
        else { return nil }
        let meters = CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
        guard meters > 0 else { return nil }
        return CGFloat(meters / Double(dx))
    }

    /// 尺子上的距离与它该有多长。**只取整到 1 / 2 / 5 这三档**（尺子的通用做法）：
    /// 在「画出来不超宽」的档里挑最大的一档，于是它随缩放**跳档**
    ///（500 m → 1 km → 2 km …），而不是一条不断变长的模糊线。
    ///
    /// 两个数一起返回：一个印在尺子上、一个决定尺子多长 ——
    /// 它们是**同一个决定的两种说法**，分到两处算一定会对不上。
    @MainActor
    func scaleBar(metersPerPoint: CGFloat, maxWidth: CGFloat) -> (label: String, width: CGFloat)? {
        let steps: [Double] = [1, 2, 5, 10, 20, 50, 100, 200, 500,
                               1_000, 2_000, 5_000, 10_000, 20_000, 50_000,
                               100_000, 200_000, 500_000]
        let reach = Double(maxWidth) * Double(metersPerPoint)
        guard let meters = steps.last(where: { $0 <= reach }) else { return nil }
        let width = CGFloat(meters / Double(metersPerPoint))
        let label = meters >= 1_000
            ? String(format: "%g km", meters / 1_000)
            : String(format: "%g m", meters)
        return (label, width)
    }

    /// 让比例尺露两秒（用户 2026-09-25：「2 秒后消失」）。
    ///
    /// 调用点有两处，都是「地图动了」这件事：页面出现时一次（`task`），
    /// 镜头变更时一次（`onChange(of: camera)`）—— 与 Apple 地图同一个节奏：
    /// 动就露，停就自己走掉。
    ///
    /// 计时器带代号：两秒内地图又动了，上一次的隐藏就作废（与模式条收回同一条手法）——
    /// 少了它，连续拖地图时尺子会在你正需要它的时候被上一次的计时器收走。
    @MainActor
    func flashScale() {
        withAnimation(TokensMotion.fade) { scaleShown = true }
        scaleToken += 1
        let token = scaleToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            guard token == scaleToken else { return }
            withAnimation(TokensMotion.fade) { scaleShown = false }
        }
    }
}
