import SwiftUI
import UIKit

// =============================================================================
//  开发者工具 —— v4 信息架构
// =============================================================================
//  这一页是「设计令牌 + 运行状态」的检查器，用来在真机上核对深浅双模式。
//  ① 令牌按类分组：画布与表面 / 文字 / 语义色 / 几何 / 动效
//     —— 每个色块都带 HEX，每种字体都用自己的字号渲染出来（不是写一句话描述它）
//  ② 运行状态：加载耗时、指令数、能耗记录数、缓存条目、网络状态
//     —— 还包括那批「启动了但从来没人看」的监控（内存 / 网络质量 /
//        性能 / 崩溃 / 充电状态 / 摇一摇 / 维保里程）。它们本来就跑着，
//        只是输出没有任何界面在显示 —— 那就等于没有。
//  ③ 操作：复制诊断信息 / 清除缓存（带确认）
// =============================================================================

struct DevView: View {
    private let store = AppStore.shared
    @State private var showClearConfirm = false
    /// 「原始日志」那一组的重读代号（`RawLogStore` 不是 ObservableObject）
    @State private var logTick = 0
    // 订阅那些「启动了但没人看」的监控。用 @ObservedObject 而不是直接读单例：
    // 内存每 10 秒刷新一次、网络质量也是周期性的 —— 不订阅就永远停在打开那一瞬的值。
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
            capabilityGroups
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

    // MARK: - 能力位图（car.funCode）

    /// 服务端 `funCode` 说这辆车有什么功能：本次抓包 7 个分组、43 个开关。
    ///
    /// 这里**故意只显示原文**（键名 + 1/0）。43 个缩写里只有少数能自证
    /// （`StateWindow` 车窗、`Statelock` 门锁）；其余（`zjcsStatusRC`/`openPJ`/
    /// `openBY`/`isFence`/`#18`…）没有任何可核实的依据，参考实现也零引用。
    /// 而且**两组同名开关互相矛盾**（本车 `remoteBaseControl.airBtn = 1` 而
    /// `remoteBaseControl_XNY.airBtn = 0`），无从判断哪一组作准。
    /// 猜一个中文写上去就是换一种方式说谎；按 0 隐藏控件又可能藏掉真能用的功能。
    /// 所以位图留在这里当证据 —— 等某组位与真实车控的失败一一对应，
    /// 再让 `VM.Capability.on` 去驱动界面。
    private var capabilityGroups: some View {
        let caps = VM.capabilities(store.car)
        let groups = Dictionary(grouping: caps, by: { $0.group })
        return VStack(alignment: .leading, spacing: TokensSpacing.md) {
            if caps.isEmpty {
                kvGroup("能力位图", [("funCode", "未取到")],
                        footer: "getMyCars 里没有 FunCode，或它的 JSON 没解析出来。")
            } else {
                DSSectionHeader(title: "能力位图（funCode 原文）")
                ForEach(groups.keys.sorted(), id: \.self) { g in
                    let items = groups[g] ?? []
                    let onCount = items.filter { $0.on }.count
                    DSExpandGroup(title: g,
                                  trailing: "\(onCount)/\(items.count)",
                                  trailingCls: onCount == items.count ? "ok" : "na") {
                        ForEach(Array(items.enumerated()), id: \.offset) { idx, c in
                            DSGroupRow(showsSeparator: idx < items.count - 1) {
                                DSKeyValueRow(key: c.key, value: c.on ? "1" : "0",
                                              valueCls: c.on ? "ok" : "na")
                            }
                        }
                    }
                }
            }
        }
    }

    /// 两台仪器放在一起：消息自检（「到底返回了啥」）与原始日志（每次请求的原文）。
    /// 它们回答的是同一个问题的两半，所以同处一行 —— 同一个问题只该有一个地方看。
    private var diagnosticsGroups: some View {
        VStack(alignment: .leading, spacing: TokensSpacing.lg) {
            startupGroup
            MessageProbeSection()
            rawLogGroup
        }
    }

    /// 上一次启动的轨迹 —— 「上一次为什么没走完」的**唯一**证据来源。
    ///
    /// 系统级处决（内存回收 / 看门狗）不调用 App 里任何一行代码，所以系统可能什么
    /// 都不留（用户 2026-09-24 报的就是「闪退、而且没有日志」）。这一组读的是启动时
    /// 一路写下来的路标（`StartupJournal`）：**没有收尾标记 = 上一次没走完**，
    /// 最后一行就是它死前到达的那一步，而那一行里的「距上限」就是被杀与否的判据。
    ///
    /// 第一行给的是**结论**（`prev.verdict`）：这张表本来是要人自己读的
    ///（「心跳停在高水位就是被杀」），而用户回来的是「我感觉是因为内存占用太多
    /// 被系统杀了」—— 一句猜测。能算的不该让人猜。
    private var startupGroup: some View {
        let prev = StartupJournal.shared.previousRun()
        return DSGroup(title: "上一次启动",
                       trailing: prev.exists ? (prev.finished ? "走完" : "没走完") : nil,
                       trailingCls: prev.finished ? "ok" : "bad",
                       footer: "只留上一次与这一次两回，每回上限 4 KB。") {
            DSGroupRow {
                DSRow(icon: "doc.on.doc", title: "复制轨迹") {
                    UIPasteboard.general.string = prev.lines.joined(separator: "\n")
                    TokensHaptic.result(true)
                    ToastManager.shared.show("启动轨迹已复制", icon: "doc.on.doc.fill")
                }
            }
            DSGroupRow {
                Text(prev.verdict)
                    .font(TokensTypo.footnote)
                    .foregroundStyle(prev.finished ? TokensPalette.secondary : TokensPalette.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if prev.lines.isEmpty {
                DSGroupRow(showsSeparator: false) {
                    Text("还没有更早的启动记录")
                        .font(TokensTypo.footnote)
                        .foregroundStyle(TokensPalette.secondary)
                }
            } else {
                // 头三行是「被信号杀死的纸条 / 这一次启动的标记 / 这一版装了哪几个围栏」，
                // 末尾十几行是「死前那几步」。两段都要在：轨迹一长，只取末尾会把
                // 「是不是我们自己的代码崩的」与「这一次是哪个实验」一并切掉 ——
                // 而那两样正是复制出去之后别人先看的东西。中间的清单省掉。
                //
                // 拼接在 `shortenedStartupLines` 里做，**不能**就地写在 `DSGroup { }` 里：
                // ViewBuilder 只把表达式当视图，而 `shown = …` 这种赋值语句的类型是 `()`，
                // 于是编译器去问它「你 conform to View 吗」—— 2026-09-24 那轮 CI
                //（`DevView.swift:393: error: type '()' cannot conform to 'View'`）
                // 就是这一行。函数调用是一个值，放在任何位置都成立。
                let shown = Self.shortenedStartupLines(prev.lines)
                ForEach(Array(shown.enumerated()), id: \.offset) { idx, line in
                    DSGroupRow(showsSeparator: idx < shown.count - 1) {
                        Text(line)
                            .font(TokensTypo.fixed(11, weight: .regular).monospacedDigit())
                            .foregroundStyle(TokensPalette.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
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

    /// 启动轨迹的展示形态：够短就整条照给，够长就留头三行 + 尾十二行，中间折成一行。
    ///
    /// 它必须是个函数。上一版把它写在 `startupGroup` 的 `DSGroup { }` 里，用的是
    /// `var shown` + `if … { shown = … }` —— 而 ViewBuilder 只接受表达式，赋值语句
    /// 的类型是 `()`，于是那一行在 macOS runner 上炸成
    /// `type '()' cannot conform to 'View'`（2026-09-24，白烧一整轮 10 倍计费的机器）。
    /// 判据是「这个值是不是视图」，而拼接取值从来不是视图 —— 它就该待在函数里。
    ///
    /// 用 `guard` 而不是三元：本仓库在三元的类型推断上丢过 CI 轮次
    ///（见 4203c67 / 2f088bd），这里不值得再赌一次。
    private static func shortenedStartupLines(_ lines: [String],
                                             headCount: Int = 3,
                                             tailCount: Int = 12) -> [String] {
        guard lines.count > headCount + tailCount else { return lines }
        return Array(lines.prefix(headCount)) + ["⋯（中间略）"] + Array(lines.suffix(tailCount))
    }

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
