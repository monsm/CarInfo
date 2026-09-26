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

    /// 抽屉的头：**那「一横」**（一条可以拖、也可以点的拉手）+ 收起时露出来的三个数。
    ///
    /// 两态都长这样：收起时它**就是**整张卡，拉出来时它是卡的头。
    ///
    ///  ⚠️ 2026-09-26（用户：「下面抽屉的现在选择放到抽屉里面，外面只显示 3 个」）：
    ///  头里那一枚**图层胶囊**已搬进抽屉的正文（见 `MapNowCard.drawerContent`）。
    ///  它在两态都在，只是现在只在拉开时看得见 —— 收起时这张卡就剩下一横，
    ///  而那一横上只有三个数。
    @MainActor
    func drawerHead(_ d: MapSpineData) -> some View {
        VStack(alignment: .leading, spacing: TokensSpacing.sm) {
            drawerGrabber()
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
                            alignment: .center,
                            // 用户 2026-09-25 第 3 条：「卡片的 3 个要素字体加粗」。
                            // 超细字重是这个原语的「仪器感」（见 `TokensTypo.display`），
                            // 但这一行压在通透玻璃上 —— 超细的笔画在瓦片/照片上会散掉。
                            weight: .bold)
                    //  这三个数下面是什么颜色的瓦片不由我们决定 —— 它们一度带一层
                    //  **全局**文字壳（用户第 2 条），而那一层已于 2026-09-26 删掉
                    //  （用户：「完全删除文字发光和文字发光功能」）。现在靠的是
                    //  `weight: .bold` 与卡片自己的玻璃。
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

    /// 拉手（以及卡的头那一行）上的那一下拖动 —— **现在是跟手的**。
    ///
    ///  用户 2026-09-26：「抽屉和原版地图的抽屉不一样，原版支持跟手抽出，
    ///  现在的只支持点击抽出」。于是这一版与两代旧写法（① 自己量高度、
    ///  ② 系统 sheet、③ 两态硬切）都不同：**两态之间那一段也是真的** ——
    ///  手指走到哪，卡片就长到哪（`drawerReveal` = 手指位移 ÷ 正文自然高度）。
    ///
    ///  松手时落在哪个端点：**先看位置**（过一半就以位置为准），没过一半才看
    ///  那一甩的方向（`predictedEndTranslation`）。与模式条的吸附、与系统的 sheet
    ///  是同一条规矩：只按「松手那一刻的位置」判的话，「甩」与「停」会得到同一个结果。
    var drawerDrag: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { v in
                //  分母：正文的自然高度（`MapNowCard` 里量出来的）。
                //  `max(80, …)` 是一道回退：第一帧还没量到时（高度 0），
                //  至少让 80pt 的手势位移走完一整段 —— 而不是除零或瞬开。
                let travel = max(80, drawerBodyHeight)
                let base: CGFloat = drawerOpen ? 1 : 0
                drawerReveal = min(1, max(0, base - v.translation.height / travel))
            }
            .onEnded { v in
                let dy = v.predictedEndTranslation.height
                //  过了一半：位置说了算（往下甩不超过 60pt 就算放回原位）。
                //  没过一半：只有明确那一甩才算（60pt 是模式条用的同一个数）。
                let wantsOpen = drawerReveal > 0.5 ? (dy <= 60) : (dy < -60)
                setDrawer(open: wantsOpen)
            }
    }

    func toggleDrawer() {
        TokensHaptic.select()
        setDrawer(open: !drawerOpen)
    }

    /// 唯一的写点（拉手、点按、拖动、换图层四处都走它）。
    /// 它自己**不出触觉**：点击与拖动各有自己的手感，谁也不该替谁发。
    ///
    ///  ⚠️ 它**不能再守「`open` 与 `drawerOpen` 相同就不动」**：跟手拖到一半
    ///  松手时，目标可能与当前状态相同（拉到 40% 又放回去）—— 而那个中间位置
    ///  必须归位。所以每次都把 `drawerReveal` 与 `drawerOpen` 一起写到目标。
    func setDrawer(open: Bool) {
        withAnimation(TokensMotion.value) {
            drawerOpen = open
            drawerReveal = open ? 1 : 0
        }
    }

    /// 抽屉里属于「读数」的那一半：一瞬看不出来的那些数。
    /// （图层胶囊不在这里 —— 它在 `MapNowCard.drawerContent` 的最上面。）
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

    //  这里原本是**自己量的一把尺子**（2026-09-25 第 9 条那一轮）：`scaleRuler(proxy)`
    //  + `ruler` + `metersPerPoint` + `scaleBar` + `flashScale`，配套的还有 `MapReader`、
    //  两个 `@State`（`scaleShown` / `scaleToken`）与一条每帧回调。
    //  **第十一轮全部删掉**，理由只有一句：当时那句「系统的 `MapScaleView` 位置由 MapKit 定、
    //  搬不动」是**错的** —— 它和 `MapCompass` 都能当独立视图挂
    //（`MapScaleView(anchorEdge:scope:)` + `.mapScope(_:)`），位置由我们自己给。
    //  为躲一个不存在的限制，这一屏多养了一整套测距与计时器。
}

// =============================================================================
//  MapRefreshBadge —— 地图页上那枚自动刷新的倒计时（调试）
// =============================================================================

extension MapSpineView {
    /// 把那枚徽标摆到地图上：左上角、比例尺那一格之下。
    ///
    /// 为什么它的位置在这儿而不是在 `MapSpineView.swift`：那一份贴着 `lintcfg.py` 的
    /// 1200 行门禁（差一行就红），而这一格与「读数」同一类东西（本文件头注的理由）。
    /// `xxxl`（64）是比例尺那一格（`sm`）+ 它自己的高度之外那一格呼吸位 ——
    /// 复用间距刻度上的已有档，不新造一个数。
    func mapRefreshBadge() -> some View {
        MapRefreshBadge()
            .padding(.leading, TokensSpacing.md)
            .padding(.top, TokensSpacing.xxxl)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// 用户 2026-09-26：「地图页加入刷新倒计时吧，我感觉没刷新一样（调试用）」。
///
/// 那句话说的是一件真事：这条循环**没有任何可见的反馈** —— 停着的车报文几乎不变，
/// 数据不变、界面就不变，于是「在刷」与「没在刷」看起来一模一样。这枚徽标把
/// 三件事写在脸上：**还剩几秒**、**此刻这一档的节律**、**退避走到第几拍**。
///
/// ⚠️ 它读的全是循环自己的数（`interval` / `lastTickAt` / `zeroStreak`），
/// **不另存**「下次该几点刷」—— 那会是第二个节律（`RefreshLoop` 头注：节律只有一处）。
/// 秒表由 `TimelineView` 走：它自己不持任何状态，也只有这一格每秒重画，
/// 整屏（含那张活地图）不会被拖进来。
struct MapRefreshBadge: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            content(now: ctx.date)
        }
    }

    private func content(now: Date) -> some View {
        let loop = RefreshLoop.shared
        return HStack(spacing: TokensSpacing.xs) {
            Image(safeSymbol: "arrow.triangle.2.circlepath", fallback: "arrow.clockwise")
                .font(TokensTypo.fixed(11, weight: .semibold))
                .foregroundStyle(TokensPalette.secondary)
            //  `monospacedDigit`：倒计时是每秒变的数，等宽才不跳。
            Text(left(now: now, loop: loop))
                .font(TokensTypo.fixed(11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(TokensPalette.primary)
            Text(cadence(loop))
                .font(TokensTypo.fixed(11, weight: .medium))
                .foregroundStyle(TokensPalette.tertiary)
        }
        .padding(.horizontal, TokensSpacing.sm)
        .padding(.vertical, TokensSpacing.xs)
        //  它是浮在**连续画面**（地图瓦片）上的一小块 —— 材质走全 App 唯一那一档（`.clear`）。
        .dsGlassCapsule(hairline: false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("自动刷新，还剩 \(left(now: now, loop: loop))"))
        //  它是**只读**的一格：不接手势，免得地图上多一块挡住拖动的东西。
        .allowsHitTesting(false)
    }

    /// 还剩几秒。
    ///
    /// 三种写法各对应一个真实状态（不编数）：
    ///   · 还没走过第一趟 → **「—」**（启动那一趟归 `bootstrap()`，这儿不该猜）
    ///   · 到了点而请求还没回来 → **「…」**（在飞，不是在等）
    ///   · 其余 → 向上取整的秒数
    private func left(now: Date, loop: RefreshLoop) -> String {
        guard let last = loop.lastTickAt else { return "—" }
        let rest = loop.interval - now.timeIntervalSince(last)
        return rest <= 0 ? "…" : "\(max(1, Int(rest.rounded(.up))))s"
    }

    /// 此刻这一档的节律（写给人看的那一句）。
    /// 它读的 `parkedInterval` 就是 `interval` 在停着时用的那个数 —— 同一个出处。
    private func cadence(_ loop: RefreshLoop) -> String {
        if AppStore.shared.isCarMoving { return "车在动 · 2s" }
        let beats = min(loop.zeroStreak, RefreshLoop.Cadence.parkedSteps)
        return "停 · ×\(beats) → \(Int(loop.parkedInterval))s"
    }
}
