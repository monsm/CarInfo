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
        // `frosted:` 收的就是抽屉的开合（用户 2026-09-25 第 3 条）——
        // 收起时卡片是一层不磨砂的玻璃（地图透出来），拉出来时它变成磨砂的
        // （卡里现在是一片要读的字）。为什么这个参数只能由调用点给、
        // 以及它为什么不是「再加一层模糊」，写在 `GlassCard.frosted` 上。
        GlassCard(accent: HomeMode.now.accent, frosted: drawerOpen) {
            VStack(alignment: .leading, spacing: 0) {
                drawerHead(d)
                if drawerOpen {
                    //  2026-09-25「给它一点呼吸」：这一块原来在 `withAnimation` 里是**硬切**的
                    //（卡片高度在长，而内容一上来就是满不透明）。淡入之后两件事同拍：
                    // 高度长出来的同时内容显影 —— 与模式条展开同一种手感。
                    // （不用 `.move` 那一类：抽屉是从卡里长出来的，不是从外面滑进来的。）
                    drawerContent(d)
                        .transition(.opacity)
                }
            }
        }
    }

    /// 抽屉拉出来之后的正文。**`switch` 在这里**：图层是本屏的状态（`layer`），
    /// 而三个图层各自的正文本来就在 `MapSpineLayers.swift` 里；
    /// `now` 那一层的一半在 `MapSpineReadouts.swift`。
    @ViewBuilder
    func drawerContent(_ d: MapSpineData) -> some View {
        VStack(alignment: .leading, spacing: TokensSpacing.lg) {
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
