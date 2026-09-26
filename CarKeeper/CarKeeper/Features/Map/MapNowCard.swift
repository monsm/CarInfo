import SwiftUI

// =============================================================================
//  MapSpineView · 「现在」那一张卡（抽屉的两态 + 卡里的地址 / 副行 / 光带）
// =============================================================================
//
//  与 `MapSpineReadouts.swift`、`MapQuickButtons.swift` 同一个理由 —— 关切不同：
//  `MapSpineView` 管这一屏的骨架（六页同屏、底条、镜头、图层、手势），这里只回答
//  「这张卡长什么样、里面的数怎么排、取不到时写什么」。
//
//  另一条理由更实际：`scan/lintcfg.py` 的 `file_length` 盯着最大那个文件。2026-09-25
//  搬了**两次**，都是同一个阈值：先搬三个数的排版（骨架那一份当时 1211 行），
//  再搬这张卡本身（加完抽屉之后它又到 1201 行）。搬的都是**一件独立的事**，
//  界面一字未改 —— 不是把它加进排除清单，也不是把阈值抬到刚够。
//
//  注：下面用到的 `store` / `layer` / `layerMenu` / `drawerOpen` 因此
//  **不是 `private`** —— `private` 的作用域是**文件**，跨文件看不见。
//  它们在骨架里的注释写明了为什么。
// =============================================================================

extension MapSpineView {

    // =========================================================================
    // MARK: 「现在」那一张卡（抽屉）
    // =========================================================================

    /// 「现在」这一档底部那张卡 —— **它现在是一个抽屉**（用户 2026-09-25 第 2 条：
    /// 「下面的卡片不是抽屉样，不是我发的图片的参考 …… 默认只显示一横，拉出来才是全部」）。
    ///
    /// 收起（默认）= 拉手 + 三个数（续航 / 电量 / 车速）+ 图层胶囊；
    /// 拉出来 = 这张卡的全部内容。两态的排版（拉手、拖动、那三个数、其余读数）
    /// 都在 `MapSpineReadouts.swift`（与读数同一份文件），这里只有它们的外壳。
    ///
    /// 两件事因此从这一处消失，理由写在它们的新家：
    ///   · 巨字续航 → 它已是收起时那三个数之一（`summaryBar`），不再摆在卡里：
    ///     一个事实一个出处（用户 2026-09-24：「地图页的信息有很多是重复的」）；
    ///   · 上一轮那张系统 sheet 与它那行「其余读数」入口 → 删。抽屉就是这张卡，
    ///     同一个抽屉只有一个开法（见 `MapSpineReadouts` 头注的三代写法）。
    @ViewBuilder
    func nowCard(_ d: MapSpineData) -> some View {
        //  ⚠️ 它此前还给 `GlassCard` 传一个 `frosted: drawerOpen`（收起不磨砂 /
        //  拉出磨砂）—— 那一个参数随「玻璃默认更透」一起删了（用户 2026-09-26：
        //  「玻璃就默认选更透」），现在全 App 的玻璃只有一档材质（见 `DSGlass.swift`）。
        GlassCard(accent: HomeMode.now.accent) {
            VStack(alignment: .leading, spacing: 0) {
                drawerHead(d)
                //  抽屉的正文：**它的高度就是手指走出来的那一段**
                //（`drawerReveal` 0…1 × 正文的自然高度）。
                //  用户 2026-09-26：「抽屉和原版地图的抽屉不一样，原版支持跟手抽出，
                //  现在的只支持点击抽出」—— 于是两态之间那一段也真实存在了。
                //  `clipped()` 是必须的：正文的高度被压着，没它就会画出卡外。
                if drawerReveal > 0.001 {
                    drawerContent(d)
                        .frame(height: drawerBodyHeight * drawerReveal, alignment: .top)
                        .clipped()
                }
            }
            //  量一遍正文的**自然高度** —— 跟手时的分母（手指走多少 = 拉开多少）。
            //  它住在 `background` 里：背景不参与父视图的排版，所以这一份既不占位、
            //  也不出现在版面上（`.hidden()` 连绘制都省了，但它仍然参与布局）。
            //  ⚠️ 它**总是**建着（不只是拉开的时候）：拉开的第一帧就有分母 ——
            //  否则高度会先从 0 跳到真值，跟手那一下会先闪一格。
            .background(alignment: .top) {
                drawerContent(d)
                    .background {
                        GeometryReader { g in
                            Color.clear
                                .onAppear { drawerBodyHeight = g.size.height }
                                .onChange(of: g.size.height) { _, h in drawerBodyHeight = h }
                        }
                    }
                    .hidden()
                    .allowsHitTesting(false)
            }
        }
        //  记住的那一档：拉出来过就还是拉出来的（`drawerOpen` 是持久化的设备键）。
        //  **动画不出现在这里**：启动那一下应该就是那个样子，不是「从收起长出来」。
        .onAppear { drawerReveal = drawerOpen ? 1 : 0 }
    }

    /// 抽屉拉出来之后的正文。**`switch` 在这里**：图层是本屏的状态（`layer`），
    /// 而三个图层各自的正文本来就在 `MapSpineLayers.swift` 里；
    /// `now` 那一层的一半在 `MapSpineReadouts.swift`。
    ///
    ///  ⚠️ 2026-09-26（用户：「下面抽屉的现在选择放到抽屉里面，外面只显示 3 个」）：
    ///  **图层胶囊搬进来了**（它此前坐在卡头那一行、与拉手同一排）。
    ///  于是收起时那张卡只剩「拉手 + 三个数」—— 一横，而不再多一件控件；
    ///  要看图上看哪一层、或换一层，把抽屉拉出来。
    @ViewBuilder
    func drawerContent(_ d: MapSpineData) -> some View {
        VStack(alignment: .leading, spacing: TokensSpacing.lg) {
            layerMenu(d)
            switch layer {
            case .now:
                if d.hasLocation == false {
                    // 没有位置时不摆一堆「--」：说清为什么
                    emptyNotice(MapSpineLayer.now.emptyNote)
                } else {
                    nowMetrics(d)
                }
                readoutsDrawer(d)
            case .trips: tripsContent(d)
            case .holds: holdsContent(d)
            case .charge: chargeContent(d)
            }
        }
        .padding(.top, TokensSpacing.lg)
    }

    /// 抽屉拉出来之后卡里的正文：地址 → 副行 → 光带。
    ///
    ///  这里原本还有**巨字续航**（`DSBigNumber` 56pt）+ 它取不到时的空态
    ///（`GlassCardEmpty("还没收到剩余续航")`）。两者 2026-09-25 第三轮一起搬走：
    ///  卡收起时只剩「一横」，而那一横上是**续航 / 电量 / 车速**三个数
    ///（`MapSpineReadouts.summaryBar`）—— 同一个数在卡里说两遍就是这一仓
    ///  反复删的那种重复（用户 2026-09-24：「地图页的信息有很多是重复的」）。
    ///  「车没报续航」那一支也跟着走了：现在那**一格自己写「无数据」**，
    ///  与抽屉里其余读数是同一条写法（不摆 `--`、也不摆一块空态）。
    @ViewBuilder
    func nowMetrics(_ d: MapSpineData) -> some View {
        if !d.address.isEmpty {
            Text(d.address)
                .font(TokensTypo.fixed(22))
                .tracking(TokensTracking.title)
                .foregroundStyle(TokensPalette.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        nowSub(d)
        // 光带 = 电量（全 App 唯一的形状，在地图上它是「车钉外面那圈弧」的展开）
        // `showsGlow` 不再传：它以前读「当前艺术方向允不允许发光」（纸上不允许 —— 纸张没有
        // 发光）。主题只剩原生之后那是常真，于是这一处回到 `DSLightBar` 的默认值（true），
        // 而那个参数仍在（充电页那类地方需要不发光的光带）。
        DSLightBar(progress: Double(d.socPct) / 100,
                   height: 5,
                   tint: TokensPalette.lightBar)
    }

    /// 副行。空段直接丢掉（不摆占位）—— 「表显 53,766 km · 未充电」里任何一个字
    /// 取不到，那一句就不出现，而不是留一个 `--`。
    ///
    /// 它曾经从「电量 68%」开头 —— 那个数已经是下面读数里的「电量」那一格，
    /// 而电量在这张卡里还有第三种说法（光带）。一个 68% 说三遍不是信息多，是没精简。
    @ViewBuilder
    func nowSub(_ d: MapSpineData) -> some View {
        let mileage = VM.vehicleSummary(store.car, store.controlCache)?.mileage
        let line = Self.join([mileage.map { "表显 \($0) km" },
                              d.chargeText])
        if !line.isEmpty {
            Text(line)
                .font(TokensTypo.caption)
                .foregroundStyle(TokensPalette.tertiary)
        }
    }

    /// 把若干片段拼成一行：空段与 `--` 直接丢掉（全站统一的做法）。
    /// `private` 到本文件为止 —— 用它的只有上面那一处。
    private static func join(_ parts: [String?]) -> String {
        parts.compactMap { $0 }
            .filter { !$0.isEmpty && $0 != "--" }
            .joined(separator: " · ")
    }
}
