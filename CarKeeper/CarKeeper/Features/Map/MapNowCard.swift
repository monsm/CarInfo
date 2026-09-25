import SwiftUI

// =============================================================================
//  MapSpineView · 「现在」那张卡里的三个数（地址 / 巨字续航 / 副行 / 光带）
// =============================================================================
//
//  与 `MapSpineReadouts.swift`、`MapQuickButtons.swift` 同一个理由 —— 关切不同：
//  `MapSpineView` 管这一屏的骨架（六页同屏、底条、镜头、图层、手势），这里只回答
//  「卡里那三个数怎么排、取不到时写什么」。
//
//  另一条理由更实际：`scan/lintcfg.py` 的 `file_length` 盯着最大那个文件。2026-09-25
//  这一轮加了两枚快速钮、手机位置的点与抽屉的三段状态之后，骨架那一份涨到 1211 行
//  （阈值 1200）。搬出来的是**一件独立的事**（三个数的排版），界面一字未改。
//
//  注：下面用到的 `spec`（艺术方向落成的地图规格）与 `store` 因此**不是 `private`** ——
//  `private` 的作用域是**文件**，跨文件看不见。它们在骨架里的注释写明了为什么。
// =============================================================================

extension MapSpineView {

    /// 现状卡的读数：地址 → 巨字续航 → 副行 → 光带。
    @ViewBuilder
    func nowMetrics(_ d: MapSpineData) -> some View {
        if !d.address.isEmpty {
            Text(d.address)
                .font(TokensSerif.title(22))
                .tracking(TokensTracking.title)
                .foregroundStyle(TokensPalette.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        if d.rangeText == "--" {
            // 车没报续航就**不摆「-- km」** —— 那是一个假的读数
            GlassCardEmpty(text: "还没收到剩余续航", icon: "bolt.slash")
        } else {
            DSBigNumber(value: d.rangeText, unit: "km", caption: "续航", size: 56,
                        tint: TokensPalette.primary)
        }
        nowSub(d)
        // 光带 = 电量（全 App 唯一的形状，在地图上它是「车钉外面那圈弧」的展开）
        DSLightBar(progress: Double(d.socPct) / 100,
                   height: 5,
                   showsGlow: spec.allowsGlow,
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
