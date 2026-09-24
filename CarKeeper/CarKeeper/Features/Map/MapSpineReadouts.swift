import SwiftUI

// =============================================================================
//  MapSpineView · 「现在」这一档里的四格读数（车速 / 电量 / 胎压 / 车锁）
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

    func readoutChips(_ d: MapSpineData) -> some View {
        let cells = readouts(d)
        return GlassCard(accent: HomeMode.now.accent) {
            // 四格等分：`readoutCell` 自己 `maxWidth: .infinity`，行里不摆任何偏移。
            HStack(spacing: 9) {
                ForEach(cells) { c in
                    readoutCell(c)
                }
            }
        }
    }

    /// 四格的值。取不到的那一格**照实说「无数据」**：不摆 `--`、也不拿别的数顶上。
    ///
    /// 四格**同一行、同一基线**（用户 2026-09-24：「下面 4 个按钮要规整，不要歪歪扭扭」）。
    /// 原型里有一手 `nth-child(odd){translateY(-7px)}` 的奇偶错位 —— 它是样品期的排版游戏，
    /// 在真机上只会读成「没对齐」，于是这一版明确去掉（`readoutCell` 不再收偏移）。
    @MainActor
    func readouts(_ d: MapSpineData) -> [Readout] {
        let speed = VM.driveStatus(store.caches).speed
        let lock = VM.bodyStatus(store.caches).first { $0.label == "车锁" }
        // 胎压取**最低的那一条**：一格放不下四条，而四轮里最危险的就是它。
        // 「哪一轮低」在「车辆 → 体检」里有完整的一行，这里只做首页的一瞥。
        let lowest = d.tyres.min { (Int($0.kpa) ?? Int.max) < (Int($1.kpa) ?? Int.max) }
        return [
            Readout(id: "speed", key: "车速",
                    value: speed == "--" ? "无数据" : speed,
                    unit: speed == "--" ? nil : "km/h"),
            Readout(id: "soc", key: "电量", value: "\(d.socPct)", unit: "%", cls: d.socCls),
            Readout(id: "tyre", key: "胎压",
                    value: lowest?.kpa ?? "无数据",
                    unit: lowest == nil ? nil : "kPa",
                    cls: lowest?.warn == true ? "bad" : "na"),
            Readout(id: "lock", key: "车锁",
                    value: lock?.text ?? "无数据",
                    cls: lock?.cls ?? "na")
        ]
    }

    /// 一格：上面是键（小字），下面是值（数字体）。四格完全同高同宽 ——
    /// 行里没有一格带额外偏移，所以「一行四个」就是它们的**全部排版**。
    func readoutCell(_ r: Readout) -> some View {
        VStack(spacing: 5) {
            Text(r.key)
                .font(TokensTypo.caption2)
                .foregroundStyle(TokensPalette.tertiary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
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
        .padding(.vertical, 9)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(TokensPalette.fillSubtle)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(TokensPalette.glassBorder, lineWidth: TokensHair.border)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(r.unit.map { "\(r.key) \(r.value) \($0)" } ?? "\(r.key) \(r.value)"))
    }
}
