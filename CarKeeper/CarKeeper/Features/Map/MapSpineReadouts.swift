import SwiftUI

// =============================================================================
//  MapSpineView · 「现在」这一档里的读数（默认一排：电量 / 车速；抽屉里：胎压 / 车锁 / 充满）
// =============================================================================
//
//  与 `MapSpineLayers.swift` 同一个理由 —— 关切不同：`MapSpineView` 管这一屏的
//  骨架（六页同屏、底条、车牌徽标、底部浮动两卡），这里只回答一件事：
//  「一瞥的那四个数从哪来、取不到时写什么」。
//
//  另一条理由更实际：`scan/lintcfg.py` 的 `file_length` 盯着最大那个文件。
//  2026-09-24 骨架那一份涨到 1206 行（阈值 1200），差 6 行就红 ——
//  这一轮拆完约 1112 行。不选「把阈值抬到刚够」：贴着阈值的代价是下一次**任何**
//  小改动都要先做一遍取舍，而 `MapSpineLayers.swift` 的头注里已经写过一次这个账
//  （它当时也是从贴着阈值拆出来的）。
//
//  注：下面用到的 `store` 因此**不是 `private`** —— `private` 的作用域是文件，
//  跨文件看不见。它在骨架里的注释写明了为什么。
// =============================================================================

extension MapSpineView {
    // ---- 四格读数 ----
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
    /// 默认那一排与抽屉里那一排都是它 —— 两处形状一模一样，所以「拉开抽屉」看起来是
    /// 「下面又长出一排」，而不是「换了一套排版」。
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

    /// 抽屉里那几格（默认收起来的那一半）。顺序 = 关心的顺序：胎压 → 车锁 → 还要充多久。
    ///
    /// 取不到的那一格**照实说「无数据」**：不摆 `--`、也不拿别的数顶上（全站同一条）。
    /// 「还要充多久」只在充电时存在（`timeToFull` 为 nil 就是没有这件事），
    /// 所以它不占一格 —— 没在充电时抽屉里只有胎压与车锁，而不是一格空着。
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

    // =========================================================================
    // MARK: 「更多读数」抽屉
    // =========================================================================

    /// 那道拉手 + 收在它后面的几格读数（用户 2026-09-25：「地图页数据用抽屉的方式
    /// 展示，默认只有续航 电量 车速，其他数据均通过拉开抽屉展示」）。
    ///
    /// HIG 把这件事叫**渐进披露**（Layout → Visual hierarchy，原话是
    /// “Use progressive disclosure to make layouts cleaner and easier to interact with…
    /// reduce how much content to initially display”）：它的目的不是藏东西，
    /// 而是让「一瞬」与「细看」各自有一个明确的量。
    ///
    /// 拉手既是**按钮**也是**拖动面**：只做拖动会把「想看一眼」变成一次猜手感，
    /// 只做点按又与「拉开抽屉」这个说法不符 —— 两种都给，谁也不会因为不知道怎么用而卡住。
    /// 命中区按 HIG 的最小触控目标给足 44pt（`TokensSpacing.row`），而画出来的把手
    /// 只是一条 3pt 的横线 —— 手感来自可点面积，不来自把它画得更黑。
    ///
    /// 它**不需要** `CardFit` 分块，因为它的展开量被构造限定了：拉手一行（44）+ 最多一排
    /// 读数（胎压/车锁/充满 三格同高同宽），不再有第二种排法 —— 那是比「算出来放得下」
    /// 更强的保证。万一以后滑屉里开始堆行（比如按轮位展开四条胎压），这里要改成
    /// CardFit 那一套（那是目前仓库里唯一的算法，见 `Design/CardFit.swift` 的头注）。
    func moreDrawer(_ d: MapSpineData) -> some View {
        let more = readoutsMore(d)
        return VStack(alignment: .leading, spacing: TokensSpacing.sm) {
            Button {
                TokensHaptic.tap()
                withAnimation(TokensMotion.count) { drawerOpen.toggle() }
            } label: {
                HStack(spacing: TokensSpacing.sm) {
                    Capsule()
                        .fill(TokensPalette.track)
                        .frame(width: 36, height: 3)
                    Text(drawerOpen ? "收起" : "更多读数")
                        .font(TokensTypo.caption2)
                        .foregroundStyle(TokensPalette.tertiary)
                    Spacer(minLength: 0)
                    Image(safeSymbol: drawerOpen ? "chevron.down" : "chevron.up",
                          fallback: "chevron.down")
                        .font(TokensTypo.micro)
                        .foregroundStyle(TokensPalette.tertiary)
                }
                .frame(minHeight: TokensSpacing.row)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(drawerOpen ? "收起更多读数" : "更多读数"))
            .accessibilityHint(Text("胎压、车锁、还要充多久"))
            // 「拉开」也真能拉：向上拖过 12pt 开，向下拖过 12pt 收。
            // 12pt 是手势与点按的分界（小于它一律算点按，与底条那条手势同一个门槛）。
            .simultaneousGesture(
                DragGesture(minimumDistance: 12)
                    .onEnded { v in
                        if v.translation.height < -12, !drawerOpen {
                            TokensHaptic.tap()
                            withAnimation(TokensMotion.count) { drawerOpen = true }
                        } else if v.translation.height > 12, drawerOpen {
                            TokensHaptic.tap()
                            withAnimation(TokensMotion.count) { drawerOpen = false }
                        }
                    }
            )
            // 收起来时**不占高度**（不是「高度 0 但还在」的那种）：
            // 抽屉关着就是一排两格 + 一道拉手，与其他卡一样干净。
            if drawerOpen, !more.isEmpty {
                readoutRow(more)
            }
        }
    }

    /// 一格：上面是键（小字），下面是值（数字体）。各格完全同高同宽 ——
    /// 行里没有一格带额外偏移，所以「一行四个」就是它们的**全部排版**。
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
        // 同宽：`.frame(maxWidth: .infinity)` 让四格平分行宽；
        // 同高：两行文字 + 同一个 9pt 内边距，没有哪一格多一行。
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
