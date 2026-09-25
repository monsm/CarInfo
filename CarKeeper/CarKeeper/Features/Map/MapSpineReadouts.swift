import SwiftUI

// =============================================================================
//  MapSpineView · 「现在」这一档里的读数
//（默认一排：电量 / 车速；点开「其余读数」：胎压 / 车锁 / 充满 + 平均电耗 / 航向 / GPS）
// =============================================================================
//
//  与 `MapSpineLayers.swift` 同一个理由 —— 关切不同：`MapSpineView` 管这一屏的
//  骨架（六页同屏、底条、车牌徽标、底部浮动两卡），这里只回答一件事：
//  「一瞥的那几个数从哪来、取不到时写什么、其余的怎么让人看到」。
//
//  另一条理由更实际：`scan/lintcfg.py` 的 `file_length` 盯着最大那个文件。
//  2026-09-24 骨架那一份涨到 1206 行（阈值 1200），差 6 行就红 ——
//  这一轮拆完约 1112 行。不选「把阈值抬到刚够」：贴着阈值的代价是下一次**任何**
//  小改动都要先做一遍取舍，而 `MapSpineLayers.swift` 的头注里已经写过一次这个账
//  （它当时也是从贴着阈值拆出来的）。
//
//  注：下面用到的 `store` 因此**不是 `private`** —— `private` 的作用域是文件，
//  跨文件看不见。它在骨架里的注释写明了为什么。
//
//  2026-09-25（第二轮）：**「其余读数」改成了系统的 sheet**（用户：把地图的抽屉做成
//  iOS 地图那种；并在我列的候选里选了「换成系统 sheet + `presentationDetents`」）。
//  上一版是卡里自己拉的一道抽屉：一枚自画的拉手 + `drawerReveal` 连续量 + 自算的两个
//  落点 + 把内容藏起来量自然高度（`drawerMeasure`）。那套东西**每一条都在重做系统
//  已经做好的事**，而且做得少：
//    · 系统 sheet 的落点是三个 + 橡皮筋，我们只有两个 + 手算的吸附；
//    · 系统的拉手是 UIKit 那一枚（尺寸 / 对比度 / 点击热区都随动态字号与辅助功能设置走），
//      我们画的是 `Capsule().fill(track).frame(width: 36, height: 5)`；
//    · 系统在 `.medium` 那一档会让**底下的地图继续可交互**（`.presentationBackgroundInteraction`），
//      而卡里那道抽屉从头到尾都盖在地图上；
//    · 系统给下拉关闭、VoiceOver 的「收起/展开」、键盘与指针行为，这些都要自己写。
//  现在这一档只剩一句话：「点这行 → 系统把它拉上来」。`drawerReveal` / `drawerBase` /
//  `drawerHeight` / `drawerMeasure` / `drawerGrabber` / `moreDrawer` 全部删除。
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

    /// 一排读数格（同一行、同一基线；裸的一行，不含玻璃壳）：排进 `nowCard` 大卡的下沿。
    ///
    /// 卡里那一排与 sheet 里那两排都是它 —— 三处形状一模一样，所以「点开其余读数」
    /// 看起来是「同一套读数多出来两排」，而不是换了一套排版。
    /// 排版权：每格同高同宽（`readoutCell` 自己 `maxWidth: .infinity`）。
    func readoutRow(_ items: [Readout]) -> some View {
        HStack(spacing: TokensSpacing.sm) {
            ForEach(items) { c in
                readoutCell(c)
            }
        }
    }

    /// 默认那一排：**只有电量与车速**（用户 2026-09-25：「地图页数据用抽屉的方式展示，
    /// 默认只有续航 电量 车速，其他数据均通过拉开抽屉展示」）。
    ///
    /// 「续航」不在这一排里：它是这张卡的**巨字**（`DSBigNumber`）—— 同一屏再摆一格
    /// 「续航 412 km」就是把一个数说两遍，而这个仓库反复删的正是那种重复
    ///（上一次是副行里的「电量 68%」：它在本卡里已经有格子与光带两种说法）。
    /// 于是默认一屏恰好是用户点名的三个数：**续航（巨字）/ 电量 / 车速**。
    /// 两格分一行，所以它们比原来四格挤一行时**宽一倍** —— 这也是「控件太小」那一半。
    @MainActor
    func readoutsPrimary(_ d: MapSpineData) -> [Readout] {
        let speed = VM.driveStatus(store.caches).speed
        return [
            Readout(id: "soc", key: "电量", value: "\(d.socPct)", unit: "%", cls: d.socCls),
            Readout(id: "speed", key: "车速",
                    value: speed == "--" ? "无数据" : speed,
                    unit: speed == "--" ? nil : "km/h")
        ]
    }

    /// 收在 sheet 里的第一排（一瞬看不出来的那半）。顺序 = 关心的顺序：胎压 → 车锁 → 还要充多久。
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

    /// sheet 里的第二排：**其余读数里还有的那几个**。
    ///
    /// 用户 2026-09-25 要的是 iOS 地图那种抽屉：「仅显示重要项，拉开抽屉就是剩余数据」——
    /// 上一版拉开只多一排（胎压/车锁/充满），「剩余」这两个字没兑现。
    /// 这三个都是 `MapSpineData` 里**真实存在**的字段，推不出来就整格不出现：
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

    // =========================================================================
    // MARK: 「其余读数」—— 一行入口 + 一个系统 sheet
    // =========================================================================

    /// 卡里那一行入口。**它是 iOS 的分级披露那一行**：一句标签 + 一个右尖括号，
    /// 点开是系统 sheet（见 `readoutsSheet` 与 `nowCard` 上的 `.sheet`）。
    ///
    /// 为什么不再自己画拉手：iOS 里「这里可以拉」是**底部表单**这件事本身，
    /// 而底部表单的拉手由系统画（尺寸、对比度、点击热区都随辅助功能设置走）。
    /// 卡里再画一枚 36×5 的胶囊，等于在系统已经画了拉手的地方又画一个 ——
    /// 而这一行是**卡片内容**，不是表单：它该长得像「一条通往更多数据的路」，
    /// 也就是 iOS 里无处不在的那种 disclosure 行。
    ///
    /// 命中区给足 `TokensSpacing.row`（HIG 最小触控目标 44pt）。
    @MainActor
    func readoutsDisclosure() -> some View {
        Button {
            TokensHaptic.tap()
            showReadouts = true
        } label: {
            HStack(spacing: TokensSpacing.sm) {
                Text("其余读数")
                    .font(TokensTypo.caption)
                    .foregroundStyle(TokensPalette.secondary)
                Spacer(minLength: TokensSpacing.sm)
                Image(safeSymbol: "chevron.right", fallback: "chevron.right")
                    .font(TokensTypo.micro)
                    .foregroundStyle(TokensPalette.tertiary)
            }
            .frame(minHeight: TokensSpacing.row)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("其余读数"))
        .accessibilityHint(Text("胎压、车锁、还要充多久、平均电耗、航向、GPS"))
    }

    /// sheet 里的内容：一排一瞥时看不见的那些读数。
    ///
    /// **不重复卡里已经有的三个数**（续航 / 电量 / 车速）—— 一个事实只有一个出处是
    /// 这个仓库反复删出来的规矩，而它们此刻就在底下那张卡上。
    ///
    /// 两排之间让一格（`TokensSpacing.lg`）：它们回答的是两个不同的问题
    ///（「车此刻的状态」与「这趟路走得怎么样」），挤在一起会被读成一排六个。
    @MainActor
    func readoutsSheet(_ d: MapSpineData) -> some View {
        let more = readoutsMore(d)
        let rest = readoutsRest(d)
        return ScrollView {
            VStack(alignment: .leading, spacing: TokensSpacing.lg) {
                Text("其余读数")
                    .font(TokensTypo.headline)
                    .foregroundStyle(TokensPalette.primary)
                readoutRow(more)
                // 一排都不剩就不占位（不摆一行空气）—— 与卡里同一条规矩。
                if !rest.isEmpty {
                    readoutRow(rest)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // 页边距用 `TokensSpacing.lg`：sheet 的四边都是系统给的，这一格是内容与
            // 它的边缘之间那点呼吸位（与分组卡片的水平边距同一档）。
            .padding(.horizontal, TokensSpacing.lg)
            .padding(.top, TokensSpacing.md)
            .padding(.bottom, TokensSpacing.xl)
        }
        // `ScrollView` 而不是 `VStack`：这一屏现在装得下，但读数会随「充着电」
        //（多一格「充满」）与以后的字段变多 —— 系统的做法是「表单可以滚」，
        // 而不是我们自己算它能长多高。
        .scrollBounceBehavior(.basedOnSize)
        // 标题不进导航栏（这是 sheet，不是页面）：系统在 `.medium` 档位下不会给标题栏，
        // 而一个只在一档出现的栏会让 sheet 在拖动时「跳」一下。
    }

    /// 一格：上面是键（小字），下面是值（数字体）。各格完全同高同宽 ——
    /// 行里没有一格带额外偏移，所以「一行两格」就是它们的**全部排版**。
    func readoutCell(_ r: Readout) -> some View {
        VStack(spacing: TokensSpacing.xs) {
            Text(r.key)
                .font(TokensTypo.caption2)
                .foregroundStyle(TokensPalette.tertiary)
            HStack(alignment: .firstTextBaseline, spacing: TokensSpacing.xxs) {
                Text(r.value)
                    .font(TokensTypo.digits(15))
                    .foregroundStyle(r.cls == "na" ? TokensPalette.primary
                                                   : TokensPalette.statusColor(r.cls))
                if let unit = r.unit {
                    Text(unit)
                        .font(TokensTypo.caption2)
                        .foregroundStyle(TokensPalette.tertiary)
                }
            }
        }
        // 同宽：`.frame(maxWidth: .infinity)` 让一格平分一行宽；
        // 同高：两行文字 + 同一个内边距，没有哪一格多一行。
        .frame(maxWidth: .infinity)
        .padding(.vertical, TokensSpacing.sm)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(TokensPalette.fillSubtle)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(TokensPalette.hairline, lineWidth: TokensHair.border)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(r.unit.map { "\(r.key) \(r.value) \($0)" } ?? "\(r.key) \(r.value)"))
    }
}
