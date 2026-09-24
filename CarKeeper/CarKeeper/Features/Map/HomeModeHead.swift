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
//
//  **它只给一个事实，不给依据行**（用户 2026-09-24：「全部页面检查精致度」）。
//  依据行曾经长在这里：三行键值（车牌 / 车架号 / 保险 之类），而它们逐条又在
//  下面那张卡里再说一遍 —— 车辆档的头写「车牌 / 车架号 / 保险」，紧跟的「身份」
//  卡就是这三样；充电档写「充电 / 电压电流 / 电池温度」，紧跟的「此刻」卡里
//  正好是同一组读数。同一页上同一句话说两遍，读起来就是没做完。
//
//  删掉之后每条事实只剩**一个出处**，而头卡剩下的事说得更清：
//  它是这一页的**标题**（巨字 + 一行小字），依据在下面每一张卡里。
//  `StackCard.title` 也已经写着这一档的名字，所以连「这是什么」都不必再重复。
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

    var body: some View {
        if mode == .now {
            // 见文件头第 ③ 条
            EmptyView()
        } else {
            let h = hero
            DSBigNumber(value: h.value, unit: h.unit,
                        caption: h.caption, size: h.size, tint: h.tint)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
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

    /// 把若干片段拼成一行：空段与 `--` 直接丢掉，不摆占位符（全站统一的做法）。
    private static func line(_ parts: [String?]) -> String {
        parts.compactMap { $0 }
            .filter { !$0.isEmpty && $0 != "--" }
            .joined(separator: " · ")
    }
}
