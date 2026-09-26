// =============================================================================
// TripsEventsView — 出行：两段（行程 / 事件）—— 行程是一张时间轴，每一段都长在地图上，
// 常停之地与评分在它末尾；车的事件是另一段（2026-09-25 从上下两叠改成 tab，见 `cards`）
// =============================================================================
//
// 取代旧 TripAnalyticsView（分段柱状图 + 汇总卡）之后，这一屏回答的问题变了：
//   旧：「这段时间开了多少」→ 一个大数字加一张柱状图
//   新：「我的时间花在哪些路上」→ 时间轴上每段行程配一张真地图，
//       常停的地方聚成圈（与地图主屏同一套聚类，同一个答案）
//
// 数据事实（不美化）：
//   • TripRecord 只有起终点两个坐标 —— 线是连线，不是轨迹；地图窗口框住两地
//   • 没有行程时整屏只有一句真话，不摆 0 km 冒充统计
// =============================================================================

import SwiftUI
import MapKit

/// 出行页一次建几张行程卡（见 `TripsEventsView.shownTrips` 的说明）。
/// 2026-09-25 起它不再是「一次点多少」，而是**滑到底就续多少**（用户第 1 条）。
private let tripCardStep: Int = 5

/// 出行页最多建几张行程卡 —— **30 是用户定的上限**（2026-09-25：
/// 「行程页的最大行程控制在 30 条，其他均以消息显示」）。
///
/// 为什么需要一个上限：每张行程卡里是一张**真的** `MiniTripMap`（See `MiniTripMap`），
/// 而 227 条消息能配出几十段。30 张已经是一次要点开四五次「再放」的量，
/// 再往上加只会把这一页变成「滑动地图墙」。
///
/// 超出的那些**不是丢掉**：点火 / 熄火事件本来就一条条列着
///（`MessagesSection` 读的是同一份消息，现在是本页的另一段），所以本页的规则是
/// **先按行程看最近 30 段，再往前的按事件看** —— 同一份数据，两种读法。
private let tripCardCap: Int = 30

/// 出行 —— 每一次出行的时间轴 + 常停的地方 + 车发来的事件。
///
/// 原为「行程」页（`TripsTimelineView`）。批 7 把「消息」吸收进来：
/// 消息流里的 IGNITION / FLAMEOUT 事件本来就是行程的骨架，两页读的是同一件事。
struct TripsEventsView: View {
    private let store = AppStore.shared
    /// 路线服务。**必须订阅它**（而不是只读缓存）：背面那一行「路线长度」是
    /// 路线到手之后才出现的，而路线到手是一场异步回调 —— 不订阅，那一行要等到
    /// 下一次重绘才显示（见 `RouteService.revision`）。
    @ObservedObject private var routes = RouteService.shared

    /// 一次建几张行程卡 —— **这不是分页，是防处决**。
    ///
    /// 每张行程卡里是一张真的 `Map`（`MiniTripMap`：132pt 高，带折线与两个标点），
    /// 而这一页的卡由 `ArcStack` **一次全建出来**。227 条消息配出来的行程动辄几十段，
    /// 于是「点开出行」等于同时初始化几十个 MapKit 视图与它们各自的资源。
    ///
    /// 真机轨迹（2026-09-24 第五轮）：0.97s 消息到手 → 2.01s 673 MB →
    /// 4.01s 1720 MB → 5.3s 被系统收走；而同一份数据在**其他档一点事都没有**
    /// （主屏上也有一张地图，但它只有一张）。用户的原话就是「点到出行界面就闪退」。
    @State private var shownTrips = tripCardStep

    /// 事件那一段一次画几天。**它在这里而不在 `MessagesSection` 里**：
    /// 用户 2026-09-26「事件也采用懒加载」之后，续的那个动作发生在**这一叠**上
    /// （`ArcStack.onReachBottom` → `loadMoreEventDays`），而消息那一节只负责裁。
    /// 3 与行程那一叠的步长同一个量级：一屏大约就是这么几天。
    @State private var eventDays = 3

    /// 当前翻到背面的那一段（键是它的 `startTime`，理由见 `tripFlip`）。
    /// `nil` = 没有一张是翻过来的 —— 一开始是这个状态，面且**只有一张**能翻：
    /// 它是“我正在看这一段”的标记，不是每一张自己的开关。
    @State private var flippedTrip: Double? = nil

    /// 档内段落：行程 / 事件。
    ///
    /// 用 `HomeSub`（车辆档那三段用的是同一个枚举）而不是另写一个局部枚举：
    /// 「档内段落」这件事只能有一份词汇（同一个事实一个出处）。
    /// 它是 `@State` 而不是持久化的键：段落是一次**看法的选择**，不是「当前位置」——
    /// 后者是 `HomeMode`（它有 `storageKey`）。所以离开出行页再回来，它回到「行程」。
    @State private var tab: HomeSub = .journeys

    private var trips: [AppStore.TripRecord] {
        store.tripHistory.sorted { $0.startTime > $1.startTime }
    }

    private var hotspots: [MapHotspot] {
        MapSpineData.clusterHotspots(from: store.parkingHistory, excluding: store.parkingLocation)
    }

    /// 从消息缓存里的 IGNITION / FLAMEOUT 事件直接配成行程（不等 ingestEvents）。
    /// 数据源与 `store.tripHistory` 是**同一件事**，但这里多一个好处：
    /// 消息一拉到手就能渲染，不依赖 `fetchVehicleData()` 的触发时机。
    private var tripsFromMessages: [AppStore.TripRecord] {
        let raw = store.caches["messages"] as? [[String: Any]] ?? []
        guard !raw.isEmpty else { return [] }
        // 复用 AppStore 里已有的现成方法：跳去、配对、写进 tripHistory
        // —— 不行，那会改全局状态。这里只做「展示用」的临时配对，不写。
        let events: [(ignition: Bool, at: Date, loc: CLLocationCoordinate2D?, addr: String)] = raw
            .compactMap { m -> (Bool, Date, CLLocationCoordinate2D?, String)? in
                guard let kind = ciString(m, ["InfoTypeId", "infoTypeId"])?.uppercased(),
                      kind == "IGNITION" || kind == "FLAMEOUT" else { return nil }
                let p = AppStore.jumpParams(m)
                let fallbackAt = VM.serverDate(ciPick(m, ["CreatedAt", "createdAt"]))
                guard let at = VM.serverDate(p["gpsTime"]) ?? fallbackAt else { return nil }
                var loc: CLLocationCoordinate2D?
                if let lat = VM.vnum(p["lat"]), let lng = VM.vnum(p["lng"]) {
                    loc = CLLocationCoordinate2D(latitude: lat, longitude: lng)
                }
                let addr = (p["addrName"] as? String) ?? ""
                return (kind == "IGNITION", at, loc, addr)
            }
            .sorted { $0.at < $1.at }

        // 点火 → 下一个熄火 = 一段行程（里程差 = 两点直线距离，只有 GPS 时才真）
        var out: [AppStore.TripRecord] = []
        var open: (ignitionAt: Date, ignitionLoc: CLLocationCoordinate2D?, ignitionAddr: String)?
        for e in events {
            if e.ignition {
                open = (e.at, e.loc, e.addr)
            } else if let o = open {
                let dist: Double = {
                    guard let a = o.ignitionLoc, let b = e.loc else { return 0 }
                    let m1 = CLLocation(latitude: a.latitude, longitude: a.longitude)
                    let m2 = CLLocation(latitude: b.latitude, longitude: b.longitude)
                    return m1.distance(from: m2) / 1000
                }()
                out.append(AppStore.TripRecord(
                    startTime: o.ignitionAt, endTime: e.at,
                    startLocation: o.ignitionLoc.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) },
                    endLocation: e.loc.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) },
                    distanceKm: dist,
                    startSoc: 0, endSoc: 0,
                    avgEfficiency: nil, kmPerPercent: nil,
                    // 位置名就是这两条事件各自的 `addrName`（见 `TripRecord.startAddr`）——
                    // 配对时手里本来就有，没有任何一步是反查。
                    startAddr: o.ignitionAddr, endAddr: e.addr))
                open = nil
            }
        }
        // 只有点着火还没熄火的：也展示（进行中的一段）
        if let o = open {
            out.append(AppStore.TripRecord(
                startTime: o.ignitionAt, endTime: nil,
                startLocation: o.ignitionLoc.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) },
                endLocation: nil,
                distanceKm: 0,
                startSoc: 0, endSoc: 0,
                avgEfficiency: nil, kmPerPercent: nil))
        }
        return out
    }

    /// 展示用的行程：两个来源**合并**。
    ///
    /// 为什么必须合并而不是「本机非空就只看本机」：历史事件被 `ingestEvents`
    /// 事后配对时，点火/熄火的里程都是**今天的读数**，差值恒为 0 —— 只看本机的
    /// 话，用户看到的全是 0 km 行程，真正有意义的距离（GPS 直线）反被压住。
    /// 用户 2026-09-23 报的第 4 条（「行程根据历史消息配对看不到」）病根就在这。
    ///
    /// 规则：**每个时刻只留一条**（按 `startTime` 对齐）；有里程的那条赢，
    /// 两条都是 0 就留本机的（它带 `kmPerPercent` 等更多字段）。
    /// **位置名从落选的那条补上**（2026-09-26）：一边有里程、另一边有地址是常态
    ///（本机那条从读数算里程，消息那条带 `addrName`）—— 少了这一步，
    /// 「合并」恰好会把唯一存在的那两个名字丢掉，而它们是同一段行程的事实。
    /// 展示序：有里程的在前、全是 0 的在后；各按时间倒序（最近的在上面）。
    private var displayTrips: [AppStore.TripRecord] {
        let m = tripsFromMessages
        guard !m.isEmpty else { return trips }
        var byStart: [Date: AppStore.TripRecord] = [:]
        for t in m { byStart[t.startTime] = t }
        for t in trips {
            guard let cand = byStart[t.startTime] else {
                byStart[t.startTime] = t
                continue
            }
            var winner: AppStore.TripRecord
            var loser: AppStore.TripRecord
            if t.distanceKm > 0 && cand.distanceKm <= 0 { winner = t; loser = cand }
            else { winner = cand; loser = t }
            if winner.startAddr.isEmpty { winner.startAddr = loser.startAddr }
            if winner.endAddr.isEmpty { winner.endAddr = loser.endAddr }
            byStart[t.startTime] = winner
        }
        let all = Array(byStart.values)
        return all.filter { $0.distanceKm > 0 }
            .sorted { $0.startTime > $1.startTime }
            + all.filter { $0.distanceKm == 0 }
                .sorted { $0.startTime > $1.startTime }
    }

    /// 往下滑就续这一段 —— 懒加载的**唯一**动作。
    ///
    /// 2026-09-25（用户第 1 条：「行程卡片采用懒加载，而不是需要人点加载 N 条」）：
    /// 原来这里是一个 `DSRow` 按钮（「再放 5 段出来」）。改成自动续的理由不是“少一步”：
    /// 往下滑这个动作**本身就是**「我还要看」的证据，按钮只是把同一个意图多问了一遍；
    /// 而那个按钮还有一个更差的后果 —— 不点就永远看不到（列表看起来就到此为止了）。
    ///
    /// 上限仍然由人定（`tripCardCap` = 30，用户 2026-09-25：「最大行程控制在 30 条」）：
    /// 到 30 就不再续，剩下的在「事件」那一段里按时间列着（见 `restAsMessagesRow`）。
    /// 夹在上限里而不是「过了上限就不再变」：真正的夹取只有这一处，
    /// 所以「续多少」不可能算出 35。
    private func loadMoreTrips() {
        guard shownTrips < tripCardCap else { return }
        shownTrips = min(shownTrips + tripCardStep, tripCardCap)
    }

    /// 还没显示完时的一句话。**它不是按钮**（按钮已经跟着第 1 条删了），
    /// 而它必须说清楚剩下的怎么才会出来 —— 否则那几段对用户来说等于不存在。
    private func moreTripsNote(_ rest: Int) -> some View {
        HStack(spacing: TokensSpacing.sm) {
            Image(safeSymbol: "arrow.down.circle", fallback: "arrow.down.circle")
                .font(TokensTypo.footnote)
                .foregroundStyle(TokensPalette.tertiary)
            Text("往下滑，剩下的 \(rest) 段接着出来")
                .font(TokensTypo.footnote)
                .foregroundStyle(TokensPalette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 到上限之后那一行：**不是按钮**，是一句交代。
    ///
    /// 它必须是陈述句而不是灰色的按钮 —— 「按了没反应」与「这里没有可按的东西」
    /// 是两件事，而用户只会把它读成前者。
    private func restAsMessagesRow(_ rest: Int) -> some View {
        VStack(alignment: .leading, spacing: TokensSpacing.xs) {
            //  它此前写的是「在下面『车的事件』里」—— 而车的事件现在是**另一段**（tab），
            //  不在下面。指示的是位置，位置换了，指示也得分着换。
            Text("再往前的 \(rest) 段在「事件」那一段里，按时间列着。")
                .font(TokensTypo.footnote)
                .foregroundStyle(TokensPalette.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("每一段在这里都会占一张地图，所以封顶 30 段。")
                .font(TokensTypo.caption)
                .foregroundStyle(TokensPalette.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 这一档的叠叠乐：巨字头 → 分段控件（行程 / 事件）→ 当前那一段的卡。
    ///
    /// **为什么分成两段**（用户 2026-09-25：「出行里面行程卡和消息列表的上下布局改为 tab 页」）：
    /// 它们此前是同一叠里一上一下两张卡，而中间还夹着常停之地与评分 ——
    /// 想看一眼车的事件要滑过 30 张地图卡。同一份数据（消息流里的点火 / 熄火配成行程）
    /// 的两种读法不该是一条长卷，而是两段。
    ///
    /// 分段控件的**做法照车辆档**（档案 / 健康 / 保养）：巨字头与分段控件停在原地
    ///（它们是同一张卡），换段时下面那一叠只换一个成员 —— 看起来是「那张卡换了」，
    /// 而不是「又翻了一页」。
    ///
    /// 常停之地与评分留在「行程」那一段里：它们是行程的另两个读数（聚类按停车点、
    /// 评分按电耗，都由同一份行程算出来），不是第三种读法。
    @MainActor
    private var cards: [StackCard] {
        var out = HomeMode.trips.headCards
        out.append(StackCard(id: "tabs", content: AnyView(
            DSSegmentPicker(options: HomeSub.tripsTabs.map { (value: $0, title: $0.title) },
                            selection: $tab,
                            label: "段落"))))
        switch tab {
        case .events:
            // 车的事件：点火 / 熄火 / 控制记录（原「消息」页）。
            // 它单独占一段：这一条流是**按时间列的消息**，与下面那叠地图卡是两种排版，
            // 混在一起时两边都不好看（用户看到的正是那一幕）。
            //  这里的 `shownDays` 是绑定：续由「滑到底」触发（见 `eventDays`）。
            out.append(StackCard(id: "events", title: "车的事件",
                                 content: AnyView(MessagesSection(shownDays: $eventDays))))
        default:
            out.append(contentsOf: journeyCards)
        }
        return out
    }

    /// 「行程」那一段的卡（**不含巨字头与分段控件** —— 那两张在 `cards` 里）。
    ///
    /// **行程本身是「一组组」的** ——
    /// 每一段行程单独占一张玻璃卡，而不是一张长列表：上下滑过的是一程一程，
    /// 每程自己一个可读的块（这正是「行程叠叠乐」想要的速度感）。
    @MainActor
    private var journeyCards: [StackCard] {
        var out: [StackCard] = []
        let list = displayTrips
        // 只把最近的一段交给界面去建（见 `shownTrips`）。汇总仍用整份 list ——
        // 数字要是全部的，卡片才是按需的。
        let visible = Array(list.prefix(min(shownTrips, tripCardCap)))
        if list.isEmpty {
            out.append(StackCard(id: "empty", content: AnyView(emptyState)))
        } else {
            // 时间戳跟「消息」那个源：行程是从点火/熄火事件配出来的，
            // 所以「这份汇总是什么时候的」等于「消息最后一次到手是什么时候」。
            out.append(StackCard(id: "summary", title: "总览",
                                 at: store.cacheTime("messages"),
                                 content: AnyView(summaryHeader(list))))
            for (idx, trip) in visible.enumerated() {
                // 时间轴那根竖线只在这一段确实是最后一段（没有更多行程藏着）时才断。
                let isLast = idx == visible.count - 1 && visible.count == list.count
                out.append(StackCard(id: "trip-\(idx)", title: "行程",
                                     value: String(format: "%.1f km", trip.distanceKm), cls: "ok",
                                     content: AnyView(timelineRow(trip, isLast: isLast))))
            }
            // 没到上限：一句话说清「接着往下滑就出来」（真正的续在 `loadMoreTrips`，
            // 由 `ArcStack.onReachBottom` 那个滚动位置信号触发）。
            // 到了上限：同一件事改成另一句陈述，而剩下的那些在「事件」那一段里仍然读得到。
            if visible.count < min(list.count, tripCardCap) {
                let rest = min(list.count, tripCardCap) - visible.count
                out.append(StackCard(id: "more-trips", title: "还有 \(rest) 段",
                                     content: AnyView(moreTripsNote(rest))))
            } else if list.count > tripCardCap {
                out.append(StackCard(id: "rest-as-messages", title: "更早的 \(list.count - tripCardCap) 段",
                                     content: AnyView(restAsMessagesRow(list.count - tripCardCap))))
            }
            if !hotspots.isEmpty {
                out.append(StackCard(id: "hotspots", title: "常停之地",
                                     content: AnyView(hotspotsBand(hotspots))))
            }
        }
        // 分数：完全由上面那些行程的电耗算出来（原「驾驶评分」页）
        out.append(StackCard(id: "score", title: "评分", content: AnyView(ScoreSection())))
        return out
    }

    /// 滑到底要不要继续放东西出来 —— **两段都有**。
    ///
    ///  用户第 1 条（2026-09-25）先给行程要了它；2026-09-26 又给事件要了一次
    ///  （「事件也采用懒加载」）。于是它不再是一个只属于行程的回调：
    ///  按当前那一段分派到各自的「再放一点」——两段都是**只看滚动位置**，
    ///  不需要谁去按一下（`ArcStack` 只在「从不到底 → 到底」那一刻叫一次）。
    private var reachBottom: (() -> Void)? {
        tab == .journeys ? { loadMoreTrips() } : { loadMoreEventDays() }
    }

    /// 事件那一段的「再放一点」：多画几天。
    /// 封顶交给数据自己（`filteredGrouped` 有多少天就画多少天）——
    /// 一天里能有几十条消息，而天数是**服务端那 7 天窗口**决定的。
    private func loadMoreEventDays() {
        eventDays += 3
    }

    var body: some View {
        // 出行有两段（行程 / 事件），见 `cards`。
        StackPageView(accent: HomeMode.trips.accent, label: "出行", cards: cards,
                      onReachBottom: reachBottom)
        .dsPageTitle("出行")
        .accessibilityLabel(Text("出行"))
    }

    // ---- 空态：一句真话，不放假统计 ----
    private var emptyState: some View {
        VStack(spacing: TokensSpacing.md) {
            Image(safeSymbol: "point.topleft.down.to.point.bottomright.curvepath",
                            fallback: "point.topleft.down.to.point.bottomright.curvepath")
                .font(TokensTypo.fixed(34, weight: .light))
                .foregroundStyle(TokensPalette.tertiary)
            Text("还没有行程记录")
                .font(TokensTypo.headline)
                .foregroundStyle(TokensPalette.primary)
            // 这里原来第二行是「还没有出行记录」—— 与上一行的「还没有行程记录」
            // 是同一句话（`copy.py` 拦的正是这种）。第二行改成**为什么**会有记录。
            Text("点火与熄火各记一次，配成一段行程。")
                .font(TokensTypo.footnote)
                .foregroundStyle(TokensPalette.secondary)
                .multilineTextAlignment(.center)
        }
        // 不再吃掉整屏高度：它后面还有「评分」这一张卡
        .frame(maxWidth: .infinity)
        .padding(.vertical, TokensSpacing.xxl)
    }

    private func summaryHeader(_ trips: [AppStore.TripRecord]) -> some View {
        let totalKm = trips.reduce(0) { $0 + $1.distanceKm }
        let effs = trips.compactMap(\.avgEfficiency)
        let avgEff = effs.isEmpty ? nil : effs.reduce(0, +) / Double(effs.count)
        return VStack(alignment: .leading, spacing: TokensSpacing.xs) {
            Text("全部 \(trips.count) 段行程")
                .font(TokensTypo.footnote)
                .foregroundStyle(TokensPalette.secondary)
            HStack(alignment: .firstTextBaseline, spacing: TokensSpacing.sm) {
                Text(String(format: "%.0f", totalKm))
                    .font(TokensTypo.digits(56))
                    .foregroundStyle(TokensPalette.primary)
                Text("km 合计")
                    .font(TokensTypo.footnote)
                    .foregroundStyle(TokensPalette.tertiary)
                Spacer(minLength: 0)
                if let eff = avgEff {
                    Text(String(format: "均耗 %.1f", eff))
                        .font(TokensTypo.digits(15))
                        .foregroundStyle(TokensPalette.secondary)
                }
            }
        }
        .padding(.bottom, TokensSpacing.lg)
    }

    private func timelineRow(_ trip: AppStore.TripRecord, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: TokensSpacing.md) {
            // 时间轴轴线：圆点 + 向下延伸的发丝线
            VStack(spacing: 0) {
                Circle()
                    .fill(TokensPalette.accent)
                    .frame(width: 9, height: 9)
                if !isLast {
                    Rectangle()
                        .fill(TokensPalette.hairline)
                        .frame(width: 1.5)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 9)

            tripFlip(trip)
        }
        .padding(.bottom, TokensSpacing.xl)
    }

    /// 一段行程：**点一下翻到背面**（用户第 1 条：「点击行程卡片可反转看详情」）。
    ///
    /// 两件实现细节，都不是风格选择：
    ///   · 两面**始终**都在视图树里（只是不透明的那一面看得见）—— 否则背面是在
    ///     点击那一刻才被建出来的，“翻过来”就没有起点可动；
    ///   · 翻的是**这一张**（`flippedTrip` 记的是行程的 `startTime`）。
    ///     不能用 `TripRecord.id`：那个 `id` 是 `let id = UUID()`，而这个数组
    ///     每次求值都重建（`displayTrips` 现算），于是每一个 UUID 都是新的 ——
    ///     用它当键的话，任何一次重绘都会把翻面状态弄丢。`startTime` 是这段行程
    ///     唯一稳定的身份（合并两个数据源时用的就是它）。
    @ViewBuilder
    private func tripFlip(_ trip: AppStore.TripRecord) -> some View {
        let key = trip.startTime.timeIntervalSince1970
        let flipped = flippedTrip == key
        //  两面**不是 `ZStack` 的两个兄弟**（用户 2026-09-25：「行程卡片的高度没有被地图
        //  占满 才一半」）。`ZStack` 会取两个孩子的**最大值**当自己的高度，而背面比正面高
        //  一大截（背面是 6–9 行读数，正面是「头 + 地图 + 一行数字」）—— 于是正面被裁在
        //  上半截、下半截空着，看起来就是「地图只占了一半」。
        //  换成 `overlay`：**背面定高度、正面铺在它上面**（overlay 拿到的是被覆盖那一层的
        //  尺寸）。正面里那张地图因此可以取弹性高度 —— 多出来的高度**归地图**，
        //  而不是归一片空白。
        tripBack(trip)
            .opacity(flipped ? 1 : 0)
            .rotation3DEffect(.degrees(flipped ? 0 : -180), axis: (x: 0, y: 1, z: 0))
            .overlay {
                tripFront(trip)
                    .opacity(flipped ? 0 : 1)
                    .rotation3DEffect(.degrees(flipped ? 180 : 0), axis: (x: 0, y: 1, z: 0))
            }
        .contentShape(Rectangle())
        .onTapGesture {
            TokensHaptic.tap()
            withAnimation(TokensMotion.value) { flippedTrip = flipped ? nil : key }
        }
        .accessibilityElement(children: .contain)
        .accessibilityHint(Text("点一下翻到背面看详情"))
        .accessibilityAction { flippedTrip = flipped ? nil : key }
    }

    /// 正面：地图 + 三个数（就是原来那一版，只是多了一个“可以翻”的提示）。
    ///
    /// 地图的高度**是弹性的**（`minHeight: 132` 是它的下限，也就是「这一段没有坐标」
    /// 那种空面最矮的样子）：这一面铺在背面之上，多出来的高度全给地图。
    private func tripFront(_ trip: AppStore.TripRecord) -> some View {
        VStack(alignment: .leading, spacing: TokensSpacing.sm) {
            headerText(trip)
            MiniTripMap(from: trip.startLocation?.coordinate, to: trip.endLocation?.coordinate)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 132, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: TokensRadius.medium, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: TokensRadius.medium, style: .continuous)
                        .strokeBorder(TokensPalette.hairline, lineWidth: 0.5)
                )
            placeNamesRow(trip)
            statsRow(trip)
        }
        // 头贴顶、数字贴底，中间那一段归地图（`alignment: .top` 写在里面就没这个效果了）。
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// 从哪到哪 —— **位置名**（用户 2026-09-26：「行程页 去掉电量，显示起点和终点位置名」）。
    ///
    /// 它取代的正是正面原来那颗「5% 电量」：正面回答的问题是「这段路从哪到哪」，
    /// 而电量是背面那一行读数的事（那一行也一起删了 —— 用户要求「去掉电量」）。
    /// 名字来自点火 / 熄火两条事件各自的 `addrName`（见 `TripRecord.startAddr`）。
    ///
    /// ⚠️ **两个名字都没有时这一行整个不出现**，不画一个空箭头：
    /// 「取不到名字」与「这段没有起终点」在界面上必须是同一个样子，
    /// 摆一行 `→` 只会让人以为两地之间有个位置。
    @ViewBuilder
    private func placeNamesRow(_ trip: AppStore.TripRecord) -> some View {
        if !trip.startAddr.isEmpty || !trip.endAddr.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: TokensSpacing.xs) {
                Text(trip.startAddr.isEmpty ? "起点未知" : trip.startAddr)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(safeSymbol: "arrow.right", fallback: "arrow.right")
                    .font(TokensTypo.caption2)
                    .foregroundStyle(TokensPalette.tertiary)
                Text(trip.endAddr.isEmpty ? "终点未知" : trip.endAddr)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .font(TokensTypo.caption)
            .foregroundStyle(TokensPalette.secondary)
        }
    }

    /// 背面：这一段的其余事实（都是这一段行程自己的读数，没有新数据源）。
    ///
    /// 它为什么值得存在：正面那张地图回答的是「从哪到哪」，而「开了多久、掉了几格电、
    /// 每格电跑多远」在这张卡里原来**没有地方放** —— 摆到正面就是把卡片变成表格。
    private func tripBack(_ trip: AppStore.TripRecord) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            headerText(trip)
            DSDivider()
            DSKeyValueRow(key: "出发", value: trip.startTime.formatted(date: .omitted, time: .shortened))
            DSDivider()
            DSKeyValueRow(key: "到达",
                          value: trip.endTime.map { $0.formatted(date: .omitted, time: .shortened) }
                                 ?? "还没熄火")
            DSDivider()
            DSKeyValueRow(key: "时长", value: trip.durationText)
            DSDivider()
            DSKeyValueRow(key: "两点直线", value: String(format: "%.1f km", trip.distanceKm))
            // 真正沿着路走出来的长度。它要有求到路线才出现（`RouteService` 的缓存）——
            // 求不到就不摆一行「--」：那个数此刻不存在，摆占位就是装。
            if let road = roadRoute(trip) {
                DSDivider()
                DSKeyValueRow(key: "路线长度",
                              value: String(format: "%.1f km", road.distanceMeters / 1000))
            }
            // 「电量 60% → 55%」那一行已删（用户 2026-09-26：「行程页 去掉电量，
            // 显示起点和终点位置名」）。它替掉的这两行回答的是背面这张表本来的问题
            //（这一段从哪到哪），而 SoC 的差值在充电页有更完整的说法。
            // 缺名字时不摆一行「--」：那个名字此刻不存在（同 `roadRoute` 那一段的规矩）。
            if !trip.startAddr.isEmpty {
                DSDivider()
                DSKeyValueRow(key: "起点", value: trip.startAddr)
            }
            if !trip.endAddr.isEmpty {
                DSDivider()
                DSKeyValueRow(key: "终点", value: trip.endAddr)
            }
            if let kmPerPct = trip.kmPerPercent {
                DSDivider()
                DSKeyValueRow(key: "每 1% 电量", value: String(format: "%.2f km", kmPerPct))
            }
            if let eff = trip.avgEfficiency {
                DSDivider()
                DSKeyValueRow(key: "平均能耗", value: String(format: "%.1f kWh/100km", eff))
            }
        }
    }

    private func headerText(_ trip: AppStore.TripRecord) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(dayText(trip.startTime))
                .font(TokensTypo.subheadline)
                .foregroundStyle(TokensPalette.primary)
            Spacer(minLength: 0)
            Text(trip.durationText)
                .font(TokensTypo.caption)
                .foregroundStyle(TokensPalette.tertiary)
        }
    }

    private func dayText(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "今天 " + date.formatted(date: .omitted, time: .shortened) }
        if cal.isDateInYesterday(date) { return "昨天 " + date.formatted(date: .omitted, time: .shortened) }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private func statsRow(_ trip: AppStore.TripRecord) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: TokensSpacing.md) {
            Text(String(format: "%.1f km", trip.distanceKm))
                .font(TokensTypo.digits(17))
                .foregroundStyle(TokensPalette.primary)
            //  这一个字是用户第 1 条里那句「且是俩点直线距离」的直接回答：
            //  行程记录里只有起终两个坐标（`TripRecord` 没有轨迹点），所以这个数
            //  **本来就是直线** —— 之前它只写「3.2 km」，看起来像车真开了 3.2 公里。
            //  现在把它标出来，而真正的道路长度在背面（`tripBack`）。
            Text("直线")
                .font(TokensTypo.caption2)
                .foregroundStyle(TokensPalette.tertiary)
            // 这里原来是「5% 电量」（`startSoc - endSoc`）。用户 2026-09-26：
            // 「行程页 去掉电量，显示起点和终点位置名」—— 两颗数换成一行名字
            //（在 `tripFront` 里、地图正下方：起点与终点本来就该贴着那张图）。
            Spacer(minLength: 0)
            // 能效只显示**算得出来**的那个：kWh/100km 需要电池容量（报文里 capacity 是 null），
            // 所以实际先用「每 1% SOC 跑多少 km」——它不需要容量，是行程里真实读到的事实。
            if let eff = trip.avgEfficiency {
                Text(String(format: "%.1f kWh/100km", eff))
                    .font(TokensTypo.caption)
                    .foregroundStyle(TokensPalette.tertiary)
            } else if let kmPerPct = trip.kmPerPercent {
                Text(String(format: "%.1f km / 1%% 电量", kmPerPct))
                    .font(TokensTypo.caption)
                    .foregroundStyle(TokensPalette.tertiary)
            }
            // 「这一张能翻」的提示。一个可以点但没有提示的东西等于不能点 ——
            // 而这一个是**整张卡的**交互（不是某个按钮），没有可认的控件形状。
            Image(safeSymbol: "arrow.triangle.2.circlepath", fallback: "arrow.triangle.2.circlepath")
                .font(TokensTypo.caption2)
                .foregroundStyle(TokensPalette.tertiary)
                .accessibilityHidden(true)
        }
    }

    /// 这一段求到过的那条道路路线（没有就是 nil）。
    /// 读的是 `RouteService` 的**缓存**（不是再发一次请求）：请求由 `MiniTripMap`
    /// 发过的那一次负责，这里只是换个地方读同一个答案。
    private func roadRoute(_ trip: AppStore.TripRecord) -> RouteService.Route? {
        guard let a = trip.startLocation?.coordinate, let b = trip.endLocation?.coordinate else {
            return nil
        }
        return routes.cached(from: a, to: b)
    }

    /// 常停热区与地图主屏是**同一套聚类** —— 两处必须是同一个答案
    private func hotspotsBand(_ spots: [MapHotspot]) -> some View {
        //  正文里原来有一行 `DSSectionHeader(title: "常来之地")`，而这张卡叫「常停之地」
        //  —— 同一个东西两个名字（用户 2026-09-24：「全部页面检查精致度」）。
        //  卡头已经给它起过名，正文直接从第一条开始。
        VStack(alignment: .leading, spacing: TokensSpacing.sm) {
            ForEach(spots.prefix(3)) { s in
                HStack(alignment: .firstTextBaseline) {
                    Image(safeSymbol: "mappin.circle.fill", fallback: "mappin.circle.fill")
                        .font(TokensTypo.fixed(13))
                        .foregroundStyle(TokensPalette.accent)
                    Text("\(s.visits) 次")
                        .font(TokensTypo.footnote)
                        .foregroundStyle(TokensPalette.primary)
                    Spacer(minLength: 0)
                    Text(MapSpineData.agoText(s.lastVisit))
                        .font(TokensTypo.caption)
                        .foregroundStyle(TokensPalette.tertiary)
                }
            }
            Text("停车史聚类（±80 米算同一处）")
                .font(TokensTypo.caption)
                .foregroundStyle(TokensPalette.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, TokensSpacing.lg)
    }
}

// =============================================================================
//  每段行程的真地图：起点 → 终点两点一线
// =============================================================================

/// 一次行程的迷你地图。
///
/// 2026-09-25（用户第 1 条）两处改动：
///  ① **线是道路路线**（不再是两点直线）—— 由 `RouteService` 取，取不到才退直线，
///     而退直线时图上会自己说一句（不能默认用户看不出区别）；
///  ② 两个端点有了**字**：「起」绿、「终」蓝，各自一枚圆牌与两个点区分形状。
///     用户原话是「起点终点图标不容易区分」，而两个同色的点本来就没法区分 ——
///     之前那个形状上的区别（一个深一点、一个蓝一点）隔着一条地图很难看出来。
///
/// `TripRecord` 没有逐点轨迹（只有起终两个坐标），所以：
///  **有路线时画的不是轨迹，是那两地之间此刻的道路走法** —— 它不等于车当时开的那条路
///  （同样的起终点，早高峰与凌晨的推荐路线可以不同）。这一点不写在界面上，
///  但写在代码里，免得下一个读的人把它当成轨迹。
struct MiniTripMap: View {
    let from: CLLocationCoordinate2D?
    let to: CLLocationCoordinate2D?

    /// 道路路线（点串）。空 = 还没取到 / 取不到 —— 那时画直线。
    @State private var road: [CLLocationCoordinate2D] = []
    /// 问过了没有。它区分两件事：「正在取」与「取不到」——
    /// 前者不该在卡片上写“还没有路线”（那会变成一次闪烁），后者必须说。
    @State private var tried = false

    /// 镜头。**它是状态**，不是 `.constant`（那个形状写在 `fit` 上）。
    @State private var camera: MapCameraPosition = .automatic

    var body: some View {
        if let a = from, let b = to {
            Map(position: $camera) {
                // 一次算好再画：`line(_:_:)` 在取不到路线时是现拼的数组，
                // 写两遍就是拼两遍（而它们内容必须一样）—— 一个局部量把它变成一次。
                let pts = line(a, b)
                MapPolyline(MKPolyline(coordinates: pts, count: pts.count))
                    .stroke(TokensPalette.accent.opacity(0.9),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round))
                // 标题传空串：`Annotation` 的第一个参数是**图上会画的标题** ——
                // 地图那一屏的车钉上就因此多出一行服务端给的车名（那一轮记过账）。
                // 这里的字已经在圆牌里了，再让 MapKit 画一行就是两遍。
                Annotation("", coordinate: a) { endpoint("起", TokensPalette.success) }
                Annotation("", coordinate: b) { endpoint("终", TokensPalette.accent) }
            }
            .mapStyle(.standard(elevation: .flat, emphasis: .muted,
                                pointsOfInterest: .excludingAll, showsTraffic: false))
            //  镜头改成状态（上一行）之后，地图本身**会接手势**了 —— 而这张图在一叠卡里，
            //  手指落在图上就不再滚那一叠（竖向拖动会被 MapKit 吃掉）。它本来就是个「说明图」
            //  （没有任何控件、POI 全关），所以不接手势：镜头仍然跟着状态走。
            .allowsHitTesting(false)
            // 取路线：挂在卡片自己身上（卡片被建出来才发请求）。
            // `.task(id:)` 的 id 是两点 ⇒ 行程变了就重新取（同一段不会重复取，
            // 缓存与合流都在服务里，见 `RouteService`）。
            .task(id: routeKey(a, b)) {
                tried = false
                //  先按「两点直线」取一次景（第一帧就有画面），路线回来再框一次 ——
                //  **第二次才是「把行程居中」那一下**（见 `fit`）。
                camera = fit(a, b)
                road = await RouteService.shared.route(from: a, to: b)?.points ?? []
                tried = true
                camera = fit(a, b)
            }
            .overlay(alignment: .bottomLeading) { fallbackNote }
        } else {
            ZStack {
                // 它是「一块地图空着」的占位面，在卡里 —— 与 `DSPlaceholder` 同一层底：
                // 读 `panel`（半透明），不是不透明的 `raised`（深色 #2C2C2E）。
                RoundedRectangle(cornerRadius: TokensRadius.medium, style: .continuous)
                    .fill(TokensPalette.panel)
                Text("这一段没有记录坐标")
                    .font(TokensTypo.caption)
                    .foregroundStyle(TokensPalette.tertiary)
            }
        }
    }

    /// 画在地图上的那串坐标：有路线就是路线，没有就是两点。
    private func line(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> [CLLocationCoordinate2D] {
        road.count > 1 ? road : [a, b]
    }

    /// 把**画出来的那串坐标**框进画面：中心取**包围盒的中心**，视距按它的长边算。
    ///
    /// ⚠️ 2026-09-26（用户：「行程页地图应该把行程居中」）—— 此前是
    /// `Map(position: .constant(…))`，那个值在**第一帧**（`road` 还空着）就定下了：
    /// 那时画的是两点直线，于是镜头按「两点之间」取景；路线回来之后线换成了绕行的
    /// 那一条，镜头却不动 —— 看到的就是「行程偏在一边、甚至被裁掉」。两处一起改了：
    ///
    ///   · 镜头是**状态**（`camera`），路线回来再框一次（见 `.task`）；
    ///   · 中心从此取**包围盒的中心**。上一版取「点串正中间那一个点」：
    ///     采样点按距离均匀时它才约等于中点，而绕行（下高速绕一圈）会让它整个偏到一侧，
    ///     包围盒的中心与采样无关 —— 它量的是「画出来的形状占在哪一片」这个几何事实。
    ///   · `2.4` 这个系数**留着**（它此前就在这里：视距 = 跨度的 2.4 倍），
    ///     只是跨度改成包围盒的**长边**（此前是「离起点最远的那个方向」—— 同一个量，
    ///     但那是以起点为原点的，路线绕回起点一侧时两个数会差很多）。
    private func fit(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> MapCameraPosition {
        let pts = line(a, b)
        let lats = pts.map(\.latitude)
        let lngs = pts.map(\.longitude)
        let minLat = lats.min() ?? a.latitude, maxLat = lats.max() ?? a.latitude
        let minLng = lngs.min() ?? a.longitude, maxLng = lngs.max() ?? a.longitude
        let midLat = (minLat + maxLat) / 2
        let midLng = (minLng + maxLng) / 2
        // 纬度差按 111 km/度换算；经度差乘 cos(纬度)。
        let spanLat = (maxLat - minLat) * 111_000
        let spanLng = (maxLng - minLng) * 111_000 * max(0.2, cos(midLat * .pi / 180))
        return .camera(MapCamera(
            centerCoordinate: CLLocationCoordinate2D(latitude: midLat, longitude: midLng),
            // 两端重合或几乎没动：退到能看清两个牌的默认视距。
            distance: max(max(spanLat, spanLng) * 2.4, 900),
            heading: 0,
            pitch: 0))
    }

    /// 直线的说明。只在**问过、且没拿到**时才出现（正在取时什么都不说 ——
    /// 否则每一张卡出现时都会先闪一下这句）。
    @ViewBuilder
    private var fallbackNote: some View {
        if tried && road.isEmpty {
            Text("线是两点连线")
                .font(TokensTypo.caption2)
                .foregroundStyle(TokensPalette.secondary)
                .padding(.horizontal, TokensSpacing.xs)
                .padding(.vertical, TokensSpacing.xxs)
                .background(TokensPalette.panel, in: Capsule())
                .padding(TokensSpacing.xs)
        }
    }

    /// 一个端点：圆牌里写着「起」或「终」。
    /// 字才是区分两个端点的那一件东西 —— 颜色与形状只是辅助（色盲用户也在看这张图）。
    private func endpoint(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(TokensTypo.fixed(11, weight: .bold))
            .foregroundStyle(TokensPalette.labelOnTint)
            .frame(width: 20, height: 20)
            .background(Circle().fill(color))
            .overlay(Circle().strokeBorder(TokensPalette.surface, lineWidth: 2))
            //  这里原本还有一圈反色外发光（`dsInkGlow()`）—— 2026-09-26 随整个
            //  外壳机制删除（用户：「完全删除文字发光和文字发光功能」）。
            //  两个端点仍能区分：字（起/终）+ 颜色 + 那圈 `surface` 描边。
    }

    /// 取路线的键（两点；5 位小数与 `RouteService` 的键同一口径）。
    private func routeKey(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> String {
        String(format: "%.5f,%.5f>%.5f,%.5f", a.latitude, a.longitude, b.latitude, b.longitude)
    }
}
