import SwiftUI

// =============================================================================
//  HomeModeHead —— 底部大卡（设计 02）的「大字主角」摘要头
// =============================================================================
//
//  02 的身份不是配色，是**一行巨字**：进到任何一档，先给一个事实，
//  再给依据。没有这个头，九个档位只是「把九张整页塞进同一个卡片」——
//  卡片的外壳统一了，但每张脸还是原来那张。
//
//  三条自我约束：
//    ① 数字一律来自已有的 ViewModel（`VM.*`），页面里**不重算** ——
//       同一件事两处各算一次，就会出现两个答案。
//    ② 取不到就照实说（"还没有体检记录"），不摆 `--` 占位冒充数据。
//    ③ 「现在」那一档没有头：那张纸本身就是地图的面板（车名 + 地址 + 状态行），
//       再叠一个巨字就是两层标题。
struct HomeModeHead: View {
    let mode: HomeMode

    private let store = AppStore.shared

    /// 巨字 + 一行说明。`size` 分两档：54 给「一个数」，44 给「一段字」
    /// （车名 / 昵称这种长度不定的，用大字号会换行）。
    private struct Hero {
        let value: String
        var unit: String? = nil
        var caption: String? = nil
        var size: CGFloat = 54
        var tint: Color = TokensPalette.primary
    }

    /// 巨字下面的依据行
    private struct Fact {
        let key: String
        let value: String
        var cls: String = "na"
    }

    var body: some View {
        if mode == .now {
            // 见文件头第 ③ 条
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: TokensSpacing.sm) {
                DSBigNumber(value: hero.value, unit: hero.unit,
                            caption: hero.caption, size: hero.size, tint: hero.tint)
                if !facts.isEmpty {
                    VStack(spacing: TokensSpacing.sm) {
                        ForEach(Array(facts.enumerated()), id: \.offset) { _, f in
                            DSKeyValueRow(key: f.key, value: f.value, valueCls: f.cls)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
        }
    }

    // MARK: - 巨字

    @MainActor
    private var hero: Hero {
        switch mode {
        case .now:
            return Hero(value: "--")
        case .vehicle:
            let s = VM.vehicleSummary(store.car, store.controlCache)
            // 里程只写在车控报文里（getMyCars 的 totalOdometer 恒为 null），
            // 所以「取不到里程」是常见状态，此时主角换成车牌 —— 不摆假的数字。
            if let km = s?.mileage {
                return Hero(value: "\(km)", unit: "km",
                            caption: Self.line([s?.plate, s?.model]))
            }
            return Hero(value: s?.plate ?? "--", caption: "里程还没上报",
                        size: 44, tint: TokensPalette.secondary)
        case .charge:
            let e = VM.energy(store.caches, store.car)
            return Hero(value: "\(e.socPct)", unit: "%",
                        caption: Self.line([e.range.isEmpty ? nil : "续航 \(e.range)", e.carName]))
        case .control:
            let c = VM.comfortStatus(store.caches)
            return Hero(value: c.cabinTemp, unit: "°C",
                        caption: Self.line(["空调 \(c.acText)"]))
        case .trips:
            let today = store.tripHistory.filter { Calendar.current.isDateInToday($0.startTime) }
            let km = today.reduce(0.0) { $0 + $1.distanceKm }
            return Hero(value: String(format: "%.1f", km), unit: "km",
                        caption: today.isEmpty ? "今天还没有行程" : "今天 · \(today.count) 段")
        case .mine:
            let plate = VM.vehicleSummary(store.car, store.controlCache)?.plate
            if let u = VM.userModel(store.user) {
                let name = u.nickname.isEmpty ? u.name : u.nickname
                return Hero(value: name.isEmpty ? "--" : name,
                            caption: Self.line([plate, u.mobile]), size: 44)
            }
            return Hero(value: "--", caption: "还没取到账号信息", size: 44, tint: TokensPalette.secondary)
        }
    }

    // MARK: - 依据行

    @MainActor
    private var facts: [Fact] {
        switch mode {
        case .now:
            return []
        case .vehicle:
            guard let s = VM.vehicleSummary(store.car, store.controlCache) else { return [] }
            return [
                Fact(key: "车牌", value: s.plate),
                Fact(key: "车架号", value: s.vin.isEmpty ? "未登记" : s.vin),
                Fact(key: "保险", value: Self.line([s.insuranceEnd,
                                                    s.insuranceDays.map { "\($0) 天后" }]))
            ]
        case .charge:
            let e = VM.energy(store.caches, store.car)
            return [
                Fact(key: "充电", value: e.chargeText, cls: e.chargeCls),
                Fact(key: "电压电流", value: e.voltAmp),
                Fact(key: "电池温度", value: e.battTemp)
            ]
        case .control:
            // 车锁 / 车窗 / 后备箱这类「开还是关」的事实：直接用车况芯片，
            // 它们本来就是从 `control` 报文里读出来的同一批值。
            return VM.bodyStatus(store.caches).prefix(3).map {
                Fact(key: $0.label, value: $0.text, cls: $0.cls)
            }
        case .trips:
            return store.tripHistory.prefix(3).map { t in
                Fact(key: t.startTime.formatted(date: .abbreviated, time: .shortened),
                     value: String(format: "%.1f km", t.distanceKm))
            }
        case .mine:
            let u = VM.userModel(store.user)
            let authed = u?.authed == true
            return [
                Fact(key: "实名认证", value: authed ? "已认证" : "未认证",
                     cls: authed ? "ok" : "warn"),
                Fact(key: "车辆", value: "\(store.cars.count) 辆"),
                Fact(key: "上次登录", value: Self.line([u?.lastLoginTime, nil]))
            ]
        }
    }

    /// 把若干片段拼成一行：空段与 `--` 直接丢掉，不摆占位符（全站统一的做法）。
    private static func line(_ parts: [String?]) -> String {
        parts.compactMap { $0 }
            .filter { !$0.isEmpty && $0 != "--" }
            .joined(separator: " · ")
    }
}
