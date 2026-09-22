// =============================================================================
// #NEW-123 全局搜索 HUD
// =============================================================================
//
// 上一版这个页面搜的是**写死的 6 条字符串**，而且每一条的 `action` 都是空闭包
// —— 点下去什么都不发生；它本身也没有任何入口（零外部引用）。
// 也就是说：你以为有一个「全局搜索」，实际是一个搜不到东西、点不动的假界面。
//
// 现在它搜的是真东西，搜到就能去：
//   • 页面（16 个深潜页，跳转用统一导航 `NavState.pushNavigation`）
//   • 车（车辆档案里的字段：车牌 / VIN / 车型 / 颜色）
//   • 车况读数（电量 / 续航 / 胎压 / 充电 —— 命中就跳到对应页）
//   • 行程（`store.tripHistory`：时间、里程、起止 SOC）
//   • 指令历史（`store.commandHistory`：指令名、成功与失败）
//   • 充电记录（`ChargeLedger` 的真实会话）
//
// 搜不到就照实说「没有匹配」，不编造结果。
// =============================================================================

import SwiftUI

struct GlobalSearchHUD: View {
    @Binding var isPresented: Bool
    @EnvironmentObject private var nav: NavState
    private let store = AppStore.shared

    @State private var searchText = ""
    @State private var searchResults: [SearchResult] = []
    @FocusState private var focused: Bool

    struct SearchResult: Identifiable {
        let id = UUID()
        let title: String
        let subtitle: String
        let icon: String
        /// 命中关键词的标题 —— 用于排序（标题命中排在正文命中之前）
        let action: () -> Void
    }

    var body: some View {
        ZStack {
            // 背景遮罩（浮层自己的一层，合法）。色相来自主题：纸主题的遮罩是墨，不是黑。
            TokensPalette.scrim.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { isPresented = false }

            VStack(spacing: 0) {
                // 搜索框（浮在内容之上的一层 → 允许玻璃）
                HStack(spacing: TokensSpacing.sm) {
                    Image(systemName: "magnifyingglass")
                        .font(TokensTypo.title3)
                        .foregroundStyle(TokensPalette.secondary)

                    TextField("搜索页面、车、行程、指令、充电…", text: $searchText)
                        .font(TokensTypo.subheadline)
                        .textFieldStyle(.plain)
                        .foregroundColor(TokensPalette.primary)
                        .focused($focused)
                        .submitLabel(.search)

                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(TokensPalette.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(TokensSpacing.md)
                .background(.ultraThinMaterial,
                            in: RoundedRectangle(cornerRadius: TokensRadius.medium, style: .continuous))
                .overlay {
                    if TokensPalette.decor != .none {
                        RoundedRectangle(cornerRadius: TokensRadius.medium, style: .continuous)
                            .strokeBorder(TokensPalette.hairline, lineWidth: TokensHair.line)
                    }
                }
                .padding(.horizontal, TokensSpacing.page)

                ScrollView {
                    if searchResults.isEmpty {
                        DSPlaceholder(icon: searchText.isEmpty ? "magnifyingglass" : "questionmark.circle",
                                      title: searchText.isEmpty ? "搜什么？" : "没有匹配的项",
                                      message: searchText.isEmpty
                                        ? "可以搜页面（如「胎压」「维保」）、车牌、行程、指令名、充电记录。"
                                        : "换一个词试试。这里只搜本机已有的数据，不会去猜。")
                            .padding(.horizontal, TokensSpacing.page)
                            .padding(.top, TokensSpacing.lg)
                    } else {
                        DSGroup(title: nil, trailing: "\(searchResults.count)") {
                            ForEach(Array(searchResults.enumerated()), id: \.element.id) { idx, result in
                                DSGroupRow(showsSeparator: idx < searchResults.count - 1) {
                                    SearchResultRow(result: result) {
                                        focused = false
                                        result.action()
                                        isPresented = false
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, TokensSpacing.page)
                        .padding(.top, TokensSpacing.md)
                        .padding(.bottom, TokensSpacing.xxl)
                    }
                }
            }
            .padding(.top, TokensSpacing.md)
        }
        .onChange(of: searchText) { _, text in
            searchResults = performSearch(text)
        }
        .onAppear {
            searchResults = []
            focused = true
        }
    }

    // MARK: - 搜索

    private func performSearch(_ text: String) -> [SearchResult] {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard q.count >= 1 else { return [] }

        var out: [SearchResult] = []

        // ① 页面（静态清单 + 真实导航）
        for page in Self.pages {
            if page.title.lowercased().contains(q) || page.hint.lowercased().contains(q) {
                out.append(SearchResult(title: page.title, subtitle: page.hint, icon: page.icon) { [nav] in
                    nav.pushNavigation(page.link)
                })
            }
        }

        // ② 车（车辆档案里的真实字段）
        if let sum = VM.vehicleSummary(store.car) {
            let fields: [(String, String)] = [
                ("车牌", sum.plate),
                ("VIN", sum.vin),
                ("车型", sum.model),
                ("颜色", sum.color)
            ]
            for f in fields where !f.1.isEmpty && f.1 != "--" {
                if f.1.lowercased().contains(q) {
                    out.append(SearchResult(title: "\(f.0) \(f.1)",
                                            subtitle: "车辆档案",
                                            icon: "car.fill") { [nav] in
                        nav.pushNavigation(.vehicle)
                    })
                }
            }
        }

        // ③ 车况读数（命中「电量/续航/胎压/充电」这类词就跳到那一页）
        let energy = VM.energy(store.caches, store.car)
        let readings: [(String, String, String, Deeplink)] = [
            ("电量", "\(energy.soc)（\(energy.socPct)%）", "battery.100", .battery),
            ("续航", "\(energy.range) km", "gauge.with.dots.needle.50percent", .dashboard),
            ("胎压", "四轮压力与温度", "circle.dashed", .health),
            ("充电", energy.chargeText, "bolt.fill", .battery),
            ("空调", "车内温度与风量", "fan.fill", .control)
        ]
        for r in readings where r.0.contains(q) || q.contains(r.0) {
            out.append(SearchResult(title: "\(r.0)：\(r.1)", subtitle: "实时车况", icon: r.2) { [nav] in
                nav.pushNavigation(r.3)
            })
        }

        // ④ 行程
        for trip in store.tripHistory.prefix(30) {
            let when = trip.startTime.formatted(date: .abbreviated, time: .shortened)
            let dist = String(format: "%.1f km", trip.distanceKm)
            let soc = "\(trip.startSoc)% → \(trip.endSoc)%"
            if when.lowercased().contains(q) || dist.lowercased().contains(q) || soc.lowercased().contains(q) {
                out.append(SearchResult(title: "行程 \(dist)",
                                        subtitle: "\(when) · \(soc)",
                                        icon: "point.topleft.down.curvedto.point.bottomright.up") { [nav] in
                    nav.pushNavigation(.trips)
                })
            }
        }

        // ⑤ 指令历史
        for entry in store.commandHistory.prefix(30) {
            let when = entry.startedAt.formatted(date: .abbreviated, time: .shortened)
            let state = entry.success ? "成功" : "失败"
            if entry.name.lowercased().contains(q) || entry.cmd.lowercased().contains(q) {
                out.append(SearchResult(title: "指令 \(entry.name)",
                                        subtitle: "\(when) · \(state) · 用时 \(entry.durationText)",
                                        icon: entry.iconName) { [nav] in
                    // 指令记录现在住在车控页的「做过什么」里，所以搜到指令 → 去车控页
                    nav.pushNavigation(.control)
                })
            }
        }

        // ⑥ 充电记录（真实会话：功率采样积分出来的度数）
        for s in ChargeLedger.shared.sessions.prefix(30) {
            let when = s.start.formatted(date: .abbreviated, time: .shortened)
            let kwh = "\(ChargeLedger.kwhText(s.kWh)) kWh"
            if when.lowercased().contains(q) || kwh.lowercased().contains(q) {
                out.append(SearchResult(title: "充电 \(kwh)",
                                        subtitle: "\(when) · ¥\(ChargeLedger.moneyText(ChargeLedger.shared.cost(s)))",
                                        icon: "bolt.fill") { [nav] in
                    nav.pushNavigation(.battery)
                })
            }
        }

        // 标题命中排在前面；同权重保持来源顺序（页面 → 车 → 车况 → 行程 → 指令 → 充电）
        let matched = out.filter { !$0.title.lowercased().contains(q) }
        let titled = out.filter { $0.title.lowercased().contains(q) }
        return Array((titled + matched).prefix(24))
    }

    /// 可搜的页面清单。与壳层的 `Deeplink` 一一对应（少一个就等于少一条入口）。
    private static let pages: [(title: String, hint: String, icon: String, link: Deeplink)] = [
        ("车辆档案", "车牌、车型、保险与保养到期", "doc.text.fill", .vehicle),
        ("健康报告", "胎压、故障码、保养建议", "shield.lefthalf.filled", .health),
        ("电池充电", "SOC、充电曲线、充电账单", "battery.100", .battery),
        ("全量数据", "所有原始读数与历史曲线", "chart.bar.xaxis", .data),
        ("驾驶评分", "用行程里真有的事实算的评分", "trophy.fill", .score),
        ("行程分析", "每一次出行的时间与能耗", "chart.bar.fill", .trips),
        ("维保记录", "保养里程与提醒", "wrench.and.screwdriver.fill", .service),
        ("停车位置", "最近一次停放的位置", "mappin.circle.fill", .parking),
        ("车与账号", "车辆、账号、隐私与关于", "person.fill", .mine),
        ("车辆提示", "针对你车的用车建议", "lightbulb.fill", .tips),
        ("紧急求助", "拖车、保险、救援电话", "exclamationmark.octagon.fill", .emergency),
        ("导出数据", "把行程与充电记录导出去", "square.and.arrow.up", .export),
        ("消息中心", "车辆给你发的通知", "bubble.left.fill", .messages),
        ("远程控车", "锁车、空调、寻车", "dot.radiowaves.left.and.right", .control),
        ("驾驶总览", "一屏看完今天", "gauge.with.dots.needle.50percent", .dashboard),
        ("开发者工具", "设计令牌、运行状态、诊断", "wrench.adjustable", .dev)
    ]
}

struct SearchResultRow: View {
    let result: GlobalSearchHUD.SearchResult
    let action: () -> Void

    var body: some View {
        // DSRow 自己就是那个按钮（传 action 时它会包一层 Button + 按压反馈），
        // 外面不再套一层 —— 套两层会出现两个按钮语义，读屏会念两遍。
        DSRow(icon: result.icon,
              title: result.title,
              subtitle: result.subtitle,
              showsChevron: true,
              action: action)
    }
}
