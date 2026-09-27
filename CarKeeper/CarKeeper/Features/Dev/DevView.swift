import SwiftUI
import UIKit

// =============================================================================
//  诊断 —— 这一页回答的是「这台设备此刻在发生什么」
// =============================================================================
//  四块（顺序即屏幕上的顺序）：
//    ① 运行状态：指令数 / 能耗记录数 / 网络状态 / 车辆 ID / 内存 /
//        网络延迟 / 充电监控 / 里程与保养计划（每一项对应一个真的在跑的服务）
//    ② 请求日志：消息自检 + 原始日志（最近 60 条请求/响应的原文，已打码）
//    ③ 操作：复制诊断信息 / 清除缓存（带确认）
//    ④ 关于：版本 / 构建 / 外观
//
//  ⚠️ 2026-09-27（用户：「删除开发者入口，诊断中删除无用的」）两块整组删掉：
//    · **能力位图**（`funCode` 原文：7 组 43 个开关）—— 它当时是给「哪些位对应
//      哪些功能」收集证据用的（那一段结论已落在 `API-FIELD-MAP.md` §17），
//      而它是一个**快照**：要看它拿一份报文对照就行，不必在 App 里养一条
//      只有开发者读的链（`VM.capabilities` / `VM.Capability` 一起删了）；
//    · **「上一次启动」**（启动轨迹）—— 它的目的从头到尾只有一个：
//      给「载入不到 10 秒就退」那次二分定位提供事后证据（见 `StartupJournal`
//      头注），而那份头注自己就写着「查完就删」。它连带的还有
//      `Services/LaunchFence.swift`（那一轮二分实验的四个开关，四个都是「开」）
//      以及全 App 那十几处 `StartupJournal.shared.mark(...)` 路标。
//      这一步的代价如实记：以后若又出现「启动后几秒自己退、系统里查不到日志」，
//      那次立好的仪器已经不在了 —— 它当初的源文件在 git 历史里（删于本轮）。
// =============================================================================
//
//  这一页取代了更早的「设计令牌检查器」（2026-09-25 用户第 6 条：
//  「诊断里面删除一切和 UI 相关的」）：卡片叠预览、色板、字体样张、几何与动效
//  数值六组都走了 —— 它们回答的是「我们的设计长什么样」，而这一页的名字叫诊断。

struct DevView: View {
    private let store = AppStore.shared
    @State private var showClearConfirm = false
    /// 「原始日志」那一组的重读代号（`RawLogStore` 不是 ObservableObject）
    @State private var logTick = 0
    // 订阅下面那几个监控。用 @ObservedObject 而不是直接读单例：
    // 内存每 10 秒刷新一次 —— 不订阅就永远停在打开那一瞬的值。
    @ObservedObject private var memory = MemoryMonitor.shared
    @ObservedObject private var networkQuality = NetworkQualityMonitor.shared
    @ObservedObject private var chargeMonitor = ChargingStatusMonitor.shared
    //  （这里原有 `@ObservedObject private var offline = OfflineModeManager.shared`：
    //   那个类只是 `networkQuality.isReachable` 取反后的第二个名字，已整份删除 ——
    //   见 `Services/NetworkEnhancements.swift` 的文件头。下面那一行读的就是它的原值。）

    var body: some View {
        //  正文只提供内容 —— 它住在「我的」那张叫「诊断」的卡里（`StackCard`），
        //  而那一叠自己就是滚动容器（`ArcStack` 头注：系统 `ScrollView`）。
        //  这里原本还包着一层 `ScrollView`：里外两层都能滚时手势塌给内层，
        //  而内层拿到的是无限高 —— 它自己永远滚不动，却把这块区域的拖动吃掉了
        //  （用户 2026-09-25：「每个卡片仔细核对，内容展开后是否拥挤」）。
        //  页标题也一并删：卡头写着「诊断」，正文再写一遍「设计令牌」是同一个东西
        //  两个名字（它下面那一节自己还有「艺术主题」的标题）。
        //  2026-09-25 第 6 条（用户：「诊断里面删除一切和 UI 相关的」）：
        //  上面原本还挂着六组**与界面本身有关**的东西 ——
        //  卡片叠预览（`StackLabView`）、画布与表面色板、语义色色板、字体样张、
        //  几何数值、动效数值。它们回答的是「我们的设计长什么样」，
        //  而这一页的名字叫诊断：诊断回答的是「这台设备此刻在发生什么」。
        //  两件事住在一页里的代价很实在：真正要报障的人得先划过一屏设计令牌。
        //  （色板与样张当年还有第二个理由 —— 用眼睛挑二十套艺术主题；主题只剩原生
        //   之后那个理由早就没了，是这一次一起走的。）
        VStack(alignment: .leading, spacing: TokensSpacing.lg) {
            kvGroup("运行状态", runtime)
            diagnosticsGroups
            actionsGroup
            kvGroup("关于", about)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        //  延迟只在这一页打开时测一次（原先是一个永远在跑的 30 秒定时器 ——
        //  见 `NetworkQualityMonitor` 的文件头）：没人看着这一行的时候，它没有意义。
        .task { networkQuality.measureLatency() }
        .confirmationDialog("清除全部车端缓存？", isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button("清除缓存", role: .destructive) {
                store.clearCache()
                TokensHaptic.result(true)
                ToastManager.shared.show("缓存已清除", icon: "trash")
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text("只清空车况、充电、定位、环境、检测、消息缓存，不会退出登录。")
        }
    }

    // MARK: - 已删除：能力位图（2026-09-27）

    /// 这里以前是「能力位图（funCode 原文）」：7 个折叠组、43 个开关，每个只有
    /// **原文键名 + 1/0**（不猜中文 —— 43 个缩写里只有少数能自证）。
    /// 删掉它的理由写在文件头上（它是快照，不是运行状态）；
    /// 而它带来的那条解析链（`VM.capabilities` / `VM.Capability`）也一起删了。

    // MARK: - 已删除：艺术主题入口（2026-09-25）

    /// 这里以前是「诊断」里的第一组：二十套艺术主题的样张（`ThemeGallerySection`），
    /// 点一套全 App 立刻变 —— 那时它的用途是**用眼睛挑**。
    /// 用户 2026-09-25 定下只用原生、其余 19 套全删，于是样张页与本入口一起删掉：
    /// 只剩一套取值时，一页样张是「拿真实的取值给自己的唯一答案看」。
    /// 取值现在住在 `Tokens.swift`（`TokensPalette`），下面那些色板就是它的读数。

    // MARK: - 通用键值组

    private func kvGroup(_ title: String, _ rows: [(String, String)], footer: String? = nil) -> some View {
        DSGroup(title: title, footer: footer) {
            ForEach(Array(rows.enumerated()), id: \.offset) { idx, row in
                DSGroupRow(showsSeparator: idx < rows.count - 1) {
                    DSKeyValueRow(key: row.0, value: row.1, mono: false)
                }
            }
        }
    }

    // MARK: - 运行状态与操作

    /// 这一组全是**此刻真在跑的东西**的读数，没有一项来自本机累积的统计。
    ///
    /// ⚠️ 这里原有六行：「首页加载耗时」（那个键从来没有人写过，永远显示「—」）、
    ///    「已缓存接口」（它数的是 `store.caches` 里非 nil 的项，而那不是缓存，
    ///    名字本身就是错的）、「API 成功率」与「崩溃记录」（两项都来自已删的
    ///    埋点与崩溃记录）。2026-09-23 一并删除，同时删掉了写入这些键的
    ///    `PerformanceTracker` 与 `CrashReporter`。
    private var runtime: [(String, String)] {
        let mileage = UserDefaults.standard.integer(forKey: AppStore.currentMileageKey)
        let lastService = UserDefaults.standard.integer(forKey: AppStore.lastServiceMileageKey)
        // 同一辆车、同一份报文算出来的保养计划（间隔与上次保养来自服务端字段）
        let plan = store.maintenancePlan

        return [
            ("指令历史", "\(store.commandHistory.count) 条"),
            ("能耗记录", "\(store.energyHistory.count) 次"),
            ("网络状态", networkText),
            ("车辆 ID", store.carId.isEmpty ? "—" : store.carId),
            // ——— 监控：每个都对应一个真的在跑的服务 ———
            ("内存占用", memory.usedMemoryMB > 0
                ? String(format: "%.1f MB", memory.usedMemoryMB) + "（\(memoryLevelText)）"
                : "采样中…"),
            ("网络延迟", networkQuality.latency > 0
                ? String(format: "%.0f ms", networkQuality.latency) + " · \(networkQuality.connectionType)"
                : "未测出"),
            ("网络可达", networkQuality.isReachable ? "可达" : "不可达"),
            ("充电监控", chargeMonitor.summary),
            ("车端里程", mileage > 0 ? "\(mileage) km" : "未取到"),
            // 保养计划：这里要看得出「数字从哪来」—— 服务端字段（20000 / 20100）
            // 与本机兜底（10000 / 用户手记）会给出完全不同的结论。
            ("保养计划", plan.map { p in
                let src = p.fromServer ? "车厂计划" : "本机记录"
                return "\(p.last) + \(p.interval) = \(p.next) km（\(src)，当前 \(p.current)）"
            } ?? "未登记"),
            ("上次保养里程", lastService > 0 ? "\(lastService) km" : "未设置")
        ]
    }

    private var memoryLevelText: String {
        switch memory.warningLevel {
        case 2: return "临界"
        case 1: return "偏高"
        default: return "正常"
        }
    }

    private var networkText: String { store.networkStatus.rawValue }

    /// 两台仪器放在一起：消息自检（「到底返回了啥」）与原始日志（每次请求的原文）。
    /// 它们回答的是同一个问题的两半，所以同处一行 —— 同一个问题只该有一个地方看。
    private var diagnosticsGroups: some View {
        VStack(alignment: .leading, spacing: TokensSpacing.lg) {
            MessageProbeSection()
            rawLogGroup
        }
    }

    /// 原始请求 / 响应日志（`RawLogStore`：内存环形 60 条，已打码）。
    ///
    /// 它一直存在 —— 每个请求都写一行 —— 而**没有任何界面在读它**。
    /// 代价在 2026-09-24 那次「消息接口拿不到数据」里看得很清楚：
    /// 「服务端真的没给」与「我们没解析到」在界面上长得一模一样，
    /// 只能靠猜与来回问。这一组就是那台仪器：最近几条直接列出来，全部可一键复制。
    /// 复制的是一份可核对的报文（status + 响应长度 + 正文形状）。
    private var rawLogGroup: some View {
        let entries = RawLogStore.shared.allEntries()
        return DSGroup(title: "原始日志", trailing: "\(entries.count) 条",
                       footer: "最近 60 条，内存里；token / 控车码 / 车牌 / 坐标已打码。" +
                               "报「消息拿不到」时，先看 pageReceiverInfoByTime 那条的 status 与长度。") {
            DSGroupRow {
                DSRow(icon: "arrow.clockwise", title: "重新读取") { logTick += 1 }
            }
            DSGroupRow {
                DSRow(icon: "doc.on.doc", title: "复制全部日志") {
                    UIPasteboard.general.string = RawLogStore.shared.joined()
                    TokensHaptic.result(true)
                    ToastManager.shared.show("原始日志已复制", icon: "doc.on.doc.fill")
                }
            }
            if entries.isEmpty {
                DSGroupRow(showsSeparator: false) {
                    Text("还没有请求记录")
                        .font(TokensTypo.footnote)
                        .foregroundStyle(TokensPalette.secondary)
                }
            } else {
                ForEach(Array(entries.prefix(8).enumerated()), id: \.offset) { idx, e in
                    DSGroupRow(showsSeparator: idx < min(8, entries.count) - 1) {
                        VStack(alignment: .leading, spacing: TokensSpacing.xxs) {
                            Text(Self.logHeadline(e))
                                .font(TokensTypo.fixed(11, weight: .regular).monospacedDigit())
                                .foregroundStyle(TokensPalette.primary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text("\(e.count) 字符")
                                .font(TokensTypo.caption2)
                                .foregroundStyle(TokensPalette.tertiary)
                        }
                    }
                }
            }
        }
        // `RawLogStore` 是普通单例（不是 ObservableObject）：不动一下状态，
        // 这份列表就不会重画 —— 「重新读取」因此靠 `logTick` 重建这一组。
        .id(logTick)
    }

    /// 一条日志的**第一行**（`[时间] REQ/RES 路径`）—— 列表里只读这一行就够定位。
    private static func logHeadline(_ entry: String) -> String {
        entry.split(separator: "\n").first.map(String.init) ?? entry
    }

    //  这里原有 `shortenedStartupLines`（把启动轨迹折成「头三行 + 尾巴十二行」）——
    //  随「上一次启动」那一组一起删（2026-09-27）。它留下的一条教训仍然成立，所以
    //  记在这里：ViewBuilder 只接受表达式，而 `var shown` + `if … { shown = … }`
    //  那种拼接语句的类型是 `()`，写在 `DSGroup { }` 里就是
    //  `type '()' cannot conform to 'View'`（2026-09-24 那一轮 CI 红在这上面）。
    //  取值拼接只能待在**函数**里，不能待在视图构建器里。

    private var actionsGroup: some View {
        DSGroup(title: "操作", footer: "诊断信息包含版本、车辆 ID、缓存与网络状态，用于报障。") {
            DSGroupRow {
                DSRow(icon: "doc.on.doc", title: "复制诊断信息") {
                    UIPasteboard.general.string = diagnostics
                    TokensHaptic.result(true)
                    ToastManager.shared.show("诊断信息已复制", icon: "doc.on.doc.fill")
                }
            }
            DSGroupRow(showsSeparator: false) {
                DSRow(icon: "trash", title: "清除缓存", subtitle: "不会退出登录") {
                    showClearConfirm = true
                }
            }
        }
    }

    private var diagnostics: String {
        var lines = ["【CarKeeper 诊断信息】", "版本 \(appVersion) (\(buildNumber))"]
        lines.append("车辆 ID：\(store.carId.isEmpty ? "未绑定" : store.carId)")
        lines.append("登录状态：\(store.isLoggedIn ? "已登录" : "未登录")")
        lines.append("网络状态：\(networkText)")
        for row in runtime { lines.append("\(row.0)：\(row.1)") }
        return lines.joined(separator: "\n")
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    private var about: [(String, String)] {
        [
            ("版本", appVersion),
            ("构建", buildNumber),
            ("外观", "跟随系统（浅色 / 深色各一套）")
        ]
    }
}
